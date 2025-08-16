#include "audioengine.h"
#include <QTimer>
#include <QDebug>
#include <QUrl>
#include <QPointer>
#include <QFileInfo>

bool AudioEngine::s_gstInitialized = false;

AudioEngine::AudioEngine(QObject *parent)
    : QObject(parent)
{
    if (!s_gstInitialized) {
        GError *error = nullptr;
        if (!gst_init_check(nullptr, nullptr, &error)) {
            qCritical() << "Failed to initialize GStreamer:" << (error ? error->message : "Unknown error");
            if (error) g_error_free(error);
            return;
        }
        s_gstInitialized = true;
    }
    
    initializePipeline();
    
    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(250);
    connect(m_positionTimer, &QTimer::timeout, this, &AudioEngine::updatePosition);
    
    // We don't need complex timers anymore since STREAM_START gives us the exact transition point
    // Keep a simple fallback timer just in case
    m_transitionTimer = nullptr;
    
    // Fallback timer in case STREAM_START doesn't arrive (shouldn't happen but be safe)
    m_transitionFallbackTimer = new QTimer(this);
    m_transitionFallbackTimer->setSingleShot(true);
    m_transitionFallbackTimer->setInterval(1000); // 1 second fallback
    connect(m_transitionFallbackTimer, &QTimer::timeout, this, [this]() {
        if (m_hasQueuedTrack && !m_trackTransitionDetected) {
            qDebug() << "[AudioEngine] Warning: Using fallback transition detection (no STREAM_START received)";
            m_hasQueuedTrack = false;
            m_trackTransitionDetected = false;
            
            // Emit signal to notify that the track transition has occurred
            emit trackTransitioned();
            
            // Query and emit duration for the new track
            gint64 duration;
            if (gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration)) {
                emit durationChanged(duration / GST_MSECOND);
            }
        }
    });
}

AudioEngine::~AudioEngine()
{
    qDebug() << "[AudioEngine::~AudioEngine] Destructor called, cleaning up...";
    
    // Ensure timers are deleted
    if (m_positionTimer) {
        m_positionTimer->stop();
        delete m_positionTimer;  // Use delete instead of deleteLater in destructor
        m_positionTimer = nullptr;
    }
    
    if (m_transitionTimer) {
        m_transitionTimer->stop();
        delete m_transitionTimer;
        m_transitionTimer = nullptr;
    }
    
    if (m_transitionFallbackTimer) {
        m_transitionFallbackTimer->stop();
        delete m_transitionFallbackTimer;
        m_transitionFallbackTimer = nullptr;
    }
    
    // Stop playback before cleanup
    if (m_pipeline) {
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
        // Wait for state change to complete
        GstStateChangeReturn ret = gst_element_get_state(m_pipeline, nullptr, nullptr, GST_SECOND);
        if (ret == GST_STATE_CHANGE_FAILURE) {
            qWarning() << "[AudioEngine::~AudioEngine] Failed to stop pipeline cleanly";
        }
    }
    
    cleanupPipeline();
    
    qDebug() << "[AudioEngine::~AudioEngine] Cleanup complete";
}

