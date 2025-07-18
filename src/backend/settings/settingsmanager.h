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
    
    // Setters
    void setQueueActionDefault(QueueAction action);
    void setShowTrackInfoByDefault(bool show);
    void setRestorePlaybackPosition(bool restore);

signals:
    void queueActionDefaultChanged(QueueAction action);
    void showTrackInfoByDefaultChanged(bool show);
    void restorePlaybackPositionChanged(bool restore);

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
};

#endif // SETTINGSMANAGER_H