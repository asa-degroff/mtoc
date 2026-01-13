#include "scrobblemanager.h"

#include <QDebug>

#include "backend/playback/mediaplayer.h"
#include "backend/library/track.h"
#include "backend/database/databasemanager.h"
#include "backend/settings/settingsmanager.h"

namespace Mtoc {

ScrobbleManager::ScrobbleManager(QObject *parent)
    : QObject(parent)
{
    qDebug() << "[ScrobbleManager] Initialized";
}

ScrobbleManager::~ScrobbleManager()
{
}

void ScrobbleManager::setMediaPlayer(MediaPlayer* player)
{
    if (m_mediaPlayer) {
        disconnect(m_mediaPlayer, nullptr, this, nullptr);
    }

    m_mediaPlayer = player;

    if (m_mediaPlayer) {
        connect(m_mediaPlayer, &MediaPlayer::currentTrackChanged,
                this, &ScrobbleManager::onTrackChanged);
        connect(m_mediaPlayer, &MediaPlayer::stateChanged,
                this, &ScrobbleManager::onStateChanged);

        // Online scrobbling - position tracking commented out until implemented
        // connect(m_mediaPlayer, &MediaPlayer::positionChanged,
        //         this, &ScrobbleManager::onPositionChanged);

        qDebug() << "[ScrobbleManager] Connected to MediaPlayer";
    }
}

void ScrobbleManager::setDatabaseManager(DatabaseManager* dbManager)
{
    m_dbManager = dbManager;
}

void ScrobbleManager::setSettingsManager(SettingsManager* settingsManager)
{
    if (m_settingsManager) {
        disconnect(m_settingsManager, nullptr, this, nullptr);
    }

    m_settingsManager = settingsManager;

    if (m_settingsManager) {
        // Load initial state from settings
        m_enabled = m_settingsManager->scrobblingEnabled();
        qDebug() << "[ScrobbleManager] Loaded settings - enabled:" << m_enabled;

        // Connect to settings changes
        connect(m_settingsManager, &SettingsManager::scrobblingEnabledChanged,
                this, [this](bool enabled) {
            if (m_enabled != enabled) {
                m_enabled = enabled;
                emit enabledChanged(m_enabled);
                qDebug() << "[ScrobbleManager] Settings changed - enabled:" << m_enabled;
            }
        });
    }
}

void ScrobbleManager::loadSettings()
{
    if (!m_settingsManager) return;
    m_enabled = m_settingsManager->scrobblingEnabled();
}

void ScrobbleManager::saveSettings()
{
    if (!m_settingsManager) return;
    m_settingsManager->setScrobblingEnabled(m_enabled);
}

bool ScrobbleManager::enabled() const
{
    return m_enabled;
}

void ScrobbleManager::setEnabled(bool enabled)
{
    if (m_enabled != enabled) {
        m_enabled = enabled;
        saveSettings();
        emit enabledChanged(m_enabled);
        qDebug() << "[ScrobbleManager] Scrobbling" << (m_enabled ? "enabled" : "disabled");
    }
}

int ScrobbleManager::totalListens() const
{
    if (!m_dbManager) return 0;
    return m_dbManager->getListenCount();
}

bool ScrobbleManager::currentTrackScrobbled() const
{
    return m_currentTrackScrobbled;
}

void ScrobbleManager::scrobbleNow()
{
    if (!m_currentTrack || m_currentTrackScrobbled) {
        qDebug() << "[ScrobbleManager] scrobbleNow: No track or already scrobbled";
        return;
    }

    recordListen();
}

QVariantList ScrobbleManager::getRecentListens(int limit)
{
    if (!m_dbManager) return QVariantList();
    return m_dbManager->getRecentListens(limit, 0);
}

QVariantList ScrobbleManager::getValidRecentListens(int limit)
{
    if (!m_dbManager) return QVariantList();
    return m_dbManager->getValidRecentListens(limit);
}

void ScrobbleManager::clearHistory()
{
    if (!m_dbManager) {
        qWarning() << "[ScrobbleManager] Cannot clear history: no database manager";
        return;
    }

    if (m_dbManager->clearListens()) {
        emit historyCleared();
        emit totalListensChanged(0);
        qDebug() << "[ScrobbleManager] History cleared";
    }
}

void ScrobbleManager::onTrackChanged(Track* track)
{
    // Reset state for new track
    resetTrackState();

    if (!track) {
        qDebug() << "[ScrobbleManager] Track cleared";
        return;
    }

    m_currentTrack = track;
    m_trackStartTime = QDateTime::currentSecsSinceEpoch();

    qDebug() << "[ScrobbleManager] New track:" << track->title()
             << "by" << track->artist();

    // LOCAL HISTORY: Record immediately when playback starts.
    // This gives users a complete history of what they played, even if they skip tracks.
    // Skip if restoring state from previous session (track was already recorded).
    if (m_enabled && m_mediaPlayer && !m_mediaPlayer->isRestoringState()) {
        recordListen();
    }
}

void ScrobbleManager::onPositionChanged(qint64 position)
{
    Q_UNUSED(position);
    // Online scrobbling - position tracking commented out until implemented
    // This was used to:
    // 1. Track accumulated listen time for scrobble threshold
    // 2. Report scrobbleProgress to UI
    // 3. Emit scrobbleThresholdReached when threshold met
}

void ScrobbleManager::onStateChanged(int state)
{
    MediaPlayer::State playerState = static_cast<MediaPlayer::State>(state);

    bool wasPlaying = m_isPlaying;
    m_isPlaying = (playerState == MediaPlayer::PlayingState);

    if (wasPlaying && !m_isPlaying) {
        qDebug() << "[ScrobbleManager] Playback paused/stopped";
    } else if (!wasPlaying && m_isPlaying) {
        qDebug() << "[ScrobbleManager] Playback resumed";
    }
}

void ScrobbleManager::resetTrackState()
{
    m_currentTrack = nullptr;
    m_trackStartTime = 0;

    if (m_currentTrackScrobbled) {
        m_currentTrackScrobbled = false;
        emit currentTrackScrobbledChanged(false);
    }
}

void ScrobbleManager::recordListen()
{
    if (!m_currentTrack || !m_dbManager) {
        qWarning() << "[ScrobbleManager] Cannot record listen: missing track or database";
        return;
    }

    // For local playback history, record any playback regardless of duration

    QVariantMap listenData;
    // Use NULL for track_id if it's 0 (track not in database) to satisfy foreign key constraint
    int trackId = m_currentTrack->id();
    listenData["track_id"] = (trackId > 0) ? QVariant(trackId) : QVariant();
    listenData["track_name"] = m_currentTrack->title();
    listenData["artist_name"] = m_currentTrack->artist();
    listenData["album_name"] = m_currentTrack->album();
    listenData["duration_seconds"] = m_currentTrack->duration();
    listenData["listened_at"] = m_trackStartTime;
    listenData["listen_duration"] = 0; // Not tracking duration for local history

    int listenId = m_dbManager->insertListen(listenData);

    if (listenId > 0) {
        m_currentTrackScrobbled = true;
        emit currentTrackScrobbledChanged(true);
        emit listenRecorded(m_currentTrack->title(), m_currentTrack->artist());
        emit totalListensChanged(m_dbManager->getListenCount());

        qDebug() << "[ScrobbleManager] Listen recorded:" << m_currentTrack->title()
                 << "by" << m_currentTrack->artist();
    }
}

// ============================================================================
// Online scrobbling - commented out until implemented
// ============================================================================
/*
void ScrobbleManager::checkScrobbleThreshold()
{
    // ONLINE SCROBBLING: Check if we've reached the scrobble threshold.
    // Online services (ListenBrainz, Last.fm) require listening to a minimum duration
    // before a play "counts" as a scrobble. This emits a signal when threshold is reached.
    // Note: Local history is recorded immediately in onTrackChanged() - this is separate.

    if (m_thresholdSignalEmitted || !m_currentTrack || m_scrobbleThreshold <= 0) {
        return;
    }

    if (m_accumulatedTime >= m_scrobbleThreshold) {
        m_thresholdSignalEmitted = true;
        qDebug() << "[ScrobbleManager] Scrobble threshold reached:"
                 << m_accumulatedTime << ">=" << m_scrobbleThreshold << "ms";
        emit scrobbleThresholdReached();
    }
}

qint64 ScrobbleManager::calculateThreshold(qint64 durationMs) const
{
    // ListenBrainz rule: half the track or 4 minutes, whichever is LOWER
    // This is more conservative and ensures compatibility with both services

    const qint64 fourMinutesMs = 4 * 60 * 1000; // 240000 ms
    const qint64 halfTrack = durationMs / 2;

    return qMin(halfTrack, fourMinutesMs);
}
*/
// ============================================================================

} // namespace Mtoc
