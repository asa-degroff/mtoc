#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>
#include <QString>
#include <QColor>

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
    Q_PROPERTY(Theme theme READ theme WRITE setTheme NOTIFY themeChanged)
    Q_PROPERTY(bool isSystemDark READ isSystemDark NOTIFY systemThemeChanged)
    Q_PROPERTY(QColor systemAccentColor READ systemAccentColor NOTIFY systemAccentColorChanged)
    Q_PROPERTY(LayoutMode layoutMode READ layoutMode WRITE setLayoutMode NOTIFY layoutModeChanged)
    Q_PROPERTY(bool replayGainEnabled READ replayGainEnabled WRITE setReplayGainEnabled NOTIFY replayGainEnabledChanged)
    Q_PROPERTY(ReplayGainMode replayGainMode READ replayGainMode WRITE setReplayGainMode NOTIFY replayGainModeChanged)
    Q_PROPERTY(double replayGainPreAmp READ replayGainPreAmp WRITE setReplayGainPreAmp NOTIFY replayGainPreAmpChanged)
    Q_PROPERTY(double replayGainFallbackGain READ replayGainFallbackGain WRITE setReplayGainFallbackGain NOTIFY replayGainFallbackGainChanged)
    Q_PROPERTY(MiniPlayerLayout miniPlayerLayout READ miniPlayerLayout WRITE setMiniPlayerLayout NOTIFY miniPlayerLayoutChanged)
    Q_PROPERTY(int miniPlayerX READ miniPlayerX WRITE setMiniPlayerX NOTIFY miniPlayerXChanged)
    Q_PROPERTY(int miniPlayerY READ miniPlayerY WRITE setMiniPlayerY NOTIFY miniPlayerYChanged)
    Q_PROPERTY(bool miniPlayerHidesMainWindow READ miniPlayerHidesMainWindow WRITE setMiniPlayerHidesMainWindow NOTIFY miniPlayerHidesMainWindowChanged)
    Q_PROPERTY(int thumbnailScale READ thumbnailScale WRITE setThumbnailScale NOTIFY thumbnailScaleChanged)
    Q_PROPERTY(double artistsScrollPosition READ artistsScrollPosition WRITE setArtistsScrollPosition NOTIFY artistsScrollPositionChanged)
    Q_PROPERTY(QStringList expandedArtistsList READ expandedArtistsList WRITE setExpandedArtistsList NOTIFY expandedArtistsListChanged)
    Q_PROPERTY(double librarySplitRatio READ librarySplitRatio WRITE setLibrarySplitRatio NOTIFY librarySplitRatioChanged)

public:
    enum QueueAction {
        Replace,
        Insert,
        Append,
        Ask
    };
    Q_ENUM(QueueAction)

    enum Theme {
        Dark,
        Light,
        System
    };
    Q_ENUM(Theme)

    enum LayoutMode {
        Wide,
        Compact,
        Automatic
    };
    Q_ENUM(LayoutMode)

    enum ReplayGainMode {
        Off,
        Track,
        Album
    };
    Q_ENUM(ReplayGainMode)

    enum MiniPlayerLayout {
        Vertical,
        Horizontal,
        CompactBar
    };
    Q_ENUM(MiniPlayerLayout)

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
    Theme theme() const { return m_theme; }
    bool isSystemDark() const;
    QColor systemAccentColor() const;
    LayoutMode layoutMode() const { return m_layoutMode; }
    bool replayGainEnabled() const { return m_replayGainEnabled; }
    ReplayGainMode replayGainMode() const { return m_replayGainMode; }
    double replayGainPreAmp() const { return m_replayGainPreAmp; }
    double replayGainFallbackGain() const { return m_replayGainFallbackGain; }
    MiniPlayerLayout miniPlayerLayout() const { return m_miniPlayerLayout; }
    int miniPlayerX() const { return m_miniPlayerX; }
    int miniPlayerY() const { return m_miniPlayerY; }
    bool miniPlayerHidesMainWindow() const { return m_miniPlayerHidesMainWindow; }
    int thumbnailScale() const { return m_thumbnailScale; }
    double artistsScrollPosition() const { return m_artistsScrollPosition; }
    QStringList expandedArtistsList() const { return m_expandedArtistsList; }
    double librarySplitRatio() const { return m_librarySplitRatio; }
    
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
    void setTheme(Theme theme);
    void setLayoutMode(LayoutMode mode);
    void setReplayGainEnabled(bool enabled);
    void setReplayGainMode(ReplayGainMode mode);
    void setReplayGainPreAmp(double preAmp);
    void setReplayGainFallbackGain(double fallbackGain);
    void setMiniPlayerLayout(MiniPlayerLayout layout);
    void setMiniPlayerX(int x);
    void setMiniPlayerY(int y);
    void setMiniPlayerHidesMainWindow(bool hides);
    void setThumbnailScale(int scale);
    void setArtistsScrollPosition(double position);
    void setExpandedArtistsList(const QStringList& artists);
    void setLibrarySplitRatio(double ratio);

protected:
    bool event(QEvent *event) override;

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
    void themeChanged(Theme theme);
    void systemThemeChanged();
    void systemAccentColorChanged();
    void layoutModeChanged(LayoutMode mode);
    void replayGainEnabledChanged(bool enabled);
    void replayGainModeChanged(ReplayGainMode mode);
    void replayGainPreAmpChanged(double preAmp);
    void replayGainFallbackGainChanged(double fallbackGain);
    void miniPlayerLayoutChanged(MiniPlayerLayout layout);
    void miniPlayerXChanged(int x);
    void miniPlayerYChanged(int y);
    void miniPlayerHidesMainWindowChanged(bool hides);
    void thumbnailScaleChanged(int scale);
    void artistsScrollPositionChanged(double position);
    void expandedArtistsListChanged(const QStringList& artists);
    void librarySplitRatioChanged(double ratio);

private slots:

private:
    explicit SettingsManager(QObject *parent = nullptr);
    
    void loadSettings();
    void saveSettings();
    void setupSystemThemeDetection();
    
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
    Theme m_theme;
    LayoutMode m_layoutMode;
    bool m_replayGainEnabled;
    ReplayGainMode m_replayGainMode;
    double m_replayGainPreAmp;
    double m_replayGainFallbackGain;
    MiniPlayerLayout m_miniPlayerLayout;
    int m_miniPlayerX;
    int m_miniPlayerY;
    bool m_miniPlayerHidesMainWindow;
    int m_thumbnailScale;
    double m_artistsScrollPosition;
    QStringList m_expandedArtistsList;
    double m_librarySplitRatio;
};

#endif // SETTINGSMANAGER_H