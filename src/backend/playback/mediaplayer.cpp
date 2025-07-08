#include "mediaplayer.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/library/librarymanager.h"
#include <QDebug>
#include <QFile>
#include <QDateTime>
#include <QTextStream>
#include <QStandardPaths>
#include <QDir>
#include <QTimer>
#include <QFileInfo>

QString MediaPlayer::getDebugLogPath()
{
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataPath); // Ensure the directory exists
    return QDir(dataPath).filePath("debug_log.txt");
}

MediaPlayer::MediaPlayer(QObject *parent)
    : QObject(parent)
    , m_audioEngine(std::make_unique<AudioEngine>(this))
    , m_saveStateTimer(new QTimer(this))
{
    setupConnections();
    
    // Set up periodic state saving every 10 seconds while playing
    m_saveStateTimer->setInterval(10000); // 10 seconds
    connect(m_saveStateTimer, &QTimer::timeout, this, &MediaPlayer::periodicStateSave);
    
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() << " - MediaPlayer initialized" << Qt::endl;
    }
    
    // MediaPlayer starts in a not-ready state
    m_isReady = false;
}

MediaPlayer::~MediaPlayer()
{
    // Cancel any pending restoration
    if (m_restoreConnection) {
        disconnect(m_restoreConnection);
    }
    clearRestorationState();
    
    // Clean up any remaining tracks in the queue
    clearQueue();
}

void MediaPlayer::setLibraryManager(Mtoc::LibraryManager* manager)
{
    m_libraryManager = manager;
    
    // Once we have a library manager, we're ready
    setReady(true);
}

void MediaPlayer::setupConnections()
{
    connect(m_audioEngine.get(), &AudioEngine::stateChanged,
            this, &MediaPlayer::onEngineStateChanged);
    
    connect(m_audioEngine.get(), &AudioEngine::positionChanged,
            this, &MediaPlayer::positionChanged);
    
    connect(m_audioEngine.get(), &AudioEngine::positionChanged,
            this, &MediaPlayer::checkPositionSync);
    
    connect(m_audioEngine.get(), &AudioEngine::durationChanged,
            this, [this](qint64 engineDuration) {
                // During restoration, be careful about duration signals from AudioEngine
                if (m_restoringState) {
                    // If we have a valid track duration already, don't let AudioEngine override it
                    if (m_currentTrack && m_currentTrack->duration() > 0) {
                        // Only emit if the engine duration matches what we expect
                        // (allow some tolerance for rounding)
                        qint64 expectedDuration = m_currentTrack->duration() * 1000;
                        if (qAbs(engineDuration - expectedDuration) < 1000) {
                            emit durationChanged(engineDuration);
                        }
                        return;
                    }
                    // Ignore zero duration during restoration
                    if (engineDuration == 0) {
                        qDebug() << "MediaPlayer: Ignoring zero duration during restoration";
                        return;
                    }
                }
                emit durationChanged(engineDuration);
            });
    
    connect(m_audioEngine.get(), &AudioEngine::trackFinished,
            this, &MediaPlayer::handleTrackFinished);
    
    connect(m_audioEngine.get(), &AudioEngine::error,
            this, &MediaPlayer::error);
}

MediaPlayer::State MediaPlayer::state() const
{
    return m_state;
}

qint64 MediaPlayer::position() const
{
    return m_audioEngine->position();
}

qint64 MediaPlayer::duration() const
{
    // If we have a current track with a valid duration, use that (convert seconds to milliseconds)
    if (m_currentTrack && m_currentTrack->duration() > 0) {
        return m_currentTrack->duration() * 1000;
    }
    
    // Fall back to AudioEngine duration
    return m_audioEngine->duration();
}

float MediaPlayer::volume() const
{
    return m_audioEngine->volume();
}

void MediaPlayer::setVolume(float volume)
{
    m_audioEngine->setVolume(volume);
    emit volumeChanged(volume);
}

bool MediaPlayer::hasNext() const
{
    return m_currentQueueIndex >= 0 && m_currentQueueIndex < m_playbackQueue.size() - 1;
}

bool MediaPlayer::hasPrevious() const
{
    // Only return true if we can actually go to a previous track
    // (i.e., we're not on the first track)
    return m_currentQueueIndex > 0 && m_playbackQueue.size() > 0;
}

