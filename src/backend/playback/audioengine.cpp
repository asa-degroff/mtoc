#include "audioengine.h"
#include <QTimer>
#include <QDebug>
#include <QUrl>

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
}

AudioEngine::~AudioEngine()
{
    cleanupPipeline();
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
    
    QUrl url = QUrl::fromLocalFile(filePath);
    g_object_set(m_playbin, "uri", url.toString().toUtf8().constData(), nullptr);
    
    gst_element_set_state(m_pipeline, GST_STATE_READY);
    setState(State::Ready);
    
    GstState state;
    if (gst_element_get_state(m_pipeline, &state, nullptr, 2 * GST_SECOND) == GST_STATE_CHANGE_SUCCESS) {
        gint64 duration;
        if (gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration)) {
            emit durationChanged(duration / GST_MSECOND);
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
        QTimer::singleShot(100, this, [this, position]() {
            // Only emit if we're still waiting for this seek to complete
            if (m_seekPending && m_seekTarget == position) {
                // Query actual position from GStreamer
                qint64 actualPos = this->position();
                // Only emit if position is reasonable (not 0 unless we're actually at the start)
                if (actualPos > 0 || position < 1000) {
                    emit positionChanged(actualPos);
                    m_seekPending = false;
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
                    emit engine->durationChanged(duration / GST_MSECOND);
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
}