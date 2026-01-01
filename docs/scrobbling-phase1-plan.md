# Phase 1: Scrobbling Foundation Implementation Plan

*Created: 2025-12-31*

This document outlines the implementation plan for Phase 1 of scrobbling integration, which establishes the foundation for listen tracking without external service integration.

## Goals

- Track all completed listens locally in the database
- Implement scrobble threshold detection logic
- Create ScrobbleManager class to coordinate listen tracking
- Prepare database schema for future service integrations

---

## 1. Database Schema Changes

### File: `src/backend/database/databasemanager.cpp`

Add migration to create the `listens` table.

```sql
CREATE TABLE IF NOT EXISTS listens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    track_id INTEGER,
    track_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    album_name TEXT,
    duration_seconds INTEGER,
    listened_at INTEGER NOT NULL,
    listen_duration INTEGER,

    -- MusicBrainz metadata (for future use)
    recording_mbid TEXT,
    artist_mbid TEXT,
    release_mbid TEXT,
    isrc TEXT,

    -- Service submission tracking
    listenbrainz_submitted INTEGER DEFAULT 0,
    listenbrainz_submitted_at INTEGER,
    tealfm_submitted INTEGER DEFAULT 0,
    tealfm_submitted_at INTEGER,

    -- Retry logic
    submission_attempts INTEGER DEFAULT 0,
    last_error TEXT,

    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_listens_listened_at ON listens(listened_at DESC);
CREATE INDEX IF NOT EXISTS idx_listens_pending ON listens(listenbrainz_submitted, tealfm_submitted);
CREATE INDEX IF NOT EXISTS idx_listens_track_id ON listens(track_id);
```

### DatabaseManager Methods to Add

```cpp
// Listen operations
int insertListen(const QVariantMap& listenData);
QVariantList getRecentListens(int limit = 50, int offset = 0);
QVariantList getPendingListens(const QString& service); // "listenbrainz" or "tealfm"
bool markListenSubmitted(int listenId, const QString& service);
bool updateListenError(int listenId, const QString& error);
int getListenCount();
int getPendingListenCount(const QString& service);

// Statistics (optional, for future listen history UI)
QVariantMap getListeningStats(); // total listens, top artists, etc.
```

---

## 2. ScrobbleManager Class

### Files to Create

- `src/backend/scrobble/scrobblemanager.h`
- `src/backend/scrobble/scrobblemanager.cpp`

### Header Structure

```cpp
#ifndef SCROBBLEMANAGER_H
#define SCROBBLEMANAGER_H

#include <QObject>
#include <QPointer>
#include <QTimer>

namespace Mtoc {
class Track;
class DatabaseManager;
}

class MediaPlayer;

class ScrobbleManager : public QObject
{
    Q_OBJECT

    // Scrobbling enabled state
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

    // Statistics
    Q_PROPERTY(int totalListens READ totalListens NOTIFY totalListensChanged)
    Q_PROPERTY(int pendingListenBrainz READ pendingListenBrainz NOTIFY pendingListenBrainzChanged)
    Q_PROPERTY(int pendingTealFm READ pendingTealFm NOTIFY pendingTealFmChanged)

    // Current track scrobble state
    Q_PROPERTY(bool currentTrackScrobbled READ currentTrackScrobbled NOTIFY currentTrackScrobbledChanged)
    Q_PROPERTY(float scrobbleProgress READ scrobbleProgress NOTIFY scrobbleProgressChanged)

public:
    explicit ScrobbleManager(QObject *parent = nullptr);
    ~ScrobbleManager();

    void setMediaPlayer(MediaPlayer* player);
    void setDatabaseManager(Mtoc::DatabaseManager* dbManager);

    // Properties
    bool enabled() const;
    void setEnabled(bool enabled);

    int totalListens() const;
    int pendingListenBrainz() const;
    int pendingTealFm() const;

    bool currentTrackScrobbled() const;
    float scrobbleProgress() const; // 0.0 to 1.0, 1.0 = threshold reached

    // Manual operations
    Q_INVOKABLE void scrobbleNow(); // Force scrobble current track
    Q_INVOKABLE QVariantList getRecentListens(int limit = 50);

signals:
    void enabledChanged(bool enabled);
    void totalListensChanged(int count);
    void pendingListenBrainzChanged(int count);
    void pendingTealFmChanged(int count);
    void currentTrackScrobbledChanged(bool scrobbled);
    void scrobbleProgressChanged(float progress);

    void listenRecorded(const QString& trackName, const QString& artistName);
    void scrobbleThresholdReached();

private slots:
    void onTrackChanged(Mtoc::Track* track);
    void onPositionChanged(qint64 position);
    void onStateChanged(int state);

private:
    void resetTrackState();
    void checkScrobbleThreshold();
    void recordListen();
    qint64 calculateThreshold(qint64 durationMs) const;

    MediaPlayer* m_mediaPlayer = nullptr;
    Mtoc::DatabaseManager* m_dbManager = nullptr;

    bool m_enabled = true;

    // Current track state
    QPointer<Mtoc::Track> m_currentTrack;
    qint64 m_trackStartTime = 0;        // Unix timestamp when track started
    qint64 m_accumulatedTime = 0;       // Time listened (handles pause/resume)
    qint64 m_lastPosition = 0;          // For detecting seeks
    qint64 m_scrobbleThreshold = 0;     // Threshold for current track
    bool m_currentTrackScrobbled = false;
    bool m_isPlaying = false;

    // Seek detection
    static constexpr qint64 SEEK_THRESHOLD_MS = 3000; // 3 second tolerance
};

#endif // SCROBBLEMANAGER_H
```

