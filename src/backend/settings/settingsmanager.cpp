#include "settingsmanager.h"
#include <QDebug>
#include <QGuiApplication>
#include <QPalette>
#include <QEvent>

SettingsManager* SettingsManager::s_instance = nullptr;

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("mtoc", "mtoc")
    , m_layoutMode(Wide)
    , m_replayGainEnabled(false)
    , m_replayGainMode(Off)
    , m_replayGainPreAmp(0.0)
    , m_replayGainFallbackGain(0.0)
    , m_miniPlayerLayout(Vertical)
    , m_miniPlayerX(-1)
    , m_miniPlayerY(-1)
    , m_miniPlayerHidesMainWindow(true)
    , m_thumbnailScale(200)  // Default to 200% (400px) for backward compatibility
    , m_artistsScrollPosition(0.0)
    , m_expandedArtistsList()
    , m_librarySplitRatio(0.51)  // Default to 51%
    , m_singleClickToPlay(false)  // Default to double-click behavior
    , m_minimizeToTray(false)  // Default to quit on close
    , m_showCollabAlbumsUnderAllArtists(true)  // Default to showing collab albums under all artists
    , m_useAlbumArtistDelimiters(true)  // Default to enabled for backward compatibility
    , m_albumArtistDelimiters({";", "|"})  // Default delimiters: semicolon and pipe (whitespace-insensitive)
{
    loadSettings();
    setupSystemThemeDetection();
}

SettingsManager::~SettingsManager()
{
    qDebug() << "[SettingsManager::~SettingsManager] Destructor called, saving settings...";
    saveSettings();
    s_instance = nullptr;
    qDebug() << "[SettingsManager::~SettingsManager] Cleanup complete";
}

SettingsManager* SettingsManager::instance()
{
    if (!s_instance) {
        s_instance = new SettingsManager();
    }
    return s_instance;
}

void SettingsManager::setQueueActionDefault(QueueAction action)
{
    if (m_queueActionDefault != action) {
        m_queueActionDefault = action;
        emit queueActionDefaultChanged(action);
        saveSettings();
    }
}

void SettingsManager::setShowTrackInfoByDefault(bool show)
{
    if (m_showTrackInfoByDefault != show) {
        m_showTrackInfoByDefault = show;
        emit showTrackInfoByDefaultChanged(show);
        saveSettings();
    }
}

void SettingsManager::setRestorePlaybackPosition(bool restore)
{
    if (m_restorePlaybackPosition != restore) {
        m_restorePlaybackPosition = restore;
        emit restorePlaybackPositionChanged(restore);
        saveSettings();
    }
}