void AudioEngine::initializePipeline()
{
    m_playbin = gst_element_factory_make("playbin3", "playbin");
    if (!m_playbin) {
        qCritical() << "Failed to create playbin3 element";
        return;
    }
    
    m_pipeline = m_playbin;
    
    g_object_set(m_playbin, "buffer-size", 512 * 1024, nullptr);
    g_object_set(m_playbin, "buffer-duration", 2 * GST_SECOND, nullptr);
    
    // Create and configure replay gain element with audioconvert for format compatibility
    m_rgvolume = gst_element_factory_make("rgvolume", "rgvolume");
    if (m_rgvolume) {
        // Create audioconvert elements for format conversion
        GstElement* audioconvert1 = gst_element_factory_make("audioconvert", "audioconvert1");
        GstElement* audioconvert2 = gst_element_factory_make("audioconvert", "audioconvert2");
        
        if (audioconvert1 && audioconvert2) {
            // Create a bin to contain the audio filter pipeline
            m_audioFilterBin = gst_bin_new("audio-filter-bin");
            
            // Add elements to the bin
            gst_bin_add_many(GST_BIN(m_audioFilterBin), audioconvert1, m_rgvolume, audioconvert2, nullptr);
            
            // Link the elements: audioconvert1 -> rgvolume -> audioconvert2
            if (gst_element_link_many(audioconvert1, m_rgvolume, audioconvert2, nullptr)) {
                // Create ghost pads to expose the bin's sink and src
                GstPad* sinkPad = gst_element_get_static_pad(audioconvert1, "sink");
                GstPad* srcPad = gst_element_get_static_pad(audioconvert2, "src");
                
                GstPad* ghostSink = gst_ghost_pad_new("sink", sinkPad);
                GstPad* ghostSrc = gst_ghost_pad_new("src", srcPad);
                
                gst_pad_set_active(ghostSink, TRUE);
                gst_pad_set_active(ghostSrc, TRUE);
                
                gst_element_add_pad(m_audioFilterBin, ghostSink);
                gst_element_add_pad(m_audioFilterBin, ghostSrc);
                
                gst_object_unref(sinkPad);
                gst_object_unref(srcPad);
                
                // Set default replay gain properties
                g_object_set(m_rgvolume, 
                    "album-mode", FALSE,        // Start with track mode
                    "pre-amp", 0.0,            // No pre-amplification by default
                    "fallback-gain", 0.0,       // 0 dB fallback gain
                    nullptr);
                
                // Add a reference to keep the bin alive
                gst_object_ref(m_audioFilterBin);
                
                // Set the bin as the audio filter for playbin
                g_object_set(m_playbin, "audio-filter", m_audioFilterBin, nullptr);
                qDebug() << "[ReplayGain] GStreamer replay gain pipeline created successfully (audioconvert -> rgvolume -> audioconvert)";
            } else {
                qWarning() << "[ReplayGain] Failed to link audio filter elements";
                gst_object_unref(m_audioFilterBin);
                m_audioFilterBin = nullptr;
                m_rgvolume = nullptr;
            }
        } else {
            qWarning() << "[ReplayGain] Failed to create audioconvert elements for replay gain";
            if (audioconvert1) gst_object_unref(audioconvert1);
            if (audioconvert2) gst_object_unref(audioconvert2);
            gst_object_unref(m_rgvolume);
            m_rgvolume = nullptr;
        }
    } else {
        qWarning() << "[ReplayGain] Failed to create rgvolume element - replay gain will not be available";
        qWarning() << "[ReplayGain] Make sure gstreamer1.0-plugins-good is installed";
    }
    
    g_signal_connect(m_playbin, "about-to-finish", G_CALLBACK(aboutToFinishCallback), this);
    
    m_bus = gst_element_get_bus(m_pipeline);
    m_busWatchId = gst_bus_add_watch(m_bus, busCallback, this);
}

void AudioEngine::cleanupPipeline()
{
    if (m_positionTimer) {
        m_positionTimer->stop();
    }
    
    if (m_pipeline) {
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
    }
    
    if (m_busWatchId) {
        g_source_remove(m_busWatchId);
        m_busWatchId = 0;
    }
    
    if (m_bus) {
        gst_object_unref(m_bus);
        m_bus = nullptr;
    }
    
    if (m_audioFilterBin) {
        // Release our extra reference to the audio filter bin
        gst_object_unref(m_audioFilterBin);
        m_audioFilterBin = nullptr;
        m_rgvolume = nullptr;  // This was part of the bin, don't unref separately
    }
    
    if (m_pipeline) {
        gst_object_unref(m_pipeline);
        m_pipeline = nullptr;
        m_playbin = nullptr;
    }
}

