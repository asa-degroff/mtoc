#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QueueAction queueActionDefault READ queueActionDefault WRITE setQueueActionDefault NOTIFY queueActionDefaultChanged)
    Q_PROPERTY(bool showTrackInfoByDefault READ showTrackInfoByDefault WRITE setShowTrackInfoByDefault NOTIFY showTrackInfoByDefaultChanged)
    Q_PROPERTY(bool restorePlaybackPosition READ restorePlaybackPosition WRITE setRestorePlaybackPosition NOTIFY restorePlaybackPositionChanged)
    Q_PROPERTY(bool repeatEnabled READ repeatEnabled WRITE setRepeatEnabled NOTIFY repeatEnabledChanged)
    Q_PROPERTY(bool shuffleEnabled READ shuffleEnabled WRITE setShuffleEnabled NOTIFY shuffleEnabledChanged)

public:
    enum QueueAction {
        Replace,
        Insert,
        Append,
        Ask
    };
    Q_ENUM(QueueAction)

    static SettingsManager* instance();
    
    // Getters
    QueueAction queueActionDefault() const { return m_queueActionDefault; }
    bool showTrackInfoByDefault() const { return m_showTrackInfoByDefault; }
    bool restorePlaybackPosition() const { return m_restorePlaybackPosition; }
    bool repeatEnabled() const { return m_repeatEnabled; }
    bool shuffleEnabled() const { return m_shuffleEnabled; }
    
    // Setters
    void setQueueActionDefault(QueueAction action);
    void setShowTrackInfoByDefault(bool show);
    void setRestorePlaybackPosition(bool restore);
    void setRepeatEnabled(bool enabled);
    void setShuffleEnabled(bool enabled);

signals:
    void queueActionDefaultChanged(QueueAction action);
    void showTrackInfoByDefaultChanged(bool show);
    void restorePlaybackPositionChanged(bool restore);
    void repeatEnabledChanged(bool enabled);
    void shuffleEnabledChanged(bool enabled);

private:
    explicit SettingsManager(QObject *parent = nullptr);
    ~SettingsManager();
    
    void loadSettings();
    void saveSettings();
    
    static SettingsManager* s_instance;
    QSettings m_settings;
    
    // Settings values
    QueueAction m_queueActionDefault;
    bool m_showTrackInfoByDefault;
    bool m_restorePlaybackPosition;
    bool m_repeatEnabled;
    bool m_shuffleEnabled;
};

#endif // SETTINGSMANAGER_H