void MediaPlayer::play()
{
    if (m_state == PausedState) {
        m_audioEngine->play();
    } else if (m_currentTrack && m_state == StoppedState) {
        m_audioEngine->loadTrack(m_currentTrack->filePath());
        m_audioEngine->play();
    }
}

void MediaPlayer::pause()
{
    if (m_state == PlayingState) {
        m_audioEngine->pause();
    }
}

void MediaPlayer::stop()
{
    m_audioEngine->stop();
    m_currentQueueIndex = -1;
    clearQueue();
}

void MediaPlayer::togglePlayPause()
{
    if (m_state == PlayingState) {
        pause();
    } else {
        play();
    }
}

void MediaPlayer::next()
{
    if (hasNext()) {
        m_currentQueueIndex++;
        Mtoc::Track* nextTrack = m_playbackQueue[m_currentQueueIndex];
        playTrack(nextTrack);
        emit playbackQueueChanged();
    }
}

void MediaPlayer::previous()
{
    if (position() > 3000) {
        seek(0);
    } else if (hasPrevious()) {
        m_currentQueueIndex--;
        Mtoc::Track* prevTrack = m_playbackQueue[m_currentQueueIndex];
        playTrack(prevTrack);
        emit playbackQueueChanged();
    } else {
        seek(0);
    }
}

void MediaPlayer::seek(qint64 position)
{
    m_audioEngine->seek(position);
}

void MediaPlayer::playTrack(Mtoc::Track* track)
{
    loadTrack(track, true);
}

void MediaPlayer::loadTrack(Mtoc::Track* track, bool autoPlay)
{
    if (!track) {
        qWarning() << "MediaPlayer::loadTrack called with null track";
        return;
    }
    
    // Log to file only to reduce overhead
    // qDebug() << "MediaPlayer::loadTrack called with track:" << track->title() 
    //          << "by" << track->artist() 
    //          << "path:" << track->filePath();
    
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Loading track: " << track->title() 
               << " by " << track->artist() 
               << " (autoPlay: " << autoPlay << ")" << Qt::endl;
    }
    
    updateCurrentTrack(track);
    
    // If we're restoring and the track has a duration, emit the signal immediately
    // This ensures QML gets the duration even before AudioEngine loads
    if (m_restoringState && track && track->duration() > 0) {
        qDebug() << "MediaPlayer: Emitting duration during restoration for track:" << track->title() 
                 << "duration:" << track->duration() * 1000 << "ms";
        emit durationChanged(track->duration() * 1000);
        
        // Also emit after a short delay to ensure QML bindings are updated
        QTimer::singleShot(100, this, [this, track]() {
            if (m_currentTrack == track && track->duration() > 0) {
                qDebug() << "MediaPlayer: Re-emitting duration after delay:" << track->duration() * 1000 << "ms";
                emit durationChanged(track->duration() * 1000);
            }
        });
    }
    
    // Clear saved position when loading a new track (unless we're restoring state)
    if (!m_restoringState) {
        clearSavedPosition();
        // Also clear any lingering restore state to prevent seeking to old positions
        m_targetRestorePosition = 0;
        if (m_restoreConnection) {
            disconnect(m_restoreConnection);
            m_restoreConnection = QMetaObject::Connection();
        }
    }
    
    QString filePath = track->filePath();
    if (filePath.isEmpty()) {
        qWarning() << "Track has empty file path!";
        return;
    }
    
    // qDebug() << "Loading track into audio engine:" << filePath;
    m_audioEngine->loadTrack(filePath);
    if (autoPlay) {
        m_audioEngine->play();
    }
}

void MediaPlayer::playAlbum(Mtoc::Album* album, int startIndex)
{
    if (!album || album->tracks().isEmpty()) {
        return;
    }
    
    // Clear any restoration state to prevent old positions from being applied
    clearRestorationState();
    clearSavedPosition();
    
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Playing album: " << album->title() 
               << " by " << album->artist() << Qt::endl;
    }
    
    clearQueue();
    
    m_currentAlbum = album;
    emit currentAlbumChanged(m_currentAlbum);
    
    m_playbackQueue = album->tracks();
    m_currentQueueIndex = qBound(0, startIndex, m_playbackQueue.size() - 1);
    
    emit playbackQueueChanged();
    
    if (!m_playbackQueue.isEmpty()) {
        playTrack(m_playbackQueue[m_currentQueueIndex]);
    }
}

