#include "mediaplayer.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/library/librarymanager.h"
#include "backend/settings/settingsmanager.h"
#include "backend/database/databasemanager.h"
#include "backend/playlist/VirtualPlaylistModel.h"
#include "backend/playlist/VirtualPlaylist.h"
#include "backend/playlist/playlistmanager.h"
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
#include <QPixmapCache>
#include <QThread>
#include <QPointer>
#include <algorithm>
#include <random>

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
    qDebug() << "[MediaPlayer::~MediaPlayer] Destructor called, cleaning up...";
    
    // Stop the save state timer
    if (m_saveStateTimer) {
        m_saveStateTimer->stop();
        m_saveStateTimer->deleteLater();
        m_saveStateTimer = nullptr;
    }
    
    // Cancel any pending restoration
    if (m_restoreConnection) {
        disconnect(m_restoreConnection);
    }
    clearRestorationState();
    
    // Clean up any remaining tracks in the queue
    clearQueue();
    
    // Final cache statistics
    qDebug() << "[MediaPlayer::~MediaPlayer] Final QPixmapCache limit:" << QPixmapCache::cacheLimit() / 1024 << "MB";
    qDebug() << "[MediaPlayer::~MediaPlayer] Cleanup complete";
}

QString MediaPlayer::currentTrackLyrics() const
{
    if (m_currentTrack) {
        return m_currentTrack->lyrics();
    }
    return QString();
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
    
    // Load initial repeat/shuffle states from settings
    if (m_settingsManager) {
        setRepeatEnabled(m_settingsManager->repeatEnabled());
        setShuffleEnabled(m_settingsManager->shuffleEnabled());
        
        // Sync settings when they change
        connect(this, &MediaPlayer::repeatEnabledChanged,
                m_settingsManager, &SettingsManager::setRepeatEnabled);
        connect(this, &MediaPlayer::shuffleEnabledChanged,
                m_settingsManager, &SettingsManager::setShuffleEnabled);
        
        // Configure replay gain settings
        applyReplayGainSettings();
        
        // Connect to replay gain setting changes
        connect(m_settingsManager, &SettingsManager::replayGainEnabledChanged,
                this, &MediaPlayer::applyReplayGainSettings);
        connect(m_settingsManager, &SettingsManager::replayGainModeChanged,
                this, &MediaPlayer::applyReplayGainSettings);
        connect(m_settingsManager, &SettingsManager::replayGainPreAmpChanged,
                this, &MediaPlayer::applyReplayGainSettings);
        connect(m_settingsManager, &SettingsManager::replayGainFallbackGainChanged,
                this, &MediaPlayer::applyReplayGainSettings);
    }
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
    
    // Connect for gapless playback
    connect(m_audioEngine.get(), &AudioEngine::requestNextTrack,
            this, &MediaPlayer::onAboutToFinish);
    
    // Connect for track transition detection
    connect(m_audioEngine.get(), &AudioEngine::trackTransitioned,
            this, &MediaPlayer::onTrackTransitioned);
    
    connect(m_audioEngine.get(), &AudioEngine::error,
            this, &MediaPlayer::error);
}

void MediaPlayer::applyReplayGainSettings()
{
    if (!m_settingsManager || !m_audioEngine) {
        return;
    }
    
    // Apply replay gain settings to the audio engine
    bool enabled = m_settingsManager->replayGainEnabled();
    m_audioEngine->setReplayGainEnabled(enabled);
    
    qDebug() << "[ReplayGain] Configuration:"
             << "Enabled=" << enabled
             << "| Mode=" << (m_settingsManager->replayGainMode() == SettingsManager::Off ? "Off" :
                             m_settingsManager->replayGainMode() == SettingsManager::Track ? "Track" : "Album")
             << "| PreAmp=" << m_settingsManager->replayGainPreAmp() << "dB"
             << "| Fallback=" << m_settingsManager->replayGainFallbackGain() << "dB";
    
    if (enabled) {
        // Set mode (album vs track)
        bool albumMode = (m_settingsManager->replayGainMode() == SettingsManager::Album);
        m_audioEngine->setReplayGainMode(albumMode);
        
        // Set pre-amplification
        m_audioEngine->setReplayGainPreAmp(m_settingsManager->replayGainPreAmp());
        
        // Set fallback gain
        m_audioEngine->setReplayGainFallbackGain(m_settingsManager->replayGainFallbackGain());
    }
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

void MediaPlayer::setRepeatEnabled(bool enabled)
{
    if (m_repeatEnabled != enabled) {
        m_repeatEnabled = enabled;
        emit repeatEnabledChanged(enabled);
        emit playbackQueueChanged(); // Update hasNext status
        saveState();
    }
}

void MediaPlayer::setShuffleEnabled(bool enabled)
{
    if (m_shuffleEnabled != enabled) {
        m_shuffleEnabled = enabled;
        
        if (enabled) {
            generateShuffleOrder();
        } else {
            // Clear shuffle state
            m_shuffleOrder.clear();
            m_shuffleIndex = -1;
        }
        
        emit shuffleEnabledChanged(enabled);
        emit playbackQueueChanged(); // Update hasNext status
        saveState();
    }
}

bool MediaPlayer::hasNext() const
{
    // Handle virtual playlist
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        if (m_repeatEnabled) {
            return true;
        }
        // With shuffle enabled, we always have next unless we've played all tracks
        if (m_shuffleEnabled) {
            // If we have tracks, we can always shuffle to another one
            return m_virtualPlaylist->trackCount() > 1;
        }
        return m_virtualCurrentIndex < m_virtualPlaylist->trackCount() - 1;
    }
    
    // Regular queue handling
    if (m_playbackQueue.isEmpty()) {
        return false;
    }
    
    if (m_repeatEnabled) {
        return true; // Always has next with repeat enabled
    }
    
    if (m_shuffleEnabled) {
        return m_shuffleIndex >= 0 && m_shuffleIndex < m_shuffleOrder.size() - 1;
    }
    
    return m_currentQueueIndex >= 0 && m_currentQueueIndex < m_playbackQueue.size() - 1;
}

bool MediaPlayer::hasPrevious() const
{
    // Handle virtual playlist
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        return m_virtualCurrentIndex > 0;
    }
    
    // Regular queue handling
    // Only return true if we can actually go to a previous track
    // (i.e., we're not on the first track)
    return m_currentQueueIndex > 0 && m_playbackQueue.size() > 0;
}

QVariantList MediaPlayer::queue() const
{
    // For virtual playlists, return empty list (UI should use the VirtualPlaylistModel directly)
    if (m_isVirtualPlaylist) {
        return QVariantList();
    }
    
    // Regular queue handling
    QVariantList queueList;
    for (Mtoc::Track* track : m_playbackQueue) {
        if (track) {
            QVariantMap trackMap;
            trackMap["title"] = track->title();
            trackMap["artist"] = track->artist();
            trackMap["album"] = track->album();
            trackMap["albumArtist"] = track->albumArtist();
            trackMap["duration"] = track->duration() * 1000; // Convert seconds to milliseconds
            trackMap["filePath"] = track->filePath();
            queueList.append(trackMap);
        }
    }
    return queueList;
}

int MediaPlayer::queueLength() const
{
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        return m_virtualPlaylist->trackCount();
    }
    return m_playbackQueue.size();
}

int MediaPlayer::currentQueueIndex() const
{
    if (m_isVirtualPlaylist) {
        return m_virtualCurrentIndex;
    }
    return m_currentQueueIndex;
}

