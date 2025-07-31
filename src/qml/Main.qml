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
    minimumWidth: 800  // Set a reasonable minimum to fit all panes
    minimumHeight: 500
    visible: true
    title: SystemInfo.appName + " - " + SystemInfo.appVersion
    
    // Save state when window is closing
    onClosing: function(close) {
        console.log("Main.qml: Window closing, saving playback state");
        
        // Close all child windows first
        if (libraryPane && libraryPane.closeAllWindows) {
            libraryPane.closeAllWindows();
        }
        
        if (MediaPlayer) {
            MediaPlayer.saveState();
        }
    }

    // Property to hold the current track metadata
    property var currentTrack: ({})
    
    // Timer to debounce window geometry changes
    Timer {
        id: saveGeometryTimer
        interval: 500  // Wait 500ms after resize/move stops
        onTriggered: {
            SettingsManager.windowWidth = window.width
            SettingsManager.windowHeight = window.height
            SettingsManager.windowX = window.x
            SettingsManager.windowY = window.y
            console.log("Main.qml: Saved window geometry - " + window.width + "x" + window.height + " at " + window.x + "," + window.y)
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
        
        // Basic two-pane layout
        RowLayout {
            anchors.fill: parent
            spacing: 0  // Remove default spacing

            // Library Pane
            LibraryPane {
                id: libraryPane
                Layout.fillWidth: true
                Layout.preferredWidth: mainContent.width * 0.45 // 45% of content width
                Layout.fillHeight: true
            }


            // Now Playing Pane
            NowPlayingPane {
                id: nowPlayingPane
                Layout.fillWidth: true
                Layout.preferredWidth: mainContent.width * 0.55 // 55% of content width
                Layout.fillHeight: true
                
                // Pass reference to library pane for navigation
                libraryPane: libraryPane
                
                Component.onCompleted: {
                    console.log("NowPlayingPane added to Main.qml");
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
        console.log("Main.qml: Window loaded");
        
        // Ensure window is visible on screen
        ensureWindowVisible();
        
        // Give focus to library pane for keyboard navigation
        libraryPane.forceActiveFocus();
        
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
            libraryPane.focusSearchBar()
        }
    }
}
