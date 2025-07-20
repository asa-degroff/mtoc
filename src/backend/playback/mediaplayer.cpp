#include "mediaplayer.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/library/librarymanager.h"
#include "backend/settings/settingsmanager.h"
#include "backend/playlist/VirtualPlaylistModel.h"
#include "backend/playlist/VirtualPlaylist.h"
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
    
    // Load initial repeat/shuffle states from settings
    if (m_settingsManager) {
        setRepeatEnabled(m_settingsManager->repeatEnabled());
        setShuffleEnabled(m_settingsManager->shuffleEnabled());
        
        // Sync settings when they change
        connect(this, &MediaPlayer::repeatEnabledChanged,
                m_settingsManager, &SettingsManager::setRepeatEnabled);
        connect(this, &MediaPlayer::shuffleEnabledChanged,
                m_settingsManager, &SettingsManager::setShuffleEnabled);
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
    // For virtual playlists, we can't easily calculate total duration without loading all tracks
    // Return 0 for now - UI should get this info from PlaylistManager if needed
    if (m_isVirtualPlaylist) {
        return 0;
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
            m_currentQueueIndex = m_shuffleOrder[m_shuffleIndex];
            Mtoc::Track* prevTrack = m_playbackQueue[m_currentQueueIndex];
            playTrack(prevTrack);
            emit playbackQueueChanged();
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
            
            // Set up a connection to retry when the track is loaded
            QMetaObject::Connection* connection = new QMetaObject::Connection();
            *connection = connect(m_virtualPlaylist, &Mtoc::VirtualPlaylist::rangeLoaded, this,
                    [this, index, connection](int startIdx, int endIdx) {
                        if (index >= startIdx && index <= endIdx) {
                            // Disconnect to avoid multiple attempts
                            disconnect(*connection);
                            delete connection;
                            
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

void MediaPlayer::clearQueue()
{
    // Clear virtual playlist if active
    if (m_isVirtualPlaylist) {
        clearVirtualPlaylist();
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
    Mtoc::Track* track = new Mtoc::Track(this);
    track->setTitle(title);
    track->setArtist(trackMap.value("artist").toString());
    track->setAlbum(trackMap.value("album").toString());
    track->setAlbumArtist(trackMap.value("albumArtist").toString());
    track->setTrackNumber(trackMap.value("trackNumber").toInt());
    // Duration from playlist is already in seconds (from library) or milliseconds (from queue)
    // We need to handle both cases - tracks store duration in seconds
    int duration = trackMap.value("duration").toInt();
    if (duration > 10000) { // Likely in milliseconds if > 10000
        duration = duration / 1000;
    }
    track->setDuration(duration);
    track->setFileUrl(QUrl::fromLocalFile(filePath));
    
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
    if (m_shuffleEnabled && !m_playbackQueue.isEmpty()) {
        // Add the new track index to shuffle order after current position
        int newTrackIndex = insertIndex;
        if (m_shuffleIndex >= 0 && m_shuffleIndex < m_shuffleOrder.size() - 1) {
            m_shuffleOrder.insert(m_shuffleIndex + 1, newTrackIndex);
            // Adjust indices after insertion
            for (int i = m_shuffleIndex + 2; i < m_shuffleOrder.size(); ++i) {
                if (m_shuffleOrder[i] >= newTrackIndex) {
                    m_shuffleOrder[i]++;
                }
            }
        } else {
            m_shuffleOrder.append(newTrackIndex);
        }
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
        // No more tracks and repeat is off
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
                                        m_isQueueModified, queueData, virtualPlaylistInfo);
    
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
        
        // Set up a connection to retry when tracks are loaded
        QMetaObject::Connection* connection = new QMetaObject::Connection();
        *connection = connect(m_virtualPlaylist, &Mtoc::VirtualPlaylist::rangeLoaded, this,
                [this, firstTrack, connection](int startIdx, int endIdx) {
                    if (firstTrack >= startIdx && firstTrack <= endIdx) {
                        // Disconnect to avoid multiple attempts
                        disconnect(*connection);
                        delete connection;
                        
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
    m_virtualPlaylist = nullptr;
    m_isVirtualPlaylist = false;
    m_virtualCurrentIndex = -1;
    m_virtualShuffleIndex = -1;
    m_waitingForVirtualTrack = false;
    
    // Clear buffer - tracks are owned by LibraryManager, don't delete
    m_virtualBufferTracks.clear();
}

void MediaPlayer::preloadVirtualTracks(int centerIndex)
{
    if (!m_virtualPlaylist || centerIndex < 0) {
        return;
    }
    
    qDebug() << "[MediaPlayer::preloadVirtualTracks] Center index:" << centerIndex 
             << "shuffle enabled:" << m_shuffleEnabled;
    
    if (m_shuffleEnabled) {
        // For shuffle mode, preload the next/previous tracks in shuffle order
        QVector<int> nextTracks = m_virtualPlaylist->getNextShuffleIndices(centerIndex, 3);
        
        // Preload the current track's range first
        m_virtualPlaylist->preloadRange(centerIndex, 1);
        
        // Create Track object for current track
        getOrCreateTrackFromVirtual(centerIndex);
        
        // Preload next tracks in shuffle order
        for (int trackIndex : nextTracks) {
            m_virtualPlaylist->preloadRange(trackIndex, 1);
            getOrCreateTrackFromVirtual(trackIndex);
        }
    } else {
        // Sequential mode - preload tracks around the center index
        const int preloadRadius = 3;  // Load 3 tracks before and after
        int startIndex = qMax(0, centerIndex - preloadRadius);
        int endIndex = qMin(m_virtualPlaylist->trackCount() - 1, centerIndex + preloadRadius);
        
        // Request virtual playlist to preload this range
        m_virtualPlaylist->preloadRange(centerIndex, preloadRadius);
        
        // Create Track objects for immediate neighbors
        for (int i = centerIndex - 1; i <= centerIndex + 1; ++i) {
            if (i >= 0 && i < m_virtualPlaylist->trackCount()) {
                getOrCreateTrackFromVirtual(i);
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
        m_virtualBufferTracks.append(track);
        
        // Keep buffer size limited
        const int maxBufferSize = 10;
        while (m_virtualBufferTracks.size() > maxBufferSize) {
            // Just remove from buffer, don't delete as LibraryManager owns the tracks
            m_virtualBufferTracks.takeFirst();
        }
    }
    
    return track;
}