void MediaPlayer::clearQueue()
{
    // Clean up any tracks we created
    for (auto track : m_playbackQueue) {
        if (track && track->parent() == this) {
            track->deleteLater();
        }
    }
    m_playbackQueue.clear();
    m_currentQueueIndex = -1;
    emit playbackQueueChanged();
}

void MediaPlayer::playAlbumByName(const QString& artist, const QString& title, int startIndex)
{
    qDebug() << "MediaPlayer::playAlbumByName called with artist:" << artist << "title:" << title << "startIndex:" << startIndex;
    
    if (!m_libraryManager) {
        qWarning() << "LibraryManager not set on MediaPlayer";
        return;
    }
    
    // Clear any restoration state to prevent old positions from being applied
    clearRestorationState();
    clearSavedPosition();
    
    // Debug: Check library state
    qDebug() << "LibraryManager album count:" << m_libraryManager->albumCount();
    qDebug() << "LibraryManager track count:" << m_libraryManager->trackCount();
    
    // Since albumByTitle might not work with deferred loading, let's use a different approach
    // Get tracks for the album and create a temporary queue
    qDebug() << "Calling getTracksForAlbumAsVariantList with artist:" << artist << "title:" << title;
    auto trackList = m_libraryManager->getTracksForAlbumAsVariantList(artist, title);
    qDebug() << "Found" << trackList.size() << "tracks for album via getTracksForAlbumAsVariantList";
    
    if (!trackList.isEmpty()) {
        // Clear current queue and set up new one
        clearQueue();
        
        // Set the current album info
        m_currentAlbum = nullptr; // We don't have the actual album object
        
        // Build the queue from track data
        for (const auto& trackData : trackList) {
            auto trackMap = trackData.toMap();
            QString title = trackMap.value("title").toString();
            QString filePath = trackMap.value("filePath").toString();
            
            if (filePath.isEmpty()) {
                qWarning() << "Empty filePath for track:" << title;
                continue;
            }
            
            // Create a new Track object from the data
            Mtoc::Track* track = new Mtoc::Track(this);
            track->setTitle(title);
            track->setArtist(trackMap.value("artist").toString());
            track->setAlbum(trackMap.value("album").toString());
            track->setAlbumArtist(trackMap.value("albumArtist").toString());
            track->setTrackNumber(trackMap.value("trackNumber").toInt());
            track->setDuration(trackMap.value("duration").toInt());
            track->setFileUrl(QUrl::fromLocalFile(filePath));
            
            m_playbackQueue.append(track);
        }
        
        qDebug() << "Built queue with" << m_playbackQueue.size() << "tracks";
        
        if (!m_playbackQueue.isEmpty() && startIndex < m_playbackQueue.size()) {
            m_currentQueueIndex = startIndex;
            emit playbackQueueChanged();
            playTrack(m_playbackQueue[startIndex]);
        }
    } else {
        qWarning() << "No tracks found for album:" << artist << "-" << title;
    }
}

void MediaPlayer::playTrackFromData(const QVariant& trackData)
{
    auto trackMap = trackData.toMap();
    QString title = trackMap.value("title").toString();
    QString filePath = trackMap.value("filePath").toString();
    
    qDebug() << "MediaPlayer::playTrackFromData called with track:" << title << "path:" << filePath;
    
    if (filePath.isEmpty()) {
        qWarning() << "Empty filePath for track:" << title;
        return;
    }
    
    // Clear any restoration state to prevent old positions from being applied
    clearRestorationState();
    clearSavedPosition();
    
    // Clear any existing queue
    clearQueue();
    
    // Create a new Track object from the data
    Mtoc::Track* track = new Mtoc::Track(this);
    track->setTitle(title);
    track->setArtist(trackMap.value("artist").toString());
    track->setAlbum(trackMap.value("album").toString());
    track->setAlbumArtist(trackMap.value("albumArtist").toString());
    track->setTrackNumber(trackMap.value("trackNumber").toInt());
    track->setDuration(trackMap.value("duration").toInt());
    track->setFileUrl(QUrl::fromLocalFile(filePath));
    
    // Add to queue so it gets cleaned up properly
    m_playbackQueue.append(track);
    m_currentQueueIndex = 0;
    
    // Play the single track
    playTrack(track);
    
    emit playbackQueueChanged();
}