int MediaPlayer::totalQueueDuration() const
{
    // For "All Songs" virtual playlist, get the total duration from the database
    // This ensures consistency with what's shown in the playlist view
    if (m_isVirtualPlaylist && m_virtualPlaylistName == "All Songs" && m_libraryManager) {
        auto db = m_libraryManager->databaseManager();
        if (db) {
            return db->getTotalDuration();
        }
    }
    
    // For other virtual playlists, get the total duration from the virtual playlist
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        return m_virtualPlaylist->totalDuration();
    }
    
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
    } else if (m_isVirtualPlaylist && m_virtualPlaylist && m_virtualCurrentIndex < 0) {
        // Start playing from beginning of virtual playlist
        playTrackAt(0);
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
    qDebug() << "[MediaPlayer::next] Called - virtual:" << m_isVirtualPlaylist 
             << "shuffle:" << m_shuffleEnabled 
             << "currentIndex:" << m_virtualCurrentIndex;
    
    // Monitor cache usage during rapid skipping
    static int skipCount = 0;
    static qint64 lastCacheCheck = QDateTime::currentMSecsSinceEpoch();
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    
    skipCount++;
    
    // Check cache every 10 skips or every 2 seconds
    if (skipCount >= 10 || (now - lastCacheCheck) > 2000) {
        // Log cache statistics
        int cacheLimit = QPixmapCache::cacheLimit();
        qDebug() << "[MediaPlayer::next] QPixmapCache status - Limit:" << cacheLimit / 1024 << "MB";
        
        // Clear cache if we're doing rapid skipping (more than 5 skips in 2 seconds)
        if (skipCount > 5 && (now - lastCacheCheck) < 2000) {
            qDebug() << "[MediaPlayer::next] Rapid skipping detected, clearing pixmap cache";
            QPixmapCache::clear();
        }
        
        skipCount = 0;
        lastCacheCheck = now;
    }
    
    // Don't skip if we're still waiting for a track to load
    if (m_waitingForVirtualTrack) {
        qDebug() << "[MediaPlayer::next] Still waiting for virtual track to load, ignoring skip";
        return;
    }
    
    if (!hasNext()) {
        qDebug() << "[MediaPlayer::next] hasNext() returned false";
        return;
    }
    
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        // Handle virtual playlist navigation
        int nextIndex = -1;
        
        if (m_shuffleEnabled) {
            qDebug() << "[MediaPlayer::next] Getting next shuffle index from" << m_virtualCurrentIndex;
            // Get next shuffle index from virtual playlist
            QVector<int> nextIndices = m_virtualPlaylist->getNextShuffleIndices(m_virtualCurrentIndex, 1);
            if (!nextIndices.isEmpty()) {
                nextIndex = nextIndices.first();
                m_virtualShuffleIndex++;  // Increment shuffle position
                qDebug() << "[MediaPlayer::next] Shuffle next from" << m_virtualCurrentIndex << "to" << nextIndex;
            } else if (m_repeatEnabled) {
                // Re-shuffle and start from beginning
                qDebug() << "[MediaPlayer::next] End of shuffle, re-shuffling with repeat";
                m_virtualPlaylist->generateShuffleOrder();
                m_virtualShuffleIndex = 0;  // Reset to beginning of new shuffle order
                // After re-shuffle, get the first track (index 0 in shuffle order)
                if (m_virtualPlaylist->trackCount() > 0) {
                    nextIndex = m_virtualPlaylist->getShuffledIndex(0);
                    qDebug() << "[MediaPlayer::next] Starting from shuffled index:" << nextIndex;
                }
            } else {
                qDebug() << "[MediaPlayer::next] End of shuffle, no repeat";
            }
        } else {
            // Sequential playback
            if (m_virtualCurrentIndex >= m_virtualPlaylist->trackCount() - 1) {
                if (m_repeatEnabled) {
                    nextIndex = 0; // Loop to beginning
                }
            } else {
                nextIndex = m_virtualCurrentIndex + 1;
            }
        }
        
        if (nextIndex >= 0) {
            playTrackAt(nextIndex);
        }
    } else {
        // Handle regular queue navigation
        if (m_shuffleEnabled) {
            int nextShuffleIdx = getNextShuffleIndex();
            
            // Check if we need to re-shuffle for repeat
            if (nextShuffleIdx == 0 && m_shuffleIndex == m_shuffleOrder.size() - 1 && m_repeatEnabled) {
                // We're looping with repeat, re-shuffle without putting current track first
                generateShuffleOrder(false);
                // m_shuffleIndex is already set to 0 by generateShuffleOrder
            } else {
                m_shuffleIndex = nextShuffleIdx;
            }
            
            if (m_shuffleIndex >= 0 && m_shuffleIndex < m_shuffleOrder.size()) {
                m_currentQueueIndex = m_shuffleOrder[m_shuffleIndex];
            } else {
                qWarning() << "Invalid shuffle index after update:" << m_shuffleIndex << "shuffle order size:" << m_shuffleOrder.size();
                return;
            }
        } else {
            // Sequential playback
            if (m_currentQueueIndex >= m_playbackQueue.size() - 1) {
                if (m_repeatEnabled) {
                    m_currentQueueIndex = 0; // Loop to beginning
                } else {
                    return; // Should not happen due to hasNext() check
                }
            } else {
                m_currentQueueIndex++;
            }
        }
        
        if (m_currentQueueIndex >= 0 && m_currentQueueIndex < m_playbackQueue.size()) {
            Mtoc::Track* nextTrack = m_playbackQueue[m_currentQueueIndex];
            playTrack(nextTrack);
            emit playbackQueueChanged();
        }
    }
}

