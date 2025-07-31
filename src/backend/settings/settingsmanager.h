#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>
#include <QString>

class SettingsManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QueueAction queueActionDefault READ queueActionDefault WRITE setQueueActionDefault NOTIFY queueActionDefaultChanged)
    Q_PROPERTY(bool showTrackInfoByDefault READ showTrackInfoByDefault WRITE setShowTrackInfoByDefault NOTIFY showTrackInfoByDefaultChanged)
    Q_PROPERTY(bool restorePlaybackPosition READ restorePlaybackPosition WRITE setRestorePlaybackPosition NOTIFY restorePlaybackPositionChanged)
    Q_PROPERTY(bool repeatEnabled READ repeatEnabled WRITE setRepeatEnabled NOTIFY repeatEnabledChanged)
    Q_PROPERTY(bool shuffleEnabled READ shuffleEnabled WRITE setShuffleEnabled NOTIFY shuffleEnabledChanged)
    Q_PROPERTY(int libraryActiveTab READ libraryActiveTab WRITE setLibraryActiveTab NOTIFY libraryActiveTabChanged)
    Q_PROPERTY(QString lastSelectedAlbumId READ lastSelectedAlbumId WRITE setLastSelectedAlbumId NOTIFY lastSelectedAlbumIdChanged)
    Q_PROPERTY(QString lastSelectedPlaylistName READ lastSelectedPlaylistName WRITE setLastSelectedPlaylistName NOTIFY lastSelectedPlaylistNameChanged)
    Q_PROPERTY(bool lastSelectedWasPlaylist READ lastSelectedWasPlaylist WRITE setLastSelectedWasPlaylist NOTIFY lastSelectedWasPlaylistChanged)
    Q_PROPERTY(int windowWidth READ windowWidth WRITE setWindowWidth NOTIFY windowWidthChanged)
    Q_PROPERTY(int windowHeight READ windowHeight WRITE setWindowHeight NOTIFY windowHeightChanged)
    Q_PROPERTY(int windowX READ windowX WRITE setWindowX NOTIFY windowXChanged)
    Q_PROPERTY(int windowY READ windowY WRITE setWindowY NOTIFY windowYChanged)

public:
    enum QueueAction {
        Replace,
        Insert,
        Append,
        Ask
    };
    Q_ENUM(QueueAction)

    static SettingsManager* instance();
    ~SettingsManager();
    
    // Getters
    QueueAction queueActionDefault() const { return m_queueActionDefault; }
    bool showTrackInfoByDefault() const { return m_showTrackInfoByDefault; }
    bool restorePlaybackPosition() const { return m_restorePlaybackPosition; }
    bool repeatEnabled() const { return m_repeatEnabled; }
    bool shuffleEnabled() const { return m_shuffleEnabled; }
    int libraryActiveTab() const { return m_libraryActiveTab; }
    QString lastSelectedAlbumId() const { return m_lastSelectedAlbumId; }
    QString lastSelectedPlaylistName() const { return m_lastSelectedPlaylistName; }
    bool lastSelectedWasPlaylist() const { return m_lastSelectedWasPlaylist; }
    int windowWidth() const { return m_windowWidth; }
    int windowHeight() const { return m_windowHeight; }
    int windowX() const { return m_windowX; }
    int windowY() const { return m_windowY; }
    
    // Setters
    void setQueueActionDefault(QueueAction action);
    void setShowTrackInfoByDefault(bool show);
    void setRestorePlaybackPosition(bool restore);
    void setRepeatEnabled(bool enabled);
    void setShuffleEnabled(bool enabled);
    void setLibraryActiveTab(int tab);
    void setLastSelectedAlbumId(const QString& albumId);
    void setLastSelectedPlaylistName(const QString& playlistName);
    void setLastSelectedWasPlaylist(bool wasPlaylist);
    void setWindowWidth(int width);
    void setWindowHeight(int height);
    void setWindowX(int x);
    void setWindowY(int y);

signals:
    void queueActionDefaultChanged(QueueAction action);
    void showTrackInfoByDefaultChanged(bool show);
    void restorePlaybackPositionChanged(bool restore);
    void repeatEnabledChanged(bool enabled);
    void shuffleEnabledChanged(bool enabled);
    void libraryActiveTabChanged(int tab);
    void lastSelectedAlbumIdChanged(const QString& albumId);
    void lastSelectedPlaylistNameChanged(const QString& playlistName);
    void lastSelectedWasPlaylistChanged(bool wasPlaylist);
    void windowWidthChanged(int width);
    void windowHeightChanged(int height);
    void windowXChanged(int x);
    void windowYChanged(int y);

private:
    explicit SettingsManager(QObject *parent = nullptr);
    
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
    int m_libraryActiveTab;
    QString m_lastSelectedAlbumId;
    QString m_lastSelectedPlaylistName;
    bool m_lastSelectedWasPlaylist;
    int m_windowWidth;
    int m_windowHeight;
    int m_windowX;
    int m_windowY;
};

#endif // SETTINGSMANAGER_H