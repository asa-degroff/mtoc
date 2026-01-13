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
    
    // System accent color
    property color systemAccentColor: SettingsManager.systemAccentColor
    
    // Primary colors
    property color primaryText: isDark ? "white" : "#333333"
    property color secondaryText: isDark ? "#cccccc" : "#3d3d3d"
    property color tertiaryText: isDark ? "#999999" : "#444444"
    
    // Background colors
    property color backgroundColor: isDark ? "#1a1a1a" : "#f5f5f5"
    property color overlayColor: isDark ? "black" : "white"
    property real overlayOpacity: 0.65
    property real nowPlayingOverlayOpacity: isDark ? 0.4 : 0.5
    
    // UI element colors
    property color panelBackground: isDark ? "#333333" : "#e8e8e8"
    property color inputBackground: isDark ? "#383838" : "#ffffff"
    property color inputBackgroundHover: isDark ? "#404040" : "#f0f0f0"
    property color borderColor: isDark ? "#505050" : "#d0d0d0"
    property color selectedBackground: systemAccentColor
    property color hoverBackground: isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.05)
    
    // Selection colors with different opacity levels (derived from system accent)
    property color selectedBackgroundHighOpacity: Qt.rgba(systemAccentColor.r, systemAccentColor.g, systemAccentColor.b, 0.35)
    property color selectedBackgroundMediumOpacity: Qt.rgba(systemAccentColor.r, systemAccentColor.g, systemAccentColor.b, 0.25)
    property color selectedBackgroundLowOpacity: Qt.rgba(systemAccentColor.r, systemAccentColor.g, systemAccentColor.b, 0.15)
    property color selectedBackgroundVeryLowOpacity: Qt.rgba(systemAccentColor.r, systemAccentColor.g, systemAccentColor.b, isDark ? 0.15 : 0.08)
    property color highlightedBackground: Qt.rgba(systemAccentColor.r, systemAccentColor.g, systemAccentColor.b, 0.25)
    property color selectedBackgroundArtist: Qt.rgba(systemAccentColor.r, systemAccentColor.g, systemAccentColor.b, 0.38)
    
    // Special UI elements
    property color errorText: "#ff6b6b"
    property color successText: "#51cf66"
    property color linkColor: Qt.lighter(systemAccentColor, isDark ? 1.3 : 1.0)
    property color specialItemColor: Qt.lighter(systemAccentColor, isDark ? 1.4 : 1.2)
    
    // Edge/separator colors
    property color edgeLineColor: isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1)
    property real edgeLineOpacity: 0.6

    // Overlay colors (for UI elements displayed over dark backgrounds like album art)
    property color overlayPrimaryText: "#ffffff"
    property color overlaySecondaryText: "#aaaaaa"
    property color overlayTertiaryText: "#c0c0c0"
    property color overlayHoverBackground: Qt.rgba(1, 1, 1, 0.04)
    property color overlayDefaultBackground: Qt.rgba(1, 1, 1, 0.02)
    property color overlayBorderColor: Qt.rgba(1, 1, 1, 0.04)

    // Carousel gradient
    property color upperGradientColor: isDark ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.35)
    property color lowerGradientColor: isDark ? Qt.rgba(0, 0, 0, 1.0) : Qt.rgba(0, 0, 0, 1.0)
}