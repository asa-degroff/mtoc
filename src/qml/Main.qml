import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Mtoc.Backend 1.0
import "Views/"
import "Components/"

ApplicationWindow {
    id: window
    width: SettingsManager.windowWidth
    height: SettingsManager.windowHeight
    x: SettingsManager.windowX >= 0 ? SettingsManager.windowX : Screen.width / 2 - width / 2
    y: SettingsManager.windowY >= 0 ? SettingsManager.windowY : Screen.height / 2 - height / 2
    minimumWidth: effectiveLayoutMode === SettingsManager.Compact ? 700 : 1050
    minimumHeight: 700
    visible: true
    title: SystemInfo.appName
    
    // Save state when window is closing
    onClosing: function(close) {
        console.log("Main.qml: Window closing, saving playback state");
        
        // Close all child windows first
        if (libraryPaneWide && libraryPaneWide.closeAllWindows) {
            libraryPaneWide.closeAllWindows();
        }
        if (libraryPaneCompact && libraryPaneCompact.closeAllWindows) {
            libraryPaneCompact.closeAllWindows();
        }
        
        if (MediaPlayer) {
            MediaPlayer.saveState();
        }
    }

    // Property to hold the current track metadata
    property var currentTrack: ({})
    
    // Responsive layout properties
    property real libraryPaneRatio: mainContent.width < 1250 ? 0.55 : 0.45
    property real nowPlayingPaneRatio: 1.0 - libraryPaneRatio
    
    // Effective layout mode (considering automatic mode)
    property int effectiveLayoutMode: {
        if (SettingsManager.layoutMode === SettingsManager.Automatic) {
            return window.width < 1200 ? SettingsManager.Compact : SettingsManager.Wide
        }
        return SettingsManager.layoutMode
    }
    
    // Close popups when layout mode changes
    onEffectiveLayoutModeChanged: {
        if (compactNowPlayingBar) {
            compactNowPlayingBar.queuePopupVisible = false
            compactNowPlayingBar.albumArtPopupVisible = false
        }
    }
    
    // Timer to debounce window geometry changes
    Timer {
        id: saveGeometryTimer
        interval: 500  // Wait 500ms after resize/move stops
        onTriggered: {
            SettingsManager.windowWidth = window.width
            SettingsManager.windowHeight = window.height
            SettingsManager.windowX = window.x
            SettingsManager.windowY = window.y
            //console.log("Main.qml: Saved window geometry - " + window.width + "x" + window.height + " at " + window.x + "," + window.y)
        }
    }
    
    // Save window dimensions when they change
    onWidthChanged: saveGeometryTimer.restart()
    onHeightChanged: saveGeometryTimer.restart()
    onXChanged: saveGeometryTimer.restart()
    onYChanged: saveGeometryTimer.restart()
    
    // Resize handler for deferred resizing
    ResizeHandler {
        id: resizeHandler
        resizeDelay: 250  // Wait 250ms after resize stops
        
        onResizeStarted: {
            // During resize, we just clip/letterbox the content
            // No need to hide anything
        }
        
        onResizeCompleted: function(newWidth, newHeight) {
            // Apply new dimensions to content
            mainContent.width = newWidth
            mainContent.height = newHeight
            
            // Force garbage collection after resize
            gc()
        }
    }
    
    // Black background for letterboxing effect
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
    }
    
    // Viewport container that clips or letterboxes content
    Item {
        id: viewportContainer
        anchors.fill: parent
        clip: true  // Clip content when window is smaller
        
        // Main content container - stays at deferred size
        Item {
            id: mainContent
            width: resizeHandler.deferredWidth
            height: resizeHandler.deferredHeight
            
            // Center content when window is larger (letterbox)
            x: parent.width > width ? (parent.width - width) / 2 : 0
            y: parent.height > height ? (parent.height - height) / 2 : 0
        
        // Layout based on mode
        Item {
            anchors.fill: parent
            
            // Wide layout (default)
            RowLayout {
                anchors.fill: parent
                spacing: 0
                visible: effectiveLayoutMode === SettingsManager.Wide

                // Library Pane
                LibraryPane {
                    id: libraryPaneWide
                    Layout.fillWidth: true
                    Layout.preferredWidth: mainContent.width * libraryPaneRatio
                    Layout.fillHeight: true
                }

                // Now Playing Pane
                NowPlayingPane {
                    id: nowPlayingPane
                    Layout.fillWidth: true
                    Layout.preferredWidth: mainContent.width * nowPlayingPaneRatio
                    Layout.fillHeight: true
                    
                    // Pass reference to library pane for navigation
                    libraryPane: libraryPaneWide
                    
                    Component.onCompleted: {
                        console.log("NowPlayingPane added to Main.qml");
                    }
                }
            }
            
            // Compact layout
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: effectiveLayoutMode === SettingsManager.Compact
                
                // Library Pane (full width)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    
                    LibraryPane {
                        id: libraryPaneCompact
                        anchors.fill: parent
                    }
                    
                    // Queue popup for compact mode - parented to library pane container
                    QueuePopup {
                        id: queuePopup
                        parent: parent
                        queueModel: MediaPlayer.queue
                        currentPlayingIndex: MediaPlayer.currentQueueIndex
                        isOpen: compactNowPlayingBar.queuePopupVisible
                        onClosed: compactNowPlayingBar.queuePopupVisible = false
                    }
                    
                    // Album art popup for compact mode - parented to library pane container
                    AlbumArtPopup {
                        id: albumArtPopup
                        parent: parent
                        albumArtUrl: compactNowPlayingBar.albumArtUrl
                        isOpen: compactNowPlayingBar.albumArtPopupVisible
                        onClosed: compactNowPlayingBar.albumArtPopupVisible = false
                    }
                }
                
                // Compact Now Playing Bar
                CompactNowPlayingBar {
                    id: compactNowPlayingBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    
                    onAlbumTitleClicked: function(artistName, albumTitle) {
                        libraryPaneCompact.jumpToAlbum(artistName, albumTitle)
                    }
                    
                    onArtistClicked: function(artistName) {
                        libraryPaneCompact.jumpToArtist(artistName)
                    }
                }
            }
        }
        }  // mainContent
    }  // viewportContainer

    // Function to format duration in seconds to MM:SS format
    function formatDuration(seconds) {
        var minutes = Math.floor(seconds / 60);
        var remainingSeconds = seconds % 60;
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }
    
    // Timer to check rendering info after window is ready
    Timer {
        id: renderInfoTimer
        interval: 100
        running: true
        repeat: false
    }
    
    // Function to ensure window is visible on screen
    function ensureWindowVisible() {
        // Check if window position is valid and visible
        var screenGeometry = Qt.application.screens[0];
        var screenWidth = screenGeometry.width;
        var screenHeight = screenGeometry.height;
        
        // Ensure at least 100 pixels of the window are visible
        var minVisible = 100;
        
        // Check horizontal bounds
        if (window.x + minVisible > screenWidth) {
            window.x = screenWidth - window.width / 2;
        } else if (window.x + window.width < minVisible) {
            window.x = minVisible - window.width / 2;
        }
        
        // Check vertical bounds
        if (window.y + minVisible > screenHeight) {
            window.y = screenHeight - window.height / 2;
        } else if (window.y < 0) {
            window.y = 0;
        }
        
        // Ensure window fits on screen
        if (window.width > screenWidth) {
            window.width = screenWidth - 50;
        }
        if (window.height > screenHeight) {
            window.height = screenHeight - 50;
        }
    }
    
    // Restore playback state when application is fully loaded
    Component.onCompleted: {
        //console.log("Main.qml: Window loaded");
        
        // Ensure window is visible on screen
        ensureWindowVisible();
        
        // Give focus to library pane for keyboard navigation
        if (effectiveLayoutMode === SettingsManager.Wide) {
            libraryPaneWide.forceActiveFocus();
        } else {
            libraryPaneCompact.forceActiveFocus();
        }
        
        // Wait for MediaPlayer to be ready before restoring state
        if (MediaPlayer.isReady) {
            console.log("Main.qml: MediaPlayer is ready, restoring playback state");
            MediaPlayer.restoreState();
        } else {
            console.log("Main.qml: MediaPlayer not ready yet, waiting...");
            // MediaPlayer will handle restoration when it becomes ready
            MediaPlayer.restoreState();
        }
    }
    
    // Global keyboard shortcut for search
    Shortcut {
        sequence: StandardKey.Find  // Ctrl+F on Linux, Cmd+F on macOS
        onActivated: {
            if (effectiveLayoutMode === SettingsManager.Wide) {
                libraryPaneWide.focusSearchBar()
            } else {
                libraryPaneCompact.focusSearchBar()
            }
        }
    }
    
}
