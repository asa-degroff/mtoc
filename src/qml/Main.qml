import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0
import "Views/"

ApplicationWindow {
    id: window
    width: 1280
    height: 720
    visible: true
    title: SystemInfo.appName + " - " + SystemInfo.appVersion

    // Property to hold the current track metadata
    property var currentTrack: ({})

    // Basic two-pane layout (placeholders)
    RowLayout {
        anchors.fill: parent

        // Library Pane
        LibraryPane {
            id: libraryPane
            Layout.fillWidth: true
            Layout.preferredWidth: window.width * 0.35 // 35% of window width
            Layout.fillHeight: true
        }

        // Now Playing Pane (Placeholder)
        Rectangle {
            id: nowPlayingPanePlaceholder
            Layout.fillWidth: true // Ensure it participates in filling
            Layout.preferredWidth: window.width * 0.65 // 65% of window width
            Layout.fillHeight: true
            color: "whitesmoke"
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 15
                
                // Now Playing Header
                Text {
                    text: "Now Playing"
                    font.pixelSize: 24
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 10
                }
                
                // Track Title
                Text {
                    text: "Title: " + (currentTrack.title || "Unknown")
                    font.pixelSize: 18
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                
                // Artist
                Text {
                    text: "Artist: " + (currentTrack.artist || "Unknown")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                
                // Album
                Text {
                    text: "Album: " + (currentTrack.album || "Unknown")
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                
                // Additional metadata in a grid
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    columnSpacing: 20
                    rowSpacing: 5
                    
                    Text { text: "Track Number:" }
                    Text { text: currentTrack.trackNumber || "--" }
                    
                    Text { text: "Year:" }
                    Text { text: currentTrack.year || "--" }
                    
                    Text { text: "Genre:" }
                    Text { text: currentTrack.genre || "--" }
                    
                    Text { text: "Duration:" }
                    Text { 
                        text: currentTrack.duration ? formatDuration(currentTrack.duration) : "--" 
                    }
                }
                
                // File path (small, for debug purposes)
                Text {
                    text: "File: " + (currentTrack.filePath || "--")
                    font.pixelSize: 10
                    color: "gray"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    Layout.topMargin: 20
                }
                
                // System information at the bottom
                Text {
                    text: SystemInfo.appName + " v" + SystemInfo.appVersion
                    font.pixelSize: 10
                    color: "gray"
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 20
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
            
            // Check if we have any music folders configured
            if (LibraryManager.musicFolders.length === 0) {
                // Add a default music folder for testing
                var musicDir = "/home/asa/Music";
                console.log("Adding default music folder for testing:", musicDir);
                LibraryManager.addMusicFolder(musicDir);
            } else {
                console.log("Music folders already configured:", JSON.stringify(LibraryManager.musicFolders));
            }
            
            // Test MetadataExtractor functionality
            var filePath = "/home/asa/Music/Beck/Guero/01 E‐Pro.m4a";
            var metadata = MetadataExtractor.extractAsVariantMap(filePath);
            
            // Store it in our property for display
            currentTrack = metadata;
            
            // Log metadata to the console
            console.log("Audio File Metadata loaded:", JSON.stringify(metadata, null, 2));
            
            // Start a library scan if needed
            if (LibraryManager.trackCount === 0) {
                console.log("Starting initial library scan...");
                LibraryManager.startScan();
            } else {
                console.log("Library already contains", LibraryManager.trackCount, "tracks");
            }
        } catch (e) {
            console.error("Error during initialization:", e);
        }
    }
}