void AudioEngine::loadTrack(const QString &filePath)
{
    if (!m_playbin) {
        emit error("Audio engine not initialized");
        return;
    }
    
    stop();
    
    m_currentTrack = filePath;
    m_hasQueuedTrack = false;  // Reset gapless tracking
    m_transitionPending = false;
    m_trackTransitionDetected = false;
    m_lastPosition = 0;
    m_lastKnownDuration = 0;  // Reset duration
    // No need to stop transition timer anymore
    if (m_transitionFallbackTimer) {
        m_transitionFallbackTimer->stop();
    }
    
    // Log replay gain status when loading a track
    if (m_rgvolume) {
        gboolean enabled = FALSE;
        gboolean albumMode = FALSE;
        gdouble preAmp = 0.0;
        gdouble fallbackGain = 0.0;
        
        // Check if audio filter bin is currently set as audio filter
        GstElement* currentFilter = nullptr;
        g_object_get(m_playbin, "audio-filter", &currentFilter, nullptr);
        enabled = (currentFilter == m_audioFilterBin);
        if (currentFilter) {
            gst_object_unref(currentFilter);
        }
        
        g_object_get(m_rgvolume, 
            "album-mode", &albumMode,
            "pre-amp", &preAmp,
            "fallback-gain", &fallbackGain,
            nullptr);
        
        qDebug() << "[ReplayGain] Loading track:" << QFileInfo(filePath).fileName();
        qDebug() << "[ReplayGain] Status: Enabled=" << enabled 
                 << "| Mode=" << (albumMode ? "Album" : "Track")
                 << "| PreAmp=" << preAmp << "dB"
                 << "| Fallback=" << fallbackGain << "dB";
    }
    
    QUrl url = QUrl::fromLocalFile(filePath);
    g_object_set(m_playbin, "uri", url.toString().toUtf8().constData(), nullptr);
    
    gst_element_set_state(m_pipeline, GST_STATE_READY);
    setState(State::Ready);
    
    GstState state;
    if (gst_element_get_state(m_pipeline, &state, nullptr, 2 * GST_SECOND) == GST_STATE_CHANGE_SUCCESS) {
        gint64 duration;
        if (gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration)) {
            m_lastKnownDuration = duration / GST_MSECOND;
            emit durationChanged(m_lastKnownDuration);
        }
    }
}

void AudioEngine::play()
{
    if (!m_pipeline || m_state == State::Null) {
        return;
    }
    
    if (gst_element_set_state(m_pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE) {
        setState(State::Playing);
        m_positionTimer->start();
        // Clear any pending seek state when resuming playback
        m_seekPending = false;
    }
}

void AudioEngine::pause()
{
    if (!m_pipeline || m_state != State::Playing) {
        return;
    }
    
    if (gst_element_set_state(m_pipeline, GST_STATE_PAUSED) != GST_STATE_CHANGE_FAILURE) {
        setState(State::Paused);
        m_positionTimer->stop();
    }
}

void AudioEngine::stop()
{
    if (!m_pipeline || m_state == State::Null || m_state == State::Stopped) {
        return;
    }
    
    m_positionTimer->stop();
    
    if (gst_element_set_state(m_pipeline, GST_STATE_READY) != GST_STATE_CHANGE_FAILURE) {
        setState(State::Stopped);
        emit positionChanged(0);
    }
}

void AudioEngine::seek(qint64 position)
{
    if (!m_pipeline || m_state == State::Null) {
        return;
    }
    
    // Track that we're seeking
    m_seekPending = true;
    m_seekTarget = position;
    
    gst_element_seek_simple(m_pipeline, GST_FORMAT_TIME, 
                           static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
                           position * GST_MSECOND);
    
    // Emit target position immediately for UI responsiveness
    emit positionChanged(position);
    
    // For paused state, also schedule a position query after a short delay
    // This handles cases where ASYNC_DONE might not be received
    if (m_state == State::Paused) {
        // Use a QPointer to ensure the object is still valid when the timer fires
        QPointer<AudioEngine> self = this;
        QTimer::singleShot(100, this, [self, position]() {
            if (!self) return;  // Object was destroyed
            // Only emit if we're still waiting for this seek to complete
            if (self->m_seekPending && self->m_seekTarget == position) {
                // Query actual position from GStreamer
                qint64 actualPos = self->position();
                // Only emit if position is reasonable (not 0 unless we're actually at the start)
                if (actualPos > 0 || position < 1000) {
                    emit self->positionChanged(actualPos);
                    self->m_seekPending = false;
                }
            }
        });
    }
}

qint64 AudioEngine::position() const
{
    if (!m_pipeline || m_state == State::Null) {
        return 0;
    }
    
    gint64 position;
    if (gst_element_query_position(m_pipeline, GST_FORMAT_TIME, &position)) {
        return position / GST_MSECOND;
    }
    
    return 0;
}

qint64 AudioEngine::duration() const
{
    if (!m_pipeline || m_state == State::Null) {
        return 0;
    }
    
    gint64 duration;
    if (gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration)) {
        return duration / GST_MSECOND;
    }
    
    return 0;
}