void MediaPlayer::updateCurrentTrack(Mtoc::Track* track)
{
    if (m_currentTrack != track) {
        m_currentTrack = track;
        emit currentTrackChanged(track);
        
        // If we're not playing from an album queue, clear the current album
        if (m_playbackQueue.isEmpty() || !m_playbackQueue.contains(track)) {
            if (m_currentAlbum) {
                m_currentAlbum = nullptr;
                emit currentAlbumChanged(nullptr);
            }
        }
    }
}

void MediaPlayer::handleTrackFinished()
{
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Track finished, checking for next track" << Qt::endl;
    }
    
    if (hasNext()) {
        next();
    } else {
        m_state = StoppedState;
        emit stateChanged(m_state);
    }
}

void MediaPlayer::onEngineStateChanged(AudioEngine::State state)
{
    State newState = StoppedState;
    
    switch (state) {
    case AudioEngine::State::Playing:
        newState = PlayingState;
        break;
    case AudioEngine::State::Paused:
        newState = PausedState;
        break;
    default:
        newState = StoppedState;
        break;
    }
    
    if (m_state != newState) {
        m_state = newState;
        emit stateChanged(m_state);
        
        // Manage periodic save timer based on state
        if (m_state == PlayingState) {
            m_saveStateTimer->start();
            // Save immediately when starting playback
            saveState();
        } else {
            m_saveStateTimer->stop();
            // Save state when pausing or stopping
            if (m_state == PausedState || (m_state == StoppedState && m_currentTrack)) {
                saveState();
            }
        }
    }
}

void MediaPlayer::saveState()
{
    if (!m_libraryManager || !m_currentTrack) {
        qDebug() << "MediaPlayer::saveState - no current track or library manager";
        return;
    }
    
    QString filePath = m_currentTrack->filePath();
    qint64 currentPosition = position();
    
    // Get album info if playing from an album
    QString albumArtist;
    QString albumTitle;
    int trackIndex = m_currentQueueIndex;
    
    if (m_currentAlbum) {
        albumArtist = m_currentAlbum->artist();
        albumTitle = m_currentAlbum->title();
    } else if (!m_playbackQueue.isEmpty() && m_currentQueueIndex >= 0) {
        // We're playing from a queue but don't have album object
        // Try to get album info from the current track
        albumArtist = m_currentTrack->albumArtist();
        if (albumArtist.isEmpty()) {
            albumArtist = m_currentTrack->artist();
        }
        albumTitle = m_currentTrack->album();
    }
    
    // Get the duration
    qint64 trackDuration = duration(); // This already handles both track and engine duration
    
    // Save the state
    m_libraryManager->savePlaybackState(filePath, currentPosition, 
                                        albumArtist, albumTitle, trackIndex, trackDuration);
    
    // qDebug() << "MediaPlayer::saveState - saved state for track:" << m_currentTrack->title()
    //         << "position:" << currentPosition << "ms";
}

