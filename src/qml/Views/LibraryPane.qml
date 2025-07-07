import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1
import QtQuick.Effects
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
    property var expandedArtistsCache: ({})  // Cache for quick lookups without triggering bindings
    property string highlightedArtist: ""  // Track which artist to highlight
    property url thumbnailUrl: ""
    property url pendingThumbnailUrl: ""  // Buffer for thumbnail URL changes
    property var artistNameToIndex: ({})  // Cache for artist name to index mapping
    property var artistAlbumCache: ({})  // Cache for artist's albums: { "artistName": { "albumTitle": albumObject } }
    property var collapsedArtistCleanupTimers: ({})  // Timers for cleaning up collapsed artist data
    property int cleanupDelayMs: 30000  // Clean up artist data 30 seconds after collapse
    property var expandCollapseDebounceTimer: null  // Debounce timer for expansion/collapse
    property string pendingExpandCollapseArtist: ""  // Artist pending expansion/collapse
    property bool pendingExpandCollapseState: false  // State to apply after debounce
    
    // Search state
    property string currentSearchTerm: ""
    property var searchResults: ({})
    property bool isSearching: false
    property string previousExpandedState: ""  // Store expanded state before search
    property var searchResultsCache: ({})  // Cache for search results
    property int cacheExpiryTime: 60000  // Cache expires after 1 minute
    
    // TODO: fix keybaord navigation
    // Navigation state for keyboard controls
    property string navigationMode: "none"  // "none", "artist", "album", "track"
    property int selectedArtistIndex: -1
    property int selectedAlbumIndex: -1
    property int selectedTrackIndex: -1
    property string selectedArtistName: ""
    property var selectedAlbumData: null
    
    // Memory cleanup timer
    Timer {
        id: memoryCleanupTimer
        interval: 60000  // Run cleanup check every minute
        running: true
        repeat: true
        onTriggered: {
            cleanupUnusedMemory()
        }
    }
    
    // Function to schedule cleanup for a collapsed artist
    function scheduleArtistCleanup(artistName) {
        if (!artistName) return
        
        // Clear any existing timer for this artist
        if (collapsedArtistCleanupTimers[artistName]) {
            collapsedArtistCleanupTimers[artistName].stop()
            collapsedArtistCleanupTimers[artistName].destroy()
        }
        
        // Create a new timer for cleanup
        var cleanupTimer = Qt.createQmlObject(
            'import QtQuick 2.15; Timer { interval: ' + cleanupDelayMs + '; running: true; repeat: false }',
            root
        )
        
        cleanupTimer.triggered.connect(function() {
            // Clean up this artist's data if still collapsed
            if (!expandedArtists[artistName] && !expandedArtistsCache[artistName]) {
                delete artistAlbumCache[artistName]
                delete expandedArtistsCache[artistName]
            }
            // Clean up the timer itself
            delete collapsedArtistCleanupTimers[artistName]
            cleanupTimer.destroy()
        })
        
        collapsedArtistCleanupTimers[artistName] = cleanupTimer
    }
    
    // Function to cancel cleanup for an artist (when expanded)
    function cancelArtistCleanup(artistName) {
        if (!artistName) return
        
        if (collapsedArtistCleanupTimers[artistName]) {
            collapsedArtistCleanupTimers[artistName].stop()
            collapsedArtistCleanupTimers[artistName].destroy()
            delete collapsedArtistCleanupTimers[artistName]
        }
    }
    
    // Function to clean up unused memory
    function cleanupUnusedMemory() {
        // Clean up artist album cache for artists that are no longer expanded
        var artistsToClean = []
        for (var artist in artistAlbumCache) {
            if (!expandedArtists[artist] && !expandedArtistsCache[artist]) {
                artistsToClean.push(artist)
            }
        }
        
        artistsToClean.forEach(function(artist) {
            delete artistAlbumCache[artist]
        })
        
        // Clean up search results cache based on expiry time
        var currentTime = Date.now()
        for (var searchTerm in searchResultsCache) {
            if (currentTime - searchResultsCache[searchTerm].timestamp > cacheExpiryTime) {
                delete searchResultsCache[searchTerm]
            }
        }
    }
    
    // Keyboard navigation handler
    Keys.onPressed: function(event) {
        // Only handle navigation keys if we're in navigation mode
        if (navigationMode !== "none") {
            if (event.key === Qt.Key_Down) {
                handleNavigationDown()
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                handleNavigationUp()
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                handleNavigationActivate()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                // Return focus to search bar on Escape
                resetNavigation()
                searchBar.forceActiveFocus()
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                handleNavigationLeft()
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                handleNavigationRight()
                event.accepted = true
            }
        } else {
            // When not in navigation mode, allow quick search access
            if (event.key === Qt.Key_Slash || event.key === Qt.Key_F && event.modifiers & Qt.ControlModifier) {
                searchBar.forceActiveFocus()
                event.accepted = true
            }
        }
        // Allow Tab/Shift+Tab to work normally for focus traversal
    }
    
    Component.onCompleted: {
        // Set initial thumbnail from MediaPlayer if available
        if (MediaPlayer.currentTrack && MediaPlayer.currentTrack.album && MediaPlayer.currentTrack.albumArtist) {
            var encodedArtist = encodeURIComponent(MediaPlayer.currentTrack.albumArtist)
            var encodedAlbum = encodeURIComponent(MediaPlayer.currentTrack.album)
            thumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail"
        }
        // Build initial artist index mapping
        updateArtistIndexMapping()
    }
    
    Component.onDestruction: {
        // Clean up all timers
        if (expandCollapseDebounceTimer) {
            expandCollapseDebounceTimer.stop()
            expandCollapseDebounceTimer.destroy()
        }
        
        // Clean up all artist cleanup timers
        for (var artist in collapsedArtistCleanupTimers) {
            if (collapsedArtistCleanupTimers[artist]) {
                collapsedArtistCleanupTimers[artist].stop()
                collapsedArtistCleanupTimers[artist].destroy()
            }
        }
    }
    
    // Update artist mapping when library changes
    Connections {
        target: LibraryManager
        function onLibraryChanged() {
            updateArtistIndexMapping()
            // Clear caches when library changes
            searchResultsCache = {}
            albumDurationCache = {}
            artistAlbumCache = {}
        }
    }
    
    // Function to build artist name to index mapping for O(1) lookups
    function updateArtistIndexMapping() {
        var mapping = {}
        var artists = LibraryManager.artistModel
        for (var i = 0; i < artists.length; i++) {
            mapping[artists[i].name] = i
        }
        artistNameToIndex = mapping
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
                if (selectedAlbum.hasArt === true) {
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
        backgroundOpacity: 0.8
        z: -2  // Put this behind the dark overlay
    }
    
    // Dark overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.65  // Increased to compensate for reduced blur
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
        anchors.margins: 8
        spacing: 8
        
        // Header section - minimal design
        Item {
            Layout.fillWidth: true
            height: 24  // Reduced height
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                
                Label {
                    text: "Music Library"
                    font.pixelSize: 18  // Slightly smaller
                    font.bold: true
                    color: "white"
                }
                
                Item { Layout.fillWidth: true } // Spacer
                
                Button {
                    text: "Edit Library"
                    implicitHeight: 28  // Reduced button height
                    implicitWidth: 100  // Smaller width
                    
                    background: Rectangle {
                        id: buttonRect
                        color: Qt.rgba(1, 1, 1, 0.03)  // Subtle background like artist items
                        radius: 4  // Smaller radius
                        
                        //light border
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)  // Subtle top highlight

                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12  // Smaller font
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
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 360  // Height for albums with reflections
            color: Qt.rgba(0, 0, 0, 0.5)  // Semi-transparent dark to match other panes
            radius: 8
            clip: true  // Clip content to rounded corners
            
            //border
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
            
            HorizontalAlbumBrowser {
                id: albumBrowser
                anchors.centerIn: parent
                width: Math.min(parent.width - 16, 1600)  // Max width with margins
                height: parent.height - 16  // Account for margins
                
                onAlbumClicked: function(album) {
                    root.selectedAlbum = album
                    
                    // Highlight the album's artist
                    root.highlightedArtist = album.albumArtist
                }
            }
            
            // Gradient overlay to fade the bottom to black
            Item {
                anchors.fill: parent
                anchors.margins: 2  // Keep gradient inside borders
                z: 10  // Above album browser but below any text
                clip: true
                
                Rectangle {
                    anchors.fill: parent
                    radius: parent.parent.radius - 2  // Match parent radius with margin adjustment
                    
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.6; color: "transparent" }
                        GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.5) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1.0) }
                    }
                }
            }
            
            // Artist/album text overlaid on the reflections
            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 50
                z: 20  // Higher z-order than gradient overlay
                
                Label {
                    anchors.centerIn: parent
                    anchors.bottomMargin: 12
                    text: albumBrowser.selectedAlbum && albumBrowser.selectedAlbum.albumArtist && albumBrowser.selectedAlbum.title ? 
                          albumBrowser.selectedAlbum.albumArtist + " - " + albumBrowser.selectedAlbum.title : ""
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    
                    // Simple text shadow using duplicate text instead of DropShadow
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        anchors.verticalCenterOffset: 1
                        text: parent.text
                        color: "#80000000"
                        font: parent.font
                        elide: parent.elide
                        horizontalAlignment: parent.horizontalAlignment
                        z: -1
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
                SplitView.preferredWidth: parent.width * 0.51  // 51% of parent width
                SplitView.minimumWidth: 280  // Minimum for 2 album covers
                SplitView.maximumWidth: 600  // Maximum width to prevent it from getting too wide
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
                        
                        onEnterPressed: {
                            // Move focus to library content on Enter key
                            if (currentSearchTerm.length > 0 && searchResults.bestMatch) {
                                // Start navigation from search result
                                setupNavigationFromSearch()
                            } else if (LibraryManager.artistModel.length > 0) {
                                // Start navigation from beginning if no search
                                startArtistNavigation()
                            }
                            root.forceActiveFocus()
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
                    
                    // Increase scroll speed
                    flickDeceleration: 8000  // Default is 1500, can increase for faster stopping
                    maximumFlickVelocity: 2750  // Default is 2500, increase for faster scrolling
                    
                    // Smooth scrolling with bounds
                    boundsMovement: Flickable.StopAtBounds
                    boundsBehavior: Flickable.StopAtBounds
                    
                    
                    // Smooth wheel scrolling with moderate speed
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(event) {
                            var pixelDelta = 0;
                            
                            // Different handling for touchpad vs mouse wheel
                            if (event.pixelDelta.y !== 0) {
                                // Touchpad - use pixelDelta with higher multiplier for faster scrolling
                                pixelDelta = event.pixelDelta.y * 300; // Much higher sensitivity for touchpad
                            } else {
                                // Mouse wheel - use angleDelta with current multiplier
                                pixelDelta = (event.angleDelta.y / 4) * 60; // Keep current behavior for mouse wheel
                            }
                            
                            artistsListView.flick(0, pixelDelta);
                        }
                    }

                    delegate: Column {
                        width: ListView.view.width - 12  // Account for scrollbar space
                        spacing: 2  // Match the ListView spacing for consistency
                        // Height will be dynamic based on albumsVisible
                        
                        // Store modelData for easier access in nested views/functions
                        property var artistData: modelData
                        property bool albumsVisible: false
                        property bool isHighlighted: root.highlightedArtist === artistData.name
                        property bool isKeyboardFocused: root.selectedArtistIndex === index && root.navigationMode === "artist"
                        
                        // Update albumsVisible binding whenever artist data changes or component completes
                        function updateAlbumsVisibility() {
                            if (artistData && artistData.name) {
                                albumsVisible = root.expandedArtistsCache[artistData.name] === true || root.expandedArtists[artistData.name] === true
                            } else {
                                albumsVisible = false
                            }
                        }
                        
                        // Reset delegate state when recycled by monitoring artistData changes
                        onArtistDataChanged: {
                            updateAlbumsVisibility()
                        }
                        
                        Component.onCompleted: {
                            updateAlbumsVisibility()
                        }
                        
                        // Watch for expandedArtists changes more efficiently
                        property var expandedArtistsWatcher: root.expandedArtists
                        onExpandedArtistsWatcherChanged: {
                            if (artistData && artistData.name) {
                                var isExpanded = root.expandedArtists[artistData.name] === true;
                                root.expandedArtistsCache[artistData.name] = isExpanded;
                                albumsVisible = isExpanded;
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
                                } else if (isKeyboardFocused) {
                                    return Qt.rgba(0.35, 0.42, 0.81, 0.3)  // Keyboard navigation focus
                                } else if (isHighlighted) {
                                    return Qt.rgba(0.16, 0.16, 0.31, 0.25)  // Highlighted color with transparency
                                } else {
                                    return Qt.rgba(1, 1, 1, 0.03)  // Subtle background
                                }
                            }
                            radius: 6
                            
                            // border
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.06)  // subtle border
                            

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
                                    // Debounced expansion/collapse handling
                                    var currentState = root.expandedArtistsCache[artistData.name] || false;
                                    var newExpandedState = !currentState;
                                    
                                    // Update visual state immediately for responsiveness
                                    root.expandedArtistsCache[artistData.name] = newExpandedState;
                                    albumsVisible = newExpandedState;
                                    
                                    // Store pending state
                                    root.pendingExpandCollapseArtist = artistData.name;
                                    root.pendingExpandCollapseState = newExpandedState;
                                    
                                    // Cancel any existing debounce timer
                                    if (root.expandCollapseDebounceTimer) {
                                        root.expandCollapseDebounceTimer.stop();
                                        root.expandCollapseDebounceTimer.destroy();
                                    }
                                    
                                    // Create new debounce timer
                                    root.expandCollapseDebounceTimer = Qt.createQmlObject(
                                        'import QtQuick 2.15; Timer { interval: 150; running: true; repeat: false }',
                                        root
                                    );
                                    
                                    root.expandCollapseDebounceTimer.triggered.connect(function() {
                                        // Apply the debounced state change
                                        var artistName = root.pendingExpandCollapseArtist;
                                        var expandState = root.pendingExpandCollapseState;
                                        
                                        // Schedule cleanup or cancel it based on new state
                                        if (expandState) {
                                            root.cancelArtistCleanup(artistName);
                                        } else {
                                            root.scheduleArtistCleanup(artistName);
                                        }
                                        
                                        // Batch update the property to reduce re-renders
                                        var updatedExpanded = Object.assign({}, root.expandedArtists);
                                        if (expandState) {
                                            updatedExpanded[artistName] = true;
                                        } else {
                                            delete updatedExpanded[artistName];
                                        }
                                        root.expandedArtists = updatedExpanded;
                                        
                                        // Clean up timer
                                        root.expandCollapseDebounceTimer.destroy();
                                        root.expandCollapseDebounceTimer = null;
                                    });
                                    
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
                            
                            // Cache albums data when artist changes or becomes visible
                            property var cachedAlbums: []
                            property string cachedArtistName: ""
                            
                            // Function to refresh album data
                            function refreshAlbumData() {
                                if (visible && artistData && artistData.name) {
                                    if (cachedArtistName !== artistData.name) {
                                        cachedArtistName = artistData.name
                                        cachedAlbums = LibraryManager.getAlbumsForArtist(artistData.name)
                                        // Update the album cache when artist is expanded
                                        root.updateAlbumCacheForArtist(artistData.name)
                                    }
                                } else {
                                    // Clear cache when not visible or no artist data
                                    cachedArtistName = ""
                                    cachedAlbums = []
                                }
                            }
                            
                            onVisibleChanged: {
                                refreshAlbumData()
                            }
                            
                            // Also refresh when parent's artistData changes (delegate recycled)
                            property var artistDataWatcher: parent.artistData
                            onArtistDataWatcherChanged: {
                                refreshAlbumData()
                            }

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

                                model: artistAlbumsContainer.cachedAlbums

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
                                            // Cache the visibility check
                                            property bool shouldShow: root.navigationMode === "album" && 
                                                    root.selectedArtistName === artistData.name && 
                                                    root.selectedAlbumIndex === index
                                            visible: shouldShow
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
                                                sourceSize.width: 220  // Limit to 2x the display size for retina
                                                sourceSize.height: 220
                                                
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
                                                
                                                // Watch album image status directly
                                                property int imageStatus: albumImage.status
                                                onImageStatusChanged: {
                                                    if (imageStatus === Image.Ready) {
                                                        updateSelectionBounds()
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
                            
                            // Default reduced opacity
                            opacity: scrollBarMouseArea.containsMouse || artistScrollBar.hovered || artistScrollBar.pressed ? 1.0 : 0.3
                            
                            // Smooth opacity transition
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.InOutQuad
                                }
                            }
                            
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
                        
                        // Mouse area for proximity detection
                        MouseArea {
                            id: scrollBarMouseArea
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 50  // Wide detection area for proximity
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton  // Just for hover detection
                        }
                    }
                }
            }

            // Right Pane: Track List
            Rectangle {
                id: rightPane
                SplitView.minimumWidth: 250  // Ensure enough space for track information
                SplitView.fillWidth: true
                color: Qt.rgba(0.1, 0.1, 0.1, 0.25)  // Semi-transparent dark with smoky tint
                radius: 8
                clip: true
                
                //border
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                

                property var currentAlbumTracks: []
                property string albumTitleText: "No album selected"

                onCurrentAlbumTracksChanged: {
                    if (trackListView) {
                        trackListView.currentIndex = -1
                    }
                }

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
                        
                        // Cache multi-disc check for all tracks
                        property bool isMultiDiscAlbum: {
                            if (!rightPane.currentAlbumTracks || rightPane.currentAlbumTracks.length <= 1) return false
                            for (var i = 0; i < rightPane.currentAlbumTracks.length; i++) {
                                var track = rightPane.currentAlbumTracks[i]
                                if (track && track.discNumber && track.discNumber > 1) {
                                    return true
                                }
                            }
                            return false
                        }
                        
                        // Track list model updates automatically
                        
                        // Layer effect removed to fix rendering artifact.
                        // Parent container handles corner clipping.
                        
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
                                var pixelDelta = 0;
                                
                                // Different handling for touchpad vs mouse wheel
                                if (event.pixelDelta.y !== 0) {
                                    // Touchpad - use pixelDelta with higher multiplier for faster scrolling
                                    pixelDelta = event.pixelDelta.y * 300; // Much higher sensitivity for touchpad
                                } else {
                                    // Mouse wheel - use angleDelta with current multiplier
                                    pixelDelta = (event.angleDelta.y / 4) * 60; // Keep current behavior for mouse wheel
                                }
                                
                                trackListView.flick(0, pixelDelta);
                            }
                        }

                        delegate: Column {
                            width: ListView.view.width
                            
                            // Helper properties to determine if we should show disc number
                            property int currentDiscNumber: modelData.discNumber || 1
                            property int previousDiscNumber: index > 0 && rightPane.currentAlbumTracks[index - 1] ? 
                                                           (rightPane.currentAlbumTracks[index - 1].discNumber || 1) : 0
                            property bool showDiscNumber: currentDiscNumber > 1 && (index === 0 || currentDiscNumber !== previousDiscNumber)
                            
                            // Cache multi-disc check at the ListView level
                            property bool isMultiDisc: trackListView.isMultiDiscAlbum
                            
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
                                
                                //border
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.04)



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
                                        sourceSize.width: 32  // 2x for retina
                                        sourceSize.height: 32
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
    
    // Cache for album duration calculations
    property var albumDurationCache: ({})
    
    function formatAlbumDuration() {
        try {
            if (!rightPane || !rightPane.currentAlbumTracks || rightPane.currentAlbumTracks.length === 0) {
                return "";
            }
            
            // Create a cache key from album ID
            var cacheKey = root.selectedAlbum ? root.selectedAlbum.id : "empty"
            if (albumDurationCache[cacheKey]) {
                return albumDurationCache[cacheKey]
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
            
            var result;
            if (hours > 0) {
                result = hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
            } else {
                result = minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
            }
            
            // Cache the result
            albumDurationCache[cacheKey] = result
            return result
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
        
        // Check cache first
        var cacheKey = searchTerm.toLowerCase()
        var cachedResult = searchResultsCache[cacheKey]
        if (cachedResult && (Date.now() - cachedResult.timestamp < cacheExpiryTime)) {
            searchResults = cachedResult.results
        } else {
        // Get search results from LibraryManager
        searchResults = LibraryManager.searchAll(searchTerm)
            // Cache the results
            searchResultsCache[cacheKey] = {
                results: searchResults,
                timestamp: Date.now()
            }
        }
        
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
                
                // Expand the artist first
                expandedArtistsCache[artistName] = true
                Qt.callLater(function() {
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[artistName] = true
                expandedArtists = updatedExpanded
                })
                
                // Select the album
                selectedAlbum = bestMatch
                
                // Scroll to the artist after expansion to ensure artist stays at top
                Qt.callLater(function() {
                    scrollToArtist(artistName)
                })
            }
        } else if (matchType === "track") {
            // Find the album and artist for this track and expand
            if (bestMatch.album && bestMatch.artist) {
                highlightedArtist = bestMatch.artist
                
                // Expand the artist
                expandedArtistsCache[bestMatch.artist] = true
                Qt.callLater(function() {
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[bestMatch.artist] = true
                expandedArtists = updatedExpanded
                })
                
                // Try to find and select the album
                var albums = LibraryManager.getAlbumsForArtist(bestMatch.artist)
                for (var i = 0; i < albums.length; i++) {
                    if (albums[i].title === bestMatch.album) {
                        selectedAlbum = albums[i]
                        break
                    }
                }
                
                // Scroll to the artist after expansion and album selection
                Qt.callLater(function() {
                    scrollToArtist(bestMatch.artist)
                })
            }
        }
    }
    
    function scrollToArtist(artistName) {
        // Find the artist in the list and scroll to it
        var artists = LibraryManager.artistModel
        for (var i = 0; i < artists.length; i++) {
            if (artists[i].name === artistName) {
                // Use ListView.Beginning to position the artist at the top of the view
                artistsListView.positionViewAtIndex(i, ListView.Beginning)
                // Add a small offset to ensure the artist is not right at the edge
                Qt.callLater(function() {
                    if (artistsListView.contentY > 0) {
                        artistsListView.contentY = Math.max(0, artistsListView.contentY - 8)
                    }
                })
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
            artistsListView.positionViewAtIndex(0, ListView.Beginning)
            // Add a small offset to ensure the artist is not right at the edge
            Qt.callLater(function() {
                if (artistsListView.contentY > 0) {
                    artistsListView.contentY = Math.max(0, artistsListView.contentY - 8)
                }
            })
        }
    }
    
    function setupNavigationFromSearch() {
        resetNavigation()
        if (searchResults.bestMatch && searchResults.bestMatchType === "artist") {
            navigationMode = "artist"
            // Use O(1) lookup instead of O(n) linear search
            var artistIndex = artistNameToIndex[searchResults.bestMatch.name]
            if (artistIndex !== undefined) {
                selectedArtistIndex = artistIndex
                selectedArtistName = searchResults.bestMatch.name
                // Position at top for better visibility
                artistsListView.positionViewAtIndex(artistIndex, ListView.Beginning)
                // Add a small offset to ensure the artist is not right at the edge
                Qt.callLater(function() {
                    if (artistsListView.contentY > 0) {
                        artistsListView.contentY = Math.max(0, artistsListView.contentY - 8)
                    }
                })
            }
        } else if (searchResults.bestMatch && searchResults.bestMatchType === "album") {
            // Start with the album's artist expanded and album selected
            var artistName = searchResults.bestMatch.albumArtist
            // Use O(1) lookup instead of O(n) linear search
            var artistIndex = artistNameToIndex[artistName]
            if (artistIndex !== undefined) {
                selectedArtistIndex = artistIndex
                selectedArtistName = artistName
                // Position at top for better visibility
                artistsListView.positionViewAtIndex(artistIndex, ListView.Beginning)
                // Add a small offset to ensure the artist is not right at the edge
                Qt.callLater(function() {
                    if (artistsListView.contentY > 0) {
                        artistsListView.contentY = Math.max(0, artistsListView.contentY - 8)
                    }
                })
                
                // Ensure artist is expanded
                expandedArtistsCache[artistName] = true
                Qt.callLater(function() {
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[artistName] = true
                expandedArtists = updatedExpanded
                })
                
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
            // Calculate grid dimensions
            var gridWidth = Math.floor((artistsListView.width - 24) / 130) // Approximate columns based on cell width
            var currentRow = Math.floor(selectedAlbumIndex / gridWidth)
            var currentCol = selectedAlbumIndex % gridWidth
            var totalRows = Math.ceil(albums.length / gridWidth)
            
            // Try to move down a row
            var newIndex = selectedAlbumIndex + gridWidth
            
            if (newIndex < albums.length) {
                // Move down within the same artist's albums
                selectedAlbumIndex = newIndex
                selectedAlbumData = albums[selectedAlbumIndex]
            } else if (currentRow < totalRows - 1) {
                // We're on the last incomplete row, go to last album
                selectedAlbumIndex = albums.length - 1
                selectedAlbumData = albums[selectedAlbumIndex]
            } else {
                // We're at the bottom of this artist's albums, move to next artist
                if (selectedArtistIndex < LibraryManager.artistModel.length - 1) {
                    navigationMode = "artist"
                    selectedArtistIndex++
                    selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
                    selectedAlbumIndex = -1
                    selectedAlbumData = null
                    artistsListView.positionViewAtIndex(selectedArtistIndex, ListView.Contain)
                }
            }
        } else if (navigationMode === "track") {
            if (selectedTrackIndex < rightPane.currentAlbumTracks.length - 1) {
                selectedTrackIndex++
            }
        }
    }
    
    function handleNavigationLeft() {
        if (navigationMode === "album") {
            // Navigate left within album grid
            if (selectedAlbumIndex > 0) {
                selectedAlbumIndex--
                var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
                selectedAlbumData = albums[selectedAlbumIndex]
            } else {
                // At the beginning of albums, go back to artist navigation
                navigationMode = "artist"
                selectedAlbumIndex = -1
                selectedAlbumData = null
            }
        } else if (navigationMode === "track") {
            // From track list, go back to album navigation
            navigationMode = "album"
            selectedTrackIndex = -1
        } else if (navigationMode === "artist") {
            // Already at leftmost navigation level
        }
    }
    
    function handleNavigationRight() {
        if (navigationMode === "artist") {
            // Navigate from artist to albums
            if (expandedArtistsCache[selectedArtistName] || expandedArtists[selectedArtistName]) {
                var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
                if (albums.length > 0) {
                    navigationMode = "album"
                    selectedAlbumIndex = 0
                    selectedAlbumData = albums[0]
                }
            }
        } else if (navigationMode === "album") {
            // Navigate right within album grid
            var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
            if (selectedAlbumIndex < albums.length - 1) {
                selectedAlbumIndex++
                selectedAlbumData = albums[selectedAlbumIndex]
            } else if (selectedAlbumData) {
                // At the end of albums, select the album and go to tracks
                selectedAlbum = selectedAlbumData
                if (rightPane.currentAlbumTracks.length > 0) {
                    navigationMode = "track"
                    selectedTrackIndex = 0
                }
            }
        } else if (navigationMode === "track") {
            // Already at rightmost navigation level
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
            var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
            // Calculate grid dimensions
            var gridWidth = Math.floor((artistsListView.width - 24) / 130) // Approximate columns based on cell width
            var currentRow = Math.floor(selectedAlbumIndex / gridWidth)
            
            // Try to move up a row
            var newIndex = selectedAlbumIndex - gridWidth
            
            if (newIndex >= 0) {
                // Move up within the same artist's albums
                selectedAlbumIndex = newIndex
                selectedAlbumData = albums[selectedAlbumIndex]
            } else if (currentRow > 0) {
                // We're on the first row but not at index 0, go to first album
                selectedAlbumIndex = 0
                selectedAlbumData = albums[selectedAlbumIndex]
            } else {
                // We're at the top of this artist's albums, move to previous artist
                if (selectedArtistIndex > 0) {
                    navigationMode = "artist"
                    selectedArtistIndex--
                    selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
                    selectedAlbumIndex = -1
                    selectedAlbumData = null
                    artistsListView.positionViewAtIndex(selectedArtistIndex, ListView.Contain)
                    
                    // Don't auto-expand - let user explicitly expand with Enter/Right
                }
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
            expandedArtistsCache[selectedArtistName] = true
            Qt.callLater(function() {
            var updatedExpanded = Object.assign({}, expandedArtists)
            updatedExpanded[selectedArtistName] = true
            expandedArtists = updatedExpanded
            })
            
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
                        // Position at top for better visibility
                        artistsListView.positionViewAtIndex(i, ListView.Beginning)
                        // Add a small offset to ensure the artist is not right at the edge
                        Qt.callLater(function() {
                            if (artistsListView.contentY > 0) {
                                artistsListView.contentY = Math.max(0, artistsListView.contentY - 8)
                            }
                        })
                    }
                    break
                }
            }
            
            // Expand the artist to show albums
            expandedArtistsCache[artistName] = true
            Qt.callLater(function() {
            var updatedExpanded = Object.assign({}, expandedArtists)
            updatedExpanded[artistName] = true
            expandedArtists = updatedExpanded
            })
        } catch (error) {
            console.warn("Error in jumpToArtist:", error)
        }
    }
    
    // Helper function to update album cache for an artist
    function updateAlbumCacheForArtist(artistName) {
        if (!artistName || typeof artistName !== "string") return
        
        var albums = LibraryManager.getAlbumsForArtist(artistName)
        if (!albums) return
        
        var albumMap = {}
        for (var i = 0; i < albums.length; i++) {
            if (albums[i] && albums[i].title) {
                albumMap[albums[i].title] = albums[i]
            }
        }
        
        artistAlbumCache[artistName] = albumMap
    }
    
    function jumpToAlbum(artistName, albumTitle) {
        try {
            if (!artistName || !albumTitle || typeof artistName !== "string" || typeof albumTitle !== "string") return
            
            // First jump to the artist
            jumpToArtist(artistName)
            
            // Check if we have cached albums for this artist
            if (!artistAlbumCache[artistName]) {
                updateAlbumCacheForArtist(artistName)
            }
            
            // Use O(1) lookup from cache
            var albumMap = artistAlbumCache[artistName]
            if (albumMap && albumMap[albumTitle]) {
                selectedAlbum = albumMap[albumTitle]
                // Also jump to it in the album browser
                if (albumBrowser && typeof albumBrowser.jumpToAlbum === "function") {
                    albumBrowser.jumpToAlbum(albumMap[albumTitle])
                }
            } else {
                console.warn("Album not found in cache:", artistName, "-", albumTitle)
            }
        } catch (error) {
            console.warn("Error in jumpToAlbum:", error)
        }
    }
}