### Implementation Notes

#### Scrobble Threshold Calculation

```cpp
qint64 ScrobbleManager::calculateThreshold(qint64 durationMs) const
{
    // ListenBrainz rule: half the track or 4 minutes, whichever is LOWER
    // teal.fm rule: half the track or 4 minutes, whichever is LONGER (for tracks >= 2min)

    // We'll use the ListenBrainz rule as it's more conservative
    // This ensures compatibility with both services

    const qint64 fourMinutesMs = 4 * 60 * 1000; // 240000ms
    const qint64 halfTrack = durationMs / 2;

    return qMin(halfTrack, fourMinutesMs);
}
```

#### Position Tracking Logic

```cpp
void ScrobbleManager::onPositionChanged(qint64 position)
{
    if (!m_isPlaying || !m_currentTrack || m_currentTrackScrobbled)
        return;

    // Detect seeks (position jumped significantly)
    qint64 expectedPosition = m_lastPosition + 100; // ~100ms update interval
    qint64 positionDelta = qAbs(position - expectedPosition);

    if (positionDelta > SEEK_THRESHOLD_MS) {
        // User seeked - don't count this time
        // Just update lastPosition without adding to accumulated
    } else {
        // Normal playback - accumulate time
        m_accumulatedTime += (position - m_lastPosition);
    }

    m_lastPosition = position;

    // Update progress
    float progress = static_cast<float>(m_accumulatedTime) / m_scrobbleThreshold;
    emit scrobbleProgressChanged(qMin(progress, 1.0f));

    checkScrobbleThreshold();
}
```

#### Recording a Listen

```cpp
void ScrobbleManager::recordListen()
{
    if (!m_currentTrack || !m_dbManager)
        return;

    QVariantMap listenData;
    listenData["track_id"] = m_currentTrack->id();
    listenData["track_name"] = m_currentTrack->title();
    listenData["artist_name"] = m_currentTrack->artist();
    listenData["album_name"] = m_currentTrack->album();
    listenData["duration_seconds"] = m_currentTrack->duration();
    listenData["listened_at"] = m_trackStartTime;
    listenData["listen_duration"] = m_accumulatedTime / 1000; // Convert to seconds

    // TODO: Add MusicBrainz IDs when available in Track model
    // listenData["recording_mbid"] = m_currentTrack->recordingMbid();

    int listenId = m_dbManager->insertListen(listenData);

    if (listenId > 0) {
        m_currentTrackScrobbled = true;
        emit currentTrackScrobbledChanged(true);
        emit listenRecorded(m_currentTrack->title(), m_currentTrack->artist());
        emit totalListensChanged(m_dbManager->getListenCount());
    }
}
```

---

## 3. Integration Points

### main.cpp Changes

```cpp
#include "backend/scrobble/scrobblemanager.h"

// After creating MediaPlayer and DatabaseManager:
ScrobbleManager* scrobbleManager = new ScrobbleManager(&app);
scrobbleManager->setMediaPlayer(mediaPlayer);
scrobbleManager->setDatabaseManager(databaseManager);

qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "ScrobbleManager", scrobbleManager);
```

### CMakeLists.txt Changes

Add to `PROJECT_SOURCES`:
```cmake
src/backend/scrobble/scrobblemanager.h
src/backend/scrobble/scrobblemanager.cpp
```

---

## 4. Settings Integration

### SettingsManager Additions

```cpp
// New properties for scrobbling settings
Q_PROPERTY(bool scrobblingEnabled READ scrobblingEnabled WRITE setScrobblingEnabled NOTIFY scrobblingEnabledChanged)

bool scrobblingEnabled() const;
void setScrobblingEnabled(bool enabled);
```

Storage key: `scrobbling/enabled` (default: `true`)

---

## 5. Implementation Order

1. **Database migration** - Add `listens` table and methods to DatabaseManager
2. **ScrobbleManager skeleton** - Create class with properties and signals
3. **MediaPlayer integration** - Connect signals for track/position/state changes
4. **Threshold logic** - Implement scrobble detection algorithm
5. **Listen recording** - Store listens in database
6. **Settings integration** - Enable/disable scrobbling
7. **Testing** - Verify with various playback scenarios

---

## 6. Testing Scenarios

- [ ] Short track (<2 min): Should scrobble at half duration
- [ ] Long track (>8 min): Should scrobble at 4 minutes
- [ ] Pause/resume: Accumulated time should be correct
- [ ] Seek forward: Should not count skipped time
- [ ] Seek backward: Should not double-count time
- [ ] Track skip before threshold: Should not scrobble
- [ ] Gapless transition: Should scrobble completed track, reset for new
- [ ] App restart: Pending listens should persist

---

## 7. Future Considerations (Phase 2+)

- ListenBrainz `playing_now` notification on track start
- Retry logic for failed submissions
- Offline queue processing when network available
- Listen history UI in settings
- Export listen history
- MusicBrainz ID lookup integration
