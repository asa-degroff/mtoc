import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
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

    // Property to hold the current track metadata
    property var currentTrack: ({})
    
    // Resize handler for deferred resizing
    ResizeHandler {
        id: resizeHandler
        resizeDelay: 250  // Wait 250ms after resize stops
        
        onResizeStarted: {
            // Show placeholder during resize
            mainContent.visible = false
            resizePlaceholder.visible = true
        }
        
        onResizeCompleted: {
            // Apply new dimensions and show content
            mainContent.width = newWidth
            mainContent.height = newHeight
            mainContent.visible = true
            resizePlaceholder.visible = false
            
            // Force garbage collection after resize
            gc()
        }
    }
    
    // Placeholder shown during resize
    Rectangle {
        id: resizePlaceholder
        anchors.fill: parent
        color: "#1a1a1a"
        visible: false
        
        // Simple resize indicator
        Column {
            anchors.centerIn: parent
            spacing: 20
            
            Label {
                text: "Resizing..."
                color: "white"
                font.pixelSize: 24
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Label {
                text: resizeHandler.actualWidth + " × " + resizeHandler.actualHeight
                color: "#808080"
                font.pixelSize: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Main content container
    Item {
        id: mainContent
        width: resizeHandler.deferredWidth
        height: resizeHandler.deferredHeight
        
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
    }

    // Function to format duration in seconds to MM:SS format
    function formatDuration(seconds) {
        var minutes = Math.floor(seconds / 60);
        var remainingSeconds = seconds % 60;
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }
    
    // Initialize the application
    Component.onCompleted: {
        console.log("Main.qml loaded - Initializing application");
        
        try {
            // Initialize LibraryManager
            console.log("Initializing LibraryManager...");
            
            // Music folders are now automatically loaded from settings in LibraryManager constructor
            console.log("Music folders configured:", JSON.stringify(LibraryManager.musicFolders));
            
            // Skip MetadataExtractor test for now
            // This was causing issues during startup
            
            // Don't automatically scan on startup - let user initiate
            console.log("Library contains", LibraryManager.trackCount, "tracks");
        } catch (e) {
            console.error("Error during initialization:", e);
        }
    }
}
