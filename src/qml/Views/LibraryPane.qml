import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Mtoc.Backend 1.0
import "../Components"

Item {
    id: root
    width: parent.width
    height: parent.height
    
    // Ensure we have a dark background as a base
    Rectangle {
        anchors.fill: parent
        color: "#1a1a1a"
        z: -3  // Behind everything else
    }
    
    property var selectedAlbum: null
    property var expandedArtists: ({})  // Object to store expansion state by artist name
    property string highlightedArtist: ""  // Track which artist to highlight
    property string currentAlbumId: ""
    property url albumArtUrl: ""
    property url thumbnailUrl: ""
    
    Component.onCompleted: {
        // Set initial thumbnail from MediaPlayer if available
        if (MediaPlayer.currentTrack && MediaPlayer.currentTrack.album && MediaPlayer.currentTrack.albumArtist) {
            var encodedArtist = encodeURIComponent(MediaPlayer.currentTrack.albumArtist)
            var encodedAlbum = encodeURIComponent(MediaPlayer.currentTrack.album)
            thumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail"
        }
    }

    onSelectedAlbumChanged: {
        // console.log("Selected album changed to: " + (selectedAlbum ? selectedAlbum.title : "none"));
        if (selectedAlbum) {
            // Use albumArtist instead of artist
            var tracks = LibraryManager.getTracksForAlbumAsVariantList(selectedAlbum.albumArtist, selectedAlbum.title);
            rightPane.currentAlbumTracks = tracks;
            rightPane.albumTitleText = selectedAlbum.albumArtist + " - " + selectedAlbum.title;
            
            // Update the thumbnail URL for the background when an album is selected
            // Only update if not currently playing or if this is the playing album
            if (selectedAlbum.hasArt && (!MediaPlayer.currentTrack || 
                (MediaPlayer.currentTrack.albumArtist === selectedAlbum.albumArtist && 
                 MediaPlayer.currentTrack.album === selectedAlbum.title))) {
                // Use encoded format for consistency
                var encodedArtist = encodeURIComponent(selectedAlbum.albumArtist);
                var encodedAlbum = encodeURIComponent(selectedAlbum.title);
                thumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail";
            }
        } else {
            rightPane.currentAlbumTracks = [];
            rightPane.albumTitleText = "No album selected";
            // Don't clear thumbnailUrl here - let MediaPlayer control it when playing
        }
    }
    
    // Update album art URLs when track changes
    Connections {
        target: MediaPlayer
        
        function onCurrentTrackChanged(track) {
            if (track && track.album && track.albumArtist) {
                var newAlbumId = track.albumArtist + "_" + track.album
                if (newAlbumId !== currentAlbumId) {
                    currentAlbumId = newAlbumId
                    // Use encoded format for the URLs to avoid iteration issues
                    var encodedArtist = encodeURIComponent(track.albumArtist)
                    var encodedAlbum = encodeURIComponent(track.album)
                    albumArtUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/full"
                    thumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail"
                }
            } else {
                currentAlbumId = ""
                albumArtUrl = ""
                thumbnailUrl = ""
            }
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
    
    // Edit Library Dialog
    Popup {
        id: editLibraryDialog
        modal: true
        width: 600
        height: 500
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        
        background: Rectangle {
            color: "#2a2a2a"
            radius: 8
            border.color: "#444444"
            border.width: 1
        }
        
        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                
                // Title and close button
                RowLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        text: "Edit Library"
                        font.pixelSize: 20
                        font.bold: true
                        color: "white"
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Button {
                        text: "✕"
                        flat: true
                        onClicked: editLibraryDialog.close()
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                    }
                }
            
            // Library statistics section
            Rectangle {
                Layout.fillWidth: true
                height: 100
                color: "#333333"
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
                            value: LibraryManager.scanProgress / 100.0
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
                Layout.fillHeight: true
                color: "#333333"
                radius: 4
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Label {
                            text: "Music Folders"
                            font.pixelSize: 16
                            font.bold: true
                            color: "white"
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: "Add Folder"
                            onClicked: folderDialog.open()
                        }
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
                                    Layout.fillWidth: true
                                }
                                
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
            
            // Info text and action buttons
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                color: "#404040"
                radius: 4
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    Label {
                        text: "Scan your library to add files from the chosen folders to the music collection."
                        color: "#cccccc"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        Button {
                            text: "Clear Library"
                            onClicked: {
                                LibraryManager.clearLibrary();
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: LibraryManager.scanning ? "Cancel Scan" : "Scan Library"
                            highlighted: true
                            enabled: true
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
            }
            }
        }
    }
    
    // Blurred background
    BlurredBackground {
        id: blurredBg
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 80
        backgroundOpacity: 0.3
        z: -2  // Put this behind the dark overlay
    }
    
    // Dark overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.5
        z: -1  // This should be above the blurred background but below content
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        
        // Header section
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: Qt.rgba(0.1, 0.1, 0.1, 0.38)  // Semi-transparent dark
            radius: 8
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            
            // Inner shadow for depth
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.25)
            }
            
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
                    text: "Edit Library"
                    onClicked: editLibraryDialog.open()
                }
            }
        }
        
        // Horizontal Album Browser
        HorizontalAlbumBrowser {
            id: albumBrowser
            Layout.fillWidth: true
            Layout.preferredHeight: 360  // Height for albums with reflections
            
            onAlbumClicked: function(album) {
                root.selectedAlbum = album
                
                // Highlight the album's artist
                root.highlightedArtist = album.albumArtist
                
                // Find the artist in the list and ensure it's visible
                var artists = LibraryManager.artistModel
                for (var i = 0; i < artists.length; i++) {
                    if (artists[i].name === album.albumArtist) {
                        artistsListView.positionViewAtIndex(i, ListView.Contain)
                        break
                    }
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
                SplitView.preferredWidth: 420  // Width to fit 3 album covers (3*130 + margins)
                SplitView.minimumWidth: 280  // Minimum for 2 album covers
                Layout.fillHeight: true
                color: Qt.rgba(0.1, 0.1, 0.1, 0.25)  // Semi-transparent dark with smoky tint
                radius: 8
                clip: true // Ensure content doesn't overflow radius
                
                // 3D border effect - lit from above
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                
                // Inner shadow for depth
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                }

                // Container for ListView and ScrollBar
                Item {
                    anchors.fill: parent
                    anchors.margins: 4
                    
                    ListView {
                        id: artistsListView
                        anchors.fill: parent
                        anchors.rightMargin: 12 // Space for scrollbar
                        clip: true
                        model: LibraryManager.artistModel
                        spacing: 2
                    
                    // Increase scroll speed
                    flickDeceleration: 8000  // Default is 1500, can increase for faster stopping
                    maximumFlickVelocity: 2750  // Default is 2500, increase for faster scrolling
                    
                    // Smooth scrolling with bounds
                    boundsMovement: Flickable.StopAtBounds
                    boundsBehavior: Flickable.StopAtBounds
                    
                    // Increase wheel scroll speed while keeping smooth animation
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            // Multiply the pixel delta for faster scrolling
                            var pixelDelta = event.pixelDelta.y || event.angleDelta.y / 4;
                            artistsListView.flick(0, pixelDelta * 400); // Change this value to adjust scroll speed
                        }
                    }

                    delegate: Column {
                        width: ListView.view.width
                        // Height will be dynamic based on albumsVisible
                        
                        property bool albumsVisible: root.expandedArtists[modelData.name] || false
                        // Store modelData for easier access in nested views/functions
                        property var artistData: modelData 

                        Rectangle {
                            id: artistItemRect
                            width: parent.width - 4
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            height: 40
                            color: {
                                if (artistsListView.currentIndex === index) {
                                    return Qt.rgba(0.25, 0.32, 0.71, 0.38)  // Selected color with transparency
                                } else if (root.highlightedArtist === artistData.name) {
                                    return Qt.rgba(0.16, 0.16, 0.31, 0.25)  // Highlighted color with transparency
                                } else {
                                    return Qt.rgba(1, 1, 1, 0.03)  // Subtle background
                                }
                            }
                            radius: 6
                            
                            // 3D border effect
                            border.width: 1
                            border.color: {
                                if (artistsListView.currentIndex === index) {
                                    return Qt.rgba(0.37, 0.44, 0.84, 0.5)  // Brighter for selected
                                } else {
                                    return Qt.rgba(1, 1, 1, 0.06)  // Subtle top highlight
                                }
                            }
                            
                            // Bottom shadow for 3D depth
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: artistsListView.currentIndex === index ? Qt.rgba(0.1, 0.1, 0.29, 0.5) : Qt.rgba(0, 0, 0, 0.19)
                            }

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
                                    id: chevronLabel
                                    text: "\u203A" // Right-pointing chevron
                                    color: "white"
                                    font.pixelSize: 16
                                    Layout.rightMargin: 4
                                    
                                    transform: Rotation {
                                        origin.x: chevronLabel.width / 2  // Center based on actual width
                                        origin.y: chevronLabel.height / 2  // Center based on actual height
                                        angle: albumsVisible ? 90 : 0  // Rotate 90 degrees when expanded
                                        
                                        Behavior on angle {
                                            NumberAnimation {
                                                duration: 200
                                                easing.type: Easing.InOutQuad
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: artistMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                
                                onClicked: {
                                    // Toggle expansion state in persistent storage
                                    var newExpandedState = !(root.expandedArtists[artistData.name] || false);
                                    var updatedExpanded = Object.assign({}, root.expandedArtists);
                                    if (newExpandedState) {
                                        updatedExpanded[artistData.name] = true;
                                    } else {
                                        delete updatedExpanded[artistData.name];
                                    }
                                    root.expandedArtists = updatedExpanded;
                                    artistsListView.currentIndex = index; // Optional: select on expand
                                }
                            }
                            
                            // Hover effect
                            states: State {
                                when: artistMouseArea.containsMouse && artistsListView.currentIndex !== index
                                PropertyChanges {
                                    target: artistItemRect
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.09)
                                }
                            }
                            
                            transitions: Transition {
                                ColorAnimation { duration: 150 }
                            }
                        }

                        // Albums GridView - visible based on albumsVisible
                        Rectangle {
                            id: artistAlbumsContainer
                            width: parent.width - 8
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            // Dynamic height based on content
                            height: albumsVisible ? (albumsGrid.contentHeight + (albumsGrid.count > 0 ? 16 : 0)) : 0 // Add padding if albums exist
                            color: Qt.rgba(1, 1, 1, 0.04) // Very subtle frosted background
                            radius: 6
                            visible: albumsVisible
                            clip: true
                            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } } // Smooth expand/collapse
                            
                            // Subtle inset shadow
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.13)

                            GridView {
                                id: albumsGrid
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                cellWidth: 120 + 10 // Thumbnail size + padding
                                cellHeight: 140 + 10 // Thumbnail + title + padding
                                interactive: false // Parent ListView handles scrolling primarily

                                model: albumsVisible ? LibraryManager.getAlbumsForArtist(artistData.name) : []

                                delegate: Item { 
                                    width: albumsGrid.cellWidth - 10
                                    height: albumsGrid.cellHeight - 10

                                    Item { 
                                        anchors.fill: parent

                                        Rectangle { // Album Art container
                                            id: albumArtContainer
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 110
                                            height: 110
                                            color: "transparent"
                                            radius: 3

                                            Image {
                                                id: albumImage
                                                anchors.fill: parent
                                                source: modelData.hasArt ? "image://albumart/" + modelData.id + "/thumbnail" : ""
                                                fillMode: Image.PreserveAspectFit
                                                clip: false
                                                asynchronous: true
                                                
                                                // Custom positioning based on aspect ratio
                                                onStatusChanged: {
                                                    if (status === Image.Ready && sourceSize.width > 0 && sourceSize.height > 0) {
                                                        var aspectRatio = sourceSize.width / sourceSize.height;
                                                        if (aspectRatio > 1.0) {
                                                            // Wider than square - align to bottom
                                                            anchors.fill = undefined;
                                                            anchors.bottom = parent.bottom;
                                                            anchors.left = parent.left;
                                                            anchors.right = parent.right;
                                                            height = parent.width / aspectRatio;
                                                        } else if (aspectRatio < 1.0) {
                                                            // Taller than square - center horizontally
                                                            anchors.fill = undefined;
                                                            anchors.verticalCenter = parent.verticalCenter;
                                                            anchors.horizontalCenter = parent.horizontalCenter;
                                                            width = parent.height * aspectRatio;
                                                            height = parent.height;
                                                        } else {
                                                            // Square - fill parent
                                                            anchors.fill = parent;
                                                        }
                                                    }
                                                }
                                                
                                                // Placeholder when no art available
                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: "#444444"
                                                    visible: parent.status !== Image.Ready
                                                    radius: 3
                                                    
                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: "♪"
                                                        font.pixelSize: 32
                                                        color: "#666666"
                                                    }
                                                }
                                            }
                                        }

                                        Text { // Album Title
                                            anchors.top: albumArtContainer.bottom
                                            anchors.topMargin: 4
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: 30  // Fixed height for 2 lines max
                                            text: modelData.title
                                            color: "white"
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            verticalAlignment: Text.AlignTop
                                            clip: true
                                        }
                                    }
                                    MouseArea { 
                                        anchors.fill: parent
                                        onClicked: {
                                            root.selectedAlbum = modelData; // Update the root's selectedAlbum property
                                            albumBrowser.jumpToAlbum(modelData); // Jump to album in carousel
                                        }
                                        onDoubleClicked: {
                                            // Play the album on double-click
                                            MediaPlayer.playAlbumByName(modelData.albumArtist, modelData.title, 0);
                                        }
                                    }
                                }
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }
                    }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                    }
                    
                    // Custom scrollbar positioned to the right
                    ScrollBar {
                        id: artistScrollBar
                        width: 8
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 2
                        anchors.bottomMargin: 2
                        policy: ScrollBar.AlwaysOn
                        visible: artistsListView.contentHeight > artistsListView.height
                        position: artistsListView.contentY / artistsListView.contentHeight
                        size: artistsListView.height / artistsListView.contentHeight
                        
                        onPositionChanged: {
                            if (pressed) {
                                artistsListView.contentY = position * artistsListView.contentHeight
                            }
                        }
                        
                        contentItem: Rectangle {
                            implicitWidth: 8
                            radius: 4
                            color: artistScrollBar.pressed ? Qt.rgba(1, 1, 1, 0.25) : artistScrollBar.hovered ? Qt.rgba(1, 1, 1, 0.19) : Qt.rgba(1, 1, 1, 0.13)
                            border.width: 1
                            border.color: artistScrollBar.pressed ? Qt.rgba(1, 1, 1, 0.38) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                            
                            Behavior on border.color {
                                ColorAnimation { duration: 150 }
                            }
                        }
                        
                        background: Rectangle {
                            implicitWidth: 8
                            color: Qt.rgba(0, 0, 0, 0.19)
                            radius: 4
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.03)
                        }
                    }
                }
            }

            // Right Pane: Track List
            Rectangle {
                id: rightPane
                SplitView.minimumWidth: 160  // Reduced from 250 to fit better in smaller windows
                SplitView.fillWidth: true
                color: Qt.rgba(0.1, 0.1, 0.1, 0.25)  // Semi-transparent dark with smoky tint
                radius: 8
                clip: true
                
                // 3D border effect - lit from above
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                
                // Inner shadow for depth
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                }

                property var currentAlbumTracks: []
                property string albumTitleText: "No album selected"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.margins: 4
                        height: 40
                        color: Qt.rgba(1, 1, 1, 0.07)
                        radius: 6
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        
                        // Bottom shadow
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.rgba(0, 0, 0, 0.25)
                        }
                        
                        Label {
                            id: trackListHeader
                            anchors.fill: parent
                            text: rightPane.albumTitleText
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                            padding: 8
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
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
                        
                        // Increase scroll speed to match artist list
                        flickDeceleration: 8000
                        maximumFlickVelocity: 2750
                        
                        // Smooth scrolling with bounds
                        boundsMovement: Flickable.StopAtBounds
                        boundsBehavior: Flickable.StopAtBounds
                        
                        // Increase wheel scroll speed while keeping smooth animation
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function(event) {
                                var pixelDelta = event.pixelDelta.y || event.angleDelta.y / 4;
                                trackListView.flick(0, pixelDelta * 400);
                            }
                        }

                        delegate: Rectangle {
                            id: trackDelegate
                            width: ListView.view.width - 8
                            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                            height: 45
                            color: trackListView.currentIndex === index ? Qt.rgba(0.25, 0.32, 0.71, 0.25) : Qt.rgba(1, 1, 1, 0.02)
                            radius: 4
                            
                            // 3D effect
                            border.width: 1
                            border.color: trackListView.currentIndex === index ? Qt.rgba(0.37, 0.44, 0.84, 0.38) : "transparent"
                            
                            // Bottom shadow for selected items
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: trackListView.currentIndex === index ? Qt.rgba(0.1, 0.1, 0.29, 0.38) : "transparent"
                                visible: trackListView.currentIndex === index
                            }

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
                                id: trackMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                
                                onClicked: {
                                    trackListView.currentIndex = index;
                                }
                                onDoubleClicked: {
                                    // If we have a selected album, play the album starting from this track
                                    if (root.selectedAlbum) {
                                        MediaPlayer.playAlbumByName(root.selectedAlbum.albumArtist, root.selectedAlbum.title, index);
                                    } else {
                                        // Otherwise create a single-track playlist
                                        // We'll need to add a method to play a single track from variant data
                                        MediaPlayer.playTrackFromData(modelData);
                                    }
                                }
                            }
                            
                            // Hover effect
                            states: State {
                                when: trackMouseArea.containsMouse && trackListView.currentIndex !== index
                                PropertyChanges {
                                    target: trackDelegate
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.color: Qt.rgba(1, 1, 1, 0.06)
                                }
                            }
                            
                            transitions: Transition {
                                ColorAnimation { duration: 150 }
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