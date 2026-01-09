#ifndef SCROBBLEMANAGER_H
#define SCROBBLEMANAGER_H

#include <QObject>
#include <QPointer>
#include <QDateTime>

class MediaPlayer;
class SettingsManager;

namespace Mtoc {

class Track;
class DatabaseManager;

class ScrobbleManager : public QObject
{
    Q_OBJECT

    // Local playback history properties
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int totalListens READ totalListens NOTIFY totalListensChanged)
    Q_PROPERTY(bool currentTrackScrobbled READ currentTrackScrobbled NOTIFY currentTrackScrobbledChanged)

    // Online scrobbling properties - stubbed until online scrobbling is implemented
    // These return 0/0.0 but are kept for API compatibility
    Q_PROPERTY(int pendingListenBrainz READ pendingListenBrainz NOTIFY pendingListenBrainzChanged)
    Q_PROPERTY(int pendingTealFm READ pendingTealFm NOTIFY pendingTealFmChanged)
    Q_PROPERTY(float scrobbleProgress READ scrobbleProgress NOTIFY scrobbleProgressChanged)

public:
    explicit ScrobbleManager(QObject *parent = nullptr);
    ~ScrobbleManager();

    void setMediaPlayer(MediaPlayer* player);
    void setDatabaseManager(DatabaseManager* dbManager);
    void setSettingsManager(SettingsManager* settingsManager);

    // Properties
    bool enabled() const;
    void setEnabled(bool enabled);

    int totalListens() const;
    bool currentTrackScrobbled() const;

    // Online scrobbling - stubbed (always return 0)
    int pendingListenBrainz() const { return 0; }
    int pendingTealFm() const { return 0; }
    float scrobbleProgress() const { return 0.0f; }

    // Manual operations
    Q_INVOKABLE void scrobbleNow();
    Q_INVOKABLE QVariantList getRecentListens(int limit = 50);
    Q_INVOKABLE QVariantList getValidRecentListens(int limit = 50);
    Q_INVOKABLE void clearHistory();

signals:
    void historyCleared();
    void enabledChanged(bool enabled);
    void totalListensChanged(int count);
    void currentTrackScrobbledChanged(bool scrobbled);
    void listenRecorded(const QString& trackName, const QString& artistName);

    // Online scrobbling signals - kept for API compatibility
    void pendingListenBrainzChanged(int count);
    void pendingTealFmChanged(int count);
    void scrobbleProgressChanged(float progress);
    void scrobbleThresholdReached();

private slots:
    void onTrackChanged(Track* track);
    void onPositionChanged(qint64 position);
    void onStateChanged(int state);

private:
    void resetTrackState();
    void recordListen();
    void loadSettings();
    void saveSettings();

    // Online scrobbling - commented out until implemented
    // void checkScrobbleThreshold();
    // qint64 calculateThreshold(qint64 durationMs) const;

    MediaPlayer* m_mediaPlayer = nullptr;
    DatabaseManager* m_dbManager = nullptr;
    SettingsManager* m_settingsManager = nullptr;

    bool m_enabled = true;

    // Current track state (local history)
    QPointer<Track> m_currentTrack;
    qint64 m_trackStartTime = 0;
    bool m_currentTrackScrobbled = false;
    bool m_isPlaying = false;

    // Online scrobbling state - commented out until implemented
    // qint64 m_accumulatedTime = 0;
    // qint64 m_lastPosition = 0;
    // qint64 m_scrobbleThreshold = 0;
    // bool m_thresholdSignalEmitted = false;
    // static constexpr qint64 SEEK_THRESHOLD_MS = 3000;
};

} // namespace Mtoc

#endif // SCROBBLEMANAGER_H
