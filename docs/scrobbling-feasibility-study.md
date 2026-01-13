# Scrobbling Integration Feasibility Study

*Created: 2025-12-31*

## Executive Summary

Integrating scrobbling with **ListenBrainz** is **highly feasible** with their well-documented REST API. **teal.fm** integration is promising but requires waiting for their API to stabilize, as the project is still in development.

---

## 1. ListenBrainz Integration

**Status:** Ready for implementation

### API Overview

| Aspect | Details |
|--------|---------|
| **Endpoint** | `POST https://api.listenbrainz.org/1/submit-listens` |
| **Auth** | Token-based: `Authorization: Token {user_token}` |
| **Format** | JSON |
| **Rate Limits** | Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset-In` |

### Submission Types

1. **`playing_now`** - Current track notification (no timestamp, temporary)
2. **`single`** - Completed listen with Unix timestamp
3. **`import`** - Batch historical import

### Required Fields

```json
{
  "listen_type": "single",
  "payload": [{
    "listened_at": 1703980800,
    "track_metadata": {
      "artist_name": "Artist Name",
      "track_name": "Track Title",
      "release_name": "Album Name"
    }
  }]
}
```

### Optional Fields (Recommended)

- `duration_ms` - Track duration
- `recording_mbid`, `artist_mbids`, `release_mbid` - MusicBrainz IDs
- `submission_client` / `submission_client_version` - Client identification
- `isrc` - International Standard Recording Code

### Scrobble Threshold

> Listens should be submitted when the user has listened to **half the track or 4 minutes**, whichever is lower.

---

## 2. teal.fm Integration

**Status:** In development (coming soon)

### Architecture

teal.fm uses **AT Protocol** (same as Bluesky) with custom lexicons under `fm.teal.alpha`:
- `/feed/play.json` - Play record schema
- `/feed/getPlay.json` - Retrieve play records
- `/feed/getActorFeed.json` - User feed retrieval

### Play Record Schema (`fm.teal.alpha.feed.play`)

**Required:**
- `trackName` (string, 1-256 chars)

**Optional:**
- `trackMbId`, `recordingMbId` - MusicBrainz IDs
- `duration` (integer, seconds)
- `artistNames` (array), `artists` (array of objects)
- `releaseName`, `releaseMbId`
- `isrc`, `originUrl`
- `musicServiceBaseDomain` (defaults to 'local')
- `submissionClientAgent` (format: `app-identifier/version`)
- `playedTime` (datetime)

### Scrobble Threshold

> Plays should be tracked when a user has listened to the **entire track if under 2 minutes**, or **half of the track's duration up to 4 minutes**, whichever is longest.

### Integration Notes

- Requires AT Protocol authentication (DID-based identity)
- Records are written to user's personal data repository (PDS)
- No REST API documentation yet - would need AT Protocol XRPC calls

---

## 3. mtoc Preparatory Changes

### Current State

mtoc has signals for tracking playback events:
- `MediaPlayer::stateChanged()` - Play/pause/stop transitions
- `MediaPlayer::currentTrackChanged()` - Track changes
- `MediaPlayer::positionChanged()` - Playback position updates
- `handleTrackFinished()` - Track completion

**Missing:** No listen history tracking or database table for listens.

### Recommended Preparations

#### 3.1 Database Schema for Listen History

```sql
CREATE TABLE listens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    track_id INTEGER,                    -- FK to tracks table (nullable for external)
    track_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    album_name TEXT,
    duration_seconds INTEGER,
    listened_at INTEGER NOT NULL,        -- Unix timestamp
    listen_duration INTEGER,             -- Actual time listened (seconds)

    -- Optional metadata for enhanced scrobbling
    recording_mbid TEXT,
    artist_mbid TEXT,
    release_mbid TEXT,
    isrc TEXT,

    -- Scrobble status
    listenbrainz_submitted INTEGER DEFAULT 0,
    listenbrainz_submitted_at INTEGER,
    tealfm_submitted INTEGER DEFAULT 0,
    tealfm_submitted_at INTEGER,

    -- For offline scrobbling / retry logic
    submission_attempts INTEGER DEFAULT 0,
    last_error TEXT,

    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE SET NULL
);

CREATE INDEX idx_listens_submitted ON listens(listenbrainz_submitted, tealfm_submitted);
CREATE INDEX idx_listens_listened_at ON listens(listened_at);
```

#### 3.2 New ScrobbleManager Class

Location: `src/backend/scrobble/scrobblemanager.{h,cpp}`

**Responsibilities:**
- Track playback duration (connect to `MediaPlayer::positionChanged`)
- Detect when scrobble threshold is reached
- Queue listens to database
- Submit to enabled services (async, with retry)
- Handle offline mode / queue pending submissions

**Key Properties:**
```cpp
Q_PROPERTY(bool listenBrainzEnabled READ listenBrainzEnabled WRITE setListenBrainzEnabled NOTIFY listenBrainzEnabledChanged)
Q_PROPERTY(bool tealFmEnabled READ tealFmEnabled WRITE setTealFmEnabled NOTIFY tealFmEnabledChanged)
Q_PROPERTY(QString listenBrainzToken READ listenBrainzToken WRITE setListenBrainzToken NOTIFY listenBrainzTokenChanged)
Q_PROPERTY(int pendingScrobbles READ pendingScrobbles NOTIFY pendingScrobblesChanged)
```

#### 3.3 Settings UI

Add to SettingsWindow.qml:
- ListenBrainz section: Enable toggle, token input field, test connection button
- teal.fm section: Enable toggle, AT Protocol login flow (when available)
- Scrobble history view (optional)

#### 3.4 Network Layer

Would need Qt Network additions:
- `QNetworkAccessManager` for REST calls
- JSON serialization with `QJsonDocument`
- Rate limit handling
- Retry logic with exponential backoff

---

## 4. Implementation Phases

### Phase 1: Foundation (Can start now)
1. Add `listens` table to DatabaseManager
2. Create ScrobbleManager skeleton class
3. Implement listen threshold detection
4. Store local listen history

### Phase 2: ListenBrainz Integration
1. Implement ListenBrainz API client
2. Add settings UI for token configuration
3. Submit `playing_now` on track start
4. Submit `single` listen when threshold reached
5. Handle offline queue and retry

### Phase 3: teal.fm Integration (When API stabilizes)
1. Implement AT Protocol authentication
2. Add play record creation via XRPC
3. Integrate with ScrobbleManager

---

## 5. Technical Considerations

| Concern | Mitigation |
|---------|------------|
| **Offline playback** | Queue to local DB, sync when online |
| **Privacy** | Clear opt-in, token stored securely |
| **Rate limits** | Respect headers, batch imports |
| **Duplicate scrobbles** | Track submission state in DB |
| **Gapless playback** | Handle `onTrackTransitioned()` signal |
| **Seek behavior** | Track actual listen duration vs position |

---

## Sources

- [ListenBrainz API Documentation](https://listenbrainz.readthedocs.io/en/latest/users/api/index.html)
- [ListenBrainz JSON Format](https://listenbrainz.readthedocs.io/en/latest/users/json.html)
- [ListenBrainz Last.FM Compatible API](https://listenbrainz.readthedocs.io/en/latest/users/api-compat.html)
- [teal.fm Website](https://teal.fm/)
- [teal.fm GitHub Repository](https://github.com/teal-fm/teal)
- [AT Protocol Documentation](https://atproto.com/)
- [AT Protocol Lexicon Guide](https://atproto.com/guides/lexicon)
