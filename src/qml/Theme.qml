pragma Singleton
import QtQuick
import Mtoc.Backend 1.0

QtObject {
    property bool isDark: {
        if (SettingsManager.theme === SettingsManager.System) {
            return SettingsManager.isSystemDark
        }
        return SettingsManager.theme === SettingsManager.Dark
    }
    
    // Primary colors
    property color primaryText: isDark ? "white" : "#333333"
    property color secondaryText: isDark ? "#cccccc" : "#3d3d3d"
    property color tertiaryText: isDark ? "#999999" : "#444444"
    
    // Background colors
    property color backgroundColor: isDark ? "#1a1a1a" : "#f5f5f5"
    property color overlayColor: isDark ? "black" : "white"
    property real overlayOpacity: isDark ? 0.65 : 0.75
    property real nowPlayingOverlayOpacity: isDark ? 0.4 : 0.5
    
    // UI element colors
    property color panelBackground: isDark ? "#333333" : "#e8e8e8"
    property color inputBackground: isDark ? "#383838" : "#ffffff"
    property color inputBackgroundHover: isDark ? "#404040" : "#f0f0f0"
    property color borderColor: isDark ? "#505050" : "#d0d0d0"
    property color selectedBackground: isDark ? "#4a5fba" : "#2196F3"
    property color hoverBackground: isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.05)
    
    // Special UI elements
    property color errorText: "#ff6b6b"
    property color successText: "#51cf66"
    property color linkColor: isDark ? "#5a6fca" : "#1976D2"
    
    // Edge/separator colors
    property color edgeLineColor: isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1)
    property real edgeLineOpacity: 0.6

    // Carousel gradient
    property color upperGradientColor: isDark ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.25)
    property color lowerGradientColor: isDark ? Qt.rgba(0, 0, 0, 1.0) : Qt.rgba(0, 0, 0, 0.95)
}