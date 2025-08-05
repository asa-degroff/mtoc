#include "settingsmanager.h"
#include <QDebug>
#include <QGuiApplication>
#include <QPalette>

SettingsManager* SettingsManager::s_instance = nullptr;

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("mtoc", "mtoc")
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

void SettingsManager::loadSettings()
{
    m_settings.beginGroup("QueueBehavior");
    m_queueActionDefault = static_cast<QueueAction>(m_settings.value("defaultAction", Ask).toInt());
    m_settings.endGroup();
    
    m_settings.beginGroup("Display");
    m_showTrackInfoByDefault = m_settings.value("showTrackInfoByDefault", false).toBool();
    m_theme = static_cast<Theme>(m_settings.value("theme", Dark).toInt());
    m_settings.endGroup();
    
    m_settings.beginGroup("Playback");
    m_restorePlaybackPosition = m_settings.value("restorePosition", true).toBool();
    m_repeatEnabled = m_settings.value("repeatEnabled", false).toBool();
    m_shuffleEnabled = m_settings.value("shuffleEnabled", false).toBool();
    m_settings.endGroup();
    
    m_settings.beginGroup("LibraryPane");
    m_libraryActiveTab = m_settings.value("activeTab", 0).toInt();
    m_lastSelectedAlbumId = m_settings.value("lastSelectedAlbumId", "").toString();
    m_lastSelectedPlaylistName = m_settings.value("lastSelectedPlaylistName", "").toString();
    m_lastSelectedWasPlaylist = m_settings.value("lastSelectedWasPlaylist", false).toBool();
    m_settings.endGroup();
    
    m_settings.beginGroup("Window");
    m_windowWidth = m_settings.value("width", 1920).toInt();
    m_windowHeight = m_settings.value("height", 1200).toInt();
    m_windowX = m_settings.value("x", -1).toInt();  // -1 means use default positioning
    m_windowY = m_settings.value("y", -1).toInt();
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
    m_settings.endGroup();
    
    m_settings.beginGroup("Playback");
    m_settings.setValue("restorePosition", m_restorePlaybackPosition);
    m_settings.setValue("repeatEnabled", m_repeatEnabled);
    m_settings.setValue("shuffleEnabled", m_shuffleEnabled);
    m_settings.endGroup();
    
    m_settings.beginGroup("LibraryPane");
    m_settings.setValue("activeTab", m_libraryActiveTab);
    m_settings.setValue("lastSelectedAlbumId", m_lastSelectedAlbumId);
    m_settings.setValue("lastSelectedPlaylistName", m_lastSelectedPlaylistName);
    m_settings.setValue("lastSelectedWasPlaylist", m_lastSelectedWasPlaylist);
    m_settings.endGroup();
    
    m_settings.beginGroup("Window");
    m_settings.setValue("width", m_windowWidth);
    m_settings.setValue("height", m_windowHeight);
    m_settings.setValue("x", m_windowX);
    m_settings.setValue("y", m_windowY);
    m_settings.endGroup();
    
    m_settings.sync();
    qDebug() << "SettingsManager: Settings saved";
}

bool SettingsManager::isSystemDark() const
{
    // Get the system palette to detect if we're in dark mode
    QPalette palette = QGuiApplication::palette();
    QColor windowColor = palette.color(QPalette::Window);
    
    // Consider it dark mode if the window background is dark
    // Using a threshold of 128 for the lightness value
    return windowColor.lightness() < 128;
}

void SettingsManager::setupSystemThemeDetection()
{
    // Connect to palette change events to detect system theme changes
    connect(qApp, &QGuiApplication::paletteChanged, this, &SettingsManager::onSystemThemeChanged);
}

void SettingsManager::onSystemThemeChanged()
{
    // Emit signal when system theme changes
    emit systemThemeChanged();
    
    // If we're using the System theme, also emit themeChanged
    if (m_theme == System) {
        emit themeChanged(m_theme);
    }
}