void MediaPlayer::restoreState()
{
    // Prevent multiple restoration attempts
    if (m_restoringState) {
        qDebug() << "MediaPlayer::restoreState - restoration already in progress";
        return;
    }
    
    if (!m_isReady) {
        qDebug() << "MediaPlayer::restoreState - system not ready, deferring restoration";
        // Wait for system to be ready
        connect(this, &MediaPlayer::readyChanged, this, [this](bool ready) {
            if (ready) {
                disconnect(this, &MediaPlayer::readyChanged, this, nullptr);
                restoreState();
            }
        });
        return;
    }
    
    if (!m_libraryManager) {
        qDebug() << "MediaPlayer::restoreState - no library manager";
        return;
    }
    
    QVariantMap state = m_libraryManager->loadPlaybackState();
    if (state.isEmpty()) {
        qDebug() << "MediaPlayer::restoreState - no saved state found";
        clearRestorationState();
        return;
    }
    
    QString filePath = state["filePath"].toString();
    qint64 savedPosition = state["position"].toLongLong();
    qint64 savedDuration = state["duration"].toLongLong();
    QString albumArtist = state["albumArtist"].toString();
    QString albumTitle = state["albumTitle"].toString();
    int trackIndex = state["trackIndex"].toInt();
    
    // qDebug() << "MediaPlayer::restoreState - restoring track:" << filePath
    //          << "position:" << savedPosition << "ms"
    //          << "album:" << albumArtist << "-" << albumTitle
    //          << "index:" << trackIndex;
    
    // Validate file exists before attempting restoration
    QFileInfo fileInfo(filePath);
    if (!fileInfo.exists()) {
        qWarning() << "MediaPlayer::restoreState - saved file no longer exists:" << filePath;
        clearRestorationState();
        return;
    }
    
    // Set restoration state
    m_restoringState = true;
    m_savedPosition = savedPosition;
    m_targetRestorePosition = savedPosition;
    emit restoringStateChanged(true);
    emit savedPositionChanged(m_savedPosition);
    
    try {
        // If we have album info, try to restore the album queue
        if (!albumArtist.isEmpty() && !albumTitle.isEmpty()) {
            // Load the album without auto-playing
            restoreAlbumByName(albumArtist, albumTitle, trackIndex, savedPosition);
        } else {
            // Just load the single track without auto-playing
            restoreTrackFromData(filePath, savedPosition, savedDuration);
        }
    } catch (const std::exception& e) {
        qWarning() << "MediaPlayer::restoreState - exception during restoration:" << e.what();
        clearRestorationState();
    }
}

void MediaPlayer::periodicStateSave()
{
    if (m_state == PlayingState) {
        saveState();
    }
}

void MediaPlayer::restoreAlbumByName(const QString& artist, const QString& title, int trackIndex, qint64 position)
{
    qDebug() << "MediaPlayer::restoreAlbumByName called with artist:" << artist << "title:" << title << "trackIndex:" << trackIndex;
    
    if (!m_libraryManager) {
        qWarning() << "LibraryManager not set on MediaPlayer";
        return;
    }
    
    // Get tracks for the album and create a temporary queue
    auto trackList = m_libraryManager->getTracksForAlbumAsVariantList(artist, title);
    qDebug() << "Found" << trackList.size() << "tracks for album via getTracksForAlbumAsVariantList";
    
    if (!trackList.isEmpty()) {
        // Clear current queue and set up new one
        clearQueue();
        
        // Set the current album info
        m_currentAlbum = nullptr; // We don't have the actual album object
        
        // Build the queue from track data
        for (const auto& trackData : trackList) {
            auto trackMap = trackData.toMap();
            QString title = trackMap.value("title").toString();
            QString filePath = trackMap.value("filePath").toString();
            
            if (filePath.isEmpty()) {
                qWarning() << "Empty filePath for track:" << title;
                continue;
            }
            
            // Create a new Track object from the data
            Mtoc::Track* track = new Mtoc::Track(this);
            track->setTitle(title);
            track->setArtist(trackMap.value("artist").toString());
            track->setAlbum(trackMap.value("album").toString());
            track->setAlbumArtist(trackMap.value("albumArtist").toString());
            track->setTrackNumber(trackMap.value("trackNumber").toInt());
            track->setDuration(trackMap.value("duration").toInt());
            track->setFileUrl(QUrl::fromLocalFile(filePath));
            
            m_playbackQueue.append(track);
        }
        
        qDebug() << "Built queue with" << m_playbackQueue.size() << "tracks";
        
        if (!m_playbackQueue.isEmpty() && trackIndex < m_playbackQueue.size()) {
            m_currentQueueIndex = trackIndex;
            emit playbackQueueChanged();
            
            // Set up connection to handle when track is loaded
            if (m_restoreConnection) {
                disconnect(m_restoreConnection);
            }
            
            m_restoreConnection = connect(m_audioEngine.get(), &AudioEngine::durationChanged, this, [this]() {
                if (m_audioEngine->duration() > 0) {
                    qDebug() << "MediaPlayer: Track loaded for restoration, duration:" << m_audioEngine->duration();
                    // Track is loaded, disconnect and handle restoration
                    disconnect(m_restoreConnection);
                    m_restoreConnection = QMetaObject::Connection();
                    onTrackLoadedForRestore();
                }
            });
            
            // Load track without auto-playing
            loadTrack(m_playbackQueue[trackIndex], false);
        }
    } else {
        qWarning() << "No tracks found for album:" << artist << "-" << title;
        // Clear restoration state if album not found
        clearRestorationState();
    }
}

