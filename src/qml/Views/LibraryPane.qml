import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Mtoc.Backend 1.0
import "../Components"
import "."

Item {
    id: root
    width: parent.width
    height: parent.height
    focus: true  // Enable keyboard focus for the whole pane
    
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
    
    // Search state
    property string currentSearchTerm: ""
    property var searchResults: ({})
    property bool isSearching: false
    property string previousExpandedState: ""  // Store expanded state before search
    
    // Navigation state for keyboard controls
    property string navigationMode: "none"  // "none", "artist", "album", "track"
    property int selectedArtistIndex: -1
    property int selectedAlbumIndex: -1
    property int selectedTrackIndex: -1
    property string selectedArtistName: ""
    property var selectedAlbumData: null
    
    // Keyboard navigation handler
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
            handleNavigationDown()
            event.accepted = true
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
            handleNavigationUp()
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            handleNavigationActivate()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            resetNavigation()
            event.accepted = true
        }
    }
    
    Component.onCompleted: {
        // Set initial thumbnail from MediaPlayer if available
        if (MediaPlayer.currentTrack && MediaPlayer.currentTrack.album && MediaPlayer.currentTrack.albumArtist) {
            var encodedArtist = encodeURIComponent(MediaPlayer.currentTrack.albumArtist)
            var encodedAlbum = encodeURIComponent(MediaPlayer.currentTrack.album)
            thumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail"
        }
    }

    onSelectedAlbumChanged: {
        try {
            // Validate selectedAlbum is a valid object with required string properties
            if (selectedAlbum && 
                typeof selectedAlbum === "object" &&
                selectedAlbum.albumArtist && 
                selectedAlbum.title &&
                typeof selectedAlbum.albumArtist === "string" &&
                typeof selectedAlbum.title === "string" &&
                selectedAlbum.albumArtist.length > 0 &&
                selectedAlbum.title.length > 0) {
                
                // Use albumArtist instead of artist
                var tracks;
                try {
                    tracks = LibraryManager.getTracksForAlbumAsVariantList(selectedAlbum.albumArtist, selectedAlbum.title);
                } catch (tracksError) {
                    console.warn("Error getting tracks for album:", tracksError);
                    tracks = [];
                }
                
                if (rightPane) {
                    rightPane.currentAlbumTracks = tracks || [];
                    rightPane.albumTitleText = selectedAlbum.albumArtist + " - " + selectedAlbum.title;
                }
                
                // Update the thumbnail URL for the background when an album is selected
                // Only update if not currently playing or if this is the playing album
                if (selectedAlbum.hasArt === true && (!MediaPlayer.currentTrack || 
                    (MediaPlayer.currentTrack && MediaPlayer.currentTrack.albumArtist === selectedAlbum.albumArtist && 
                     MediaPlayer.currentTrack.album === selectedAlbum.title))) {
                    try {
                        // Use encoded format for consistency
                        var encodedArtist = encodeURIComponent(selectedAlbum.albumArtist);
                        var encodedAlbum = encodeURIComponent(selectedAlbum.title);
                        var newThumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail";
                        
                        // Only update if the URL actually changed to avoid unnecessary reloads
                        if (thumbnailUrl !== newThumbnailUrl) {
                            // Use Qt.callLater to defer the URL change to avoid concurrent access issues
                            Qt.callLater(function() {
                                thumbnailUrl = newThumbnailUrl;
                            });
                        }
                    } catch (encodeError) {
                        console.warn("Error encoding album art URL:", encodeError);
                    }
                }
            } else {
                console.warn("Invalid selectedAlbum:", JSON.stringify(selectedAlbum));
                if (rightPane) {
                    rightPane.currentAlbumTracks = [];
                    rightPane.albumTitleText = "No album selected";
                }
                // Don't clear thumbnailUrl here - let MediaPlayer control it when playing
            }
        } catch (error) {
            console.warn("Error in onSelectedAlbumChanged:", error);
            if (rightPane) {
                rightPane.currentAlbumTracks = [];
                rightPane.albumTitleText = "Error loading album";
            }
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
    
    // Library editor window instance
    property var libraryEditorWindow: null
    
    // Component definition for the library editor window
    Component {
        id: libraryEditorWindowComponent
        LibraryEditorWindow {}
    }
    
    // Blurred background
    BlurredBackground {
        id: blurredBg
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 60  // Reduced from 80 for better performance
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
    
    // Subtle right edge line for cohesive background blending
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Qt.rgba(1, 1, 1, 0.1)  // Transparent white that takes on background color
        opacity: 0.6
        z: 10  // Ensure it's above other content
        
        // Gradient for fade effect at top and bottom
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.05; color: Qt.rgba(1, 1, 1, 0.1) }
            GradientStop { position: 0.95; color: Qt.rgba(1, 1, 1, 0.1) }
            GradientStop { position: 1.0; color: "transparent" }
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
                    implicitHeight: 40
                    implicitWidth: 120  // Proportional width for good spacing
                    
                    background: Rectangle {
                        id: buttonRect
                        color: Qt.rgba(1, 1, 1, 0.03)  // Subtle background like artist items
                        radius: 6
                        
                        // 3D border effect like artist items
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)  // Subtle top highlight
                        
                        // Bottom shadow for 3D depth
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.rgba(0, 0, 0, 0.19)
                        }
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 14
                    }
                    
                    // Add mouse area for hover effects
                    MouseArea {
                        id: buttonMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        
                        onClicked: parent.clicked()
                    }
                    
                    // Hover effect matching artist items
                    states: State {
                        when: buttonMouseArea.containsMouse
                        PropertyChanges {
                            target: buttonRect
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: Qt.rgba(1, 1, 1, 0.09)
                        }
                    }
                    
                    transitions: Transition {
                        ColorAnimation { duration: 150 }
                    }
                    onClicked: {
                        // Create floating window if it doesn't exist or was closed
                        if (!libraryEditorWindow || !libraryEditorWindow.visible) {
                            libraryEditorWindow = libraryEditorWindowComponent.createObject(null);
                            libraryEditorWindow.show();
                        } else {
                            // Bring existing window to front
                            libraryEditorWindow.raise();
                            libraryEditorWindow.requestActivate();
                        }
                    }
                }
            }
        }
        
        // Horizontal Album Browser with width constraint
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 360  // Height for albums with reflections
            
            HorizontalAlbumBrowser {
                id: albumBrowser
                anchors.centerIn: parent
                width: Math.min(parent.width, 832)  // Max width: 45% of 1920px minus 32px margins
                height: parent.height
                
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
        }
        
        // Main content area: Two-column layout
        SplitView {
            id: splitView
            Layout.fillWidth: true
            Layout.fillHeight: true // This will take the remaining space
            orientation: Qt.Horizontal
            handle: Item {
                implicitWidth: 8
                implicitHeight: 8
                
                // Subtle divider line
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.1)  // Very subtle white line
                    
                    // Gradient for fade effect at top and bottom
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.1; color: Qt.rgba(1, 1, 1, 0.1) }
                        GradientStop { position: 0.9; color: Qt.rgba(1, 1, 1, 0.1) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                
                // Interactive hover area (invisible)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SplitHCursor
                    hoverEnabled: true
                }
            }

            // Left Pane: Artist List
            Rectangle {
                id: leftPaneContainer
                SplitView.preferredWidth: 450  // Width to fit 3 album covers
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

                // Container for SearchBar, ListView and ScrollBar
                Item {
                    anchors.fill: parent
                    anchors.margins: 4
                    
                    // Search bar at the top
                    SearchBar {
                        id: searchBar
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        placeholderText: "Search library..."
                        z: 1
                        
                        onSearchRequested: function(searchTerm) {
                            root.performSearch(searchTerm)
                        }
                        
                        onClearRequested: {
                            root.clearSearch()
                        }
                        
                        onFocusRequested: {
                            // Scroll to top when search is focused and reset navigation
                            artistsListView.positionViewAtBeginning()
                            resetNavigation()
                        }
                        
                        // Handle Tab key to transfer focus to library navigation
                        Keys.onTabPressed: {
                            if (currentSearchTerm.length > 0 && searchResults.bestMatch) {
                                // Start navigation from search result
                                setupNavigationFromSearch()
                            } else {
                                // Start navigation from beginning
                                startArtistNavigation()
                            }
                            root.forceActiveFocus()
                        }
                    }
                    
                    ListView {
                        id: artistsListView
                        anchors.top: searchBar.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true
                        model: LibraryManager.artistModel
                        spacing: 2
                        
                        // Enable delegate recycling to prevent memory leaks
                        reuseItems: true  // Enable recycling for better performance
                        cacheBuffer: 600  // Increase cache for smoother scrolling
                        
                        // Disable layer effect for better performance
                        // Content clipping is handled by parent container's clip property
                    
                    // Increase scroll speed
                    flickDeceleration: 8000  // Default is 1500, can increase for faster stopping
                    maximumFlickVelocity: 2750  // Default is 2500, increase for faster scrolling
                    
                    // Smooth scrolling with bounds
                    boundsMovement: Flickable.StopAtBounds
                    boundsBehavior: Flickable.StopAtBounds
                    
                    // Store the index and offset of the top visible item for scroll preservation
                    property int savedTopIndex: -1
                    property real savedTopOffset: 0
                    property bool preserveScrollPosition: false
                    
                    // Better scroll position preservation using index-based approach
                    onContentHeightChanged: {
                        if (preserveScrollPosition && savedTopIndex >= 0) {
                            // Use Qt.callLater to avoid immediate position changes that cause snapping
                            Qt.callLater(function() {
                                if (savedTopIndex >= 0 && savedTopIndex < count) {
                                    positionViewAtIndex(savedTopIndex, ListView.Beginning)
                                    contentY = Math.max(0, contentY + savedTopOffset)
                                    preserveScrollPosition = false
                                    savedTopIndex = -1
                                }
                            })
                        }
                    }
                    
                    // Smooth wheel scrolling with moderate speed
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            // Use a more moderate multiplier for better control
                            var pixelDelta = event.pixelDelta.y || event.angleDelta.y / 4;
                            artistsListView.flick(0, pixelDelta * 60); // Reduced from 400 for better control
                        }
                    }

                    delegate: Column {
                        width: ListView.view.width - 12  // Account for scrollbar space
                        spacing: 2  // Match the ListView spacing for consistency
                        // Height will be dynamic based on albumsVisible
                        
                        // Store modelData for easier access in nested views/functions
                        property var artistData: modelData
                        property bool albumsVisible: root.expandedArtists[artistData.name] === true
                        
                        // Listen for changes to the expanded artists
                        Connections {
                            target: root
                            function onExpandedArtistsChanged() {
                                // Force re-evaluation by updating the binding
                                albumsVisible = Qt.binding(function() { 
                                    return root.expandedArtists[artistData.name] === true 
                                })
                            }
                        } 

                        Rectangle {
                            id: artistItemRect
                            width: parent.width
                            x: 0
                            height: 40
                            color: {
                                if (artistsListView.currentIndex === index) {
                                    return Qt.rgba(0.25, 0.32, 0.71, 0.38)  // Selected color with transparency
                                } else if (root.selectedArtistIndex === index && root.navigationMode === "artist") {
                                    return Qt.rgba(0.35, 0.42, 0.81, 0.3)  // Keyboard navigation focus
                                } else if (root.highlightedArtist === artistData.name) {
                                    return Qt.rgba(0.16, 0.16, 0.31, 0.25)  // Highlighted color with transparency
                                } else {
                                    return Qt.rgba(1, 1, 1, 0.03)  // Subtle background
                                }
                            }
                            radius: 6
                            
                            // 3D border effect with all-round shading
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.06)  // Subtle top/left highlight
                            
                            // Left highlight for 3D depth
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                width: 1
                                color: Qt.rgba(1, 1, 1, 0.05)
                            }
                            
                            // Bottom shadow for 3D depth
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                height: 1
                                color: Qt.rgba(0, 0, 0, 0.19)
                            }
                            
                            // Right shadow for 3D depth
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                                width: 1
                                color: Qt.rgba(0, 0, 0, 0.15)
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
                                    // Save current top visible item before expanding/collapsing
                                    var topItem = artistsListView.itemAt(0, artistsListView.contentY);
                                    if (topItem) {
                                        artistsListView.savedTopIndex = artistsListView.indexAt(0, artistsListView.contentY);
                                        artistsListView.savedTopOffset = artistsListView.contentY - topItem.y;
                                        artistsListView.preserveScrollPosition = true;
                                    }
                                    
                                    // Toggle expansion state more efficiently
                                    var newExpandedState = !(root.expandedArtists[artistData.name] || false);
                                    
                                    // Only update if state actually changes
                                    if ((newExpandedState && !root.expandedArtists[artistData.name]) ||
                                        (!newExpandedState && root.expandedArtists[artistData.name])) {
                                        var updatedExpanded = Object.assign({}, root.expandedArtists);
                                        if (newExpandedState) {
                                            updatedExpanded[artistData.name] = true;
                                        } else {
                                            delete updatedExpanded[artistData.name];
                                        }
                                        root.expandedArtists = updatedExpanded;
                                    }
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
                            width: artistItemRect.width
                            x: 0
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
                                
                                // Enable delegate recycling for albums too
                                reuseItems: true  // Enable recycling for better performance
                                cacheBuffer: 300  // Reasonable cache for album grid

                                model: albumsVisible && artistData && artistData.name ? 
                                       LibraryManager.getAlbumsForArtist(artistData.name) : []

                                delegate: Item { 
                                    width: albumsGrid.cellWidth - 10
                                    height: albumsGrid.cellHeight - 10

                                    Item { 
                                        anchors.fill: parent
                                        
                                        // Navigation highlight for albums
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            color: "transparent"
                                            border.width: 2
                                            border.color: Qt.rgba(0.35, 0.42, 0.81, 0.7)
                                            radius: 6
                                            visible: root.navigationMode === "album" && 
                                                    root.selectedArtistName === artistData.name && 
                                                    root.selectedAlbumIndex === index
                                        }

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
                                                
                                                // Disable layer effect for better performance
                                                // Rounded corners handled by container clipping
                                                
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
                                            
                                            // Selection indicator - white outline that matches image dimensions
                                            Rectangle {
                                                id: selectionIndicator
                                                color: "transparent"
                                                border.width: 2
                                                border.color: "#ffffff"
                                                radius: 3
                                                visible: root.selectedAlbum && root.selectedAlbum.id === modelData.id
                                                opacity: 0.8
                                                
                                                // Match the image dimensions based on its aspect ratio
                                                Component.onCompleted: updateSelectionBounds()
                                                
                                                Connections {
                                                    target: albumImage
                                                    function onStatusChanged() {
                                                        if (albumImage.status === Image.Ready) {
                                                            selectionIndicator.updateSelectionBounds()
                                                        }
                                                    }
                                                }
                                                
                                                function updateSelectionBounds() {
                                                    if (albumImage.status === Image.Ready && albumImage.sourceSize.width > 0 && albumImage.sourceSize.height > 0) {
                                                        var aspectRatio = albumImage.sourceSize.width / albumImage.sourceSize.height;
                                                        if (aspectRatio > 1.0) {
                                                            // Wider than square - match image positioning
                                                            anchors.fill = undefined;
                                                            anchors.bottom = parent.bottom;
                                                            anchors.left = parent.left;
                                                            anchors.right = parent.right;
                                                            height = parent.width / aspectRatio;
                                                        } else if (aspectRatio < 1.0) {
                                                            // Taller than square - match image positioning
                                                            anchors.fill = undefined;
                                                            anchors.verticalCenter = parent.verticalCenter;
                                                            anchors.horizontalCenter = parent.horizontalCenter;
                                                            width = parent.height * aspectRatio;
                                                            height = parent.height;
                                                        } else {
                                                            // Square - fill parent
                                                            anchors.fill = parent;
                                                        }
                                                    } else {
                                                        // Fallback to fill parent when no image or not ready
                                                        anchors.fill = parent;
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
                    
                    // Add right padding to content to make room for scrollbar
                    rightMargin: 12
                    
                    ScrollBar.vertical: ScrollBar { 
                            id: artistScrollBar
                            policy: ScrollBar.AsNeeded
                            minimumSize: 0.1
                            width: 10  // Slightly wider for easier grabbing
                            snapMode: ScrollBar.NoSnap
                            interactive: true
                            
                            // Increase step size for smoother scrolling
                            stepSize: 0.02
                            
                            background: Rectangle {
                                color: Qt.rgba(0, 0, 0, 0.2)
                                radius: width / 2
                            }
                            
                            contentItem: Rectangle {
                                color: Qt.rgba(1, 1, 1, 0.3)
                                radius: width / 2
                                
                                // Hover effect
                                states: State {
                                    when: parent.parent.hovered || parent.parent.pressed
                                    PropertyChanges {
                                        target: parent
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                    }
                                }
                                
                                transitions: Transition {
                                    ColorAnimation { duration: 150 }
                                }
                            }
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
                        height: 60
                        color: Qt.rgba(1, 1, 1, 0.07)
                        radius: 6
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        
                        // Bottom shadow
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6  // Match parent radius to avoid corner overflow
                            anchors.rightMargin: 6  // Match parent radius to avoid corner overflow
                            height: 1
                            color: Qt.rgba(0, 0, 0, 0.25)
                        }
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            
                            Label {
                                id: trackListHeader
                                Layout.fillWidth: true
                                text: rightPane.albumTitleText
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                
                                Label {
                                    text: root.selectedAlbum && root.selectedAlbum.year ? root.selectedAlbum.year : ""
                                    color: "#b0b0b0"
                                    font.pixelSize: 12
                                    visible: text !== ""
                                }
                                
                                Label {
                                    text: rightPane.currentAlbumTracks.length > 0 ? 
                                          (rightPane.currentAlbumTracks.length === 1 ? "1 track" : rightPane.currentAlbumTracks.length + " tracks") : ""
                                    color: "#b0b0b0"
                                    font.pixelSize: 12
                                    visible: text !== ""
                                }
                                
                                Label {
                                    text: rightPane.currentAlbumTracks.length > 0 ? formatAlbumDuration() : ""
                                    color: "#b0b0b0"
                                    font.pixelSize: 12
                                    visible: text !== ""
                                }
                                
                                Item { Layout.fillWidth: true } // Spacer
                            }
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
                        
                        // Enable delegate recycling for tracks
                        reuseItems: true
                        cacheBuffer: 400  // Limit cache for track list
                        
                        // Track list model updates automatically
                        
                        // Increase scroll speed to match artist list
                        flickDeceleration: 8000
                        maximumFlickVelocity: 2750
                        
                        // Smooth scrolling with bounds
                        boundsMovement: Flickable.StopAtBounds
                        boundsBehavior: Flickable.StopAtBounds
                        
                        // Smooth wheel scrolling with moderate speed
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function(event) {
                                var pixelDelta = event.pixelDelta.y || event.angleDelta.y / 4;
                                trackListView.flick(0, pixelDelta * 60); // Reduced for better control, matching artist list
                            }
                        }

                        delegate: Column {
                            width: ListView.view.width
                            
                            // Helper properties to determine if we should show disc number
                            property bool showDiscNumber: {
                                if (!modelData.discNumber || modelData.discNumber < 1) return false
                                
                                // Check if this is the first track of a new disc
                                if (index === 0) return true
                                
                                // Check if previous track has different disc number
                                var prevTrack = rightPane.currentAlbumTracks[index - 1]
                                return prevTrack && prevTrack.discNumber !== modelData.discNumber
                            }
                            
                            property bool isMultiDisc: {
                                if (!rightPane.currentAlbumTracks || rightPane.currentAlbumTracks.length <= 1) return false
                                
                                var maxDisc = 1
                                for (var i = 0; i < rightPane.currentAlbumTracks.length; i++) {
                                    var track = rightPane.currentAlbumTracks[i]
                                    if (track && track.discNumber && track.discNumber > maxDisc) {
                                        maxDisc = track.discNumber
                                    }
                                }
                                return maxDisc > 1
                            }
                            
                            // Disc number indicator
                            Item {
                                width: parent.width
                                height: 22
                                visible: showDiscNumber && isMultiDisc
                                
                                Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Disc " + (modelData.discNumber || 1)
                                    color: "#cccccc"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                            
                            Rectangle {
                                id: trackDelegate
                                width: parent.width
                                height: 45
                                color: {
                                    if (trackListView.currentIndex === index) {
                                        return Qt.rgba(0.25, 0.32, 0.71, 0.25)  // Selected track
                                    } else if (root.navigationMode === "track" && root.selectedTrackIndex === index) {
                                        return Qt.rgba(0.35, 0.42, 0.81, 0.2)  // Keyboard navigation focus
                                    } else {
                                        return Qt.rgba(1, 1, 1, 0.02)  // Default background
                                    }
                                }
                                radius: 4
                                
                                // 3D border effect with all-round shading
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.04)  // Subtle top/left highlight
                                
                                // Left highlight for 3D depth
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: 4
                                    anchors.bottomMargin: 4
                                    width: 1
                                    color: Qt.rgba(1, 1, 1, 0.03)
                                }
                                
                                // Bottom shadow for 3D depth
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    height: 1
                                    color: Qt.rgba(0, 0, 0, 0.15)
                                }
                                
                                // Right shadow for 3D depth
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: 4
                                    anchors.bottomMargin: 4
                                    width: 1
                                    color: Qt.rgba(0, 0, 0, 0.12)
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

                                    // Now Playing Indicator
                                    Image {
                                        source: "qrc:/resources/icons/speaker.svg"
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        visible: MediaPlayer.currentTrack && 
                                                MediaPlayer.currentTrack.filePath === modelData.filePath &&
                                                MediaPlayer.state === MediaPlayer.PlayingState
                                        opacity: 0.9
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
                                        border.color: Qt.rgba(1, 1, 1, 0.07)
                                    }
                                }
                                
                                transitions: Transition {
                                    ColorAnimation { duration: 150 }
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
    
    function formatAlbumDuration() {
        try {
            if (!rightPane || !rightPane.currentAlbumTracks || rightPane.currentAlbumTracks.length === 0) {
                return "";
            }
            
            var totalSeconds = 0;
            for (var i = 0; i < rightPane.currentAlbumTracks.length; i++) {
                var track = rightPane.currentAlbumTracks[i];
                if (track && 
                    typeof track === "object" &&
                    typeof track.duration !== "undefined" && 
                    typeof track.duration === "number" &&
                    !isNaN(track.duration) && 
                    track.duration > 0) {
                    totalSeconds += track.duration;
                }
            }
            
            if (totalSeconds === 0) return "";
            
            var hours = Math.floor(totalSeconds / 3600);
            var minutes = Math.floor((totalSeconds % 3600) / 60);
            var seconds = Math.floor(totalSeconds % 60);
            
            if (hours > 0) {
                return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
            } else {
                return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
            }
        } catch (error) {
            console.warn("Error in formatAlbumDuration:", error);
            return "";
        }
    }
    
    function performSearch(searchTerm) {
        if (searchTerm.trim().length === 0) {
            clearSearch()
            return
        }
        
        currentSearchTerm = searchTerm
        isSearching = true
        
        // Store current expanded state before search (only if not already searching)
        if (previousExpandedState === "") {
            previousExpandedState = JSON.stringify(expandedArtists)
        }
        
        // Get search results from LibraryManager
        searchResults = LibraryManager.searchAll(searchTerm)
        
        if (searchResults.bestMatch && searchResults.bestMatchType) {
            handleSearchResult(searchResults.bestMatch, searchResults.bestMatchType)
        }
    }
    
    function clearSearch() {
        currentSearchTerm = ""
        isSearching = false
        searchResults = {}
        highlightedArtist = ""
        
        // Restore previous expanded state
        if (previousExpandedState) {
            try {
                expandedArtists = JSON.parse(previousExpandedState)
            } catch (e) {
                expandedArtists = {}
            }
            previousExpandedState = ""
        }
    }
    
    function handleSearchResult(bestMatch, matchType) {
        if (matchType === "artist") {
            // Scroll to and highlight the artist, then expand it
            highlightedArtist = bestMatch.name
            scrollToArtist(bestMatch.name)
            
            // Expand the artist to show albums
            var updatedExpanded = Object.assign({}, expandedArtists)
            updatedExpanded[bestMatch.name] = true
            expandedArtists = updatedExpanded
        } else if (matchType === "album") {
            // Expand the artist to show the album and scroll to it
            var artistName = bestMatch.albumArtist
            if (artistName) {
                highlightedArtist = artistName
                
                // Expand the artist
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[artistName] = true
                expandedArtists = updatedExpanded
                
                // Scroll to the artist
                scrollToArtist(artistName)
                
                // Select the album
                selectedAlbum = bestMatch
            }
        } else if (matchType === "track") {
            // Find the album and artist for this track and expand
            if (bestMatch.album && bestMatch.artist) {
                highlightedArtist = bestMatch.artist
                
                // Expand the artist
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[bestMatch.artist] = true
                expandedArtists = updatedExpanded
                
                // Scroll to the artist
                scrollToArtist(bestMatch.artist)
                
                // Try to find and select the album
                var albums = LibraryManager.getAlbumsForArtist(bestMatch.artist)
                for (var i = 0; i < albums.length; i++) {
                    if (albums[i].title === bestMatch.album) {
                        selectedAlbum = albums[i]
                        break
                    }
                }
            }
        }
    }
    
    function scrollToArtist(artistName) {
        // Find the artist in the list and scroll to it
        var artists = LibraryManager.artistModel
        for (var i = 0; i < artists.length; i++) {
            if (artists[i].name === artistName) {
                artistsListView.positionViewAtIndex(i, ListView.Contain)
                break
            }
        }
    }
    
    // Navigation functions
    function resetNavigation() {
        navigationMode = "none"
        selectedArtistIndex = -1
        selectedAlbumIndex = -1
        selectedTrackIndex = -1
        selectedArtistName = ""
        selectedAlbumData = null
    }
    
    function startArtistNavigation() {
        resetNavigation()
        if (LibraryManager.artistModel.length > 0) {
            navigationMode = "artist"
            selectedArtistIndex = 0
            selectedArtistName = LibraryManager.artistModel[0].name
            artistsListView.positionViewAtIndex(0, ListView.Contain)
        }
    }
    
    function setupNavigationFromSearch() {
        resetNavigation()
        if (searchResults.bestMatch && searchResults.bestMatchType === "artist") {
            navigationMode = "artist"
            var artists = LibraryManager.artistModel
            for (var i = 0; i < artists.length; i++) {
                if (artists[i].name === searchResults.bestMatch.name) {
                    selectedArtistIndex = i
                    selectedArtistName = artists[i].name
                    artistsListView.positionViewAtIndex(i, ListView.Contain)
                    break
                }
            }
        } else if (searchResults.bestMatch && searchResults.bestMatchType === "album") {
            // Start with the album's artist expanded and album selected
            var artistName = searchResults.bestMatch.albumArtist
            var artists = LibraryManager.artistModel
            for (var i = 0; i < artists.length; i++) {
                if (artists[i].name === artistName) {
                    selectedArtistIndex = i
                    selectedArtistName = artistName
                    artistsListView.positionViewAtIndex(i, ListView.Contain)
                    
                    // Ensure artist is expanded
                    var updatedExpanded = Object.assign({}, expandedArtists)
                    updatedExpanded[artistName] = true
                    expandedArtists = updatedExpanded
                    
                    // Switch to album navigation
                    navigationMode = "album"
                    var albums = LibraryManager.getAlbumsForArtist(artistName)
                    for (var j = 0; j < albums.length; j++) {
                        if (albums[j].title === searchResults.bestMatch.title) {
                            selectedAlbumIndex = j
                            selectedAlbumData = albums[j]
                            break
                        }
                    }
                    break
                }
            }
        }
    }
    
    function handleNavigationDown() {
        if (navigationMode === "artist") {
            if (selectedArtistIndex < LibraryManager.artistModel.length - 1) {
                selectedArtistIndex++
                selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
                artistsListView.positionViewAtIndex(selectedArtistIndex, ListView.Contain)
            }
        } else if (navigationMode === "album") {
            var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
            if (selectedAlbumIndex < albums.length - 1) {
                selectedAlbumIndex++
                selectedAlbumData = albums[selectedAlbumIndex]
            }
        } else if (navigationMode === "track") {
            if (selectedTrackIndex < rightPane.currentAlbumTracks.length - 1) {
                selectedTrackIndex++
            }
        }
    }
    
    function handleNavigationUp() {
        if (navigationMode === "artist") {
            if (selectedArtistIndex > 0) {
                selectedArtistIndex--
                selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
                artistsListView.positionViewAtIndex(selectedArtistIndex, ListView.Contain)
            }
        } else if (navigationMode === "album") {
            if (selectedAlbumIndex > 0) {
                selectedAlbumIndex--
                var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
                selectedAlbumData = albums[selectedAlbumIndex]
            }
        } else if (navigationMode === "track") {
            if (selectedTrackIndex > 0) {
                selectedTrackIndex--
            }
        }
    }
    
    function handleNavigationActivate() {
        if (navigationMode === "artist") {
            // Expand the artist to show albums
            var updatedExpanded = Object.assign({}, expandedArtists)
            updatedExpanded[selectedArtistName] = true
            expandedArtists = updatedExpanded
            
            // Switch to album navigation
            var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
            if (albums.length > 0) {
                navigationMode = "album"
                selectedAlbumIndex = 0
                selectedAlbumData = albums[0]
            }
        } else if (navigationMode === "album") {
            // Select the album and switch to track navigation
            selectedAlbum = selectedAlbumData
            
            // Switch to track navigation
            if (rightPane.currentAlbumTracks.length > 0) {
                navigationMode = "track"
                selectedTrackIndex = 0
            }
        } else if (navigationMode === "track") {
            // Play the selected track
            if (selectedAlbumData && selectedTrackIndex >= 0) {
                MediaPlayer.playAlbumByName(selectedAlbumData.albumArtist, selectedAlbumData.title, selectedTrackIndex)
            }
        }
    }
    
    // Functions for Now Playing Panel integration
    function jumpToArtist(artistName) {
        try {
            if (!artistName || typeof artistName !== "string") return
            
            // Clear search state and highlight the artist
            clearSearch()
            highlightedArtist = artistName
            
            // Find and scroll to the artist
            var artists = LibraryManager.artistModel
            if (!artists) return
            
            for (var i = 0; i < artists.length; i++) {
                if (artists[i] && artists[i].name === artistName) {
                    if (artistsListView) {
                        artistsListView.positionViewAtIndex(i, ListView.Contain)
                    }
                    break
                }
            }
            
            // Expand the artist to show albums
            var updatedExpanded = Object.assign({}, expandedArtists)
            updatedExpanded[artistName] = true
            expandedArtists = updatedExpanded
        } catch (error) {
            console.warn("Error in jumpToArtist:", error)
        }
    }
    
    function jumpToAlbum(artistName, albumTitle) {
        try {
            if (!artistName || !albumTitle || typeof artistName !== "string" || typeof albumTitle !== "string") return
            
            // First jump to the artist
            jumpToArtist(artistName)
            
            // Find and select the album
            var albums = LibraryManager.getAlbumsForArtist(artistName)
            if (!albums) return
            
            for (var i = 0; i < albums.length; i++) {
                if (albums[i] && albums[i].title === albumTitle) {
                    selectedAlbum = albums[i]
                    // Also jump to it in the album browser
                    if (albumBrowser && typeof albumBrowser.jumpToAlbum === "function") {
                        albumBrowser.jumpToAlbum(albums[i])
                    }
                    break
                }
            }
        } catch (error) {
            console.warn("Error in jumpToAlbum:", error)
        }
    }
}