void MediaPlayer::previous()
{
    // Don't skip if we're still waiting for a track to load
    if (m_waitingForVirtualTrack) {
        qDebug() << "[MediaPlayer::previous] Still waiting for virtual track to load, ignoring skip";
        return;
    }
    
    if (position() > 3000) {
        seek(0);
        return;
    }
    
    // Handle virtual playlist
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        if (m_shuffleEnabled) {
            // Get previous track in shuffle order
            int prevShuffledIndex = m_virtualPlaylist->getPreviousShuffleIndex(m_virtualCurrentIndex);
            if (prevShuffledIndex >= 0) {
                m_virtualCurrentIndex = prevShuffledIndex;
                m_virtualShuffleIndex--;
                
                // Preload tracks around the new position
                preloadVirtualTracks(m_virtualCurrentIndex);
                
                // Get or create the track object
                Mtoc::Track* prevTrack = getOrCreateTrackFromVirtual(m_virtualCurrentIndex);
                if (prevTrack) {
                    playTrack(prevTrack);
                    emit playbackQueueChanged();
                }
            } else {
                seek(0);
            }
        } else {
            // Sequential mode
            if (m_virtualCurrentIndex > 0) {
                m_virtualCurrentIndex--;
                
                // Preload tracks around the new position
                preloadVirtualTracks(m_virtualCurrentIndex);
                
                // Get or create the track object
                Mtoc::Track* prevTrack = getOrCreateTrackFromVirtual(m_virtualCurrentIndex);
                if (prevTrack) {
                    playTrack(prevTrack);
                    emit playbackQueueChanged();
                }
            } else {
                seek(0);
            }
        }
        return;
    }
    
    // Regular queue handling
    if (m_shuffleEnabled) {
        int prevShuffleIdx = getPreviousShuffleIndex();
        if (prevShuffleIdx >= 0) {
            m_shuffleIndex = prevShuffleIdx;
            // Add bounds checking before accessing m_shuffleOrder
            if (m_shuffleIndex >= 0 && m_shuffleIndex < m_shuffleOrder.size()) {
                m_currentQueueIndex = m_shuffleOrder[m_shuffleIndex];
                // Add bounds checking before accessing m_playbackQueue
                if (m_currentQueueIndex >= 0 && m_currentQueueIndex < m_playbackQueue.size()) {
                    Mtoc::Track* prevTrack = m_playbackQueue[m_currentQueueIndex];
                    playTrack(prevTrack);
                    emit playbackQueueChanged();
                } else {
                    qWarning() << "Invalid queue index in shuffle order:" << m_currentQueueIndex;
                    seek(0);
                }
            } else {
                qWarning() << "Invalid shuffle index:" << m_shuffleIndex;
                seek(0);
            }
        } else {
            seek(0);
        }
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
    
    // If this is a virtual playlist track, preload neighboring tracks for gapless playback
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        int virtualIndex = track->property("virtualIndex").toInt();
        if (virtualIndex >= 0) {
            // Preload next few tracks to ensure gapless works
            preloadVirtualTracks(virtualIndex);
        }
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
        // Use QPointer to ensure object validity
        QPointer<MediaPlayer> self = this;
        QPointer<Mtoc::Track> trackPtr = track;
        QTimer::singleShot(100, this, [self, trackPtr]() {
            if (!self || !trackPtr) return;  // Object was destroyed
            if (self->m_currentTrack == trackPtr && trackPtr->duration() > 0) {
                qDebug() << "MediaPlayer: Re-emitting duration after delay:" << trackPtr->duration() * 1000 << "ms";
                emit self->durationChanged(trackPtr->duration() * 1000);
                
                // Re-emit position to update progress bar visual position
                if (self->m_savedPosition > 0) {
                    emit self->savedPositionChanged(self->m_savedPosition);
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
    
    // Set queue source album info
    if (m_queueSourceAlbumName != album->title()) {
        m_queueSourceAlbumName = album->title();
        emit queueSourceAlbumNameChanged(m_queueSourceAlbumName);
    }
    if (m_queueSourceAlbumArtist != album->artist()) {
        m_queueSourceAlbumArtist = album->artist();
        emit queueSourceAlbumArtistChanged(m_queueSourceAlbumArtist);
    }
    
    m_playbackQueue = album->tracks();
    m_currentQueueIndex = qBound(0, startIndex, m_playbackQueue.size() - 1);
    
    // Clear the queue modified flag when playing a full album
    setQueueModified(false);
    
    // Generate shuffle order if shuffle is enabled
    if (m_shuffleEnabled) {
        generateShuffleOrder();
        
        // After generating shuffle order, we need to find where our starting track ended up
        // and update m_shuffleIndex to that position
        if (!m_shuffleOrder.isEmpty() && m_currentQueueIndex >= 0) {
            int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
            if (shufflePos >= 0) {
                m_shuffleIndex = shufflePos;
            }
        }
    }
    
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
            
            // Update shuffle order if enabled
            if (m_shuffleEnabled) {
                updateShuffleOrder();
            }
            
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
            
            // Update shuffle order if enabled
            if (m_shuffleEnabled) {
                updateShuffleOrder();
            }
            
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
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
}

void MediaPlayer::removeTracks(const QList<int>& indices)
{
    if (indices.isEmpty()) return;
    
    // Sort indices in descending order to remove from end to beginning
    QList<int> sortedIndices = indices;
    std::sort(sortedIndices.begin(), sortedIndices.end(), std::greater<int>());
    
    // Check if we're removing the current track
    bool removingCurrent = false;
    int newCurrentIndex = m_currentQueueIndex;
    int tracksBeforeCurrent = 0;
    
    for (int idx : sortedIndices) {
        if (idx == m_currentQueueIndex) {
            removingCurrent = true;
        } else if (idx < m_currentQueueIndex) {
            tracksBeforeCurrent++;
        }
    }
    
    // If removing current track, determine what to play next
    Mtoc::Track* nextTrack = nullptr;
    if (removingCurrent && m_playbackQueue.size() > sortedIndices.size()) {
        // Find the first non-removed track after current
        for (int i = m_currentQueueIndex + 1; i < m_playbackQueue.size(); i++) {
            if (!sortedIndices.contains(i)) {
                nextTrack = m_playbackQueue[i];
                newCurrentIndex = i - tracksBeforeCurrent - 1; // Adjust for removed tracks
                break;
            }
        }
        
        // If no track after, find one before
        if (!nextTrack) {
            for (int i = m_currentQueueIndex - 1; i >= 0; i--) {
                if (!sortedIndices.contains(i)) {
                    nextTrack = m_playbackQueue[i];
                    newCurrentIndex = i - tracksBeforeCurrent;
                    break;
                }
            }
        }
    } else if (!removingCurrent) {
        // Just adjust the current index for removed tracks before it
        newCurrentIndex = m_currentQueueIndex - tracksBeforeCurrent;
    }
    
    // Remove tracks from queue (in descending order)
    for (int idx : sortedIndices) {
        if (idx >= 0 && idx < m_playbackQueue.size()) {
            Mtoc::Track* track = m_playbackQueue[idx];
            m_playbackQueue.removeAt(idx);
            
            // Clean up if we created this track
            if (track && track->parent() == this) {
                track->deleteLater();
            }
        }
    }
    
    // Update shuffle order if needed
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
    // Handle playback state
    if (m_playbackQueue.isEmpty()) {
        stop();
    } else if (removingCurrent && nextTrack) {
        m_currentQueueIndex = newCurrentIndex;
        playTrack(nextTrack);
    } else {
        m_currentQueueIndex = newCurrentIndex;
    }
    
    // Mark queue as modified
    setQueueModified(true);
    
    // Emit signals
    emit playbackQueueChanged();
}

void MediaPlayer::playTrackAt(int index)
{
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        // Handle virtual playlist
        if (index < 0 || index >= m_virtualPlaylist->trackCount()) {
            qWarning() << "[MediaPlayer::playTrackAt] Invalid virtual playlist index" << index 
                       << "track count:" << m_virtualPlaylist->trackCount();
            return;
        }
        
        qDebug() << "[MediaPlayer::playTrackAt] Virtual playlist index:" << index;
        
        // Update indices
        m_virtualCurrentIndex = index;
        m_currentQueueIndex = -1;  // Not using regular queue
        
        // Update shuffle index if shuffle is enabled
        if (m_shuffleEnabled) {
            // For virtual playlists, shuffle is handled by VirtualPlaylist
            // Update our virtual shuffle index
            m_virtualShuffleIndex = m_virtualPlaylist->getLinearIndex(index);
            qDebug() << "[MediaPlayer::playTrackAt] Shuffle enabled - linear index:" << m_virtualShuffleIndex 
                     << "for track index:" << index;
            
            // If this is the first track being played and shuffle order isn't initialized properly,
            // regenerate it with the current track first
            if (m_virtualShuffleIndex < 0) {
                qDebug() << "[MediaPlayer::playTrackAt] Track not in shuffle order, regenerating with current track first";
                m_virtualPlaylist->generateShuffleOrder(index);
                m_virtualShuffleIndex = 0; // Current track is now at position 0
            }
        }
        
        // Preload nearby tracks
        preloadVirtualTracks(index);
        
        // Get or create the track object
        Mtoc::Track* track = getOrCreateTrackFromVirtual(index);
        if (track) {
            m_waitingForVirtualTrack = false;
            emit playbackQueueChanged();
            playTrack(track);
        } else {
            // Track not loaded yet - set up retry when it becomes available
            qDebug() << "[MediaPlayer::playTrackAt] Track not loaded yet at index" << index << ", waiting for load";
            m_waitingForVirtualTrack = true;
            
            // Disconnect any existing connection to prevent leaks
            if (m_virtualTrackLoadConnection) {
                disconnect(m_virtualTrackLoadConnection);
            }
            
            // Set up a connection to retry when the track is loaded
            m_virtualTrackLoadConnection = connect(m_virtualPlaylist, &Mtoc::VirtualPlaylist::rangeLoaded, this,
                    [this, index](int startIdx, int endIdx) {
                        if (index >= startIdx && index <= endIdx) {
                            // Disconnect to avoid multiple attempts
                            disconnect(m_virtualTrackLoadConnection);
                            m_virtualTrackLoadConnection = QMetaObject::Connection();
                            
                            // Try again now that the track should be loaded
                            Mtoc::Track* track = getOrCreateTrackFromVirtual(index);
                            if (track) {
                                // Only play if we're still at the same index
                                if (m_virtualCurrentIndex == index) {
                                    m_waitingForVirtualTrack = false;
                                    emit playbackQueueChanged();
                                    playTrack(track);
                                }
                            } else {
                                qWarning() << "[MediaPlayer::playTrackAt] Failed to get track even after loading at index" << index;
                                m_waitingForVirtualTrack = false;
                            }
                        }
                    }, Qt::QueuedConnection);
            
            // Ensure the track gets loaded
            m_virtualPlaylist->ensureLoaded(index);
        }
    } else {
        // Handle regular queue
        if (index < 0 || index >= m_playbackQueue.size()) {
            qWarning() << "playTrackAt: Invalid index" << index;
            return;
        }
        
        qDebug() << "MediaPlayer::playTrackAt called with index:" << index;
        
        m_currentQueueIndex = index;
        
        // Update shuffle index if shuffle is enabled
        if (m_shuffleEnabled && !m_shuffleOrder.isEmpty()) {
            // Find this index in the shuffle order
            int shufflePos = m_shuffleOrder.indexOf(index);
            if (shufflePos >= 0) {
                m_shuffleIndex = shufflePos;
            }
        }
        
        emit playbackQueueChanged();
        playTrack(m_playbackQueue[index]);
    }
}

void MediaPlayer::moveTrack(int fromIndex, int toIndex)
{
    // Don't allow moving in virtual playlist mode
    if (m_isVirtualPlaylist) {
        qWarning() << "Cannot reorder tracks in virtual playlist mode";
        return;
    }
    
    // Validate indices
    if (fromIndex < 0 || fromIndex >= m_playbackQueue.size() ||
        toIndex < 0 || toIndex >= m_playbackQueue.size() ||
        fromIndex == toIndex) {
        return;
    }
    
    // Store the track being moved
    Mtoc::Track* track = m_playbackQueue[fromIndex];
    
    // Update current queue index if needed
    int newCurrentIndex = m_currentQueueIndex;
    
    // If we're moving the current track
    if (fromIndex == m_currentQueueIndex) {
        newCurrentIndex = toIndex;
    } 
    // If current track is between source and destination
    else if (m_currentQueueIndex >= 0) {
        if (fromIndex < m_currentQueueIndex && toIndex >= m_currentQueueIndex) {
            // Moving a track from before current to after current
            newCurrentIndex--;
        } else if (fromIndex > m_currentQueueIndex && toIndex <= m_currentQueueIndex) {
            // Moving a track from after current to before current
            newCurrentIndex++;
        }
    }
    
    // Remove from old position
    m_playbackQueue.removeAt(fromIndex);
    
    // Insert at new position
    m_playbackQueue.insert(toIndex, track);
    
    // Update current index
    m_currentQueueIndex = newCurrentIndex;
    
    // Update shuffle order if shuffle is enabled
    if (m_shuffleEnabled) {
        // Find the track in shuffle order
        int shuffleIndex = -1;
        for (int i = 0; i < m_shuffleOrder.size(); i++) {
            if (m_shuffleOrder[i] == fromIndex) {
                shuffleIndex = i;
                break;
            }
        }
        
        // Update all indices in shuffle order
        for (int i = 0; i < m_shuffleOrder.size(); i++) {
            int& idx = m_shuffleOrder[i];
            
            // Skip the item being moved
            if (i == shuffleIndex) {
                idx = toIndex;
            } 
            // Adjust indices affected by the move
            else {
                if (fromIndex < toIndex) {
                    // Moving forward: indices between source and destination shift back
                    if (idx > fromIndex && idx <= toIndex) {
                        idx--;
                    }
                } else {
                    // Moving backward: indices between destination and source shift forward
                    if (idx >= toIndex && idx < fromIndex) {
                        idx++;
                    }
                }
            }
        }
    }
    
    // Mark queue as modified
    setQueueModified(true);
    
    // Emit signal to update UI
    emit playbackQueueChanged();
}

void MediaPlayer::clearQueue()
{
    // Clear virtual playlist if active
    if (m_isVirtualPlaylist) {
        clearVirtualPlaylist();
    }
    
    // Clear playlist name
    if (!m_currentPlaylistName.isEmpty()) {
        m_currentPlaylistName.clear();
        emit currentPlaylistNameChanged(m_currentPlaylistName);
    }
    
    // Clear album source info
    if (!m_queueSourceAlbumName.isEmpty()) {
        m_queueSourceAlbumName.clear();
        emit queueSourceAlbumNameChanged(m_queueSourceAlbumName);
    }
    if (!m_queueSourceAlbumArtist.isEmpty()) {
        m_queueSourceAlbumArtist.clear();
        emit queueSourceAlbumArtistChanged(m_queueSourceAlbumArtist);
    }
    
    // Clean up any tracks we created
    for (auto track : m_playbackQueue) {
        if (track && track->parent() == this) {
            track->deleteLater();
        }
    }
    m_playbackQueue.clear();
    m_currentQueueIndex = -1;
    
    // Clear shuffle state
    m_shuffleOrder.clear();
    m_shuffleIndex = -1;
    
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
    m_undoQueueSourceAlbumName = m_queueSourceAlbumName;
    m_undoQueueSourceAlbumArtist = m_queueSourceAlbumArtist;
    m_undoCurrentPlaylistName = m_currentPlaylistName;
    
    // Stop audio playback without clearing the queue
    m_audioEngine->stop();
    
    // Clear the current queue without deleting tracks
    m_playbackQueue.clear();
    m_currentQueueIndex = -1;
    updateCurrentTrack(nullptr);
    setQueueModified(false);
    
    // Clear the queue source info now that we've saved it for undo
    if (!m_currentPlaylistName.isEmpty()) {
        m_currentPlaylistName.clear();
        emit currentPlaylistNameChanged(m_currentPlaylistName);
    }
    if (!m_queueSourceAlbumName.isEmpty()) {
        m_queueSourceAlbumName.clear();
        emit queueSourceAlbumNameChanged(m_queueSourceAlbumName);
    }
    if (!m_queueSourceAlbumArtist.isEmpty()) {
        m_queueSourceAlbumArtist.clear();
        emit queueSourceAlbumArtistChanged(m_queueSourceAlbumArtist);
    }
    
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
    
    // Restore the queue source info
    if (!m_undoQueueSourceAlbumName.isEmpty()) {
        m_queueSourceAlbumName = m_undoQueueSourceAlbumName;
        emit queueSourceAlbumNameChanged(m_queueSourceAlbumName);
    }
    if (!m_undoQueueSourceAlbumArtist.isEmpty()) {
        m_queueSourceAlbumArtist = m_undoQueueSourceAlbumArtist;
        emit queueSourceAlbumArtistChanged(m_queueSourceAlbumArtist);
    }
    if (!m_undoCurrentPlaylistName.isEmpty()) {
        m_currentPlaylistName = m_undoCurrentPlaylistName;
        emit currentPlaylistNameChanged(m_currentPlaylistName);
    }
    
    // Clear undo state
    m_undoQueue.clear();
    m_undoQueueIndex = -1;
    m_undoCurrentTrack = nullptr;
    m_undoQueueModified = false;
    m_undoQueueSourceAlbumName.clear();
    m_undoQueueSourceAlbumArtist.clear();
    m_undoCurrentPlaylistName.clear();
    
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
        
        // Set queue source album info
        if (m_queueSourceAlbumName != title) {
            m_queueSourceAlbumName = title;
            emit queueSourceAlbumNameChanged(m_queueSourceAlbumName);
        }
        if (m_queueSourceAlbumArtist != artist) {
            m_queueSourceAlbumArtist = artist;
            emit queueSourceAlbumArtistChanged(m_queueSourceAlbumArtist);
        }
        
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
            Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
            
            m_playbackQueue.append(track);
        }
        
        qDebug() << "Built queue with" << m_playbackQueue.size() << "tracks";
        
        if (!m_playbackQueue.isEmpty() && startIndex < m_playbackQueue.size()) {
            m_currentQueueIndex = startIndex;
            
            // Generate shuffle order if shuffle is enabled
            if (m_shuffleEnabled) {
                generateShuffleOrder();
                
                // After generating shuffle order, we need to find where our starting track ended up
                // and update m_shuffleIndex to that position
                if (!m_shuffleOrder.isEmpty() && m_currentQueueIndex >= 0) {
                    int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
                    if (shufflePos >= 0) {
                        m_shuffleIndex = shufflePos;
                    }
                }
            }
            
            emit playbackQueueChanged();
            playTrack(m_playbackQueue[startIndex]);
        }
    } else {
        qWarning() << "No tracks found for album:" << artist << "-" << title;
    }
}

void MediaPlayer::playPlaylist(const QString& playlistName, int startIndex)
{
    qDebug() << "MediaPlayer::playPlaylist called with playlist:" << playlistName << "startIndex:" << startIndex;
    
    // Clear any restoration state to prevent old positions from being applied
    clearRestorationState();
    clearSavedPosition();
    
    // Get playlist tracks from PlaylistManager
    PlaylistManager* playlistManager = PlaylistManager::instance();
    auto trackList = playlistManager->loadPlaylist(playlistName);
    
    qDebug() << "Found" << trackList.size() << "tracks in playlist";
    
    if (trackList.isEmpty()) {
        qWarning() << "No tracks found in playlist:" << playlistName;
        return;
    }
    
    // Clear current queue
    clearQueue();
    
    // Set the current playlist name
    if (m_currentPlaylistName != playlistName) {
        m_currentPlaylistName = playlistName;
        emit currentPlaylistNameChanged(m_currentPlaylistName);
    }
    
    // Build tracks from data and add to queue
    for (const auto& trackData : trackList) {
        auto trackMap = trackData.toMap();
        QString trackTitle = trackMap.value("title").toString();
        QString filePath = trackMap.value("filePath").toString();
        
        if (filePath.isEmpty()) {
            qWarning() << "Empty filePath for track:" << trackTitle;
            continue;
        }
        
        // Create a new Track object from the data
        Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
        
        m_playbackQueue.append(track);
    }
    
    // Clear the queue modified flag since this is a fresh playlist load
    setQueueModified(false);
    
    // Ensure startIndex is within bounds
    startIndex = qBound(0, startIndex, m_playbackQueue.size() - 1);
    
    if (!m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = startIndex;
        
        // Generate shuffle order if shuffle is enabled
        if (m_shuffleEnabled) {
            generateShuffleOrder();
            
            // After generating shuffle order, find where our starting track ended up
            if (!m_shuffleOrder.isEmpty() && m_currentQueueIndex >= 0) {
                int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
                if (shufflePos >= 0) {
                    m_shuffleIndex = shufflePos;
                }
            }
        }
        
        emit playbackQueueChanged();
        playTrack(m_playbackQueue[startIndex]);
    }
}

void MediaPlayer::playTrackFromData(const QVariant& trackData)
{
    auto trackMap = trackData.toMap();
    QString title = trackMap.value("title").toString();
    QString filePath = trackMap.value("filePath").toString();
    
    qDebug() << "MediaPlayer::playTrackFromData called with track:" << title << "path:" << filePath;
    qDebug() << "MediaPlayer::playTrackFromData Album:" << trackMap.value("album").toString() << "AlbumArtist:" << trackMap.value("albumArtist").toString();
    
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
    // Duration from playlist is already in seconds (from library) or milliseconds (from queue)
    // We need to handle both cases - tracks store duration in seconds
    int duration = trackMap.value("duration").toInt();
    if (duration > 10000) { // Likely in milliseconds if > 10000
        trackMap["duration"] = duration / 1000;
    }
    Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
    
    // Add to queue so it gets cleaned up properly
    m_playbackQueue.append(track);
    m_currentQueueIndex = 0;
    
    // Generate shuffle order if shuffle is enabled (even for single track)
    if (m_shuffleEnabled) {
        generateShuffleOrder();
        // For a single track, shuffle index will be 0
        m_shuffleIndex = 0;
    }
    
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
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
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
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
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
        
        Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
        
        m_playbackQueue.insert(insertIndex++, track);
    }
    
    // Mark queue as modified when adding albums to existing queue
    setQueueModified(true);
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
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
        
        Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
        
        m_playbackQueue.append(track);
    }
    
    // Mark queue as modified when adding albums to existing queue
    setQueueModified(true);
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::playPlaylistNext(const QString& playlistName)
{
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    qDebug() << "MediaPlayer::playPlaylistNext called with playlist:" << playlistName;
    
    // Get playlist tracks from PlaylistManager
    PlaylistManager* playlistManager = PlaylistManager::instance();
    auto trackList = playlistManager->loadPlaylist(playlistName);
    
    qDebug() << "Found" << trackList.size() << "tracks in playlist";
    
    if (trackList.isEmpty()) {
        qWarning() << "No tracks found in playlist:" << playlistName;
        return;
    }
    
    // Find insertion point (after current track)
    int insertIndex = m_currentQueueIndex + 1;
    
    // Build tracks from data and insert into queue
    for (const auto& trackData : trackList) {
        auto trackMap = trackData.toMap();
        QString trackTitle = trackMap.value("title").toString();
        QString filePath = trackMap.value("filePath").toString();
        
        if (filePath.isEmpty()) {
            qWarning() << "Empty filePath for track:" << trackTitle;
            continue;
        }
        
        Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
        
        m_playbackQueue.insert(insertIndex++, track);
    }
    
    // Mark queue as modified when adding playlists to existing queue
    setQueueModified(true);
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::playPlaylistLast(const QString& playlistName)
{
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    qDebug() << "MediaPlayer::playPlaylistLast called with playlist:" << playlistName;
    
    // Get playlist tracks from PlaylistManager
    PlaylistManager* playlistManager = PlaylistManager::instance();
    auto trackList = playlistManager->loadPlaylist(playlistName);
    
    qDebug() << "Found" << trackList.size() << "tracks in playlist";
    
    if (trackList.isEmpty()) {
        qWarning() << "No tracks found in playlist:" << playlistName;
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
        
        Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
        
        m_playbackQueue.append(track);
    }
    
    // Mark queue as modified when adding playlists to existing queue
    setQueueModified(true);
    
    // Update shuffle order if enabled
    if (m_shuffleEnabled) {
        updateShuffleOrder();
    }
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::updateCurrentTrack(Mtoc::Track* track)
{
    // Validate the track pointer is still valid before using it
    if (!track) {
        // Handle null track case - clear current track
        if (m_currentTrack) {
            m_currentTrack = nullptr;
            emit currentTrackChanged(nullptr);
            emit currentTrackLyricsChanged();
        }
        if (m_currentAlbum) {
            m_currentAlbum = nullptr;
            emit currentAlbumChanged(nullptr);
        }
        return;
    }
    
    if (m_currentTrack != track) {
        m_currentTrack = track;
        emit currentTrackChanged(track);
        emit currentTrackLyricsChanged();
        
        // If we're not playing from an album queue, clear the current album
        if (m_playbackQueue.isEmpty() || !m_playbackQueue.contains(track)) {
            if (m_currentAlbum) {
                m_currentAlbum = nullptr;
                emit currentAlbumChanged(nullptr);
            }
        }
    }
}

void MediaPlayer::onAboutToFinish()
{
    qDebug() << "[MediaPlayer::onAboutToFinish] Called - preparing next track for gapless playback";
    
    // Clear any previous pending track
    m_pendingTrack = nullptr;
    m_pendingQueueIndex = -1;
    m_pendingVirtualIndex = -1;
    m_pendingShuffleIndex = -1;
    
    // Check if there's a next track to queue
    if (!hasNext()) {
        qDebug() << "[MediaPlayer::onAboutToFinish] No next track available";
        return;
    }
    
    // Determine the next track based on current playback mode
    Mtoc::Track* nextTrack = nullptr;
    
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        // Handle virtual playlist mode
        if (m_shuffleEnabled) {
            // In shuffle mode, we need to check our position in the shuffle order
            // If we're at the end of the shuffle order, check if repeat is enabled
            QVector<int> nextIndices = m_virtualPlaylist->getNextShuffleIndices(m_virtualCurrentIndex, 1);
            
            if (!nextIndices.isEmpty()) {
                m_pendingVirtualIndex = nextIndices.first();
                qDebug() << "[MediaPlayer::onAboutToFinish] Found next shuffle index:" << m_pendingVirtualIndex;
                
                // Ensure the track is loaded before trying to get it
                m_virtualPlaylist->ensureLoaded(m_pendingVirtualIndex);
                nextTrack = getOrCreateTrackFromVirtual(m_pendingVirtualIndex);
                
                if (!nextTrack) {
                    qDebug() << "[MediaPlayer::onAboutToFinish] Track at index" << m_pendingVirtualIndex 
                             << "not loaded yet, checking if in valid range";
                    // Track might not be loaded yet - this is a problem for gapless
                    // Try to force load it synchronously (risky but necessary for gapless)
                    if (m_pendingVirtualIndex >= 0 && m_pendingVirtualIndex < m_virtualPlaylist->trackCount()) {
                        // Give it one more chance after ensuring it's loaded
                        QThread::msleep(10); // Small delay to allow loading
                        nextTrack = getOrCreateTrackFromVirtual(m_pendingVirtualIndex);
                    }
                }
            } else if (m_repeatEnabled && m_virtualPlaylist->trackCount() > 0) {
                // End of shuffle order with repeat enabled - regenerate shuffle and start from beginning
                qDebug() << "[MediaPlayer::onAboutToFinish] End of shuffle order, repeat enabled - will reshuffle";
                // Note: We'll regenerate the shuffle order in onTrackTransitioned
                // For now, just queue the first track in the current shuffle order
                m_virtualPlaylist->generateShuffleOrder(m_virtualCurrentIndex);
                m_pendingVirtualIndex = m_virtualPlaylist->getShuffledIndex(0);
                if (m_pendingVirtualIndex >= 0) {
                    nextTrack = getOrCreateTrackFromVirtual(m_pendingVirtualIndex);
                }
            } else {
                qDebug() << "[MediaPlayer::onAboutToFinish] No next shuffle index available, repeat disabled";
            }
        } else {
            m_pendingVirtualIndex = m_virtualCurrentIndex + 1;
            if (m_pendingVirtualIndex < m_virtualPlaylist->trackCount()) {
                nextTrack = getOrCreateTrackFromVirtual(m_pendingVirtualIndex);
            } else if (m_repeatEnabled) {
                // Loop back to start if repeat is on
                m_pendingVirtualIndex = 0;
                nextTrack = getOrCreateTrackFromVirtual(0);
            }
        }
    } else if (m_shuffleEnabled) {
        // Handle shuffle mode for regular queue
        m_pendingShuffleIndex = getNextShuffleIndex();
        if (m_pendingShuffleIndex >= 0 && m_pendingShuffleIndex < m_shuffleOrder.size()) {
            m_pendingQueueIndex = m_shuffleOrder[m_pendingShuffleIndex];
            if (m_pendingQueueIndex >= 0 && m_pendingQueueIndex < m_playbackQueue.size()) {
                nextTrack = m_playbackQueue[m_pendingQueueIndex];
            }
        }
    } else {
        // Normal sequential playback
        m_pendingQueueIndex = m_currentQueueIndex + 1;
        if (m_pendingQueueIndex < m_playbackQueue.size()) {
            nextTrack = m_playbackQueue[m_pendingQueueIndex];
        } else if (m_repeatEnabled && !m_playbackQueue.isEmpty()) {
            // Loop back to start if repeat is on
            m_pendingQueueIndex = 0;
            nextTrack = m_playbackQueue[0];
        }
    }
    
    // Queue the next track if we found one
    if (nextTrack && !nextTrack->filePath().isEmpty()) {
        qDebug() << "[MediaPlayer::onAboutToFinish] Queuing next track:" 
                 << nextTrack->title() << "by" << nextTrack->artist();
        
        // Store the pending track for when transition actually occurs
        m_pendingTrack = nextTrack;
        
        // Queue the track in GStreamer for gapless playback
        m_audioEngine->queueNextTrack(nextTrack->filePath());
    } else {
        qDebug() << "[MediaPlayer::onAboutToFinish] Failed to determine next track";
    }
}

void MediaPlayer::handleTrackFinished()
{
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Track finished (EOS received)" << Qt::endl;
    }
    
    // This is only called when EOS is received, which means:
    // 1. We've reached the end of the queue (no next track was queued for gapless)
    // 2. Or there was an error/interruption in playback
    // 3. Or we skipped gapless for AAC files
    
    // Check if we have a pending track from onAboutToFinish that wasn't queued (AAC case)
    if (m_pendingTrack) {
        qDebug() << "[MediaPlayer::handleTrackFinished] Playing pending track that wasn't queued (AAC fallback)";
        
        // Update indices based on what was set in onAboutToFinish
        if (m_pendingQueueIndex >= 0) {
            m_currentQueueIndex = m_pendingQueueIndex;
        }
        if (m_pendingVirtualIndex >= 0) {
            m_virtualCurrentIndex = m_pendingVirtualIndex;
        }
        if (m_pendingShuffleIndex >= 0) {
            if (m_isVirtualPlaylist && m_virtualPlaylist) {
                m_virtualShuffleIndex = m_pendingShuffleIndex;
            } else {
                m_shuffleIndex = m_pendingShuffleIndex;
            }
        }
        
        // Load and play the pending track
        loadTrack(m_pendingTrack, true);
        
        // Clear pending state
        m_pendingTrack = nullptr;
        m_pendingQueueIndex = -1;
        m_pendingVirtualIndex = -1;
        m_pendingShuffleIndex = -1;
        return;
    }
    
    // Check if we should restart the queue (repeat mode with no next track)
    if (!hasNext() && m_repeatEnabled && !m_playbackQueue.isEmpty()) {
        // Restart from the beginning
        if (m_isVirtualPlaylist && m_virtualPlaylist) {
            if (m_shuffleEnabled) {
                m_virtualPlaylist->generateShuffleOrder();
                m_virtualShuffleIndex = 0;
                m_virtualCurrentIndex = m_virtualPlaylist->getShuffledIndex(0);
            } else {
                m_virtualCurrentIndex = 0;
            }
            playTrackAt(0);
        } else {
            if (m_shuffleEnabled) {
                generateShuffleOrder();
                m_shuffleIndex = 0;
                m_currentQueueIndex = m_shuffleOrder[0];
            } else {
                m_currentQueueIndex = 0;
            }
            loadTrack(m_playbackQueue[0], true);
        }
    } else {
        // No more tracks and repeat is off, or queue is empty
        m_state = StoppedState;
        emit stateChanged(m_state);
    }
}

