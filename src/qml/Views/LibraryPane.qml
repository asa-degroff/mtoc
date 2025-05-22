import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1
import QtQuick.Effects
import Mtoc.Backend 1.0

Item {
    id: root
    width: parent.width
    height: parent.height
    
    property var selectedAlbum: null

    onSelectedAlbumChanged: {
        // console.log("Selected album changed to: " + (selectedAlbum ? selectedAlbum.title : "none"));
        if (selectedAlbum) {
            // Assuming selectedAlbum has 'artist' and 'title' properties
            var tracks = LibraryManager.getTracksForAlbumAsVariantList(selectedAlbum.artist, selectedAlbum.title);
            rightPane.currentAlbumTracks = tracks;
            rightPane.albumTitleText = selectedAlbum.artist + " - " + selectedAlbum.title;
        } else {
            rightPane.currentAlbumTracks = [];
            rightPane.albumTitleText = "No album selected";
        }
    }
    
    // Reference to the file dialog for selecting music folders
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        currentFolder: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
        
        onAccepted: {
            // Extract the local file path - safely handle potentially different property names
            var folderUrl;
            if (folderDialog.folder) {
                // Qt 5.x often uses folder
                folderUrl = folderDialog.folder;
            } else if (folderDialog.currentFolder) {
                // Some versions use currentFolder
                folderUrl = folderDialog.currentFolder;
            } else if (folderDialog.selectedFolder) {
                // Others might use selectedFolder
                folderUrl = folderDialog.selectedFolder;
            }
            
            if (folderUrl) {
                var path = folderUrl.toString();
                // Remove the file:// prefix but keep the leading slash for absolute paths
                if (path.startsWith("file:///")) {
                    // Linux/Mac format - preserve the leading slash
                    path = path.replace(/^(file:\/\/\/)/,"/");
                } else if (path.startsWith("file://")) {
                    // Other format - typically Windows
                    path = path.replace(/^(file:\/\/)/,"");
                }
                
                console.log("Adding music folder: " + path);
                // Add the folder to LibraryManager
                LibraryManager.addMusicFolder(path);
            } else {
                console.error("Could not determine selected folder path");
            }
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        
        // Header section
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#2a2a2a"
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12
                
                Label {
                    text: "Music Library"
                    font.pixelSize: 20
                    font.bold: true
                    color: "white"
                }
                
                Item { Layout.fillWidth: true } // Spacer
                
                Button {
                    text: "Add Folder"
                    onClicked: folderDialog.open()
                }
                
                Button {
                    text: LibraryManager.scanning ? "Cancel Scan" : "Scan Library"
                    enabled: true // Always enabled - LibraryManager handles cancel state internally
                    onClicked: {
                        if (LibraryManager.scanning) {
                            LibraryManager.cancelScan();
                        } else {
                            LibraryManager.startScan();
                        }
                    }
                }
            }
        }
        
        // Library statistics section
        Rectangle {
            Layout.fillWidth: true
            height: 100
            color: "#2a2a2a"
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 24
                
                // Artists count
                Column {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4
                    
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: LibraryManager.artistCount
                        font.pixelSize: 32
                        font.bold: true
                        color: "white"
                    }
                    
                    Label {
                        text: "Artists"
                        font.pixelSize: 14
                        color: "#cccccc"
                    }
                }
                
                // Albums count
                Column {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4
                    
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: LibraryManager.albumCount
                        font.pixelSize: 32
                        font.bold: true
                        color: "white"
                    }
                    
                    Label {
                        text: "Albums"
                        font.pixelSize: 14
                        color: "#cccccc"
                    }
                }
                
                // Tracks count
                Column {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4
                    
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: LibraryManager.trackCount
                        font.pixelSize: 32
                        font.bold: true
                        color: "white"
                    }
                    
                    Label {
                        text: "Tracks"
                        font.pixelSize: 14
                        color: "#cccccc"
                    }
                }
                
                // Scan progress
                Column {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    spacing: 4
                    visible: LibraryManager.scanning
                    
                    ProgressBar {
                        width: parent.width
                        value: LibraryManager.scanProgress
                        from: 0
                        to: 1
                    }
                    
                    Label {
                        text: "Scanning: " + LibraryManager.scanProgressText
                        font.pixelSize: 12
                        color: "#cccccc"
                    }
                }
            }
        }
        
        // Music folders section
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: "#2a2a2a"
            radius: 4
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                Label {
                    text: "Music Folders"
                    font.pixelSize: 16
                    font.bold: true
                    color: "white"
                }
                
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: LibraryManager.musicFolders
                    
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 40
                        color: index % 2 === 0 ? "#3a3a3a" : "#353535"
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            
                            Label {
                                text: modelData
                                color: "white"
                                elide: Text.ElideLeft
                            }
                            
                            Item { Layout.fillWidth: true } // Spacer
                            
                            Button {
                                text: "Remove"
                                flat: true
                                onClicked: {
                                    LibraryManager.removeMusicFolder(modelData);
                                }
                            }
                        }
                    }
                    
                    ScrollIndicator.vertical: ScrollIndicator { }
                }
            }
        }
        
        // Main content area: Two-column layout
        SplitView {
            id: splitView
            Layout.fillWidth: true
            Layout.fillHeight: true // This will take the remaining space
            orientation: Qt.Horizontal
            handle: Rectangle { // Custom handle for better visibility
                implicitWidth: 6
                implicitHeight: 6
                color: "#444444"
                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: parent.height * 0.3
                    color: "#666666"
                    radius: 1
                }
            }

            // Left Pane: Artist List
            Rectangle {
                id: leftPaneContainer
                SplitView.preferredWidth: splitView.width * 0.35
                SplitView.minimumWidth: 180  // Reduced from 280 to fit better in smaller windows
                Layout.fillHeight: true
                color: "#2c2c2c"
                radius: 4
                clip: true // Ensure content doesn't overflow radius

                ListView {
                    id: artistsListView
                    anchors.fill: parent
                    anchors.margins: 4 // Small margin inside the pane
                    clip: true
                    model: LibraryManager.artistModel
                    spacing: 2

                    delegate: Column {
                        width: ListView.view.width
                        // Height will be dynamic based on albumsVisible
                        
                        property bool albumsVisible: false
                        // Store modelData for easier access in nested views/functions
                        property var artistData: modelData 

                        Rectangle {
                            width: parent.width
                            height: 40
                            color: artistsListView.currentIndex === index ? "#3f51b5" : "transparent"
                            radius: 2

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                
                                Label {
                                    text: artistData.name
                                    color: "white"
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                // Add an indicator for expansion (e.g., chevron)
                                Label {
                                    text: albumsVisible ? "\u25BC" : "\u25B6" // Down/Right arrow
                                    color: "white"
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    albumsVisible = !albumsVisible;
                                    artistsListView.currentIndex = index; // Optional: select on expand
                                }
                            }
                        }

                        // Albums GridView - visible based on albumsVisible
                        Rectangle {
                            id: artistAlbumsContainer
                            width: parent.width
                            // Dynamic height based on content
                            height: albumsVisible ? (albumsGrid.contentHeight + (albumsGrid.count > 0 ? 16 : 0)) : 0 // Add padding if albums exist
                            color: "#333333" // Slightly different background for albums section
                            visible: albumsVisible
                            clip: true
                            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } } // Smooth expand/collapse

                            GridView {
                                id: albumsGrid
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                cellWidth: 100 + 8 // Thumbnail size + padding
                                cellHeight: 120 + 8 // Thumbnail + title + padding
                                interactive: false // Parent ListView handles scrolling primarily

                                model: {
                                    if (!albumsVisible) return []; // Don't process if not visible
                                    var artistAlbums = [];
                                    var allAlbums = LibraryManager.albumModel;
                                    for (var i = 0; i < allAlbums.length; i++) {
                                        if (allAlbums[i].artist === artistData.name) {
                                            artistAlbums.push(allAlbums[i]);
                                        }
                                    }
                                    // AlbumModel from LibraryManager should already be sorted by year for artists
                                    // If not, sort here: artistAlbums.sort(function(a,b){ return b.year - a.year; });
                                    return artistAlbums;
                                }

                                delegate: Item { 
                                    width: albumsGrid.cellWidth - 8
                                    height: albumsGrid.cellHeight - 8

                                    ColumnLayout { 
                                        anchors.fill: parent
                                        spacing: 4

                                        Rectangle { // Album Art container
                                            Layout.alignment: Qt.AlignHCenter
                                            width: 90
                                            height: 90
                                            color: "#555555"
                                            radius: 3

                                            Image {
                                                anchors.fill: parent
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                                clip: true
                                            }
                                        }

                                        Label { // Album Title
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            color: "white"
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            maximumLineCount: 2
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                    MouseArea { 
                                        anchors.fill: parent
                                        onClicked: {
                                            root.selectedAlbum = modelData; // Update the root's selectedAlbum property
                                        }
                                    }
                                }
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }
                    }
                    ScrollIndicator.vertical: ScrollIndicator { }
                }
            }

            // Right Pane: Track List
            Rectangle {
                id: rightPane
                SplitView.minimumWidth: 160  // Reduced from 250 to fit better in smaller windows
                SplitView.fillWidth: true
                color: "#252525"
                radius: 4
                clip: true

                property var currentAlbumTracks: []
                property string albumTitleText: "No album selected"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4

                    Label {
                        id: trackListHeader
                        Layout.fillWidth: true
                        text: rightPane.albumTitleText
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                        padding: 8
                        elide: Text.ElideRight
                        background: Rectangle {
                            color: "#333333"
                            radius: 2
                        }
                    }

                    ListView {
                        id: trackListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: rightPane.currentAlbumTracks
                        visible: rightPane.currentAlbumTracks.length > 0
                        spacing: 1

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 45
                            color: index % 2 === 0 ? "#2e2e2e" : "#2a2a2a"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Label { // Track Number
                                    text: modelData.trackNumber ? String(modelData.trackNumber).padStart(2, '0') : "--"
                                    color: "#aaaaaa"
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 25
                                    horizontalAlignment: Text.AlignRight
                                }

                                Label { // Track Title
                                    text: modelData.title || "Unknown Track"
                                    color: "white"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label { // Track Duration
                                    text: modelData.duration ? formatDuration(modelData.duration) : "0:00"
                                    color: "#aaaaaa"
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 40
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    console.log("Track clicked: " + modelData.title);
                                    // TODO: Implement play track functionality
                                    // LibraryManager.playTrack(modelData.filePath or uniqueId);
                                }
                            }
                        }
                        ScrollIndicator.vertical: ScrollIndicator { }
                    }

                    // Message for when no tracks are available or no album selected
                    Label {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: rightPane.selectedAlbum ? "No tracks found for this album." : "Select an album to view tracks."
                        color: "#808080"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        visible: rightPane.currentAlbumTracks.length === 0
                        font.pixelSize: 14
                    }
                }
            }
        }
    }

    function formatDuration(seconds) {
        if (isNaN(seconds) || seconds < 0) return "0:00";
        var min = Math.floor(seconds / 60);
        var sec = Math.floor(seconds % 60);
        return min + ":" + (sec < 10 ? "0" : "") + sec;
    }
}