float AudioEngine::volume() const
{
    return m_volume;
}

void AudioEngine::setVolume(float volume)
{
    m_volume = qBound(0.0f, volume, 1.0f);
    
    if (m_playbin) {
        g_object_set(m_playbin, "volume", static_cast<double>(m_volume), nullptr);
    }
}

void AudioEngine::setState(State state)
{
    if (m_state != state) {
        m_state = state;
        emit stateChanged(state);
    }
}

void AudioEngine::updatePosition()
{
    emit positionChanged(position());
}

gboolean AudioEngine::busCallback(GstBus *bus, GstMessage *message, gpointer data)
{
    Q_UNUSED(bus)
    
    AudioEngine *engine = static_cast<AudioEngine*>(data);
    
    switch (GST_MESSAGE_TYPE(message)) {
    case GST_MESSAGE_EOS:
        engine->stop();
        emit engine->trackFinished();
        break;
    
    case GST_MESSAGE_TAG: {
        // Use TAG messages to detect track transitions during gapless playback
        // But with proper duration checking to ensure the transition actually happened
        if (engine->m_hasQueuedTrack && !engine->m_trackTransitionDetected) {
            GstTagList *tags = nullptr;
            gst_message_parse_tag(message, &tags);
            if (tags) {
                gchar *title = nullptr;
                if (gst_tag_list_get_string(tags, GST_TAG_TITLE, &title)) {
                    qDebug() << "[AudioEngine] TAG message with new title:" << title << "- checking duration change";
                    g_free(title);
                    
                    // Check if duration has changed (indicating new track metadata is available)
                    gint64 currentDuration;
                    if (gst_element_query_duration(engine->m_pipeline, GST_FORMAT_TIME, &currentDuration)) {
                        currentDuration = currentDuration / GST_MSECOND;
                        
                        if (engine->m_lastKnownDuration > 0 && 
                            abs(currentDuration - engine->m_lastKnownDuration) > 1000) {
                            // Duration changed - new track metadata is loaded
                            // But we need to wait for the actual audio transition
                            qDebug() << "[AudioEngine] Duration changed from" << engine->m_lastKnownDuration 
                                     << "to" << currentDuration << "- waiting for position reset";
                            
                            engine->m_transitionFallbackTimer->stop();
                            
                            // Start monitoring position for the actual transition
                            // The position should reset to near-zero when the new track actually starts
                            if (!engine->m_transitionTimer) {
                                engine->m_transitionTimer = new QTimer(engine);
                                engine->m_transitionTimer->setInterval(50);
                            }
                            
                            // Store the new duration for later
                            qint64 newDuration = currentDuration;
                            
                            // Disconnect any existing connections
                            QObject::disconnect(engine->m_transitionTimer, nullptr, nullptr, nullptr);
                            
                            // Monitor position until it resets
                            QObject::connect(engine->m_transitionTimer, &QTimer::timeout, engine, [engine, newDuration]() {
                                static int checkCount = 0;
                                static qint64 lastSeenPos = 0;
                                checkCount++;
                                
                                qint64 currentPos = engine->position();
                                
                                // Log every 10 checks (500ms)
                                if (checkCount % 10 == 0) {
                                    qDebug() << "[AudioEngine] Position check #" << checkCount << ":" << currentPos << "ms";
                                }
                                
                                // Detect when position resets to near beginning (actual transition)
                                if (lastSeenPos > 100000 && currentPos < 5000) {
                                    qDebug() << "[AudioEngine] Position reset detected - transition complete";
                                    
                                    engine->m_transitionTimer->stop();
                                    engine->m_trackTransitionDetected = true;
                                    engine->m_lastKnownDuration = newDuration;
                                    checkCount = 0;
                                    lastSeenPos = 0;
                                    
                                    // Now we can safely update the UI
                                    engine->m_hasQueuedTrack = false;
                                    engine->m_trackTransitionDetected = false;
                                    
                                    emit engine->trackTransitioned();
                                    emit engine->durationChanged(newDuration);
                                } 
                                // Also check if we've been monitoring for too long (2 seconds)
                                else if (checkCount > 40) {
                                    qDebug() << "[AudioEngine] Position monitoring timeout - using current state";
                                    
                                    engine->m_transitionTimer->stop();
                                    engine->m_trackTransitionDetected = true;
                                    engine->m_lastKnownDuration = newDuration;
                                    checkCount = 0;
                                    lastSeenPos = 0;
                                    
                                    engine->m_hasQueuedTrack = false;
                                    engine->m_trackTransitionDetected = false;
                                    
                                    emit engine->trackTransitioned();
                                    emit engine->durationChanged(newDuration);
                                }
                                
                                lastSeenPos = currentPos;
                            });
                            
                            engine->m_transitionTimer->start();
                            
                        } else if (engine->m_lastKnownDuration == 0) {
                            // First time getting duration, store it
                            engine->m_lastKnownDuration = currentDuration;
                            qDebug() << "[AudioEngine] Initial duration stored:" << currentDuration;
                        }
                    }
                }
                gst_tag_list_unref(tags);
            }
        }
        break;
    }
        
    case GST_MESSAGE_ERROR: {
        GError *error;
        gchar *debug;
        gst_message_parse_error(message, &error, &debug);
        
        QString errorMsg = QString("Audio error: %1").arg(error->message);
        qWarning() << errorMsg << "Debug:" << debug;
        
        emit engine->error(errorMsg);
        
        g_error_free(error);
        g_free(debug);
        
        engine->stop();
        break;
    }
    
    case GST_MESSAGE_STATE_CHANGED: {
        if (GST_MESSAGE_SRC(message) == GST_OBJECT(engine->m_pipeline)) {
            GstState oldState, newState, pending;
            gst_message_parse_state_changed(message, &oldState, &newState, &pending);
            
            if (newState == GST_STATE_PLAYING && oldState != GST_STATE_PLAYING) {
                gint64 duration;
                if (gst_element_query_duration(engine->m_pipeline, GST_FORMAT_TIME, &duration)) {
                    qint64 durationMs = duration / GST_MSECOND;
                    // Only update duration if we're not in a gapless transition
                    if (!engine->m_hasQueuedTrack) {
                        engine->m_lastKnownDuration = durationMs;
                        emit engine->durationChanged(durationMs);
                    }
                }
                
                // Log replay gain values that will be applied
                if (engine->m_rgvolume) {
                    gdouble targetGain = 0.0;
                    gdouble resultGain = 0.0;
                    g_object_get(engine->m_rgvolume,
                        "target-gain", &targetGain,
                        "result-gain", &resultGain,
                        nullptr);
                    
                    if (targetGain != 0.0 || resultGain != 0.0) {
                        qDebug() << "[ReplayGain] Applied gains - Target:" << targetGain << "dB | Result:" << resultGain << "dB";
                    } else {
                        qDebug() << "[ReplayGain] No replay gain tags found in track, using fallback gain";
                    }
                }
            }
        }
        break;
    }
    
    case GST_MESSAGE_ASYNC_DONE:
        // Async operation (like seek) completed
        if (engine->m_seekPending) {
            engine->m_seekPending = false;
            // Query and emit the actual position after seek completes
            emit engine->positionChanged(engine->position());
        }
        break;
    
    default:
        break;
    }
    
    return TRUE;
}