void SettingsManager::setRepeatEnabled(bool enabled)
{
    if (m_repeatEnabled != enabled) {
        m_repeatEnabled = enabled;
        emit repeatEnabledChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setShuffleEnabled(bool enabled)
{
    if (m_shuffleEnabled != enabled) {
        m_shuffleEnabled = enabled;
        emit shuffleEnabledChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setLibraryActiveTab(int tab)
{
    if (m_libraryActiveTab != tab) {
        m_libraryActiveTab = tab;
        emit libraryActiveTabChanged(tab);
        saveSettings();
    }
}

void SettingsManager::setLastSelectedAlbumId(const QString& albumId)
{
    if (m_lastSelectedAlbumId != albumId) {
        m_lastSelectedAlbumId = albumId;
        emit lastSelectedAlbumIdChanged(albumId);
        saveSettings();
    }
}

void SettingsManager::setLastSelectedPlaylistName(const QString& playlistName)
{
    if (m_lastSelectedPlaylistName != playlistName) {
        m_lastSelectedPlaylistName = playlistName;
        emit lastSelectedPlaylistNameChanged(playlistName);
        saveSettings();
    }
}

void SettingsManager::setLastSelectedWasPlaylist(bool wasPlaylist)
{
    if (m_lastSelectedWasPlaylist != wasPlaylist) {
        m_lastSelectedWasPlaylist = wasPlaylist;
        emit lastSelectedWasPlaylistChanged(wasPlaylist);
        saveSettings();
    }
}

void SettingsManager::setWindowWidth(int width)
{
    if (m_windowWidth != width) {
        m_windowWidth = width;
        emit windowWidthChanged(width);
        saveSettings();
    }
}

void SettingsManager::setWindowHeight(int height)
{
    if (m_windowHeight != height) {
        m_windowHeight = height;
        emit windowHeightChanged(height);
        saveSettings();
    }
}

void SettingsManager::setWindowX(int x)
{
    if (m_windowX != x) {
        m_windowX = x;
        emit windowXChanged(x);
        saveSettings();
    }
}

void SettingsManager::setWindowY(int y)
{
    if (m_windowY != y) {
        m_windowY = y;
        emit windowYChanged(y);
        saveSettings();
    }
}

void SettingsManager::setTheme(Theme theme)
{
    if (m_theme != theme) {
        m_theme = theme;
        emit themeChanged(theme);
        saveSettings();
    }
}

void SettingsManager::setLayoutMode(LayoutMode mode)
{
    if (m_layoutMode != mode) {
        m_layoutMode = mode;
        emit layoutModeChanged(mode);
        saveSettings();
    }
}

void SettingsManager::setReplayGainEnabled(bool enabled)
{
    if (m_replayGainEnabled != enabled) {
        m_replayGainEnabled = enabled;
        emit replayGainEnabledChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setReplayGainMode(ReplayGainMode mode)
{
    if (m_replayGainMode != mode) {
        m_replayGainMode = mode;
        emit replayGainModeChanged(mode);
        saveSettings();
    }
}

void SettingsManager::setReplayGainPreAmp(double preAmp)
{
    // Clamp to reasonable range
    preAmp = qBound(-15.0, preAmp, 15.0);
    if (!qFuzzyCompare(m_replayGainPreAmp, preAmp)) {
        m_replayGainPreAmp = preAmp;
        emit replayGainPreAmpChanged(preAmp);
        saveSettings();
    }
}

void SettingsManager::setReplayGainFallbackGain(double fallbackGain)
{
    // Clamp to reasonable range
    fallbackGain = qBound(-15.0, fallbackGain, 15.0);
    if (!qFuzzyCompare(m_replayGainFallbackGain, fallbackGain)) {
        m_replayGainFallbackGain = fallbackGain;
        emit replayGainFallbackGainChanged(fallbackGain);
        saveSettings();
    }
}

void SettingsManager::setMiniPlayerLayout(MiniPlayerLayout layout)
{
    if (m_miniPlayerLayout != layout) {
        m_miniPlayerLayout = layout;
        emit miniPlayerLayoutChanged(layout);
        saveSettings();
    }
}

void SettingsManager::setMiniPlayerX(int x)
{
    if (m_miniPlayerX != x) {
        m_miniPlayerX = x;
        emit miniPlayerXChanged(x);
        saveSettings();
    }
}

void SettingsManager::setMiniPlayerY(int y)
{
    if (m_miniPlayerY != y) {
        m_miniPlayerY = y;
        emit miniPlayerYChanged(y);
        saveSettings();
    }
}

void SettingsManager::setMiniPlayerHidesMainWindow(bool hides)
{
    if (m_miniPlayerHidesMainWindow != hides) {
        m_miniPlayerHidesMainWindow = hides;
        emit miniPlayerHidesMainWindowChanged(hides);
        saveSettings();
    }
}

void SettingsManager::setThumbnailScale(int scale)
{
    // Validate scale value (must be 100, 150, or 200)
    if (scale != 100 && scale != 150 && scale != 200) {
        qWarning() << "Invalid thumbnail scale:" << scale << "- must be 100, 150, or 200";
        return;
    }
    
    if (m_thumbnailScale != scale) {
        m_thumbnailScale = scale;
        emit thumbnailScaleChanged(scale);
        saveSettings();
    }
}

void SettingsManager::setArtistsScrollPosition(double position)
{
    if (m_artistsScrollPosition != position) {
        m_artistsScrollPosition = position;
        emit artistsScrollPositionChanged(position);
        saveSettings();
    }
}

void SettingsManager::setExpandedArtistsList(const QStringList& artists)
{
    if (m_expandedArtistsList != artists) {
        m_expandedArtistsList = artists;
        emit expandedArtistsListChanged(artists);
        saveSettings();
    }
}

void SettingsManager::setLibrarySplitRatio(double ratio)
{
    // Clamp ratio between 0.2 and 0.8 to prevent extreme splits
    ratio = qBound(0.2, ratio, 0.8);

    if (!qFuzzyCompare(m_librarySplitRatio, ratio)) {
        m_librarySplitRatio = ratio;
        emit librarySplitRatioChanged(ratio);
        saveSettings();
    }
}

void SettingsManager::setSingleClickToPlay(bool enabled)
{
    if (m_singleClickToPlay != enabled) {
        m_singleClickToPlay = enabled;
        emit singleClickToPlayChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setMinimizeToTray(bool enabled)
{
    if (m_minimizeToTray != enabled) {
        m_minimizeToTray = enabled;
        emit minimizeToTrayChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setLastSeenChangelogVersion(const QString& version)
{
    if (m_lastSeenChangelogVersion != version) {
        m_lastSeenChangelogVersion = version;
        emit lastSeenChangelogVersionChanged(version);
        saveSettings();
    }
}

void SettingsManager::setShowCollabAlbumsUnderAllArtists(bool enabled)
{
    if (m_showCollabAlbumsUnderAllArtists != enabled) {
        m_showCollabAlbumsUnderAllArtists = enabled;
        emit showCollabAlbumsUnderAllArtistsChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setUseAlbumArtistDelimiters(bool enabled)
{
    if (m_useAlbumArtistDelimiters != enabled) {
        m_useAlbumArtistDelimiters = enabled;
        emit useAlbumArtistDelimitersChanged(enabled);
        saveSettings();
    }
}

void SettingsManager::setAlbumArtistDelimiters(const QStringList& delimiters)
{
    if (m_albumArtistDelimiters != delimiters) {
        m_albumArtistDelimiters = delimiters;
        emit albumArtistDelimitersChanged(delimiters);
        saveSettings();
    }
}

void SettingsManager::loadSettings()
{
    m_settings.beginGroup("QueueBehavior");
    m_queueActionDefault = static_cast<QueueAction>(m_settings.value("defaultAction", Ask).toInt());
    m_settings.endGroup();
    
    m_settings.beginGroup("Display");
    m_showTrackInfoByDefault = m_settings.value("showTrackInfoByDefault", false).toBool();
    m_theme = static_cast<Theme>(m_settings.value("theme", Dark).toInt());
    m_layoutMode = static_cast<LayoutMode>(m_settings.value("layoutMode", Wide).toInt());
    m_thumbnailScale = m_settings.value("thumbnailScale", 200).toInt();  // Default to 200% (400px)
    // Ensure thumbnailScale is valid (100, 150, or 200)
    if (m_thumbnailScale != 100 && m_thumbnailScale != 150 && m_thumbnailScale != 200) {
        m_thumbnailScale = 200;
    }
    m_settings.endGroup();
    
    m_settings.beginGroup("Playback");
    m_restorePlaybackPosition = m_settings.value("restorePosition", true).toBool();
    m_repeatEnabled = m_settings.value("repeatEnabled", false).toBool();
    m_shuffleEnabled = m_settings.value("shuffleEnabled", false).toBool();
    m_settings.endGroup();
    
    m_settings.beginGroup("ReplayGain");
    m_replayGainEnabled = m_settings.value("enabled", false).toBool();
    m_replayGainMode = static_cast<ReplayGainMode>(m_settings.value("mode", Off).toInt());
    m_replayGainPreAmp = m_settings.value("preAmp", 0.0).toDouble();
    m_replayGainFallbackGain = m_settings.value("fallbackGain", 0.0).toDouble();
    m_settings.endGroup();
    
    m_settings.beginGroup("LibraryPane");
    m_libraryActiveTab = m_settings.value("activeTab", 0).toInt();
    m_lastSelectedAlbumId = m_settings.value("lastSelectedAlbumId", "").toString();
    m_lastSelectedPlaylistName = m_settings.value("lastSelectedPlaylistName", "").toString();
    m_lastSelectedWasPlaylist = m_settings.value("lastSelectedWasPlaylist", false).toBool();
    m_artistsScrollPosition = m_settings.value("artistsScrollPosition", 0.0).toDouble();
    m_expandedArtistsList = m_settings.value("expandedArtistsList", QStringList()).toStringList();
    m_librarySplitRatio = m_settings.value("splitRatio", 0.51).toDouble();
    m_singleClickToPlay = m_settings.value("singleClickToPlay", false).toBool();
    m_settings.endGroup();
    
    m_settings.beginGroup("Window");
    m_windowWidth = m_settings.value("width", 1920).toInt();
    m_windowHeight = m_settings.value("height", 1200).toInt();
    m_windowX = m_settings.value("x", -1).toInt();  // -1 means use default positioning
    m_windowY = m_settings.value("y", -1).toInt();
    m_minimizeToTray = m_settings.value("minimizeToTray", false).toBool();
    m_lastSeenChangelogVersion = m_settings.value("lastSeenChangelogVersion", "").toString();
    m_settings.endGroup();
    
    m_settings.beginGroup("MiniPlayer");
    m_miniPlayerLayout = static_cast<MiniPlayerLayout>(m_settings.value("layout", Vertical).toInt());
    m_miniPlayerX = m_settings.value("x", -1).toInt();  // -1 means use default positioning
    m_miniPlayerY = m_settings.value("y", -1).toInt();
    m_miniPlayerHidesMainWindow = m_settings.value("hidesMainWindow", true).toBool();
    m_settings.endGroup();

    m_settings.beginGroup("Metadata");
    m_showCollabAlbumsUnderAllArtists = m_settings.value("showCollabAlbumsUnderAllArtists", true).toBool();
    m_useAlbumArtistDelimiters = m_settings.value("useAlbumArtistDelimiters", true).toBool();
    m_albumArtistDelimiters = m_settings.value("albumArtistDelimiters", QStringList({";", "|"})).toStringList();
    m_settings.endGroup();

    qDebug() << "SettingsManager: Loaded settings - Queue action:" << m_queueActionDefault
             << "Show track info:" << m_showTrackInfoByDefault
             << "Restore position:" << m_restorePlaybackPosition
             << "Repeat:" << m_repeatEnabled
             << "Shuffle:" << m_shuffleEnabled;
}

void SettingsManager::saveSettings()
{
    m_settings.beginGroup("QueueBehavior");
    m_settings.setValue("defaultAction", static_cast<int>(m_queueActionDefault));
    m_settings.endGroup();
    
    m_settings.beginGroup("Display");
    m_settings.setValue("showTrackInfoByDefault", m_showTrackInfoByDefault);
    m_settings.setValue("theme", static_cast<int>(m_theme));
    m_settings.setValue("layoutMode", static_cast<int>(m_layoutMode));
    m_settings.setValue("thumbnailScale", m_thumbnailScale);
    m_settings.endGroup();
    
    m_settings.beginGroup("Playback");
    m_settings.setValue("restorePosition", m_restorePlaybackPosition);
    m_settings.setValue("repeatEnabled", m_repeatEnabled);
    m_settings.setValue("shuffleEnabled", m_shuffleEnabled);
    m_settings.endGroup();
    
    m_settings.beginGroup("ReplayGain");
    m_settings.setValue("enabled", m_replayGainEnabled);
    m_settings.setValue("mode", static_cast<int>(m_replayGainMode));
    m_settings.setValue("preAmp", m_replayGainPreAmp);
    m_settings.setValue("fallbackGain", m_replayGainFallbackGain);
    m_settings.endGroup();
    
    m_settings.beginGroup("LibraryPane");
    m_settings.setValue("activeTab", m_libraryActiveTab);
    m_settings.setValue("lastSelectedAlbumId", m_lastSelectedAlbumId);
    m_settings.setValue("lastSelectedPlaylistName", m_lastSelectedPlaylistName);
    m_settings.setValue("lastSelectedWasPlaylist", m_lastSelectedWasPlaylist);
    m_settings.setValue("artistsScrollPosition", m_artistsScrollPosition);
    m_settings.setValue("expandedArtistsList", m_expandedArtistsList);
    m_settings.setValue("splitRatio", m_librarySplitRatio);
    m_settings.setValue("singleClickToPlay", m_singleClickToPlay);
    m_settings.endGroup();
    
    m_settings.beginGroup("Window");
    m_settings.setValue("width", m_windowWidth);
    m_settings.setValue("height", m_windowHeight);
    m_settings.setValue("x", m_windowX);
    m_settings.setValue("y", m_windowY);
    m_settings.setValue("minimizeToTray", m_minimizeToTray);
    m_settings.setValue("lastSeenChangelogVersion", m_lastSeenChangelogVersion);
    m_settings.endGroup();
    
    m_settings.beginGroup("MiniPlayer");
    m_settings.setValue("layout", static_cast<int>(m_miniPlayerLayout));
    m_settings.setValue("x", m_miniPlayerX);
    m_settings.setValue("y", m_miniPlayerY);
    m_settings.setValue("hidesMainWindow", m_miniPlayerHidesMainWindow);
    m_settings.endGroup();

    m_settings.beginGroup("Metadata");
    m_settings.setValue("showCollabAlbumsUnderAllArtists", m_showCollabAlbumsUnderAllArtists);
    m_settings.setValue("useAlbumArtistDelimiters", m_useAlbumArtistDelimiters);
    m_settings.setValue("albumArtistDelimiters", m_albumArtistDelimiters);
    m_settings.endGroup();

    m_settings.sync();
    qDebug() << "SettingsManager: Settings saved";
}

bool SettingsManager::isSystemDark() const
{
    // Use Qt 6.5+ color scheme API for reliable detection (preferred method)
    QStyleHints *hints = QGuiApplication::styleHints();
    Qt::ColorScheme colorScheme = hints->colorScheme();

    if (colorScheme == Qt::ColorScheme::Dark) {
        return true;
    } else if (colorScheme == Qt::ColorScheme::Light) {
        return false;
    }

    // Fallback: If colorScheme is Unknown, use palette lightness heuristic
    QPalette palette = QGuiApplication::palette();
    QColor windowColor = palette.color(QPalette::Window);

    // Consider it dark mode if the window background is dark
    // Using a threshold of 128 for the lightness value
    return windowColor.lightness() < 128;
}

QColor SettingsManager::systemAccentColor() const
{
    // Get the system palette
    QPalette palette = QGuiApplication::palette();
    
    // Return the system's highlight color (accent color)
    // This is typically the selection/accent color on most platforms
    return palette.color(QPalette::Highlight);
}

void SettingsManager::setupSystemThemeDetection()
{
    // Connect to Qt 6.5+ color scheme change signal for reliable theme detection
    QStyleHints *hints = QGuiApplication::styleHints();
    connect(hints, &QStyleHints::colorSchemeChanged,
            this, &SettingsManager::onColorSchemeChanged);

    // Note: We also keep the event() method as a fallback for palette changes
    qDebug() << "SettingsManager: System theme detection initialized";
}

void SettingsManager::onColorSchemeChanged(Qt::ColorScheme scheme)
{
    qDebug() << "SettingsManager: System color scheme changed to:" <<
        (scheme == Qt::ColorScheme::Dark ? "Dark" :
         scheme == Qt::ColorScheme::Light ? "Light" : "Unknown");

    // Emit signal when system theme changes
    emit systemThemeChanged();

    // Emit signal when system accent color might have changed
    emit systemAccentColorChanged();

    // If we're using the System theme, also emit themeChanged
    if (m_theme == System) {
        emit themeChanged(m_theme);
    }
}

bool SettingsManager::event(QEvent *event)
{
    if (event->type() == QEvent::ApplicationPaletteChange) {
        qDebug() << "SettingsManager: ApplicationPaletteChange event received (fallback)";

        // Emit signal when system theme changes
        emit systemThemeChanged();

        // Emit signal when system accent color might have changed
        emit systemAccentColorChanged();

        // If we're using the System theme, also emit themeChanged
        if (m_theme == System) {
            emit themeChanged(m_theme);
        }
        return true;
    }
    return QObject::event(event);
}