void MediaPlayer::restoreTrackFromData(const QString& filePath, qint64 position, qint64 duration)
{
    qDebug() << "MediaPlayer::restoreTrackFromData called with path:" << filePath << "duration:" << duration;
    
    if (filePath.isEmpty()) {
        qWarning() << "Empty filePath for track";
        return;
    }
    
    // Clear any existing queue
    clearQueue();
    
    // Create a new Track object from the data
    Mtoc::Track* track = new Mtoc::Track(this);
    track->setTitle(QFileInfo(filePath).baseName()); // Fallback title
    track->setFileUrl(QUrl::fromLocalFile(filePath));
    
    // Set the duration from saved state (convert ms to seconds)
    if (duration > 0) {
        qDebug() << "Restoring track with duration:" << duration << "ms";
        track->setDuration(duration / 1000);
    }
    
    // Add to queue so it gets cleaned up properly
    m_playbackQueue.append(track);
    m_currentQueueIndex = 0;
    
    // Set up connection to handle when track is loaded
    if (m_restoreConnection) {
        disconnect(m_restoreConnection);
    }
    
    m_restoreConnection = connect(m_audioEngine.get(), &AudioEngine::durationChanged, this, [this]() {
        if (m_audioEngine->duration() > 0) {
            // Track is loaded, disconnect and handle restoration
            disconnect(m_restoreConnection);
            m_restoreConnection = QMetaObject::Connection();
            onTrackLoadedForRestore();
        }
    });
    
    // Load the single track without auto-playing
    loadTrack(track, false);
    
    emit playbackQueueChanged();
}

void MediaPlayer::clearRestorationState()
{
    m_restoringState = false;
    m_targetRestorePosition = 0;
    emit restoringStateChanged(false);
    
    // Disconnect any pending restore connections
    if (m_restoreConnection) {
        disconnect(m_restoreConnection);
        m_restoreConnection = QMetaObject::Connection();
    }
    
    // Emit duration changed to ensure QML gets the correct duration
    // Now that restoration is complete, the duration() method will return the correct value
    if (m_currentTrack) {
        emit durationChanged(duration());
    }
    
    // Don't clear savedPosition immediately - let it persist until position syncs
    qDebug() << "MediaPlayer: Restoration state cleared, savedPosition preserved at:" << m_savedPosition;
}

void MediaPlayer::clearSavedPosition()
{
    if (m_savedPosition != 0) {
        qDebug() << "MediaPlayer: Clearing saved position, was:" << m_savedPosition;
        m_savedPosition = 0;
        emit savedPositionChanged(0);
    }
}

void MediaPlayer::checkPositionSync()
{
    // If we have a saved position and it's significantly different from current position,
    // check if we should clear it
    if (m_savedPosition > 0 && !m_restoringState) {
        qint64 currentPos = position();
        qint64 diff = qAbs(currentPos - m_savedPosition);
        
        // If positions are close (within 1 second) or if we're playing and position has moved significantly
        if (diff < 1000 || (m_state == PlayingState && currentPos > m_savedPosition + 5000)) {
            clearSavedPosition();
        }
    }
}

void MediaPlayer::setReady(bool ready)
{
    if (m_isReady != ready) {
        m_isReady = ready;
        emit readyChanged(ready);
        qDebug() << "MediaPlayer: Ready state changed to:" << ready;
    }
}

void MediaPlayer::onTrackLoadedForRestore()
{
    // This slot is called when a track is successfully loaded during restoration
    
    if (m_targetRestorePosition > 0 && m_audioEngine && m_audioEngine->duration() > 0) {
        qDebug() << "MediaPlayer: Seeking to restored position:" << m_targetRestorePosition;
        seek(m_targetRestorePosition);
    } else {
        qDebug() << "MediaPlayer: No position to restore or track not ready";
    }
    
    // Clear restoration state - UI will handle smooth transition
    clearRestorationState();
}

void MediaPlayer::onTrackLoadTimeout()
{
    qWarning() << "MediaPlayer: Track load timeout during restoration";
    clearRestorationState();
}