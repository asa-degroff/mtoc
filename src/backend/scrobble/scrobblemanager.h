#ifndef SCROBBLEMANAGER_H
#define SCROBBLEMANAGER_H

#include <QObject>
#include <QPointer>
#include <QDateTime>

namespace Mtoc {
class Track;
class DatabaseManager;
}

class MediaPlayer;
class SettingsManager;

class ScrobbleManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int totalListens READ totalListens NOTIFY totalListensChanged)
    Q_PROPERTY(int pendingListenBrainz READ pendingListenBrainz NOTIFY pendingListenBrainzChanged)
    Q_PROPERTY(int pendingTealFm READ pendingTealFm NOTIFY pendingTealFmChanged)
    Q_PROPERTY(bool currentTrackScrobbled READ currentTrackScrobbled NOTIFY currentTrackScrobbledChanged)
    Q_PROPERTY(float scrobbleProgress READ scrobbleProgress NOTIFY scrobbleProgressChanged)

public:
    explicit ScrobbleManager(QObject *parent = nullptr);
    ~ScrobbleManager();

    void setMediaPlayer(MediaPlayer* player);
    void setDatabaseManager(Mtoc::DatabaseManager* dbManager);
    void setSettingsManager(SettingsManager* settingsManager);

    // Properties
    bool enabled() const;
    void setEnabled(bool enabled);

    int totalListens() const;
    int pendingListenBrainz() const;
    int pendingTealFm() const;

    bool currentTrackScrobbled() const;
    float scrobbleProgress() const;

    // Manual operations
    Q_INVOKABLE void scrobbleNow();
    Q_INVOKABLE QVariantList getRecentListens(int limit = 50);
    Q_INVOKABLE QVariantList getValidRecentListens(int limit = 50);
    Q_INVOKABLE void clearHistory();

signals:
    void historyCleared();
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
    void loadSettings();
    void saveSettings();

    MediaPlayer* m_mediaPlayer = nullptr;
    Mtoc::DatabaseManager* m_dbManager = nullptr;
    SettingsManager* m_settingsManager = nullptr;

    bool m_enabled = true;

    // Current track state
    QPointer<Mtoc::Track> m_currentTrack;
    qint64 m_trackStartTime = 0;
    qint64 m_accumulatedTime = 0;
    qint64 m_lastPosition = 0;
    qint64 m_scrobbleThreshold = 0;
    bool m_currentTrackScrobbled = false;
    bool m_isPlaying = false;

    // Seek detection tolerance (3 seconds)
    static constexpr qint64 SEEK_THRESHOLD_MS = 3000;

    // Minimum track duration to scrobble (30 seconds)
    static constexpr qint64 MIN_TRACK_DURATION_MS = 30000;
};

#endif // SCROBBLEMANAGER_H
