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
    
    // Reference to the file dialog for selecting music folders
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        currentFolder: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
        
        onAccepted: {
            // Extract the local file path
            var path = folderDialog.selectedFolder.toString();
            path = path.replace(/^(file:\/{2})/,"");
            
            // Add the folder to LibraryManager
            LibraryManager.addMusicFolder(path);
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
                                Layout.fillWidth: true
                                text: modelData
                                elide: Text.ElideMiddle
                                color: "white"
                            }
                            
                            Button {
                                text: "Remove"
                                onClicked: LibraryManager.removeMusicFolder(modelData)
                            }
                        }
                    }
                }
            }
        }
        
        // Library browser view with albums grouped by artists
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#2a2a2a"
            radius: 4
            
            // View mode selector
            TabBar {
                id: libraryTabBar
                width: parent.width
                
                TabButton { text: "Artists" }
                TabButton { text: "Albums" }
            }
            
            // Views container
            StackLayout {
                id: viewStack
                anchors.top: libraryTabBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                currentIndex: libraryTabBar.currentIndex
                
                // Artists with Albums view
                Item {
                    id: artistsView
                    
                    property string selectedArtist: ""
                    
                    // Split view with artists on left, albums on right
                    RowLayout {
                        anchors.fill: parent
                        spacing: 10
                        
                        // Artists list (left side)
                        Rectangle {
                            Layout.fillHeight: true
                            Layout.preferredWidth: parent.width * 0.4
                            color: "#252525"
                            radius: 4
                            clip: true
                            
                            // Header
                            Rectangle {
                                id: artistListHeader
                                width: parent.width
                                height: 40
                                color: "#333333"
                                
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Artists"
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }
                            
                            // Artist ListView
                            ListView {
                                id: artistsListView
                                anchors.top: artistListHeader.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 1
                                clip: true
                                model: LibraryManager.artistModel
                                
                                // Highlight for selected artist
                                highlight: Rectangle {
                                    width: artistsListView.width
                                    height: 50
                                    color: "#3f51b5"
                                    radius: 2
                                }
                                highlightFollowsCurrentItem: true
                                focus: true
                                
                                // Artist item delegate
                                delegate: Item {
                                    id: artistDelegate
                                    width: artistsListView.width
                                    height: 50
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10
                                            
                                            // Artist image/icon
                                            Rectangle {
                                                width: 36
                                                height: 36
                                                radius: 18
                                                color: "#555555"
                                                
                                                Image {
                                                    id: artistImage
                                                    anchors.fill: parent
                                                    anchors.margins: 1
                                                    source: modelData.image || ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    visible: source != ""
                                                    clip: true
                                                    // Simple mask for Qt 6
                                                    layer.enabled: true
                                                }
                                                
                                                // Fallback icon if no image
                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: "#555555"
                                                    visible: artistImage.source == ""
                                                    
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.name ? modelData.name.charAt(0) : "?"
                                                        color: "white"
                                                        font.pixelSize: 18
                                                        font.bold: true
                                                    }
                                                }
                                            }
                                            
                                            // Artist info
                                            Column {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                
                                                Label {
                                                    text: modelData.name
                                                    font.pixelSize: 14
                                                    color: artistsListView.currentIndex === index ? "white" : "#f0f0f0"
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }
                                                
                                                Label {
                                                    text: modelData.albumCount + " album" + (modelData.albumCount !== 1 ? "s" : "")
                                                    font.pixelSize: 11
                                                    color: artistsListView.currentIndex === index ? "#e0e0e0" : "#909090"
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Mouse interaction
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            artistsListView.currentIndex = index
                                            artistsView.selectedArtist = modelData.name
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Albums grid for selected artist (right side)
                        Rectangle {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            color: "#252525"
                            radius: 4
                            clip: true
                            
                            // Header
                            Rectangle {
                                id: albumsHeader
                                width: parent.width
                                height: 40
                                color: "#333333"
                                
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: artistsView.selectedArtist ? artistsView.selectedArtist + " - Albums" : "All Albums"
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }
                            
                            // Albums grid showing albums for the selected artist
                            GridView {
                                id: artistAlbumsView
                                anchors.top: albumsHeader.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                clip: true
                                cellWidth: 160
                                cellHeight: 200
                                
                                // Filter albums by selected artist and sort by year (new to old)
                                model: {
                                    if (!artistsView.selectedArtist) 
                                        return [];
                                        
                                    // Filter albums for selected artist
                                    var artistAlbums = [];
                                    var allAlbums = LibraryManager.albumModel;
                                    
                                    for (var i = 0; i < allAlbums.length; i++) {
                                        if (allAlbums[i].artist === artistsView.selectedArtist) {
                                            artistAlbums.push(allAlbums[i]);
                                        }
                                    }
                                    
                                    // Sort by year (newest first)
                                    artistAlbums.sort(function(a, b) {
                                        return b.year - a.year;
                                    });
                                    
                                    return artistAlbums;
                                }
                                
                                delegate: Rectangle {
                                    width: 150
                                    height: 190
                                    color: "#3a3a3a"
                                    radius: 4
                                    
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        
                                        // Album cover
                                        Rectangle {
                                            width: parent.width
                                            height: width
                                            color: "#555555"
                                            
                                            Image {
                                                anchors.fill: parent
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                            }
                                        }
                                        
                                        // Album title
                                        Label {
                                            width: parent.width
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 1
                                            horizontalAlignment: Text.AlignHCenter
                                            color: "white"
                                            font.pixelSize: 13
                                        }
                                        
                                        // Year and track count
                                        Label {
                                            width: parent.width
                                            text: modelData.year + " • " + modelData.trackCount + " track" + (modelData.trackCount !== 1 ? "s" : "")
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            color: "#aaaaaa"
                                            font.pixelSize: 11
                                        }
                                    }
                                    
                                    // Mouse interaction
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            // TODO: Show tracks for this album
                                            console.log("Album clicked: " + modelData.title);
                                        }
                                    }
                                }
                            }
                            
                            // Empty state message when no artist is selected
                            Text {
                                anchors.centerIn: parent
                                text: "Select an artist to view their albums"
                                color: "#808080"
                                font.pixelSize: 16
                                visible: !artistsView.selectedArtist
                            }
                        }
                    }
                }
                
                // All Albums view - organized by artist
                Rectangle {
                    id: allAlbumsContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    clip: true
                    
                    // We use a ListView to display artists with their albums
                    ListView {
                        id: artistGroupsListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 10
                        model: LibraryManager.artistModel
                        
                        // Each artist section is a delegate containing album grid
                        delegate: Column {
                            id: artistSection
                            width: artistGroupsListView.width
                            spacing: 5
                            visible: modelData.albumCount > 0
                            
                            // Artist header
                            Rectangle {
                                width: parent.width
                                height: 40
                                color: "#333333"
                                
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }
                            
                            // Albums for this artist
                            GridView {
                                id: artistAlbumsGrid
                                width: parent.width
                                height: Math.ceil(count / Math.floor(width / 160)) * 200
                                clip: true
                                cellWidth: 160
                                cellHeight: 200
                                interactive: false // Parent ListView handles scrolling
                                
                                // We filter the main album model to show only this artist's albums
                                model: {
                                    var artistAlbums = [];
                                    var allAlbums = LibraryManager.albumModel;
                                    
                                    for (var i = 0; i < allAlbums.length; i++) {
                                        if (allAlbums[i].artist === modelData.name) {
                                            artistAlbums.push(allAlbums[i]);
                                        }
                                    }
                                    
                                    // Sort by year (newest first)
                                    artistAlbums.sort(function(a, b) {
                                        return b.year - a.year;
                                    });
                                    
                                    return artistAlbums;
                                }
                                
                                // Album item delegate
                                delegate: Rectangle {
                                    width: 150
                                    height: 190
                                    color: "#3a3a3a"
                                    radius: 4
                                    
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        
                                        // Album cover
                                        Rectangle {
                                            width: parent.width
                                            height: width
                                            color: "#555555"
                                            
                                            Image {
                                                anchors.fill: parent
                                                source: modelData.image || ""
                                                fillMode: Image.PreserveAspectCrop
                                            }
                                        }
                                        
                                        // Album title
                                        Label {
                                            width: parent.width
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 1
                                            horizontalAlignment: Text.AlignHCenter
                                            color: "white"
                                            font.pixelSize: 13
                                        }
                                        
                                        // Year
                                        Label {
                                            width: parent.width
                                            text: modelData.year
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            color: "#aaaaaa"
                                            font.pixelSize: 11
                                        }
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            // TODO: Show tracks for this album
                                            console.log("Album clicked: " + modelData.title);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}