void MediaPlayer::onTrackTransitioned()
{
    qDebug() << "[MediaPlayer::onTrackTransitioned] Track transition detected - updating UI";
    
    // Check if we have a pending track to transition to
    if (!m_pendingTrack) {
        qDebug() << "[MediaPlayer::onTrackTransitioned] No pending track, ignoring transition";
        return;
    }
    
    // Store a local copy of the pending track pointer before we clear it
    Mtoc::Track* trackToUpdate = m_pendingTrack;
    
    // Update indices based on pending values
    if (m_isVirtualPlaylist && m_pendingVirtualIndex >= 0) {
        // Handle special case of re-shuffle at end of playlist
        if (m_virtualPlaylist && m_shuffleEnabled && m_pendingVirtualIndex == 0 && 
            m_virtualCurrentIndex >= m_virtualPlaylist->trackCount() - 1) {
            // Re-shuffle occurred
            m_virtualPlaylist->generateShuffleOrder();
            m_virtualShuffleIndex = 0;
            m_pendingVirtualIndex = m_virtualPlaylist->getShuffledIndex(0);
        }
        
        m_virtualCurrentIndex = m_pendingVirtualIndex;
        if (m_shuffleEnabled) {
            m_virtualShuffleIndex++;
        }
    } else if (m_pendingQueueIndex >= 0) {
        m_currentQueueIndex = m_pendingQueueIndex;
        if (m_shuffleEnabled && m_pendingShuffleIndex >= 0) {
            m_shuffleIndex = m_pendingShuffleIndex;
        }
    }
    
    // Clear pending track info before updating (to avoid potential re-entrancy issues)
    m_pendingTrack = nullptr;
    m_pendingQueueIndex = -1;
    m_pendingVirtualIndex = -1;
    m_pendingShuffleIndex = -1;
    
    // Update the current track to trigger UI updates (only if track is still valid)
    if (trackToUpdate) {
        updateCurrentTrack(trackToUpdate);
    }
    
    // Emit queue changed signal
    emit playbackQueueChanged();
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
    
    // Check if we're playing from a virtual playlist
    QVariantMap virtualPlaylistInfo;
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        virtualPlaylistInfo["isVirtualPlaylist"] = true;
        virtualPlaylistInfo["virtualPlaylistType"] = "AllSongs";
        virtualPlaylistInfo["virtualTrackIndex"] = m_virtualCurrentIndex;
        virtualPlaylistInfo["virtualShuffleIndex"] = m_virtualShuffleIndex;
        virtualPlaylistInfo["shuffleEnabled"] = m_shuffleEnabled;
        
        // Save track metadata to avoid "Unknown Track" on restore
        virtualPlaylistInfo["trackTitle"] = m_currentTrack->title();
        virtualPlaylistInfo["trackArtist"] = m_currentTrack->artist();
        virtualPlaylistInfo["trackAlbum"] = m_currentTrack->album();
        virtualPlaylistInfo["trackAlbumArtist"] = m_currentTrack->albumArtist();
    }
    
    // Get album info if playing from an album
    QString albumArtist;
    QString albumTitle;
    int trackIndex = m_currentQueueIndex;
    
    if (!m_isVirtualPlaylist) {
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
    }
    
    // Get the duration
    qint64 trackDuration = duration(); // This already handles both track and engine duration
    
    // Prepare queue data if queue is modified or playing a playlist
    QVariantList queueData;
    if ((m_isQueueModified || !m_currentPlaylistName.isEmpty()) && !m_playbackQueue.isEmpty()) {
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
    
    // Add playlist info if playing a playlist
    QVariantMap playlistInfo;
    if (!m_currentPlaylistName.isEmpty()) {
        playlistInfo["playlistName"] = m_currentPlaylistName;
    }
    
    // Save the state
    m_libraryManager->savePlaybackState(filePath, currentPosition, 
                                        albumArtist, albumTitle, trackIndex, trackDuration,
                                        m_isQueueModified || !m_currentPlaylistName.isEmpty(), 
                                        queueData, virtualPlaylistInfo, playlistInfo);
    
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
    
    // Check for virtual playlist info
    bool isVirtualPlaylist = state["isVirtualPlaylist"].toBool();
    QString virtualPlaylistType = state["virtualPlaylistType"].toString();
    int virtualTrackIndex = state["virtualTrackIndex"].toInt();
    int virtualShuffleIndex = state["virtualShuffleIndex"].toInt();
    bool savedShuffleEnabled = state["shuffleEnabled"].toBool();
    
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
        // Check if we're restoring from a virtual playlist
        if (isVirtualPlaylist && virtualPlaylistType == "AllSongs") {
            qDebug() << "MediaPlayer::restoreState - Restoring virtual playlist state";
            
            // Get the All Songs playlist
            Mtoc::VirtualPlaylistModel* allSongsModel = m_libraryManager->getAllSongsPlaylist();
            if (allSongsModel && allSongsModel->virtualPlaylist()) {
                // Clear current state and load virtual playlist
                clearQueue();
                loadVirtualPlaylist(allSongsModel);
                
                // Restore shuffle state if it was enabled
                if (savedShuffleEnabled) {
                    // Make sure shuffle is enabled
                    if (!m_shuffleEnabled) {
                        setShuffleEnabled(true);
                    }
                    
                    // Generate shuffle order with the saved track first
                    m_virtualPlaylist->generateShuffleOrder(virtualTrackIndex);
                    m_virtualShuffleIndex = 0; // Saved track is now at position 0
                }
                
                // Set the virtual indices
                m_virtualCurrentIndex = virtualTrackIndex;
                if (savedShuffleEnabled) {
                    m_virtualShuffleIndex = 0; // Already set above
                }
                
                // Create a proper track object with saved metadata
                Mtoc::Track* track = m_libraryManager->trackByPath(filePath);
                if (track) {
                    // If track metadata wasn't fully loaded, use saved metadata
                    if (track->title().isEmpty() || track->title() == QFileInfo(filePath).baseName()) {
                        track->setTitle(state["trackTitle"].toString());
                        track->setArtist(state["trackArtist"].toString());
                        track->setAlbum(state["trackAlbum"].toString());
                        track->setAlbumArtist(state["trackAlbumArtist"].toString());
                    }
                    
                    // Set up restoration connection
                    if (m_restoreConnection) {
                        disconnect(m_restoreConnection);
                    }
                    
                    m_restoreConnection = connect(m_audioEngine.get(), &AudioEngine::durationChanged, this, [this]() {
                        if (m_audioEngine->duration() > 0) {
                            disconnect(m_restoreConnection);
                            m_restoreConnection = QMetaObject::Connection();
                            onTrackLoadedForRestore();
                        }
                    });
                    
                    // Load the track without auto-playing
                    loadTrack(track, false);
                    emit playbackQueueChanged();
                } else {
                    qWarning() << "MediaPlayer::restoreState - Failed to load track from virtual playlist";
                    clearRestorationState();
                }
                
                return; // Don't continue to other restoration paths
            } else {
                qWarning() << "MediaPlayer::restoreState - Failed to get All Songs playlist";
                // Fall through to regular restoration
            }
        }
        
        // Check if we have a modified queue first (even if from a playlist)
        QString playlistName = state["playlistName"].toString();
        if (queueModified && !queueData.isEmpty()) {
            qDebug() << "MediaPlayer::restoreState - Restoring modified queue";
            
            // Clear current queue and restore from saved data
            clearQueue();
            
            // If this modified queue originated from a playlist, preserve the playlist name
            if (!playlistName.isEmpty()) {
                if (m_currentPlaylistName != playlistName) {
                    m_currentPlaylistName = playlistName;
                    emit currentPlaylistNameChanged(m_currentPlaylistName);
                }
            }
            
            // Build the queue from saved data
            for (const auto& trackData : queueData) {
                auto trackMap = trackData.toMap();
                QString title = trackMap.value("title").toString();
                QString trackFilePath = trackMap.value("filePath").toString();
                
                if (trackFilePath.isEmpty()) {
                    qWarning() << "Empty filePath for track:" << title;
                    continue;
                }
                
                // Create a new Track object from the data
                Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
                
                m_playbackQueue.append(track);
            }
            
            // Restore the modified flag
            setQueueModified(true);
            
            // Set the current queue index
            if (trackIndex >= 0 && trackIndex < m_playbackQueue.size()) {
                m_currentQueueIndex = trackIndex;
                
                // Generate shuffle order if shuffle is enabled
                if (m_shuffleEnabled) {
                    generateShuffleOrder();
                    
                    // After generating shuffle order, find where our current track ended up
                    if (!m_shuffleOrder.isEmpty() && m_currentQueueIndex >= 0) {
                        int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
                        if (shufflePos >= 0) {
                            m_shuffleIndex = shufflePos;
                        }
                    }
                }
                
                emit playbackQueueChanged();
                
                // Set up restoration connection before loading
                if (m_restoreConnection) {
                    disconnect(m_restoreConnection);
                }
                
                m_restoreConnection = connect(m_audioEngine.get(), &AudioEngine::durationChanged, this, [this]() {
                    if (m_audioEngine->duration() > 0) {
                        disconnect(m_restoreConnection);
                        m_restoreConnection = QMetaObject::Connection();
                        onTrackLoadedForRestore();
                    }
                });
                
                // Load the track WITHOUT auto-playing (false parameter)
                Mtoc::Track* trackToRestore = m_playbackQueue[m_currentQueueIndex];
                loadTrack(trackToRestore, false);
            } else {
                qWarning() << "MediaPlayer::restoreState - Invalid track index for modified queue";
                clearRestorationState();
            }
            
            return; // Don't continue to other restoration paths
        }
        
        // Check if we're restoring a playlist (without modifications)
        if (!playlistName.isEmpty()) {
            qDebug() << "MediaPlayer::restoreState - Restoring playlist:" << playlistName;
            
            // Get playlist tracks from PlaylistManager
            PlaylistManager* playlistManager = PlaylistManager::instance();
            auto trackList = playlistManager->loadPlaylist(playlistName);
            
            if (trackList.isEmpty()) {
                qWarning() << "No tracks found in playlist:" << playlistName;
                clearRestorationState();
                return;
            }
            
            // Clear current queue
            clearQueue();
            
            // Set the current playlist name
            if (m_currentPlaylistName != playlistName) {
                m_currentPlaylistName = playlistName;
                emit currentPlaylistNameChanged(m_currentPlaylistName);
            }
            
            // Build tracks from data and add to queue
            for (const auto& trackData : trackList) {
                auto trackMap = trackData.toMap();
                QString trackTitle = trackMap.value("title").toString();
                QString trackFilePath = trackMap.value("filePath").toString();
                
                if (trackFilePath.isEmpty()) {
                    qWarning() << "Empty filePath for track:" << trackTitle;
                    continue;
                }
                
                // Create a new Track object from the data
                Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
                
                m_playbackQueue.append(track);
            }
            
            // Clear the queue modified flag since this is a restored playlist
            setQueueModified(false);
            
            // Ensure trackIndex is within bounds
            trackIndex = qBound(0, trackIndex, m_playbackQueue.size() - 1);
            
            if (!m_playbackQueue.isEmpty()) {
                m_currentQueueIndex = trackIndex;
                
                // Generate shuffle order if shuffle is enabled
                if (m_shuffleEnabled) {
                    generateShuffleOrder();
                    
                    // After generating shuffle order, find where our starting track ended up
                    if (!m_shuffleOrder.isEmpty() && m_currentQueueIndex >= 0) {
                        int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
                        if (shufflePos >= 0) {
                            m_shuffleIndex = shufflePos;
                        }
                    }
                }
                
                emit playbackQueueChanged();
                
                // Set up restoration connection before loading
                if (m_restoreConnection) {
                    disconnect(m_restoreConnection);
                }
                
                m_restoreConnection = connect(m_audioEngine.get(), &AudioEngine::durationChanged, this, [this]() {
                    if (m_audioEngine->duration() > 0) {
                        disconnect(m_restoreConnection);
                        m_restoreConnection = QMetaObject::Connection();
                        onTrackLoadedForRestore();
                    }
                });
                
                // Load the track WITHOUT auto-playing (false parameter)
                loadTrack(m_playbackQueue[trackIndex], false);
            }
            
            return; // Don't continue to other restoration paths
        }
        
        // Check for album-based restoration
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
        
        // Set queue source album info for the header display
        if (m_queueSourceAlbumName != title) {
            m_queueSourceAlbumName = title;
            emit queueSourceAlbumNameChanged(m_queueSourceAlbumName);
        }
        if (m_queueSourceAlbumArtist != artist) {
            m_queueSourceAlbumArtist = artist;
            emit queueSourceAlbumArtistChanged(m_queueSourceAlbumArtist);
        }
        
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
            Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);

            m_playbackQueue.append(track);
        }
        
        qDebug() << "Built queue with" << m_playbackQueue.size() << "tracks";
        
        if (!m_playbackQueue.isEmpty() && trackIndex < m_playbackQueue.size()) {
            m_currentQueueIndex = trackIndex;
            
            // Generate shuffle order if shuffle is enabled
            if (m_shuffleEnabled) {
                generateShuffleOrder();
                
                // After generating shuffle order, we need to find where our current track ended up
                // and update m_shuffleIndex to that position
                if (!m_shuffleOrder.isEmpty() && m_currentQueueIndex >= 0) {
                    int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
                    if (shufflePos >= 0) {
                        m_shuffleIndex = shufflePos;
                    }
                }
            }
            
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
    QVariantMap trackMap;
    trackMap["filePath"] = filePath;
    trackMap["title"] = QFileInfo(filePath).baseName(); // Fallback title
    trackMap["duration"] = duration / 1000; // Convert ms to seconds
    Mtoc::Track* track = Mtoc::Track::fromMetadata(trackMap, this);
    
    // Add to queue so it gets cleaned up properly
    m_playbackQueue.append(track);
    m_currentQueueIndex = 0;
    
    // Generate shuffle order if shuffle is enabled (even for single track)
    if (m_shuffleEnabled) {
        generateShuffleOrder();
        // For a single track, shuffle index will be 0
        m_shuffleIndex = 0;
    }
    
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

void MediaPlayer::updateShuffleOrder()
{
    // Handle virtual playlist shuffle update
    if (m_isVirtualPlaylist && m_virtualPlaylist && m_shuffleEnabled) {
        m_virtualPlaylist->generateShuffleOrder(m_virtualCurrentIndex);
        return;
    }
    
    // Regular queue handling
    // Only update if shuffle is enabled and we have tracks
    if (m_shuffleEnabled && !m_playbackQueue.isEmpty()) {
        // Preserve the played portion of the shuffle order
        QList<int> playedTracks;
        QList<int> unplayedTracks;
        
        // Save already played tracks (up to current position)
        if (m_shuffleIndex >= 0 && m_shuffleIndex < m_shuffleOrder.size()) {
            for (int i = 0; i <= m_shuffleIndex; i++) {
                if (m_shuffleOrder[i] < m_playbackQueue.size()) {
                    playedTracks.append(m_shuffleOrder[i]);
                }
            }
        }
        
        // Find all tracks that haven't been played yet
        for (int i = 0; i < m_playbackQueue.size(); i++) {
            if (!playedTracks.contains(i)) {
                unplayedTracks.append(i);
            }
        }
        
        // Shuffle the unplayed tracks
        std::random_device rd;
        std::mt19937 gen(rd());
        std::shuffle(unplayedTracks.begin(), unplayedTracks.end(), gen);
        
        // Rebuild shuffle order: played tracks + shuffled unplayed tracks
        m_shuffleOrder.clear();
        m_shuffleOrder.append(playedTracks);
        m_shuffleOrder.append(unplayedTracks);
        
        // Update shuffle index to point to current track
        if (m_currentQueueIndex >= 0) {
            int shufflePos = m_shuffleOrder.indexOf(m_currentQueueIndex);
            if (shufflePos >= 0) {
                m_shuffleIndex = shufflePos;
            } else {
                // Current track was removed, reset to beginning of unplayed tracks
                m_shuffleIndex = playedTracks.size() - 1;
                if (m_shuffleIndex < 0) m_shuffleIndex = 0;
            }
        }
    }
}

void MediaPlayer::generateShuffleOrder()
{
    generateShuffleOrder(true);
}

void MediaPlayer::generateShuffleOrder(bool putCurrentTrackFirst)
{
    m_shuffleOrder.clear();
    
    // Handle virtual playlist shuffle generation
    if (m_isVirtualPlaylist && m_virtualPlaylist) {
        // For virtual playlists, generate shuffle order in the VirtualPlaylist object
        m_virtualPlaylist->generateShuffleOrder(putCurrentTrackFirst ? m_virtualCurrentIndex : -1);
        m_shuffleIndex = 0;  // Not used for virtual playlists, but set for consistency
        return;
    }
    
    // Regular queue handling
    if (m_playbackQueue.isEmpty()) {
        m_shuffleIndex = -1;
        return;
    }
    
    // Create list of all indices
    for (int i = 0; i < m_playbackQueue.size(); ++i) {
        m_shuffleOrder.append(i);
    }
    
    // Shuffle all indices using modern C++ random
    std::random_device rd;
    std::mt19937 gen(rd());
    std::shuffle(m_shuffleOrder.begin(), m_shuffleOrder.end(), gen);
    
    // If requested and we have a current track, move it to the beginning
    if (putCurrentTrackFirst && m_currentQueueIndex >= 0 && m_currentQueueIndex < m_playbackQueue.size()) {
        // Find and remove the current track from wherever it is in the shuffle
        int currentPos = m_shuffleOrder.indexOf(m_currentQueueIndex);
        if (currentPos > 0) {
            m_shuffleOrder.removeAt(currentPos);
            m_shuffleOrder.prepend(m_currentQueueIndex);
        }
        // Always set shuffle index to 0 when we have a current track
        m_shuffleIndex = 0;
    } else if (!putCurrentTrackFirst) {
        // When re-shuffling for repeat, start from the beginning of the new shuffle
        m_shuffleIndex = 0;
    } else {
        m_shuffleIndex = -1;
    }
}

int MediaPlayer::getNextShuffleIndex() const
{
    if (!m_shuffleEnabled || m_shuffleOrder.isEmpty()) {
        return -1;
    }
    
    int nextIndex = m_shuffleIndex + 1;
    
    // Check if we need to loop with repeat
    if (nextIndex >= m_shuffleOrder.size()) {
        if (m_repeatEnabled) {
            return 0; // Loop to beginning
        } else {
            return -1; // No more tracks
        }
    }
    
    return nextIndex;
}

int MediaPlayer::getPreviousShuffleIndex() const
{
    if (!m_shuffleEnabled || m_shuffleOrder.isEmpty()) {
        return -1;
    }
    
    int prevIndex = m_shuffleIndex - 1;
    
    // Check if we need to loop with repeat
    if (prevIndex < 0) {
        if (m_repeatEnabled) {
            return m_shuffleOrder.size() - 1; // Loop to end
        } else {
            return -1; // No previous track
        }
    }
    
    return prevIndex;
}

void MediaPlayer::loadVirtualPlaylist(Mtoc::VirtualPlaylistModel* model)
{
    if (!model || !model->virtualPlaylist()) {
        qWarning() << "MediaPlayer: Cannot load null virtual playlist";
        return;
    }
    
    // Clear existing queue and virtual playlist
    clearQueue();
    clearVirtualPlaylist();
    
    // Set up virtual playlist
    m_virtualPlaylist = model->virtualPlaylist();
    m_isVirtualPlaylist = true;
    m_virtualCurrentIndex = -1;
    m_virtualShuffleIndex = -1;
    
    // Set the virtual playlist name - for now, we know it's "All Songs"
    // In the future, this could be passed as a parameter or stored in the model
    m_virtualPlaylistName = "All Songs";
    emit virtualPlaylistNameChanged(m_virtualPlaylistName);
    
    // Generate shuffle order if needed
    if (m_shuffleEnabled) {
        m_virtualPlaylist->generateShuffleOrder();
    }
    
    // Emit queue changed to update UI
    emit playbackQueueChanged();
}

void MediaPlayer::playVirtualPlaylist()
{
    if (!m_isVirtualPlaylist || !m_virtualPlaylist || m_virtualPlaylist->trackCount() == 0) {
        qWarning() << "[MediaPlayer::playVirtualPlaylist] No virtual playlist loaded or empty";
        return;
    }
    
    int firstTrack = 0;
    if (m_shuffleEnabled) {
        // With shuffle enabled, play the first track in shuffle order
        firstTrack = m_virtualPlaylist->getShuffledIndex(0);
        qDebug() << "[MediaPlayer::playVirtualPlaylist] Starting shuffle playback with track:" << firstTrack;
        m_virtualShuffleIndex = 0; // Reset shuffle position
    } else {
        qDebug() << "[MediaPlayer::playVirtualPlaylist] Starting sequential playback";
    }
    
    // Update current index and play
    m_virtualCurrentIndex = firstTrack;
    
    // Preload tracks around the starting position
    preloadVirtualTracks(firstTrack);
    
    // Try to get or create the track - this will trigger loading if needed
    Mtoc::Track* track = getOrCreateTrackFromVirtual(firstTrack);
    if (track) {
        m_waitingForVirtualTrack = false;
        playTrack(track);
        emit playbackQueueChanged();
    } else {
        // Track loading failed or is pending
        qDebug() << "[MediaPlayer::playVirtualPlaylist] Track not loaded yet at index" << firstTrack << ", waiting for load";
        m_waitingForVirtualTrack = true;
        
        // Disconnect any existing connection to prevent leaks
        if (m_virtualTrackLoadConnection) {
            disconnect(m_virtualTrackLoadConnection);
        }
        
        // Set up a connection to retry when tracks are loaded
        m_virtualTrackLoadConnection = connect(m_virtualPlaylist, &Mtoc::VirtualPlaylist::rangeLoaded, this,
                [this, firstTrack](int startIdx, int endIdx) {
                    if (firstTrack >= startIdx && firstTrack <= endIdx) {
                        // Disconnect to avoid multiple attempts
                        disconnect(m_virtualTrackLoadConnection);
                        m_virtualTrackLoadConnection = QMetaObject::Connection();
                        
                        // Try again now that the track should be loaded
                        Mtoc::Track* track = getOrCreateTrackFromVirtual(firstTrack);
                        if (track) {
                            m_waitingForVirtualTrack = false;
                            playTrack(track);
                            emit playbackQueueChanged();
                        } else {
                            qWarning() << "[MediaPlayer::playVirtualPlaylist] Failed to get track even after loading";
                            m_waitingForVirtualTrack = false;
                        }
                    }
                }, Qt::QueuedConnection);
        
        // Ensure the track gets loaded
        m_virtualPlaylist->ensureLoaded(firstTrack);
    }
}

void MediaPlayer::clearVirtualPlaylist()
{
    // Disconnect any pending connection
    if (m_virtualTrackLoadConnection) {
        disconnect(m_virtualTrackLoadConnection);
        m_virtualTrackLoadConnection = QMetaObject::Connection();
    }
    
    m_virtualPlaylist = nullptr;
    m_isVirtualPlaylist = false;
    m_virtualCurrentIndex = -1;
    m_virtualShuffleIndex = -1;
    m_waitingForVirtualTrack = false;
    
    // Clear the virtual playlist name
    if (!m_virtualPlaylistName.isEmpty()) {
        m_virtualPlaylistName.clear();
        emit virtualPlaylistNameChanged(m_virtualPlaylistName);
    }
    
    // Clear buffer - tracks are owned by LibraryManager, don't delete
    m_virtualBufferTracks.clear();
}

void MediaPlayer::loadVirtualPlaylistNext(Mtoc::VirtualPlaylistModel* model)
{
    if (!model || !model->virtualPlaylist()) {
        qWarning() << "MediaPlayer: Cannot load null virtual playlist";
        return;
    }
    
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    qDebug() << "MediaPlayer::loadVirtualPlaylistNext called";
    
    // If we're already in virtual playlist mode, we need to convert to regular queue
    if (m_isVirtualPlaylist) {
        // Convert current virtual playlist state to regular queue
        Mtoc::Track* currentTrack = m_currentTrack;
        int currentPosition = m_virtualCurrentIndex;
        
        // Clear virtual playlist mode
        m_isVirtualPlaylist = false;
        m_virtualPlaylist = nullptr;
        m_virtualCurrentIndex = -1;
        m_virtualShuffleIndex = -1;
        
        // Add current track to regular queue if it exists
        if (currentTrack) {
            m_playbackQueue.append(currentTrack);
            m_currentQueueIndex = 0;
        }
    }
    
    // Get all tracks from the virtual playlist and insert after current
    Mtoc::VirtualPlaylist* vPlaylist = model->virtualPlaylist();
    int insertIndex = m_currentQueueIndex + 1;
    int trackCount = vPlaylist->trackCount();
    
    // We need to create Track objects from the virtual playlist data
    for (int i = 0; i < trackCount; ++i) {
        auto trackData = vPlaylist->getTrackVariant(i);
        if (!trackData.isEmpty()) {
            QString title = trackData.value("title").toString();
            QString filePath = trackData.value("filePath").toString();
            
            if (!filePath.isEmpty()) {
                Mtoc::Track* track = Mtoc::Track::fromMetadata(trackData, this);
                
                m_playbackQueue.insert(insertIndex++, track);
            }
        }
    }
    
    // Mark queue as modified
    setQueueModified(true);
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::loadVirtualPlaylistLast(Mtoc::VirtualPlaylistModel* model)
{
    if (!model || !model->virtualPlaylist()) {
        qWarning() << "MediaPlayer: Cannot load null virtual playlist";
        return;
    }
    
    // Clear undo queue when adding new items
    clearUndoQueue();
    
    qDebug() << "MediaPlayer::loadVirtualPlaylistLast called";
    
    // If we're already in virtual playlist mode, we need to convert to regular queue
    if (m_isVirtualPlaylist) {
        // Convert current virtual playlist state to regular queue
        Mtoc::Track* currentTrack = m_currentTrack;
        int currentPosition = m_virtualCurrentIndex;
        
        // Clear virtual playlist mode
        m_isVirtualPlaylist = false;
        m_virtualPlaylist = nullptr;
        m_virtualCurrentIndex = -1;
        m_virtualShuffleIndex = -1;
        
        // Add current track to regular queue if it exists
        if (currentTrack) {
            m_playbackQueue.append(currentTrack);
            m_currentQueueIndex = 0;
        }
    }
    
    // Get all tracks from the virtual playlist and append
    Mtoc::VirtualPlaylist* vPlaylist = model->virtualPlaylist();
    int trackCount = vPlaylist->trackCount();
    
    // We need to create Track objects from the virtual playlist data
    for (int i = 0; i < trackCount; ++i) {
        auto trackData = vPlaylist->getTrackVariant(i);
        if (!trackData.isEmpty()) {
            QString title = trackData.value("title").toString();
            QString filePath = trackData.value("filePath").toString();
            
            if (!filePath.isEmpty()) {
                Mtoc::Track* track = Mtoc::Track::fromMetadata(trackData, this);
                
                m_playbackQueue.append(track);
            }
        }
    }
    
    // Mark queue as modified
    setQueueModified(true);
    
    emit playbackQueueChanged();
    
    // If nothing is playing, start playback
    if (m_currentQueueIndex < 0 && !m_playbackQueue.isEmpty()) {
        m_currentQueueIndex = 0;
        playTrack(m_playbackQueue[0]);
    }
}

void MediaPlayer::preloadVirtualTracks(int centerIndex)
{
    if (!m_virtualPlaylist || centerIndex < 0) {
        return;
    }
    
    // Monitor memory pressure before preloading
    static qint64 lastMemoryCheck = 0;
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    
    if (now - lastMemoryCheck > 5000) {  // Check every 5 seconds
        int cacheLimit = QPixmapCache::cacheLimit();
        qDebug() << "[MediaPlayer::preloadVirtualTracks] Cache status - Limit:" << cacheLimit / 1024 << "MB";
        lastMemoryCheck = now;
    }
    
    qDebug() << "[MediaPlayer::preloadVirtualTracks] Center index:" << centerIndex 
             << "shuffle enabled:" << m_shuffleEnabled;
    
    if (m_shuffleEnabled) {
        // For shuffle mode, preload the next/previous tracks in shuffle order
        QVector<int> nextTracks = m_virtualPlaylist->getNextShuffleIndices(centerIndex, 2);  // Reduced from 3
        
        // Preload the current track's range first
        m_virtualPlaylist->preloadRange(centerIndex, 1);
        
        // Create Track object for current track only if not already in buffer
        bool currentInBuffer = false;
        for (auto* track : m_virtualBufferTracks) {
            if (track && track->property("virtualIndex").toInt() == centerIndex) {
                currentInBuffer = true;
                break;
            }
        }
        if (!currentInBuffer) {
            getOrCreateTrackFromVirtual(centerIndex);
        }
        
        // Preload next tracks in shuffle order
        for (int trackIndex : nextTracks) {
            m_virtualPlaylist->preloadRange(trackIndex, 1);
            // Only create if not already in buffer
            bool inBuffer = false;
            for (auto* track : m_virtualBufferTracks) {
                if (track && track->property("virtualIndex").toInt() == trackIndex) {
                    inBuffer = true;
                    break;
                }
            }
            if (!inBuffer) {
                getOrCreateTrackFromVirtual(trackIndex);
            }
        }
    } else {
        // Sequential mode - preload tracks around the center index
        const int preloadRadius = 2;  // Reduced from 3
        int startIndex = qMax(0, centerIndex - preloadRadius);
        int endIndex = qMin(m_virtualPlaylist->trackCount() - 1, centerIndex + preloadRadius);
        
        // Request virtual playlist to preload this range
        m_virtualPlaylist->preloadRange(centerIndex, preloadRadius);
        
        // Create Track objects for immediate neighbors only
        for (int i = centerIndex - 1; i <= centerIndex + 1; ++i) {
            if (i >= 0 && i < m_virtualPlaylist->trackCount()) {
                // Only create if not already in buffer
                bool inBuffer = false;
                for (auto* track : m_virtualBufferTracks) {
                    if (track && track->property("virtualIndex").toInt() == i) {
                        inBuffer = true;
                        break;
                    }
                }
                if (!inBuffer) {
                    getOrCreateTrackFromVirtual(i);
                }
            }
        }
    }
}

Mtoc::Track* MediaPlayer::getOrCreateTrackFromVirtual(int index)
{
    if (!m_virtualPlaylist || !m_libraryManager || index < 0 || index >= m_virtualPlaylist->trackCount()) {
        qWarning() << "[MediaPlayer::getOrCreateTrackFromVirtual] Invalid parameters - index:" << index
                   << "virtualPlaylist:" << (m_virtualPlaylist != nullptr)
                   << "trackCount:" << (m_virtualPlaylist ? m_virtualPlaylist->trackCount() : -1);
        return nullptr;
    }
    
    // Check if track is already in buffer
    for (auto* track : m_virtualBufferTracks) {
        if (track && track->property("virtualIndex").toInt() == index) {
            return track;
        }
    }
    
    // Get track data from virtual playlist
    Mtoc::VirtualTrackData trackData = m_virtualPlaylist->getTrack(index);
    if (!trackData.isValid()) {
        // This is expected for tracks not yet loaded - don't warn
        return nullptr;
    }
    
    // Use LibraryManager's trackByPath to get or create Track object
    Mtoc::Track* track = m_libraryManager->trackByPath(trackData.filePath);
    if (track) {
        // Store virtual index for later reference
        track->setProperty("virtualIndex", index);
        
        // Add to buffer if not already there
        bool alreadyInBuffer = false;
        for (auto* bufferTrack : m_virtualBufferTracks) {
            if (bufferTrack == track) {
                alreadyInBuffer = true;
                break;
            }
        }
        
        if (!alreadyInBuffer) {
            m_virtualBufferTracks.append(track);
            
            // Keep buffer size limited - remove oldest tracks
            const int maxBufferSize = 10;
            while (m_virtualBufferTracks.size() > maxBufferSize) {
                // Just remove from buffer, don't delete as LibraryManager owns the tracks
                m_virtualBufferTracks.takeFirst();
            }
        }
    }
    
    return track;
}
