#include "scrobblemanager.h"

#include <QDebug>

#include "backend/playback/mediaplayer.h"
#include "backend/library/track.h"
#include "backend/database/databasemanager.h"
#include "backend/settings/settingsmanager.h"

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
        connect(m_mediaPlayer, &MediaPlayer::positionChanged,
                this, &ScrobbleManager::onPositionChanged);
        connect(m_mediaPlayer, &MediaPlayer::stateChanged,
                this, &ScrobbleManager::onStateChanged);

        qDebug() << "[ScrobbleManager] Connected to MediaPlayer";
    }
}

void ScrobbleManager::setDatabaseManager(Mtoc::DatabaseManager* dbManager)
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

int ScrobbleManager::pendingListenBrainz() const
{
    if (!m_dbManager) return 0;
    return m_dbManager->getPendingListenCount("listenbrainz");
}

int ScrobbleManager::pendingTealFm() const
{
    if (!m_dbManager) return 0;
    return m_dbManager->getPendingListenCount("tealfm");
}

bool ScrobbleManager::currentTrackScrobbled() const
{
    return m_currentTrackScrobbled;
}

float ScrobbleManager::scrobbleProgress() const
{
    if (m_scrobbleThreshold <= 0) return 0.0f;
    return qMin(static_cast<float>(m_accumulatedTime) / m_scrobbleThreshold, 1.0f);
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
        emit pendingListenBrainzChanged(0);
        emit pendingTealFmChanged(0);
        qDebug() << "[ScrobbleManager] History cleared";
    }
}

void ScrobbleManager::onTrackChanged(Mtoc::Track* track)
{
    // Reset state for new track
    resetTrackState();

    if (!track) {
        qDebug() << "[ScrobbleManager] Track cleared";
        return;
    }

    m_currentTrack = track;
    m_trackStartTime = QDateTime::currentSecsSinceEpoch();

    // Calculate scrobble threshold based on track duration (for future online scrobbling)
    qint64 durationMs = track->duration() * 1000; // Track stores duration in seconds
    m_scrobbleThreshold = calculateThreshold(durationMs);

    qDebug() << "[ScrobbleManager] New track:" << track->title()
             << "by" << track->artist()
             << "- duration:" << durationMs << "ms";

    // Record to local history immediately when playback starts
    // (Future online scrobbling will use the threshold-based approach)
    if (m_enabled) {
        recordListen();
    }

    emit scrobbleProgressChanged(0.0f);
}

void ScrobbleManager::onPositionChanged(qint64 position)
{
    if (!m_enabled || !m_isPlaying || !m_currentTrack || m_currentTrackScrobbled) {
        return;
    }

    // Detect seeks by checking if position jumped significantly
    qint64 expectedPosition = m_lastPosition + 100; // Approximate update interval
    qint64 positionDelta = qAbs(position - expectedPosition);

    if (m_lastPosition > 0 && positionDelta > SEEK_THRESHOLD_MS) {
        // User seeked - don't count this time jump
        qDebug() << "[ScrobbleManager] Seek detected: expected" << expectedPosition
                 << "got" << position << "(delta:" << positionDelta << "ms)";
    } else if (m_lastPosition > 0) {
        // Normal playback - accumulate the time difference
        qint64 timeDelta = position - m_lastPosition;
        if (timeDelta > 0 && timeDelta < SEEK_THRESHOLD_MS) {
            m_accumulatedTime += timeDelta;
        }
    }

    m_lastPosition = position;

    // Update progress
    float progress = scrobbleProgress();
    emit scrobbleProgressChanged(progress);

    // Check if we've reached the threshold
    checkScrobbleThreshold();
}

void ScrobbleManager::onStateChanged(int state)
{
    MediaPlayer::State playerState = static_cast<MediaPlayer::State>(state);

    bool wasPlaying = m_isPlaying;
    m_isPlaying = (playerState == MediaPlayer::PlayingState);

    if (wasPlaying && !m_isPlaying) {
        // Paused or stopped - we keep the accumulated time
        qDebug() << "[ScrobbleManager] Playback paused/stopped - accumulated:"
                 << m_accumulatedTime << "ms";
    } else if (!wasPlaying && m_isPlaying) {
        // Resumed playback
        qDebug() << "[ScrobbleManager] Playback resumed";
    }
}

void ScrobbleManager::resetTrackState()
{
    m_currentTrack = nullptr;
    m_trackStartTime = 0;
    m_accumulatedTime = 0;
    m_lastPosition = 0;
    m_scrobbleThreshold = 0;

    if (m_currentTrackScrobbled) {
        m_currentTrackScrobbled = false;
        emit currentTrackScrobbledChanged(false);
    }
}

void ScrobbleManager::checkScrobbleThreshold()
{
    if (m_currentTrackScrobbled || !m_currentTrack || m_scrobbleThreshold <= 0) {
        return;
    }

    if (m_accumulatedTime >= m_scrobbleThreshold) {
        qDebug() << "[ScrobbleManager] Scrobble threshold reached:"
                 << m_accumulatedTime << ">=" << m_scrobbleThreshold << "ms";
        emit scrobbleThresholdReached();
        recordListen();
    }
}

void ScrobbleManager::recordListen()
{
    if (!m_currentTrack || !m_dbManager) {
        qWarning() << "[ScrobbleManager] Cannot record listen: missing track or database";
        return;
    }

    // For local playback history, record any playback regardless of duration
    // (Future online scrobbling may re-introduce minimum duration checks)

    QVariantMap listenData;
    listenData["track_id"] = m_currentTrack->id();
    listenData["track_name"] = m_currentTrack->title();
    listenData["artist_name"] = m_currentTrack->artist();
    listenData["album_name"] = m_currentTrack->album();
    listenData["duration_seconds"] = m_currentTrack->duration();
    listenData["listened_at"] = m_trackStartTime;
    listenData["listen_duration"] = m_accumulatedTime / 1000; // Convert to seconds

    int listenId = m_dbManager->insertListen(listenData);

    if (listenId > 0) {
        m_currentTrackScrobbled = true;
        emit currentTrackScrobbledChanged(true);
        emit listenRecorded(m_currentTrack->title(), m_currentTrack->artist());
        emit totalListensChanged(m_dbManager->getListenCount());
        emit pendingListenBrainzChanged(pendingListenBrainz());
        emit pendingTealFmChanged(pendingTealFm());

        qDebug() << "[ScrobbleManager] Listen recorded:" << m_currentTrack->title()
                 << "by" << m_currentTrack->artist()
                 << "(listened" << (m_accumulatedTime / 1000) << "seconds)";
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
