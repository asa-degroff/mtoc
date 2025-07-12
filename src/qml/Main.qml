import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Mtoc.Backend 1.0
import "Views/"
import "Components/"

ApplicationWindow {
    id: window
    width: 1920
    height: 1200
    minimumWidth: 800  // Set a reasonable minimum to fit all panes
    minimumHeight: 500
    visible: true
    title: SystemInfo.appName + " - " + SystemInfo.appVersion
    
    // Save state when window is closing
    onClosing: function(close) {
        console.log("Main.qml: Window closing, saving playback state");
        if (MediaPlayer) {
            MediaPlayer.saveState();
        }
    }

    // Property to hold the current track metadata
    property var currentTrack: ({})
    
    // Resize handler for deferred resizing
    ResizeHandler {
        id: resizeHandler
        resizeDelay: 250  // Wait 250ms after resize stops
        
        onResizeStarted: {
            // During resize, we just clip/letterbox the content
            // No need to hide anything
        }
        
        onResizeCompleted: {
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
    
    // Restore playback state when application is fully loaded
    Component.onCompleted: {
        console.log("Main.qml: Window loaded");
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