void AudioEngine::aboutToFinishCallback(GstElement *playbin, gpointer data)
{
    Q_UNUSED(playbin)
    
    AudioEngine *engine = static_cast<AudioEngine*>(data);
    emit engine->aboutToFinish();
    // Request the next track from the MediaPlayer
    emit engine->requestNextTrack();
}

void AudioEngine::setReplayGainEnabled(bool enabled)
{
    if (!m_rgvolume || !m_audioFilterBin) {
        qWarning() << "Replay gain not available - rgvolume element not created";
        return;
    }
    
    if (!m_playbin) {
        qWarning() << "Playbin not available";
        return;
    }
    
    if (enabled) {
        // Add reference before setting to prevent it from being freed
        gst_object_ref(m_audioFilterBin);
        // Re-add audio filter bin to enable replay gain
        g_object_set(m_playbin, "audio-filter", m_audioFilterBin, nullptr);
    } else {
        // Remove audio filter to disable replay gain
        // First check if it's currently set
        GstElement* currentFilter = nullptr;
        g_object_get(m_playbin, "audio-filter", &currentFilter, nullptr);
        if (currentFilter) {
            // Add reference to keep it alive after removal
            if (currentFilter == m_audioFilterBin) {
                gst_object_ref(m_audioFilterBin);
            }
            g_object_set(m_playbin, "audio-filter", nullptr, nullptr);
            gst_object_unref(currentFilter);
        }
    }
}

