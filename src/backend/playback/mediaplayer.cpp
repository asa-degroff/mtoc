#include "mediaplayer.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/library/librarymanager.h"
#include "backend/settings/settingsmanager.h"
#include <QDebug>
#include <QFile>
#include <QDateTime>
#include <QTextStream>
#include <QStandardPaths>
#include <QDir>
#include <QTimer>
#include <QFileInfo>
#include <QVariantList>
#include <QVariantMap>

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

void MediaPlayer::setSettingsManager(SettingsManager* settingsManager)
{
    m_settingsManager = settingsManager;
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

QVariantList MediaPlayer::queue() const
{
    QVariantList queueList;
    for (Mtoc::Track* track : m_playbackQueue) {
        if (track) {
            QVariantMap trackMap;
            trackMap["title"] = track->title();
            trackMap["artist"] = track->artist();
            trackMap["album"] = track->album();
            trackMap["duration"] = track->duration() * 1000; // Convert seconds to milliseconds
            trackMap["filePath"] = track->filePath();
            queueList.append(trackMap);
        }
    }
    return queueList;
}

int MediaPlayer::totalQueueDuration() const
{
    int totalSeconds = 0;
    for (Mtoc::Track* track : m_playbackQueue) {
        if (track) {
            totalSeconds += track->duration();
        }
    }
    return totalSeconds;
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
    updateCurrentTrack(nullptr);
    clearQueue();
    
    // Clear the saved playback state when stopping
    if (m_libraryManager) {
        m_libraryManager->clearPlaybackState();
    }
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
                
                // Re-emit position to update progress bar visual position
                if (m_savedPosition > 0) {
                    emit savedPositionChanged(m_savedPosition);
                }
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
    } else {
        // Ensure we maintain paused state when not auto-playing
        m_state = PausedState;
        emit stateChanged(m_state);
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
    
    // Clear the queue modified flag when playing a full album
    setQueueModified(false);
    
    emit playbackQueueChanged();
    
    if (!m_playbackQueue.isEmpty()) {
        playTrack(m_playbackQueue[m_currentQueueIndex]);
    }
}

void MediaPlayer::removeTrackAt(int index)
{
    if (index < 0 || index >= m_playbackQueue.size()) {
        qWarning() << "removeTrackAt: Invalid index" << index;
        return;
    }
    
    qDebug() << "MediaPlayer::removeTrackAt called with index:" << index;
    
    // Mark queue as modified when removing tracks
    setQueueModified(true);
    
    // Get the track to remove
    Mtoc::Track* trackToRemove = m_playbackQueue[index];
    
    // Handle removal based on position relative to current track
    if (index == m_currentQueueIndex) {
        // Removing the currently playing track
        // Remember if we were paused
        bool wasPaused = (m_state == PausedState);
        
        if (hasNext()) {
            // Play next track (index stays the same after removal)
            m_playbackQueue.removeAt(index);
            if (trackToRemove && trackToRemove->parent() == this) {
                trackToRemove->deleteLater();
            }
            emit playbackQueueChanged();
            
            // Load the track but don't auto-play if we were paused
            loadTrack(m_playbackQueue[m_currentQueueIndex], !wasPaused);
        } else if (m_currentQueueIndex > 0) {
            // No next track, play previous
            m_playbackQueue.removeAt(index);
            if (trackToRemove && trackToRemove->parent() == this) {
                trackToRemove->deleteLater();
            }
            m_currentQueueIndex--;
            emit playbackQueueChanged();
            
            // Load the track but don't auto-play if we were paused
            loadTrack(m_playbackQueue[m_currentQueueIndex], !wasPaused);
        } else {
            // No other tracks, stop playback
            m_playbackQueue.removeAt(index);
            if (trackToRemove && trackToRemove->parent() == this) {
                trackToRemove->deleteLater();
            }
            m_currentQueueIndex = -1;
            emit playbackQueueChanged();
            stop();
        }
    } else if (index < m_currentQueueIndex) {
        // Removing a track before the current one
        m_playbackQueue.removeAt(index);
        if (trackToRemove && trackToRemove->parent() == this) {
            trackToRemove->deleteLater();
        }
        m_currentQueueIndex--;
        emit playbackQueueChanged();
    } else {
        // Removing a track after the current one
        m_playbackQueue.removeAt(index);
        if (trackToRemove && trackToRemove->parent() == this) {
            trackToRemove->deleteLater();
        }
        emit playbackQueueChanged();
    }
}

void MediaPlayer::playTrackAt(int index)
{
    if (index < 0 || index >= m_playbackQueue.size()) {
        qWarning() << "playTrackAt: Invalid index" << index;
        return;
    }
    
    qDebug() << "MediaPlayer::playTrackAt called with index:" << index;
    
    m_currentQueueIndex = index;
    emit playbackQueueChanged();
    playTrack(m_playbackQueue[index]);
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
    setQueueModified(false);
    
    // Also clear undo queue
    clearUndoQueue();
    
    emit playbackQueueChanged();
}

void MediaPlayer::clearQueueForUndo()
{
    // Save current queue state for undo
    m_undoQueue = m_playbackQueue;
    m_undoQueueIndex = m_currentQueueIndex;
    m_undoCurrentTrack = m_currentTrack;
    m_undoQueueModified = m_isQueueModified;
    
    // Stop audio playback without clearing the queue
    m_audioEngine->stop();
    
    // Clear the current queue without deleting tracks
    m_playbackQueue.clear();
    m_currentQueueIndex = -1;
    updateCurrentTrack(nullptr);
    setQueueModified(false);
    
    emit playbackQueueChanged();
    emit canUndoClearChanged(true);
    
    // Clear the saved playback state
    if (m_libraryManager) {
        m_libraryManager->clearPlaybackState();
    }
}

void MediaPlayer::undoClearQueue()
{
    if (m_undoQueue.isEmpty()) {
        return;
    }
    
    // Restore the queue
    m_playbackQueue = m_undoQueue;
    m_currentQueueIndex = m_undoQueueIndex;
    m_currentTrack = m_undoCurrentTrack;
    setQueueModified(m_undoQueueModified);
    
    // Clear undo state
    m_undoQueue.clear();
    m_undoQueueIndex = -1;
    m_undoCurrentTrack = nullptr;
    m_undoQueueModified = false;
    
    // Emit signals
    emit playbackQueueChanged();
    emit currentTrackChanged(m_currentTrack);
    emit canUndoClearChanged(false);
    
    // If we have a current track, ensure it's loaded but paused
    if (m_currentTrack) {
        loadTrack(m_currentTrack, false);
    }
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

void MediaPlayer::clearUndoQueue()
{
    if (!m_undoQueue.isEmpty()) {
        for (auto track : m_undoQueue) {
            if (track && track->parent() == this) {
                track->deleteLater();
            }
        }
        m_undoQueue.clear();
        m_undoQueueIndex = -1;
        m_undoCurrentTrack = nullptr;
        m_undoQueueModified = false;
        emit canUndoClearChanged(false);
    }
}

void MediaPlayer::playTrackNext(const QVariant& trackData)
{
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    auto trackMap = trackData.toMap();
    QString title = trackMap.value("title").toString();
    QString filePath = trackMap.value("filePath").toString();
    
    qDebug() << "MediaPlayer::playTrackNext called with track:" << title;
    
    if (filePath.isEmpty()) {
        qWarning() << "Empty filePath for track:" << title;
        return;
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
    
    // Insert after current track, or at beginning if nothing is playing
    int insertIndex = (m_currentQueueIndex >= 0) ? m_currentQueueIndex + 1 : 0;
    m_playbackQueue.insert(insertIndex, track);
    
    // Mark queue as modified when adding individual tracks
    setQueueModified(true);
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::playTrackLast(const QVariant& trackData)
{
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    auto trackMap = trackData.toMap();
    QString title = trackMap.value("title").toString();
    QString filePath = trackMap.value("filePath").toString();
    
    qDebug() << "MediaPlayer::playTrackLast called with track:" << title;
    
    if (filePath.isEmpty()) {
        qWarning() << "Empty filePath for track:" << title;
        return;
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
    
    // Append to end of queue
    m_playbackQueue.append(track);
    
    // Mark queue as modified when adding individual tracks
    setQueueModified(true);
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::playAlbumNext(const QString& artist, const QString& title)
{
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    qDebug() << "MediaPlayer::playAlbumNext called with artist:" << artist << "title:" << title;
    
    if (!m_libraryManager) {
        qWarning() << "LibraryManager not set on MediaPlayer";
        return;
    }
    
    auto trackList = m_libraryManager->getTracksForAlbumAsVariantList(artist, title);
    qDebug() << "Found" << trackList.size() << "tracks for album";
    
    if (trackList.isEmpty()) {
        qWarning() << "No tracks found for album:" << artist << "-" << title;
        return;
    }
    
    // Insert position: after current track, or at beginning if nothing is playing
    int insertIndex = (m_currentQueueIndex >= 0) ? m_currentQueueIndex + 1 : 0;
    
    // Build tracks from data and insert into queue
    for (const auto& trackData : trackList) {
        auto trackMap = trackData.toMap();
        QString trackTitle = trackMap.value("title").toString();
        QString filePath = trackMap.value("filePath").toString();
        
        if (filePath.isEmpty()) {
            qWarning() << "Empty filePath for track:" << trackTitle;
            continue;
        }
        
        Mtoc::Track* track = new Mtoc::Track(this);
        track->setTitle(trackTitle);
        track->setArtist(trackMap.value("artist").toString());
        track->setAlbum(trackMap.value("album").toString());
        track->setAlbumArtist(trackMap.value("albumArtist").toString());
        track->setTrackNumber(trackMap.value("trackNumber").toInt());
        track->setDuration(trackMap.value("duration").toInt());
        track->setFileUrl(QUrl::fromLocalFile(filePath));
        
        m_playbackQueue.insert(insertIndex++, track);
    }
    
    // Mark queue as modified when adding albums to existing queue
    setQueueModified(true);
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::playAlbumLast(const QString& artist, const QString& title)
{
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    qDebug() << "MediaPlayer::playAlbumLast called with artist:" << artist << "title:" << title;
    
    if (!m_libraryManager) {
        qWarning() << "LibraryManager not set on MediaPlayer";
        return;
    }
    
    auto trackList = m_libraryManager->getTracksForAlbumAsVariantList(artist, title);
    qDebug() << "Found" << trackList.size() << "tracks for album";
    
    if (trackList.isEmpty()) {
        qWarning() << "No tracks found for album:" << artist << "-" << title;
        return;
    }
    
    // Build tracks from data and append to queue
    for (const auto& trackData : trackList) {
        auto trackMap = trackData.toMap();
        QString trackTitle = trackMap.value("title").toString();
        QString filePath = trackMap.value("filePath").toString();
        
        if (filePath.isEmpty()) {
            qWarning() << "Empty filePath for track:" << trackTitle;
            continue;
        }
        
        Mtoc::Track* track = new Mtoc::Track(this);
        track->setTitle(trackTitle);
        track->setArtist(trackMap.value("artist").toString());
        track->setAlbum(trackMap.value("album").toString());
        track->setAlbumArtist(trackMap.value("albumArtist").toString());
        track->setTrackNumber(trackMap.value("trackNumber").toInt());
        track->setDuration(trackMap.value("duration").toInt());
        track->setFileUrl(QUrl::fromLocalFile(filePath));
        
        m_playbackQueue.append(track);
    }
    
    // Mark queue as modified when adding albums to existing queue
    setQueueModified(true);
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
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
    case AudioEngine::State::Ready:
        // When AudioEngine is Ready (track loaded but not playing), keep current state
        // This prevents resetting to StoppedState during restoration
        if (m_restoringState) {
            return;
        }
        // Fall through to default for non-restoration cases
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
    
    // Prepare queue data if queue is modified
    QVariantList queueData;
    if (m_isQueueModified && !m_playbackQueue.isEmpty()) {
        for (Mtoc::Track* track : m_playbackQueue) {
            if (track) {
                QVariantMap trackMap;
                trackMap["filePath"] = track->filePath();
                trackMap["title"] = track->title();
                trackMap["artist"] = track->artist();
                trackMap["album"] = track->album();
                trackMap["albumArtist"] = track->albumArtist();
                trackMap["trackNumber"] = track->trackNumber();
                trackMap["duration"] = track->duration();
                queueData.append(trackMap);
            }
        }
    }
    
    // Save the state
    m_libraryManager->savePlaybackState(filePath, currentPosition, 
                                        albumArtist, albumTitle, trackIndex, trackDuration,
                                        m_isQueueModified, queueData);
    
    // qDebug() << "MediaPlayer::saveState - saved state for track:" << m_currentTrack->title()
    //         << "position:" << currentPosition << "ms"
    //         << "queueModified:" << m_isQueueModified
    //         << "queueSize:" << queueData.size();
}

void MediaPlayer::restoreState()
{
    // Check if restoration is enabled in settings
    if (m_settingsManager && !m_settingsManager->restorePlaybackPosition()) {
        qDebug() << "MediaPlayer::restoreState - playback restoration disabled in settings";
        return;
    }
    
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
    bool queueModified = state["queueModified"].toBool();
    QVariantList queueData = state["queue"].toList();
    
    // qDebug() << "MediaPlayer::restoreState - restoring track:" << filePath
    //          << "position:" << savedPosition << "ms"
    //          << "album:" << albumArtist << "-" << albumTitle
    //          << "index:" << trackIndex
    //          << "queueModified:" << queueModified
    //          << "queueSize:" << queueData.size();
    
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
        // If we have a modified queue, restore it
        if (queueModified && !queueData.isEmpty()) {
            // Clear current queue and restore from saved data
            clearQueue();
            
            // Build the queue from saved data
            for (const auto& trackData : queueData) {
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
            
            // Restore the modified flag
            setQueueModified(true);
            
            // Set the current queue index
            if (trackIndex >= 0 && trackIndex < m_playbackQueue.size()) {
                m_currentQueueIndex = trackIndex;
                emit playbackQueueChanged();
                
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
                
                // Load track without auto-playing
                loadTrack(m_playbackQueue[trackIndex], false);
            }
        } else if (!albumArtist.isEmpty() && !albumTitle.isEmpty()) {
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
        
        // Re-emit savedPosition to force progress bar update with correct duration
        if (m_savedPosition > 0) {
            emit savedPositionChanged(m_savedPosition);
        }
    }
}

void MediaPlayer::clearSavedPosition()
{
    if (m_savedPosition != 0) {
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
        // First seek to the saved position
        seek(m_targetRestorePosition);
        
        // Check if the AudioEngine is already playing (user clicked play during restoration)
        if (m_audioEngine->state() == AudioEngine::State::Playing) {
            m_state = PlayingState;
            emit stateChanged(m_state);
        } else {
            // Otherwise set to paused - we want the track ready to play but not playing
            m_state = PausedState;
            emit stateChanged(m_state);
        }
    } else {
        // No saved position, just sync with AudioEngine state
        if (m_audioEngine && m_audioEngine->state() == AudioEngine::State::Playing) {
            m_state = PlayingState;
        } else {
            m_state = StoppedState;
        }
        emit stateChanged(m_state);
    }
    
    // Clear restoration state - this must be done after setting the state
    clearRestorationState();
}

void MediaPlayer::onTrackLoadTimeout()
{
    qWarning() << "MediaPlayer: Track load timeout during restoration";
    clearRestorationState();
}

void MediaPlayer::setQueueModified(bool modified)
{
    if (m_isQueueModified != modified) {
        m_isQueueModified = modified;
        emit queueModifiedChanged(modified);
    }
}