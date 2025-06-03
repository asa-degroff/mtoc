import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0
import "Views/"

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

    // Basic two-pane layout (placeholders)
    RowLayout {
        anchors.fill: parent
        spacing: 0  // Remove default spacing

        // Library Pane
        LibraryPane {
            id: libraryPane
            Layout.fillWidth: true
            Layout.preferredWidth: window.width * 0.45 // 45% of window width
            Layout.fillHeight: true
        }

        // Subtle divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Qt.rgba(255, 255, 255, 0.1)  // Very subtle white line
            
            // Gradient for fade effect at top and bottom
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.05; color: Qt.rgba(255, 255, 255, 0.1) }
                GradientStop { position: 0.95; color: Qt.rgba(255, 255, 255, 0.1) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Now Playing Pane
        NowPlayingPane {
            id: nowPlayingPane
            Layout.fillWidth: true
            Layout.preferredWidth: window.width * 0.55 // 55% of window width
            Layout.fillHeight: true
            
            Component.onCompleted: {
                console.log("NowPlayingPane added to Main.qml");
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
            
            // Check if we have any music folders configured
            console.log("Checking musicFolders property...");
            if (LibraryManager.musicFolders.length === 0) {
                // Add a default music folder for testing
                var musicDir = "/home/asa/Music";
                console.log("Adding default music folder for testing:", musicDir);
                LibraryManager.addMusicFolder(musicDir);
            } else {
                console.log("Music folders already configured:", JSON.stringify(LibraryManager.musicFolders));
            }
            
            // Skip MetadataExtractor test for now
            // This was causing issues during startup
            
            // Don't automatically scan on startup - let user initiate
            console.log("Library contains", LibraryManager.trackCount, "tracks");
        } catch (e) {
            console.error("Error during initialization:", e);
        }
    }
}