void AudioEngine::setReplayGainMode(bool albumMode)
{
    if (!m_rgvolume) {
        qWarning() << "Replay gain not available - rgvolume element not created";
        return;
    }
    
    g_object_set(m_rgvolume, "album-mode", albumMode ? TRUE : FALSE, nullptr);
}

void AudioEngine::setReplayGainPreAmp(double preAmp)
{
    if (!m_rgvolume) {
        qWarning() << "Replay gain not available - rgvolume element not created";
        return;
    }
    
    // Clamp pre-amp to reasonable range (-15 to +15 dB)
    preAmp = qBound(-15.0, preAmp, 15.0);
    g_object_set(m_rgvolume, "pre-amp", preAmp, nullptr);
}

void AudioEngine::setReplayGainFallbackGain(double fallbackGain)
{
    if (!m_rgvolume) {
        qWarning() << "Replay gain not available - rgvolume element not created";
        return;
    }
    
    // Clamp fallback gain to reasonable range (-15 to +15 dB)
    fallbackGain = qBound(-15.0, fallbackGain, 15.0);
    g_object_set(m_rgvolume, "fallback-gain", fallbackGain, nullptr);
}

void AudioEngine::queueNextTrack(const QString &filePath)
{
    if (!m_playbin) {
        qWarning() << "AudioEngine::queueNextTrack - playbin not initialized";
        return;
    }
    
    if (filePath.isEmpty()) {
        qDebug() << "[AudioEngine::queueNextTrack] No next track to queue";
        return;
    }
    
    QUrl url = QUrl::fromLocalFile(filePath);
    qDebug() << "[AudioEngine::queueNextTrack] Queuing next track for gapless playback:" << QFileInfo(filePath).fileName();
    
    // Mark that we have a queued track for gapless transition detection
    m_hasQueuedTrack = true;
    m_trackTransitionDetected = false;
    
    // Store current duration before transition
    gint64 duration;
    if (gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration)) {
        m_lastKnownDuration = duration / GST_MSECOND;
        qDebug() << "[AudioEngine::queueNextTrack] Current track duration:" << m_lastKnownDuration << "ms";
    }
    
    // Start fallback timer
    m_transitionFallbackTimer->start();
    
    qDebug() << "[AudioEngine::queueNextTrack] Waiting for duration change to detect transition";
    
    // Set the next URI for gapless playback
    g_object_set(m_playbin, "uri", url.toString().toUtf8().constData(), nullptr);
}