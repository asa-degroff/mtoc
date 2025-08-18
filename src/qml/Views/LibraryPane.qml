import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform
import QtQuick.Effects
import QtQuick.Window 2.15
import Mtoc.Backend 1.0
import "../Components"
import "."

Item {
    id: root
    width: parent.width
    height: parent.height
    focus: true  // Enable keyboard focus for the whole pane
    
    // Ensure we have a background as a base
    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundColor
        z: -3  // Behind everything else
    }
    
    // Background mouse area to enable keyboard navigation
    MouseArea {
        anchors.fill: parent
        z: -2  // Above background but below content
        onClicked: {
            // Enable keyboard navigation when clicking on empty space
            if (navigationMode === "none" && LibraryManager.artistModel.length > 0) {
                root.forceActiveFocus()
                startArtistNavigation()
            }
        }
    }
    
    property var selectedAlbum: null
    property var expandedArtists: ({})  // Object to store expansion state by artist name
    property string highlightedArtist: ""  // Track which artist to highlight
    property bool isJumping: false  // Flag to prevent concurrent jump operations
    property bool isProgrammaticScrolling: false  // Flag to disable animations during programmatic scrolling
    property real previousContentHeight: 0  // Track contentHeight for layout stabilization
    property int stableFrameCount: 0  // Count consecutive frames with stable height
    property url thumbnailUrl: ""
    property url pendingThumbnailUrl: ""  // Buffer for thumbnail URL changes
    property var artistNameToIndex: ({})  // Cache for artist name to index mapping
    property var artistAlbumCache: ({})  // Cache for artist's albums: { "artistName": { "albumTitle": albumObject } }
    property var artistAlbumIndexCache: ({})  // Cache for album indices: { "artistName": { "albumTitle": index } }
    property var currentTrackIndexMap: ({})  // Map for current album's tracks: { "title|artist": index }
    property var currentTrackFilePathMap: ({})  // Map for current album's tracks by file path: { "filePath": index }
    property var albumIdToIndexMap: ({})  // Map for all albums by ID: { albumId: index }
    property var collapsedArtistCleanupTimers: ({})  // Timers for cleaning up collapsed artist data
    property int cleanupDelayMs: 30000  // Clean up artist data 30 seconds after collapse
    property var expandCollapseDebounceTimer: null  // Debounce timer for expansion/collapse
    property string pendingExpandCollapseArtist: ""  // Artist pending expansion/collapse
    property bool pendingExpandCollapseState: false  // State to apply after debounce
    
    // Tab state
    property int currentTab: 0  // 0 = Artists, 1 = Playlists
    onCurrentTabChanged: {
        SettingsManager.libraryActiveTab = currentTab
    }
    
    // Playlist editing state
    property bool playlistEditMode: false
    property var editedPlaylistTracks: []
    property string editingPlaylistName: ""
    property string playlistNameError: ""
    property string playlistStatusMessage: ""
    
    // Timer to clear status message
    Timer {
        id: statusMessageTimer
        interval: 2000
        running: false
        repeat: false
        onTriggered: {
            root.playlistStatusMessage = ""
        }
    }
    
    // Multi-selection state
    property var selectedTrackIndices: []
    property int lastSelectedIndex: -1
    
    // Search state
    property string currentSearchTerm: ""
    property var searchResults: ({})
    property bool isSearching: false
    property string previousExpandedState: ""  // Store expanded state before search
    property var searchResultsCache: ({})  // Cache for search results
    property int cacheExpiryTime: 60000  // Cache expires after 1 minute
    
    // Queue action dialog
    QueueActionDialog {
        id: queueActionDialog
        
        onReplaceQueue: {
            if (isPlaylist) {
                playPlaylistReplace(playlistName, isVirtualPlaylist, startIndex)
            } else {
                MediaPlayer.playAlbumByName(albumArtist, albumTitle, startIndex)
            }
        }
        
        onPlayNext: {
            if (isPlaylist) {
                playPlaylistNext(playlistName, isVirtualPlaylist)
            } else {
                MediaPlayer.playAlbumNext(albumArtist, albumTitle)
            }
        }
        
        onPlayLast: {
            if (isPlaylist) {
                playPlaylistLast(playlistName, isVirtualPlaylist)
            } else {
                MediaPlayer.playAlbumLast(albumArtist, albumTitle)
            }
        }
    }
    
    // Track info panel state
    property bool showTrackInfoPanel: SettingsManager.showTrackInfoByDefault
    property var selectedTrackForInfo: null
    property real trackInfoPanelY: 184  // Start off-screen (below)
    property bool trackInfoPanelAnimating: false
    
    // Track selector state (for adding tracks to playlists)
    property bool showTrackSelector: false
    property string trackSelectorSearchTerm: ""
    property var trackSelectorResults: []
    
    // Scroll bar state tracking
    property bool isScrollBarDragging: false
    
    // Navigation state for keyboard controls
    property string navigationMode: "none"  // "none", "artist", "album", "track", "playlist"
    property int selectedArtistIndex: -1
    property int selectedAlbumIndex: -1
    property int selectedTrackIndex: -1
    property int selectedPlaylistIndex: -1
    property string selectedArtistName: ""
    property var selectedAlbumData: null
    
    // Smooth scrolling animation for artist list
    NumberAnimation { 
        id: scrollAnimation
        target: artistsListView
        property: "contentY"
        duration: 300
        easing.type: Easing.InOutQuad
        
        onRunningChanged: {
            if (!running && root.isProgrammaticScrolling) {
                // Reset the flag when animation completes
                Qt.callLater(function() {
                    root.isProgrammaticScrolling = false
                })
            }
        }
    }
    
    // Smooth scrolling animation for track list
    NumberAnimation {
        id: trackScrollAnimation
        target: trackListView
        property: "contentY"
        duration: 200  // Faster for track list
        easing.type: Easing.InOutQuad
    }
    
    // Smooth scrolling animation for artist list (arrow key navigation)
    NumberAnimation {
        id: artistScrollAnimation
        target: artistsListView
        property: "contentY"
        duration: 200  // Match track list duration for consistency
        easing.type: Easing.InOutQuad
    }
    
    // Navigation initialization timer to start keyboard navigation
    Timer {
        id: navigationInitTimer
        interval: 100 // lets all components intialize before starting navigation
        running: false
        repeat: false
        onTriggered: {
            if (LibraryManager.artistModel.length > 0) {
                root.forceActiveFocus()
                startArtistNavigation()
            }
        }
    }
    
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
    
    
    // Layout stabilization timer for dynamic scrolling
    Timer {
        id: layoutStabilizationTimer
        interval: 16  // ~60fps frame monitoring
        repeat: true
        running: false
        
        property int targetIndex: -1
        property int timeoutCount: 0
        property int maxTimeoutCount: 20  // 320ms maximum wait (20 * 16ms)
        
        onTriggered: {
            // Check for timeout
            timeoutCount++
            if (timeoutCount >= maxTimeoutCount) {
                console.log("Layout stabilization timeout reached, proceeding with scroll")
                stop()
                root.stableFrameCount = 0
                scrollToArtistIndex(targetIndex, true)
                return
            }
            
            // Monitor contentHeight changes
            var currentHeight = artistsListView.contentHeight
            if (Math.abs(currentHeight - root.previousContentHeight) < 0.1) {
                root.stableFrameCount++
                if (root.stableFrameCount >= 2) { // Stable for 2 consecutive frames
                    console.log("Layout stabilized after", timeoutCount * 16, "ms")
                    stop()
                    root.stableFrameCount = 0
                    scrollToArtistIndex(targetIndex, true)
                }
            } else {
                // Height changed, reset stability counter
                root.stableFrameCount = 0
                root.previousContentHeight = currentHeight
            }
        }
        
        onRunningChanged: {
            if (running) {
                // Reset counters when starting
                timeoutCount = 0
                root.stableFrameCount = 0
                root.previousContentHeight = artistsListView.contentHeight
            }
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
        
        // Create a new timer for cleanup with proper parent
        var cleanupTimer = Qt.createQmlObject(
            'import QtQuick 2.15; Timer { interval: ' + cleanupDelayMs + '; running: true; repeat: false }',
            root
        )
        
        cleanupTimer.triggered.connect(function() {
            // Check if root still exists before accessing properties
            if (!root) return
            
            // Clean up this artist's data if still collapsed
            if (expandedArtists && !expandedArtists[artistName]) {
                delete artistAlbumCache[artistName]
                delete artistAlbumIndexCache[artistName]
            }
            // Clean up the timer itself
            if (collapsedArtistCleanupTimers) {
                delete collapsedArtistCleanupTimers[artistName]
            }
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
            if (!expandedArtists[artist]) {
                artistsToClean.push(artist)
            }
        }
        
        artistsToClean.forEach(function(artist) {
            delete artistAlbumCache[artist]
            delete artistAlbumIndexCache[artist]
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
                if (navigationMode === "track" && selectedTrackIndex !== -1) {
                    // Clear track selection
                    selectedTrackIndex = -1
                    trackListView.currentIndex = -1
                    event.accepted = true
                } else {
                    // Return focus to search bar on Escape
                    resetNavigation()
                    searchBar.forceActiveFocus()
                    event.accepted = true
                }
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
        
        // Ctrl+I to toggle track info panel (works in any navigation mode)
        if (event.key === Qt.Key_I && event.modifiers & Qt.ControlModifier) {
            // Only toggle if we have a track selected
            if (navigationMode === "track" && selectedTrackIndex >= 0 && rightPane.currentAlbumTracks.length > selectedTrackIndex) {
                root.showTrackInfoPanel = !root.showTrackInfoPanel
                if (root.showTrackInfoPanel) {
                    root.selectedTrackForInfo = rightPane.currentAlbumTracks[selectedTrackIndex]
                }
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
        // Build initial index mappings
        updateArtistIndexMapping()
        updateAlbumIdMapping()
        // Initialize track info panel as hidden
        trackInfoPanelY = 184  // Start off-screen
        // Don't auto-select any track - start with no selection
        // Qt.callLater(autoSelectCurrentTrack)
        
        // Restore library pane state
        currentTab = SettingsManager.libraryActiveTab
        
        // Restore selected album or playlist after a delay to ensure everything is loaded
        if (SettingsManager.lastSelectedWasPlaylist && SettingsManager.lastSelectedPlaylistName) {
            Qt.callLater(function() {
                restoreSelectedPlaylist(SettingsManager.lastSelectedPlaylistName)
            })
        } else if (SettingsManager.lastSelectedAlbumId) {
            Qt.callLater(function() {
                restoreSelectedAlbum(SettingsManager.lastSelectedAlbumId)
            })
        }
        
        // Initialize keyboard navigation after a small delay to ensure everything is ready
        navigationInitTimer.start()
    }
    
    Component.onDestruction: {
        if (expandCollapseDebounceTimer) {
            expandCollapseDebounceTimer.stop()
        }
        
        for (var artist in collapsedArtistCleanupTimers) {
            if (collapsedArtistCleanupTimers[artist]) {
                collapsedArtistCleanupTimers[artist].stop()
            }
        }
    }
    
    // Update artist mapping when library changes
    Connections {
        target: LibraryManager
        function onLibraryChanged() {
            updateArtistIndexMapping()
            updateAlbumIdMapping()
            // Clear caches when library changes
            searchResultsCache = {}
            albumDurationCache = {}
            artistAlbumCache = {}
            artistAlbumIndexCache = {}
            currentTrackIndexMap = {}
            currentTrackFilePathMap = {}
        }
    }
    
    // Auto-select currently playing track
    Connections {
        target: MediaPlayer
        function onCurrentTrackChanged() {
            autoSelectCurrentTrack()
        }
    }
    
    // Function to build artist name to index mapping for O(1) lookups
    function updateArtistIndexMapping() {
        //console.log("updateArtistIndexMapping called")
        var mapping = {}
        var artists = LibraryManager.artistModel
        //console.log("updateArtistIndexMapping: Total artists:", artists.length)
        for (var i = 0; i < artists.length; i++) {
            if (artists[i] && artists[i].name) {
                mapping[artists[i].name] = i
            }
        }
        artistNameToIndex = mapping
        // console.log("updateArtistIndexMapping: Mapping complete, sample entries:", 
        //            Object.keys(mapping).slice(0, 3).map(function(k) { return k + ":" + mapping[k] }).join(", "))
    }
    
    // Function to build album ID to index mapping for O(1) lookups
    function updateAlbumIdMapping() {
        var mapping = {}
        var albums = LibraryManager.albumModel
        for (var i = 0; i < albums.length; i++) {
            if (albums[i] && albums[i].id !== undefined) {
                mapping[albums[i].id] = i
            }
        }
        albumIdToIndexMap = mapping
    }

    onSelectedAlbumChanged: {
        try {
            // Save selected album/playlist state
            if (selectedAlbum) {
                if (selectedAlbum.isPlaylist) {
                    // Save playlist selection
                    SettingsManager.lastSelectedPlaylistName = selectedAlbum.title
                    SettingsManager.lastSelectedWasPlaylist = true
                    SettingsManager.lastSelectedAlbumId = ""  // Clear album ID
                } else if (selectedAlbum.id) {
                    // Save album selection
                    SettingsManager.lastSelectedAlbumId = String(selectedAlbum.id)
                    SettingsManager.lastSelectedWasPlaylist = false
                    SettingsManager.lastSelectedPlaylistName = ""  // Clear playlist name
                }
            }
            
            // Sync navigation data when album changes
            root.selectedAlbumData = selectedAlbum
            
            // Clear track selection immediately when album changes
            root.selectedTrackIndex = -1;
            if (trackListView) {
                trackListView.currentIndex = -1;
            }
            
            // Clear multi-selection
            root.selectedTrackIndices = [];
            root.lastSelectedIndex = -1;
            
            // Exit edit mode when switching albums/playlists
            if (root.playlistEditMode) {
                root.playlistEditMode = false;
                root.editingPlaylistName = "";
                root.editedPlaylistTracks = [];
                root.playlistNameError = ""; // Clear any errors
            }
            
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
                    // Check if this is a playlist or regular album
                    if (selectedAlbum.isPlaylist === true) {
                        tracks = PlaylistManager.loadPlaylist(selectedAlbum.title);
                        if (rightPane) {
                            rightPane.albumTitleText = "Playlist - " + selectedAlbum.title;
                        }
                    } else {
                        tracks = LibraryManager.getTracksForAlbumAsVariantList(selectedAlbum.albumArtist, selectedAlbum.title);
                        if (rightPane) {
                            rightPane.albumTitleText = selectedAlbum.albumArtist + " - " + selectedAlbum.title;
                        }
                    }
                } catch (tracksError) {
                    console.warn("Error getting tracks for album:", tracksError);
                    tracks = [];
                }
                
                if (rightPane) {
                    rightPane.currentAlbumTracks = tracks || [];
                }
                
                // Don't auto-select any track - start with no selection
                // Qt.callLater(autoSelectCurrentTrack)
                
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
    Platform.FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        currentFolder: Platform.StandardPaths.standardLocations(Platform.StandardPaths.MusicLocation)[0]
        
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
    
    // Settings window instance
    property var settingsWindow: null
    
    // Component definition for the library editor window
    Component {
        id: libraryEditorWindowComponent
        LibraryEditorWindow {}
    }
    
    // Component definition for the settings window
    Component {
        id: settingsWindowComponent
        SettingsWindow {}
    }
    
    // Function to close all child windows
    function closeAllWindows() {
        console.log("LibraryPane: Closing all child windows")
        
        if (libraryEditorWindow && libraryEditorWindow.visible) {
            console.log("LibraryPane: Closing library editor window")
            libraryEditorWindow.close()
            libraryEditorWindow = null
        }
        
        if (settingsWindow && settingsWindow.visible) {
            console.log("LibraryPane: Closing settings window")
            settingsWindow.close()
            settingsWindow = null
        }
    }
    
    // Function to open library editor window
    function openLibraryEditor() {
        if (!libraryEditorWindow || !libraryEditorWindow.visible) {
            libraryEditorWindow = libraryEditorWindowComponent.createObject(null);
            
            // Add cleanup handler for when window is closed manually
            libraryEditorWindow.onClosing.connect(function() {
                //console.log("LibraryPane: Library editor window closed manually")
                libraryEditorWindow = null
            })
            
            libraryEditorWindow.show();
        } else {
            // Bring existing window to front
            libraryEditorWindow.raise();
            libraryEditorWindow.requestActivate();
        }
    }
    
    // Blurred background
    BlurredBackground {
        id: blurredBg
        anchors.fill: parent
        source: thumbnailUrl
        backgroundOpacity: 0.9
        z: -2  // Put this behind the dark overlay
    }
    
    // Overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: Theme.overlayColor
        opacity: Theme.overlayOpacity
        z: -1  // This should be above the blurred background but below content
    }
    
    // Subtle right edge line for cohesive background blending
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.edgeLineColor
        opacity: Theme.edgeLineOpacity
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
                    color: Theme.primaryText
                }
                
                Item { Layout.fillWidth: true } // Spacer

                Button {
                    implicitHeight: 28
                    implicitWidth: 28
                    icon.source: Theme.isDark ? "qrc:/resources/icons/minimize.svg" : "qrc:/resources/icons/minimize-dark.svg"
                    
                    onClicked: {
                        // Find the main window and call showMiniPlayer
                        var mainWindow = root.Window.window
                        if (mainWindow && mainWindow.showMiniPlayer) {
                            mainWindow.showMiniPlayer()
                        }
                    }

                    background: Rectangle {
                        id: buttonRect
                        color: Qt.rgba(1, 1, 1, 0.03)  // Subtle background like artist items
                        radius: 4  // Smaller radius
                        
                        //light border
                        border.width: 1
                        border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)

                    }

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
                            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                            border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
                        }
                    }
                    
                    transitions: Transition {
                        ColorAnimation { duration: 150 }
                    }
                }
                
                Button {
                    text: "Edit Library"
                    implicitHeight: 28  // Reduced button height
                    implicitWidth: 100  // Smaller width
                    
                    background: Rectangle {
                        id: minimizeButtonRect
                        color: Qt.rgba(1, 1, 1, 0.03)  // Subtle background like artist items
                        radius: 4  // Smaller radius
                        
                        //light border
                        border.width: 1
                        border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)

                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: Theme.primaryText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12  // Smaller font
                    }
                    
                    // Add mouse area for hover effects
                    MouseArea {
                        id: minimizeButtonMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        
                        onClicked: parent.clicked()
                    }
                    
                    // Hover effect matching artist items
                    states: State {
                        when: minimizeButtonMouseArea.containsMouse
                        PropertyChanges {
                            target: minimizeButtonRect
                            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                            border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
                        }
                    }
                    
                    transitions: Transition {
                        ColorAnimation { duration: 150 }
                    }
                    onClicked: {
                        openLibraryEditor()
                    }
                }
                
                // Settings button
                Button {
                    text: "Settings"
                    implicitHeight: 28  // Same height as Edit Library
                    implicitWidth: 80   // Slightly smaller width
                    
                    background: Rectangle {
                        id: settingsButtonRect
                        color: Qt.rgba(1, 1, 1, 0.03)  // Subtle background like Edit Library button
                        radius: 4  // Same radius
                        
                        //light border
                        border.width: 1
                        border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: Theme.primaryText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12  // Same font size
                    }
                    
                    // Add mouse area for hover effects
                    MouseArea {
                        id: settingsButtonMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        
                        onClicked: parent.clicked()
                    }
                    
                    // Hover effect matching Edit Library button
                    states: State {
                        when: settingsButtonMouseArea.containsMouse
                        PropertyChanges {
                            target: settingsButtonRect
                            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                            border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
                        }
                    }
                    
                    transitions: Transition {
                        ColorAnimation { duration: 150 }
                    }
                    onClicked: {
                        // Create floating window if it doesn't exist or was closed
                        if (!settingsWindow || !settingsWindow.visible) {
                            settingsWindow = settingsWindowComponent.createObject(null);
                            
                            // Add cleanup handler for when window is closed manually
                            settingsWindow.onClosing.connect(function() {
                                //console.log("LibraryPane: Settings window closed manually")
                                settingsWindow = null
                            })
                            
                            settingsWindow.show();
                        } else {
                            // Bring existing window to front
                            settingsWindow.raise();
                            settingsWindow.requestActivate();
                        }
                    }
                }
            }
        }
        
        // Horizontal Album Browser with width constraint
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 340  // Height for albums with reflections (reduced from 360)
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
                width: Math.min(parent.width - 4, 1600)  // Max width with very thin margin for borders
                height: parent.height - 3  // Account for margins
                
                onAlbumClicked: function(album) {
                    root.selectedAlbum = album
                    root.selectedAlbumData = album  // Keep navigation data in sync
                    
                    // Highlight the album's artist
                    root.highlightedArtist = album.albumArtist
                }
                
                onCenterAlbumChanged: function(album) {
                    // Update the background when scrolling stops on a new album
                    if (album && album.hasArt === true) {
                        try {
                            var encodedArtist = encodeURIComponent(album.albumArtist);
                            var encodedAlbum = encodeURIComponent(album.title);
                            var newThumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail";
                            
                            if (thumbnailUrl !== newThumbnailUrl) {
                                Qt.callLater(function() {
                                    thumbnailUrl = newThumbnailUrl;
                                });
                            }
                        } catch (encodeError) {
                            console.warn("Error encoding album art URL:", encodeError);
                        }
                    }
                }
                
                onAlbumTitleClicked: function(artistName, albumTitle) {
                    // Jump to the artist and select the album in the artist list
                    root.jumpToAlbum(artistName, albumTitle)
                }
            }
            
            // Gradient overlay to fade the bottom to black
            Item {
                anchors.fill: parent
                anchors.margins: 1  // Keep gradient inside borders
                z: 10  // Above album browser but below any text
                clip: true
                
                Rectangle {
                    anchors.fill: parent
                    radius: parent.parent.radius - 2  // Match parent radius with margin adjustment
                    
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.74; color: "transparent" } 
                        GradientStop { position: 0.85; color: Theme.upperGradientColor }  
                        GradientStop { position: 1.0; color: Theme.lowerGradientColor }  // Use theme color for lower gradient
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
                    id: albumTitleLabel
                    anchors.centerIn: parent
                    anchors.bottomMargin: 12
                    text: albumBrowser.selectedAlbum && albumBrowser.selectedAlbum.albumArtist && albumBrowser.selectedAlbum.title ? 
                          albumBrowser.selectedAlbum.albumArtist + " - " + albumBrowser.selectedAlbum.title : ""
                    color: "white"  // Always white due to dark gradient overlay
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
                        color: Theme.isDark ? "#80000000" : "#40000000"
                        font: parent.font
                        elide: parent.elide
                        horizontalAlignment: parent.horizontalAlignment
                        z: -1
                    }
                    
                    // Make the label clickable
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (albumBrowser.selectedAlbum && albumBrowser.selectedAlbum.albumArtist && albumBrowser.selectedAlbum.title) {
                                // Emit signal to jump to artist
                                albumBrowser.albumTitleClicked(albumBrowser.selectedAlbum.albumArtist, albumBrowser.selectedAlbum.title)
                            }
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
                SplitView.preferredWidth: parent.width * 0.51  // 51% of parent width
                SplitView.minimumWidth: 297  // Minimum for 2 album covers
                SplitView.maximumWidth: 600  // Maximum width to prevent it from getting too wide
                Layout.fillHeight: true
                color: Qt.rgba(0.1, 0.1, 0.1, 0.25)  // Semi-transparent dark with smoky tint
                radius: 8
                clip: true // Ensure content doesn't overflow radius
                
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

                // Container for SearchBar and tab content
                Item {
                    anchors.fill: parent
                    anchors.margins: 4
                    
                    // Row for search bar and tab selector
                    RowLayout {
                        id: searchRow
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 38  // Close to list item height (40px) with some breathing room
                        spacing: 8
                        
                        // Search bar at 60% width
                        SearchBar {
                            id: searchBar
                            Layout.preferredWidth: parent.width * 0.58
                            placeholderText: "Search library..."
                            z: 1
                        
                        onSearchRequested: function(searchTerm) {
                            root.performSearch(searchTerm)
                        }
                        
                        onClearRequested: {
                            root.clearSearch()
                        }
                        
                        onFocusRequested: {
                            // Reset navigation when search bar is focused
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
                        
                        // Tab selector - custom implementation
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(1, 1, 1, 0.15)
                            radius: 4
                            border.width: 1
                            border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.18)
                            
                            Item {
                                anchors.fill: parent
                                anchors.margins: 3
                                
                                // Sliding indicator background
                                Rectangle {
                                    id: tabIndicator
                                    width: (parent.width - 2) / 2  // Account for spacing
                                    height: parent.height
                                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.25)
                                    radius: 3
                                    x: root.currentTab === 0 ? 0 : parent.width / 2 + 1
                                    
                                    Behavior on x {
                                        NumberAnimation { 
                                            duration: 200
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                                
                                // Tab buttons row
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 2  // Add small spacing between buttons
                                    
                                    // Artists button
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Artists"
                                            font.pixelSize: 12
                                            color: root.currentTab === 0 ? Theme.primaryText : Theme.tertiaryText
                                            
                                            Behavior on color {
                                                ColorAnimation { duration: 150 }
                                            }
                                        }
                                        
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.currentTab = 0
                                                resetNavigation()
                                                // Start artist navigation when switching to Artists tab
                                                root.forceActiveFocus()
                                                if (LibraryManager.artistModel.length > 0) {
                                                    startArtistNavigation()
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Playlists button
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Playlists"
                                            font.pixelSize: 12
                                            color: root.currentTab === 1 ? Theme.primaryText : Theme.tertiaryText
                                            
                                            Behavior on color {
                                                ColorAnimation { duration: 150 }
                                            }
                                        }
                                        
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.currentTab = 1
                                                resetNavigation()
                                                // Start playlist navigation when switching to Playlists tab
                                                root.forceActiveFocus()
                                                if (PlaylistManager.playlists.length > 0) {
                                                    navigationMode = "playlist"
                                                    selectedPlaylistIndex = 0
                                                    if (playlistView) {
                                                        playlistView.forceActiveFocus()
                                                        playlistView.keyboardSelectedIndex = 0
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Container for sliding animation between Artists and Playlists
                    Item {
                        id: viewContainer
                        anchors.top: searchRow.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true  // Important for hiding the view that slides out
                        
                        // Inner container that slides horizontally
                        Item {
                            id: slidingContainer
                            width: parent.width * 2  // Wide enough for both views side by side
                            height: parent.height
                            
                            // Animate the x position when switching tabs
                            x: root.currentTab === 0 ? 0 : -parent.width
                            
                            Behavior on x {
                                enabled: true
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        
                            // Artists view - positioned at x: 0
                            ListView {
                                id: artistsListView
                                x: 0
                                width: viewContainer.width
                                height: parent.height
                                clip: true
                            model: LibraryManager.artistModel
                            spacing: 2
                            interactive: !root.isScrollBarDragging  // Disable ListView interaction during scroll bar drag
                            reuseItems: false  // Disabled to maintain consistent scroll positions
                            cacheBuffer: 1200  // Increase cache for smoother scrolling without recycling
                    
                    // Adaptive scroll speed - reduced when using scroll bar
                    flickDeceleration: root.isScrollBarDragging ? 1500 : 8000
                    maximumFlickVelocity: root.isScrollBarDragging ? 1000 : 2750
                    
                    // Smooth scrolling with bounds - remove to allow elastic overscroll in artist list
                    boundsMovement: Flickable.StopAtBounds
                    boundsBehavior: Flickable.StopAtBounds
                    
                    
                    // Smooth wheel scrolling with moderate speed
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        enabled: !root.isScrollBarDragging  // Disable during scroll bar dragging
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
                            
                            if (!root.isScrollBarDragging) {
                                artistsListView.flick(0, pixelDelta);
                            }
                        }
                    }

                    delegate: Item {
                        id: artistDelegate
                        width: ListView.view.width - 12  // Account for scrollbar space
                        // Dynamic height based on expansion
                        height: artistHeader.height + (albumsVisible ? albumsContainer.height + 2 : 0)
                        
                        // Store modelData for easier access in nested views/functions
                        property var artistData: modelData
                        property bool albumsVisible: false
                        property bool isHighlighted: root.highlightedArtist === artistData.name
                        property bool isKeyboardFocused: root.selectedArtistIndex === index && root.navigationMode === "artist"
                        
                        // Track delegate position for accurate scrolling
                        property real delegateY: y
                        onYChanged: {
                            // Update position when it changes
                            delegateY = y
                        }
                        
                        // Update albumsVisible binding whenever artist data changes or component completes
                        function updateAlbumsVisibility() {
                            if (artistData && artistData.name) {
                                albumsVisible = root.expandedArtists[artistData.name] === true
                            } else {
                                albumsVisible = false
                            }
                        }
                        
                        // Update visibility when artist data changes
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
                                albumsVisible = root.expandedArtists[artistData.name] === true;
                            }
                        }
                        
                        // Smooth height animation (disabled during scroll bar dragging and programmatic scrolling)
                        Behavior on height {
                            enabled: !root.isScrollBarDragging && !artistsListView.moving && !root.isProgrammaticScrolling
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InOutQuad
                            }
                        }

                        Rectangle {
                            id: artistHeader
                            width: parent.width
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
                                    color: Theme.primaryText
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                // Add an indicator for expansion (e.g., chevron)
                                Label {
                                    id: chevronLabel
                                    text: "\u203A" // Right-pointing chevron
                                    color: Theme.primaryText
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
                                    // Ensure the library pane has focus for keyboard navigation
                                    root.forceActiveFocus();
                                    
                                    // Update navigation state to artist mode
                                    root.navigationMode = "artist";
                                    root.selectedArtistIndex = index;
                                    root.selectedArtistName = artistData.name;
                                    
                                    // Toggle expansion state
                                    var currentState = root.expandedArtists[artistData.name] || false;
                                    var newExpandedState = !currentState;
                                    
                                    // Update state synchronously
                                    var updatedExpanded = Object.assign({}, root.expandedArtists);
                                    if (newExpandedState) {
                                        updatedExpanded[artistData.name] = true;
                                        root.cancelArtistCleanup(artistData.name);
                                    } else {
                                        delete updatedExpanded[artistData.name];
                                        root.scheduleArtistCleanup(artistData.name);
                                    }
                                    root.expandedArtists = updatedExpanded;
                                    
                                    artistsListView.currentIndex = index; // Optional: select on expand
                                }
                            }
                            
                            // Hover effect
                            states: State {
                                when: artistMouseArea.containsMouse && artistsListView.currentIndex !== index
                                PropertyChanges {
                                    target: artistHeader
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.09)
                                }
                            }
                            
                            transitions: Transition {
                                ColorAnimation { duration: 150 }
                            }
                        }

                        // Albums GridView - positioned below artist header
                        Rectangle {
                            id: albumsContainer
                            anchors.top: artistHeader.bottom
                            anchors.topMargin: 2
                            width: parent.width
                            // Calculate height based on album count to avoid dynamic contentHeight issues
                            height: albumsVisible ? calculateAlbumContainerHeight() : 0
                            color: Qt.rgba(1, 1, 1, 0.04) // Very subtle frosted background
                            radius: 6
                            opacity: albumsVisible ? 1 : 0
                            clip: false  // Allow glow effect to overflow
                            
                            Behavior on opacity {
                                enabled: !root.isScrollBarDragging && !artistsListView.moving
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.InOutQuad
                                }
                            }
                            
                            // Subtle inset shadow
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.13)
                            
                            // Cache albums data when artist changes or becomes visible
                            property var cachedAlbums: []
                            property string cachedArtistName: ""
                            
                            // Calculate fixed height for album container
                            function calculateAlbumContainerHeight() {
                                if (!cachedAlbums || cachedAlbums.length === 0) return 0
                                
                                var minCellWidth = 130  // Minimum width (120 thumbnail + 10 spacing)
                                var cellHeight = 150  // 140 + 10 spacing
                                var availableWidth = width - 16  // Use container's width, matching GridView calculation
                                var columns = Math.floor(availableWidth / minCellWidth)
                                if (columns < 1) columns = 1
                                var rows = Math.ceil(cachedAlbums.length / columns)
                                
                                return (rows * cellHeight) + 16  // Grid height + padding
                            }
                            
                            // Function to refresh album data
                            function refreshAlbumData() {
                                if (opacity > 0 && artistData && artistData.name) {
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
                            
                            onOpacityChanged: {
                                if (opacity > 0) {
                                    refreshAlbumData()
                                }
                            }
                            
                            // Refresh when parent's artistData changes
                            property var artistDataWatcher: parent.artistData
                            onArtistDataWatcherChanged: {
                                refreshAlbumData()
                            }

                            GridView {
                                id: albumsGrid
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: false  // Allow glow effect to overflow
                                cellWidth: {
                                    var minCellWidth = 130  // Minimum width (120 thumbnail + 10 spacing)
                                    var availableWidth = parent.width - 16  // Account for margins
                                    var columns = Math.floor(availableWidth / minCellWidth)
                                    if (columns < 1) columns = 1
                                    return Math.floor(availableWidth / columns)
                                }
                                cellHeight: 140 + 10 // Thumbnail + title + padding
                                interactive: false // Parent ListView handles scrolling primarily
                                reuseItems: false  // Disabled to prevent issues with expand/collapse
                                cacheBuffer: 600  // Increased cache for album grid

                                model: albumsContainer.cachedAlbums

                                delegate: Item { 
                                    width: albumsGrid.cellWidth - 10
                                    height: albumsGrid.cellHeight - 10
                                    
                                    // Viewport visibility detection for lazy loading
                                    property bool isInViewport: false
                                    property real globalY: 0
                                    
                                    // Calculate global position relative to the main ListView
                                    function updateGlobalPosition() {
                                        // Get position relative to artist container
                                        var pos = mapToItem(artistsListView.contentItem, 0, 0)
                                        if (pos) {
                                            globalY = pos.y
                                            // Check if in viewport with buffer zone
                                            var viewportTop = artistsListView.contentY - 200  // 200px buffer above
                                            var viewportBottom = artistsListView.contentY + artistsListView.height + 200  // 200px buffer below
                                            isInViewport = globalY + height > viewportTop && globalY < viewportBottom
                                        }
                                    }
                                    
                                    // Update visibility when scroll position changes
                                    Connections {
                                        target: artistsListView
                                        function onContentYChanged() {
                                            updateGlobalPosition()
                                        }
                                    }
                                    
                                    // Update when album becomes visible
                                    Connections {
                                        target: albumsContainer
                                        function onOpacityChanged() {
                                            if (albumsContainer.opacity > 0) {
                                                updateGlobalPosition()
                                            }
                                        }
                                    }
                                    
                                    Component.onCompleted: {
                                        updateGlobalPosition()
                                    }

                                    Item { 
                                        anchors.fill: parent
                                        clip: false  // Don't clip to allow glow overflow
                                        
                                        // Navigation selection glow effect
                                        Rectangle {
                                            id: glowSource
                                            anchors.centerIn: albumArtContainer
                                            width: albumArtContainer.width - 10
                                            height: albumArtContainer.height - 10
                                            radius: 8
                                            color: Qt.rgba(1.0, 1.0, 1.0, 0.8)
                                            // Cache the visibility check
                                            property bool shouldShow: root.navigationMode === "album" && 
                                                    root.selectedArtistName === artistData.name && 
                                                    root.selectedAlbumIndex === index
                                            visible: false // Hidden, used as source for effect
                                            
                                            layer.enabled: shouldShow
                                            layer.effect: MultiEffect {
                                                source: glowSource
                                                anchors.fill: glowSource
                                                blurEnabled: true
                                                blur: 1.0
                                                blurMax: 32
                                                brightness: 0.3
                                                saturation: 1.2
                                                visible: glowSource.shouldShow
                                                opacity: glowSource.shouldShow ? 1.0 : 0.0
                                                
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 200 }
                                                }
                                            }
                                            
                                            z: -1 // Behind the album art
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
                                                // Only load image when in viewport for better memory usage
                                                source: (modelData.hasArt && isInViewport) ? "image://albumart/" + modelData.id + "/thumbnail/220" : ""
                                                fillMode: Image.PreserveAspectFit
                                                clip: false
                                                asynchronous: true
                                                cache: false  // Don't cache in virtualized lists to save memory
                                                sourceSize.width: 220  // Limit to 2x the display size for retina
                                                sourceSize.height: 220
                                                
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
                                                    color: Theme.isDark ? "#444444" : "#dddddd"
                                                    visible: parent.status !== Image.Ready
                                                    radius: 3
                                                    
                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: "♪"
                                                        font.pixelSize: 32
                                                        color: Theme.tertiaryText
                                                    }
                                                }
                                            }
                                            
                                            // Selection indicator - white outline that matches image dimensions
                                            Rectangle {
                                                id: selectionIndicator
                                                color: "transparent"
                                                border.width: 2
                                                border.color: Theme.primaryText
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
                                            color: Theme.primaryText
                                            font.pixelSize: 11
                                            font.underline: root.navigationMode === "album" && 
                                                    root.selectedArtistName === artistData.name && 
                                                    root.selectedAlbumIndex === index
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            verticalAlignment: Text.AlignTop
                                            clip: true
                                            
                                            // Smooth transition for underline
                                            Behavior on font.underline {
                                                enabled: false // Instant transition for boolean
                                            }
                                        }
                                    }
                                    MouseArea { 
                                        id: artistAlbumMouseArea
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.LeftButton) {
                                                root.selectedAlbum = modelData; // Update the root's selectedAlbum property
                                                albumBrowser.jumpToAlbum(modelData); // Jump to album in carousel
                                            } else if (mouse.button === Qt.RightButton) {
                                                albumContextMenu.popup();
                                            }
                                        }
                                        onDoubleClicked: function(mouse) {
                                            // Play the album on double-click
                                            var globalPos = parent.mapToGlobal(mouse.x, mouse.y);
                                            
                                            // If shuffle is enabled, start with a random track instead of the first
                                            var startIndex = 0;
                                            if (MediaPlayer.shuffleEnabled && modelData.trackCount > 0) {
                                                startIndex = Math.floor(Math.random() * modelData.trackCount);
                                            }
                                            
                                            root.playAlbumWithQueueCheck(modelData.albumArtist, modelData.title, startIndex, globalPos.x, globalPos.y);
                                        }
                                    }
                                    
                                    StyledMenu {
                                        id: albumContextMenu
                                        
                                        StyledMenuItem {
                                            text: "Play"
                                            onTriggered: {
                                                var globalPos = artistAlbumMouseArea.parent.mapToGlobal(artistAlbumMouseArea.width / 2, artistAlbumMouseArea.height / 2);
                                                
                                                // If shuffle is enabled, start with a random track instead of the first
                                                var startIndex = 0;
                                                if (MediaPlayer.shuffleEnabled && modelData.trackCount > 0) {
                                                    startIndex = Math.floor(Math.random() * modelData.trackCount);
                                                }
                                                
                                                root.playAlbumWithQueueCheck(modelData.albumArtist, modelData.title, startIndex, globalPos.x, globalPos.y);
                                            }
                                        }
                                        
                                        StyledMenuItem {
                                            text: "Play Next"
                                            onTriggered: {
                                                MediaPlayer.playAlbumNext(modelData.albumArtist, modelData.title);
                                            }
                                        }
                                        
                                        StyledMenuItem {
                                            text: "Play Last"
                                            onTriggered: {
                                                MediaPlayer.playAlbumLast(modelData.albumArtist, modelData.title);
                                            }
                                        }
                                    }
                                }
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                        }
                    }  // End of artistDelegate Item
                    
                    // Add right padding to content to make room for scrollbar
                    rightMargin: 12
                    
                    ScrollBar.vertical: ScrollBar { 
                            id: artistScrollBar
                            policy: ScrollBar.AsNeeded
                            minimumSize: 0.1
                            width: 10  // Slightly wider for easier grabbing
                            snapMode: ScrollBar.NoSnap
                            interactive: true
                            
                            // Remove step size to prevent discrete jumps
                            stepSize: 0
                            
                            // Track drag state
                            onPressedChanged: {
                                root.isScrollBarDragging = pressed
                                if (!pressed) {
                                    // Force a layout update when releasing to ensure proper positioning
                                    artistsListView.forceLayout()
                                }
                            }
                            
                            // Default reduced opacity
                            opacity: scrollBarMouseArea.containsMouse || artistScrollBar.pressed ? 1.0 : 0.3
                            
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
                                color: Qt.rgba(1, 1, 1, artistScrollBar.pressed ? 0.5 : 0.3)
                                radius: width / 2
                                
                                Behavior on color {
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
                        
                            // Playlists view - positioned to the right of artists view
                            PlaylistView {
                                id: playlistView
                                x: viewContainer.width  // Positioned next to artists view
                                width: viewContainer.width
                                height: parent.height
                            
                            onPlaylistSelected: function(playlistName) {
                                // Handle special "All Songs" playlist
                                if (playlistName === "All Songs") {
                                    // Get the virtual playlist model
                                    var allSongsModel = LibraryManager.getAllSongsPlaylist()
                                    root.selectedAlbum = {
                                        title: playlistName,
                                        albumArtist: "Library",
                                        hasArt: false,
                                        isPlaylist: true,
                                        isVirtualPlaylist: true,
                                        virtualModel: allSongsModel
                                    }
                                    // For virtual playlists, we don't load all tracks immediately
                                    rightPane.currentAlbumTracks = []
                                    rightPane.albumTitleText = "All Songs - " + allSongsModel.count + " tracks"
                                } else {
                                    // Load and display regular playlist tracks
                                    var tracks = PlaylistManager.loadPlaylist(playlistName)
                                    if (tracks.length > 0) {
                                        // Create a pseudo-album for the playlist
                                        root.selectedAlbum = {
                                            title: playlistName,
                                            albumArtist: "Playlist",
                                            hasArt: false,
                                            isPlaylist: true,
                                            isVirtualPlaylist: false
                                        }
                                        rightPane.currentAlbumTracks = tracks
                                        rightPane.albumTitleText = "Playlist - " + playlistName
                                    }
                                }
                            }
                            
                            onPlaylistDoubleClicked: function(playlistName, event) {
                                var isVirtual = playlistName === "All Songs"
                                var mouseX = event ? event.x : undefined
                                var mouseY = event ? event.y : undefined
                                
                                // Map local coordinates to window coordinates if event is provided
                                if (event && playlistView) {
                                    var globalPos = playlistView.mapToItem(root, mouseX, mouseY)
                                    mouseX = globalPos.x
                                    mouseY = globalPos.y
                                }
                                
                                // Calculate start index based on shuffle mode
                                var startIndex = 0
                                if (MediaPlayer.shuffleEnabled) {
                                    var trackCount = 0
                                    if (isVirtual && playlistName === "All Songs") {
                                        // For All Songs, get count from the virtual playlist
                                        var allSongsModel = LibraryManager.getAllSongsPlaylist()
                                        trackCount = allSongsModel ? allSongsModel.rowCount() : 0
                                    } else {
                                        // For regular playlists, get count from PlaylistManager
                                        trackCount = PlaylistManager.getPlaylistTrackCount(playlistName)
                                    }
                                    
                                    if (trackCount > 0) {
                                        startIndex = Math.floor(Math.random() * trackCount)
                                    }
                                }
                                
                                playPlaylistWithQueueCheck(playlistName, isVirtual, startIndex, mouseX, mouseY)
                            }
                            
                            onPlaylistPlayRequested: function(playlistName) {
                                var isVirtual = playlistName === "All Songs"
                                
                                // Calculate start index based on shuffle mode
                                var startIndex = 0
                                if (MediaPlayer.shuffleEnabled) {
                                    var trackCount = 0
                                    if (isVirtual && playlistName === "All Songs") {
                                        // For All Songs, get count from the virtual playlist
                                        var allSongsModel = LibraryManager.getAllSongsPlaylist()
                                        trackCount = allSongsModel ? allSongsModel.rowCount() : 0
                                    } else {
                                        // For regular playlists, get count from PlaylistManager
                                        trackCount = PlaylistManager.getPlaylistTrackCount(playlistName)
                                    }
                                    
                                    if (trackCount > 0) {
                                        startIndex = Math.floor(Math.random() * trackCount)
                                    }
                                }
                                
                                playPlaylistWithQueueCheck(playlistName, isVirtual, startIndex)
                            }
                            
                            onPlaylistPlayNextRequested: function(playlistName) {
                                var isVirtual = playlistName === "All Songs"
                                playPlaylistNext(playlistName, isVirtual)
                            }
                            
                            onPlaylistPlayLastRequested: function(playlistName) {
                                var isVirtual = playlistName === "All Songs"
                                playPlaylistLast(playlistName, isVirtual)
                            }
                            
                            onNavigateToTracks: {
                                // Move focus to track list when right arrow is pressed in playlist view
                                if (rightPane.currentAlbumTracks.length > 0) {
                                    root.navigationMode = "track"
                                    root.selectedTrackIndex = -1  // Don't auto-select first track
                                    trackListView.currentIndex = -1
                                    root.forceActiveFocus()
                                }
                            }
                        }
                        }  // End of slidingContainer
                    }  // End of viewContainer
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

                // Inner shadow for depth
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.15) // Slightly lighter shadow than left pane
                }
                
                //border
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                

                property var currentAlbumTracks: []
                property string albumTitleText: "No album selected"

                onCurrentAlbumTracksChanged: {
                    if (trackListView) {
                        trackListView.currentIndex = -1
                        
                        // If we're in playlist edit mode and tracks were just added, scroll to bottom
                        if (root.playlistEditMode && root.editedPlaylistTracks.length > 0) {
                            Qt.callLater(function() {
                                var lastIndex = currentAlbumTracks.length - 1
                                if (lastIndex >= 0) {
                                    trackListView.positionViewAtIndex(lastIndex, ListView.End)
                                }
                            })
                        }
                    }
                    
                    // Build track index maps for O(1) lookups
                    var indexMap = {}
                    var filePathMap = {}
                    for (var i = 0; i < currentAlbumTracks.length; i++) {
                        var track = currentAlbumTracks[i]
                        if (track) {
                            if (track.title && track.artist) {
                                var key = track.title + "|" + track.artist
                                indexMap[key] = i
                            }
                            if (track.filePath) {
                                filePathMap[track.filePath] = i
                            }
                        }
                    }
                    root.currentTrackIndexMap = indexMap
                    root.currentTrackFilePathMap = filePathMap
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.margins: 4
                        height: 60
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.15) // Track info panel background
                        radius: 6
                        border.width: 1
                        border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.21) 
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 12
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                
                                // Playlist title - editable in edit mode
                                Loader {
                                    id: titleLoader
                                    Layout.fillWidth: true
                                    height: 24
                                    sourceComponent: root.playlistEditMode && root.selectedAlbum && root.selectedAlbum.isPlaylist && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title) ? editableTitleComponent : readOnlyTitleComponent
                                    
                                    Component {
                                        id: readOnlyTitleComponent
                                        Item {
                                            anchors.fill: parent
                                            
                                            Label {
                                                id: trackListHeader
                                                anchors.centerIn: parent
                                                width: parent.width
                                                text: rightPane.albumTitleText
                                                color: albumTitleMouseArea.containsMouse ? Theme.primaryText : Theme.secondaryText
                                                font.pixelSize: 16
                                                font.bold: true
                                                elide: Text.ElideRight
                                                wrapMode: Text.NoWrap
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            
                                            MouseArea {
                                                id: albumTitleMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: root.selectedAlbum && !root.selectedAlbum.isPlaylist ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                visible: root.selectedAlbum && !root.selectedAlbum.isPlaylist
                                                
                                                onClicked: {
                                                    if (root.selectedAlbum && !root.selectedAlbum.isPlaylist) {
                                                        albumBrowser.jumpToAlbum(root.selectedAlbum)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    Component {
                                        id: editableTitleComponent
                                        TextField {
                                            id: titleTextField
                                            anchors.fill: parent
                                            text: root.editingPlaylistName
                                            color: Theme.primaryText
                                            font.pixelSize: 16
                                            font.bold: true
                                            selectByMouse: true
                                            selectionColor: Qt.rgba(0, 0.5, 1, 0.3)
                                            selectedTextColor: "white"
                                            verticalAlignment: TextInput.AlignVCenter
                                            topPadding: 0
                                            bottomPadding: 0
                                            leftPadding: 6
                                            rightPadding: 6
                                            
                                            background: Rectangle {
                                                color: titleTextField.activeFocus ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.05)
                                                border.width: 1
                                                border.color: titleTextField.activeFocus ? Qt.rgba(0, 0.5, 1, 0.5) : Qt.rgba(1, 1, 1, 0.1)
                                                radius: 4
                                            }
                                            
                                            onTextChanged: {
                                                root.editingPlaylistName = text
                                                
                                                // Validate the name
                                                var trimmedName = text.trim()
                                                if (trimmedName.length === 0) {
                                                    root.playlistNameError = "Playlist name cannot be empty"
                                                } else if (!/^[^<>:"/\\|?*]+$/.test(trimmedName)) {
                                                    root.playlistNameError = "Invalid characters in playlist name"
                                                } else if (trimmedName !== root.selectedAlbum.title && PlaylistManager.playlists.indexOf(trimmedName) !== -1) {
                                                    root.playlistNameError = "A playlist with this name already exists"
                                                } else {
                                                    root.playlistNameError = ""
                                                }
                                            }
                                            
                                            Keys.onReturnPressed: {
                                                focus = false
                                            }
                                            
                                            Keys.onEscapePressed: {
                                                text = root.selectedAlbum.title
                                                focus = false
                                            }
                                            
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.IBeamCursor
                                                onClicked: {
                                                    titleTextField.forceActiveFocus()
                                                    titleTextField.selectAll()
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    
                                    Label {
                                        text: root.selectedAlbum && root.selectedAlbum.year ? root.selectedAlbum.year : ""
                                        color: Theme.secondaryText
                                        font.pixelSize: 12
                                        visible: text !== ""
                                    }
                                    
                                    Label {
                                        text: rightPane.currentAlbumTracks.length > 0 ? 
                                              (rightPane.currentAlbumTracks.length === 1 ? "1 track" : rightPane.currentAlbumTracks.length + " tracks") : ""
                                        color: Theme.secondaryText
                                        font.pixelSize: 12
                                        visible: text !== "" && !(root.playlistEditMode && root.playlistNameError !== "") && root.playlistStatusMessage === ""
                                    }
                                    
                                    Label {
                                        text: rightPane.currentAlbumTracks.length > 0 ? formatAlbumDuration() : ""
                                        color: Theme.secondaryText
                                        font.pixelSize: 12
                                        visible: text !== "" && !(root.playlistEditMode && root.playlistNameError !== "") && root.playlistStatusMessage === ""
                                    }
                                    
                                    Label {
                                        text: root.playlistStatusMessage !== "" ? root.playlistStatusMessage : root.playlistNameError
                                        color: root.playlistStatusMessage !== "" ? "#60ff60" : "#ff6060"
                                        font.pixelSize: 12
                                        visible: (root.playlistEditMode && root.playlistNameError !== "") || root.playlistStatusMessage !== ""
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    
                                    Item { 
                                        Layout.fillWidth: !root.playlistEditMode || root.playlistNameError === ""
                                        Layout.preferredWidth: 0
                                    } // Spacer
                                }
                            }
                            
                            // Edit/Save/Cancel buttons for playlists (excluding special playlists like "All Songs")
                            Item {
                                Layout.preferredWidth: childrenRect.width
                                Layout.fillHeight: true
                                visible: root.selectedAlbum && root.selectedAlbum.isPlaylist === true && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title)
                                
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                
                                // Edit button (shown when not in edit mode)
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 4
                                    color: editMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                                    visible: !root.playlistEditMode
                                    
                                    // Animate color transition on hover
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    
                                    Image {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: Theme.isDark ? "qrc:/resources/icons/edit.svg" : "qrc:/resources/icons/edit-dark.svg"
                                        sourceSize.width: 36
                                        sourceSize.height: 36
                                    }
                                    
                                    MouseArea {
                                        id: editMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // Enter edit mode
                                            root.playlistEditMode = true
                                            root.editingPlaylistName = root.selectedAlbum.title
                                            root.editedPlaylistTracks = rightPane.currentAlbumTracks.slice() // Make a copy
                                            root.playlistNameError = "" // Clear any previous errors
                                            root.playlistStatusMessage = "" // Clear any previous status messages
                                        }
                                    }
                                }
                                
                                // Save button (shown in edit mode)
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 4
                                    color: saveMouseArea.containsMouse ? Qt.rgba(0, 1, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                                    visible: root.playlistEditMode
                                    
                                    // Animate color transition on hover
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    
                                    Image {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: Theme.isDark ? "qrc:/resources/icons/save.svg" : "qrc:/resources/icons/save-dark.svg"
                                        sourceSize.width: 36
                                        sourceSize.height: 36
                                    }
                                    
                                    MouseArea {
                                        id: saveMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // Validate the playlist name
                                            var trimmedName = root.editingPlaylistName.trim()
                                            if (trimmedName.length === 0) {
                                                console.error("Playlist name cannot be empty")
                                                return
                                            }
                                            
                                            // Check for invalid characters
                                            if (!/^[^<>:"/\\|?*]+$/.test(trimmedName)) {
                                                console.error("Invalid characters in playlist name")
                                                return
                                            }
                                            
                                            // Check if we need to rename the playlist
                                            var originalName = root.selectedAlbum.title
                                            var needsRename = trimmedName !== originalName
                                            
                                            if (needsRename) {
                                                // Check if the new name already exists
                                                if (PlaylistManager.playlists.indexOf(trimmedName) !== -1) {
                                                    console.error("A playlist with this name already exists")
                                                    return
                                                }
                                                
                                                // Rename the playlist first
                                                if (!PlaylistManager.renamePlaylist(originalName, trimmedName)) {
                                                    console.error("Failed to rename playlist")
                                                    return
                                                }
                                                
                                                // Update the selected album title
                                                root.selectedAlbum.title = trimmedName
                                                rightPane.albumTitleText = "Playlist - " + trimmedName
                                            }
                                            
                                            // Save the edited playlist tracks
                                            PlaylistManager.updatePlaylist(trimmedName, root.editedPlaylistTracks)
                                            root.playlistEditMode = false
                                            root.playlistNameError = "" // Clear any errors
                                            root.playlistStatusMessage = "Saved changes"
                                            statusMessageTimer.restart()
                                            // Update the current view with edited tracks
                                            rightPane.currentAlbumTracks = root.editedPlaylistTracks.slice()
                                        }
                                    }
                                }
                                
                                // Cancel button (shown in edit mode)
                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 4
                                    color: cancelMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                                    visible: root.playlistEditMode
                                    
                                    // Animate color transition on hover
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    
                                    Image {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: Theme.isDark ? "qrc:/resources/icons/cancel.svg" : "qrc:/resources/icons/cancel-dark.svg"
                                        sourceSize.width: 36
                                        sourceSize.height: 36
                                    }
                                    
                                    MouseArea {
                                        id: cancelMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // Cancel edit mode and restore original tracks
                                            root.playlistEditMode = false
                                            root.editingPlaylistName = ""
                                            root.playlistNameError = "" // Clear any errors
                                            root.playlistStatusMessage = "Cancelled changes"
                                            statusMessageTimer.restart()
                                            
                                            // Reload the original playlist tracks
                                            if (root.selectedAlbum && root.selectedAlbum.isPlaylist) {
                                                var originalTracks = PlaylistManager.loadPlaylist(root.selectedAlbum.title)
                                                rightPane.currentAlbumTracks = originalTracks
                                                root.editedPlaylistTracks = []
                                            }
                                        }
                                    }
                                }
                                }
                            }
                        }
                    }

                    ListView {
                        id: trackListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.selectedAlbum && root.selectedAlbum.isVirtualPlaylist ? root.selectedAlbum.virtualModel : rightPane.currentAlbumTracks
                        visible: (root.selectedAlbum && root.selectedAlbum.isVirtualPlaylist) || rightPane.currentAlbumTracks.length > 0
                        spacing: 1
                        reuseItems: false
                        cacheBuffer: 800  // Increased cache without recycling
                        currentIndex: -1  // Start with no selection
                        
                        // Drag and drop state
                        property int draggedTrackIndex: -1
                        property int dropIndex: -1
                        
                        // Smooth height animation synchronized with panel slide
                        Behavior on Layout.preferredHeight {
                            enabled: !root.trackInfoPanelAnimating
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }
                        
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
                        
                        flickDeceleration: 8000
                        maximumFlickVelocity: 2750
                        
                        // Smooth scrolling with bounds - remove to allow elastic overscroll in track list
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
                            
                            // Helper property to determine if using virtual model
                            property bool isVirtualModel: root.selectedAlbum && (root.selectedAlbum.isVirtualPlaylist === true)
                            
                            // Track data accessor - works for both regular and virtual models
                            property var trackData: isVirtualModel ? model : modelData
                            
                            // Helper properties to determine if we should show disc number
                            property int currentDiscNumber: (trackData && trackData.discNumber) || 1
                            property int previousDiscNumber: {
                                if (!isVirtualModel && index > 0 && rightPane.currentAlbumTracks[index - 1]) {
                                    return rightPane.currentAlbumTracks[index - 1].discNumber || 1
                                }
                                return 0
                            }
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
                                    text: "Disc " + (trackData.discNumber || 1)
                                    color: Theme.secondaryText
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                            
                            Rectangle {
                                id: trackDelegate
                                width: parent.width
                                height: 45
                                
                                property bool isHovered: trackHoverArea.containsMouse
                                
                                color: {
                                    if (root.selectedTrackIndices.indexOf(index) !== -1) {
                                        return Qt.rgba(0.25, 0.32, 0.71, 0.25)  // Selected track
                                    } else if (root.selectedTrackIndex === index) {
                                        return Qt.rgba(0.25, 0.32, 0.71, 0.15)  // Current track (lighter)
                                    } else {
                                        return Theme.isDark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(1, 1, 1, 0.12) // Track background
                                    }
                                }
                                radius: 4
                                
                                //border
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.04)
                                
                                MouseArea {
                                    id: trackHoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }
                                
                                // Animated vertical offset for drag feedback
                                transform: Translate {
                                    y: trackDelegate.verticalOffset
                                    Behavior on y {
                                        enabled: root.playlistEditMode && trackListView.draggedTrackIndex !== -1
                                        NumberAnimation {
                                            duration: 200
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                                
                                property real verticalOffset: {
                                    if (!root.playlistEditMode || trackListView.draggedTrackIndex === -1) return 0
                                    
                                    var dragIdx = trackListView.draggedTrackIndex
                                    var dropIdx = trackListView.dropIndex
                                    
                                    if (dragIdx === index || dropIdx === -1) return 0  // Don't offset the dragged item
                                    
                                    if (dragIdx < dropIdx) {
                                        // Dragging down
                                        if (index > dragIdx && index <= dropIdx) return -trackDelegate.height - trackListView.spacing
                                    } else if (dragIdx > dropIdx) {
                                        // Dragging up
                                        if (index >= dropIdx && index < dragIdx) return trackDelegate.height + trackListView.spacing
                                    }
                                    
                                    return 0
                                }
                                
                                // Update drop position in real-time while dragging
                                onYChanged: {
                                    if (dragArea.drag.active && trackListView.draggedTrackIndex === index) {
                                        // Calculate potential drop position based on current Y
                                        var dragDistance = y - dragArea.originalY
                                        var itemsMoved = Math.round(dragDistance / (height + trackListView.spacing))
                                        var potentialIndex = trackListView.draggedTrackIndex + itemsMoved
                                        potentialIndex = Math.max(0, Math.min(potentialIndex, trackListView.count - 1))
                                        
                                        // Update drop index if it changed
                                        if (potentialIndex !== trackListView.dropIndex) {
                                            trackListView.dropIndex = potentialIndex
                                        }
                                    }
                                }



                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 10

                                    // Drag handle (only in edit mode for playlists)
                                    Image {
                                        id: dragHandle
                                        source: Theme.isDark ? "qrc:/resources/icons/list-drag-handle.svg" : "qrc:/resources/icons/list-drag-handle-dark.svg"
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        sourceSize.width: 40
                                        sourceSize.height: 40
                                        opacity: 0.5
                                        visible: root.playlistEditMode && root.selectedAlbum && root.selectedAlbum.isPlaylist && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title) && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title)
                                        
                                        MouseArea {
                                            id: dragArea
                                            anchors.fill: parent
                                            cursorShape: Qt.DragMoveCursor
                                            
                                            drag.target: trackDelegate
                                            drag.axis: Drag.YAxis
                                            
                                            property int originalY: 0
                                            
                                            onPressed: {
                                                trackListView.draggedTrackIndex = index
                                                trackListView.dropIndex = index
                                                originalY = trackDelegate.y
                                                trackDelegate.z = 1000
                                                trackDelegate.opacity = 0.8
                                            }
                                            
                                            onReleased: {
                                                // Use the pre-calculated drop index
                                                var newIndex = trackListView.dropIndex
                                                var draggedIdx = trackListView.draggedTrackIndex
                                                
                                                // Keep track of whether we're actually moving
                                                var isMoving = newIndex !== draggedIdx && draggedIdx >= 0
                                                
                                                // Reset visual properties
                                                trackDelegate.z = 0
                                                trackDelegate.opacity = 1.0
                                                trackDelegate.y = dragArea.originalY
                                                
                                                // Reset drag state to remove all visual offsets
                                                trackListView.draggedTrackIndex = -1
                                                trackListView.dropIndex = -1
                                                
                                                // Perform the reorder after a brief delay to allow visual reset
                                                if (isMoving) {
                                                    // Save the current scroll position before the delayed call
                                                    var savedContentY = trackListView.contentY
                                                    var listView = trackListView
                                                    
                                                    // Use a timer to ensure visual updates complete first
                                                    Qt.callLater(function() {
                                                        // Save scroll position again right before model update
                                                        var currentContentY = listView.contentY
                                                        
                                                        var movedTrack = root.editedPlaylistTracks.splice(draggedIdx, 1)[0]
                                                        root.editedPlaylistTracks.splice(newIndex, 0, movedTrack)
                                                        
                                                        // Update the view
                                                        rightPane.currentAlbumTracks = root.editedPlaylistTracks.slice()
                                                        
                                                        // Immediately restore scroll position (synchronously)
                                                        listView.contentY = currentContentY
                                                    })
                                                }
                                            }
                                        }
                                    }

                                    Label { // Track Number
                                        text: trackData.trackNumber ? String(trackData.trackNumber).padStart(1, '0') : "--"
                                        color: Theme.tertiaryText
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 25
                                        horizontalAlignment: Text.AlignRight
                                        visible: root.selectedAlbum && !root.selectedAlbum.isPlaylist
                                    }

                                    // Track Title - shows different format for albums vs playlists
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: 20
                                        
                                        property bool isPlaylist: root.selectedAlbum && root.selectedAlbum.isPlaylist === true
                                        
                                        // For albums - simple title
                                        Label {
                                            anchors.fill: parent
                                            text: trackData.title || "Unknown Track"
                                            color: Theme.primaryText
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                            visible: !parent.isPlaylist
                                        }
                                        
                                        // For playlists - title and artist with proper layout
                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 8
                                            visible: parent.isPlaylist
                                            
                                            // Track title - prioritized, takes space it needs
                                            Label {
                                                text: trackData.title || "Unknown Track"
                                                color: Theme.primaryText
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                                Layout.fillWidth: false
                                                Layout.preferredWidth: implicitWidth
                                                Layout.maximumWidth: parent.width * 0.7 // Max 70% to leave room for artist
                                            }
                                            
                                            // Artist name - gets remaining space, truncated as needed
                                            Label {
                                                text: trackData.artist || "Unknown Artist"
                                                color: Theme.tertiaryText
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignRight
                                                horizontalAlignment: Text.AlignRight
                                            }
                                        }
                                    }

                                    // Now Playing Indicator
                                    Image {
                                        source: Theme.isDark ? "qrc:/resources/icons/speaker.svg" : "qrc:/resources/icons/speaker-dark.svg"
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        sourceSize.width: 32  // 2x for retina
                                        sourceSize.height: 32
                                        visible: MediaPlayer.currentTrack && 
                                                MediaPlayer.currentTrack.filePath === trackData.filePath &&
                                                MediaPlayer.state === MediaPlayer.PlayingState &&
                                                !root.playlistEditMode
                                        opacity: 0.9
                                    }

                                    Label { // Track Duration
                                        text: trackData.duration ? formatDuration(trackData.duration) : "0:00"
                                        color: Theme.tertiaryText
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 40
                                        visible: !root.playlistEditMode
                                    }
                                    
                                    // Delete button (only in edit mode for playlists)
                                    Rectangle {
                                        id: deleteButton
                                        width: 28
                                        height: 28
                                        radius: 4
                                        color: deleteTrackMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                                        visible: root.playlistEditMode && root.selectedAlbum && root.selectedAlbum.isPlaylist && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title) && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title) && (trackDelegate.isHovered || deleteTrackMouseArea.containsMouse)
                                        opacity: visible ? 1.0 : 0.0
                                        
                                        Behavior on opacity {
                                            NumberAnimation { duration: 150 }
                                        }
                                        
                                        Item {
                                            anchors.centerIn: parent
                                            width: 16
                                            height: 16
                                            
                                            Image {
                                                id: closedLidIcon
                                                anchors.fill: parent
                                                source: Theme.isDark ? "qrc:/resources/icons/trash-can-closed-lid.svg" : "qrc:/resources/icons/trash-can-closed-lid-dark.svg"
                                                sourceSize.width: 32
                                                sourceSize.height: 32
                                                opacity: deleteTrackMouseArea.containsMouse ? 0 : 1
                                                
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 150 }
                                                }
                                            }
                                            
                                            Image {
                                                id: openLidIcon
                                                anchors.fill: parent
                                                source: Theme.isDark ? "qrc:/resources/icons/trash-can-open-lid.svg" : "qrc:/resources/icons/trash-can-open-lid-dark.svg"
                                                sourceSize.width: 32
                                                sourceSize.height: 32
                                                opacity: deleteTrackMouseArea.containsMouse ? 1 : 0
                                                
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 150 }
                                                }
                                            }
                                        }
                                        
                                        MouseArea {
                                            id: deleteTrackMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                // Capture the ListView reference to avoid reference errors
                                                var listView = trackListView
                                                
                                                // Use Qt.callLater to ensure proper timing
                                                Qt.callLater(function() {
                                                    // Save the current scroll position
                                                    var currentContentY = listView.contentY
                                                    
                                                    // Remove track from edited list
                                                    root.editedPlaylistTracks.splice(index, 1)
                                                    // Update the view
                                                    rightPane.currentAlbumTracks = root.editedPlaylistTracks.slice()
                                                    
                                                    // Immediately restore the scroll position
                                                    listView.contentY = currentContentY
                                                })
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    id: trackMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    enabled: !root.playlistEditMode // Disable in edit mode to allow drag/delete
                                    
                                    onClicked: function(mouse) {
                                        // Ensure the library pane has focus for keyboard navigation
                                        root.forceActiveFocus();
                                        
                                        if (mouse.button === Qt.LeftButton) {
                                            if (mouse.modifiers & Qt.ControlModifier) {
                                                // Ctrl+Click: Toggle selection
                                                var idx = root.selectedTrackIndices.indexOf(index);
                                                if (idx !== -1) {
                                                    // Remove from selection
                                                    root.selectedTrackIndices.splice(idx, 1);
                                                } else {
                                                    // Add to selection
                                                    root.selectedTrackIndices.push(index);
                                                }
                                                root.selectedTrackIndices = root.selectedTrackIndices.slice(); // Force update
                                                root.lastSelectedIndex = index;
                                            } else if (mouse.modifiers & Qt.ShiftModifier && root.lastSelectedIndex !== -1) {
                                                // Shift+Click: Select range
                                                root.selectedTrackIndices = [];
                                                var start = Math.min(root.lastSelectedIndex, index);
                                                var end = Math.max(root.lastSelectedIndex, index);
                                                for (var i = start; i <= end; i++) {
                                                    root.selectedTrackIndices.push(i);
                                                }
                                                root.selectedTrackIndices = root.selectedTrackIndices.slice(); // Force update
                                            } else {
                                                // Regular click: Select only this track
                                                root.selectedTrackIndices = [index];
                                                root.lastSelectedIndex = index;
                                            }
                                            
                                            trackListView.currentIndex = index;
                                            // Sync keyboard navigation state
                                            root.navigationMode = "track";
                                            root.selectedTrackIndex = index;
                                            // Update track info panel if visible
                                            if (root.showTrackInfoPanel && root.selectedTrackIndices.length === 1) {
                                                root.selectedTrackForInfo = trackData;
                                            }
                                        } else if (mouse.button === Qt.RightButton) {
                                            // If right-clicking on an unselected track, select it first
                                            if (root.selectedTrackIndices.indexOf(index) === -1) {
                                                root.selectedTrackIndices = [index];
                                                root.lastSelectedIndex = index;
                                                trackListView.currentIndex = index;
                                            }
                                            // Show context menu
                                            trackContextMenu.popup();
                                        }
                                    }
                                    onDoubleClicked: function(mouse) {
                                        // Check if this is a virtual playlist
                                        if (root.selectedAlbum && root.selectedAlbum.isVirtualPlaylist) {
                                            // For virtual playlists, use the virtual playlist model
                                            MediaPlayer.clearQueue()
                                            MediaPlayer.loadVirtualPlaylist(root.selectedAlbum.virtualModel)
                                            MediaPlayer.playTrackAt(index)
                                        } else if (root.selectedAlbum && root.selectedAlbum.isPlaylist) {
                                            // For regular playlists, use the same approach as albums
                                            var globalPos = trackDelegate.mapToGlobal(mouse.x, mouse.y);
                                            root.playPlaylistWithQueueCheck(root.selectedAlbum.title, false, index, 
                                                                          globalPos.x, globalPos.y);
                                        } else if (root.selectedAlbum) {
                                            // Regular album - use the existing method
                                            var globalPos = trackDelegate.mapToGlobal(mouse.x, mouse.y);
                                            root.playAlbumWithQueueCheck(root.selectedAlbum.albumArtist, root.selectedAlbum.title, index, 
                                                                        globalPos.x, globalPos.y);
                                        } else {
                                            // Single track
                                            MediaPlayer.playTrackFromData(trackData);
                                        }
                                    }
                                    
                                    StyledMenu {
                                        id: trackContextMenu
                                        
                                        StyledMenuItem {
                                            text: root.selectedTrackIndices.length > 1 ? 
                                                  "Play " + root.selectedTrackIndices.length + " Tracks Next" : 
                                                  "Play Next"
                                            onTriggered: {
                                                if (root.selectedAlbum && root.selectedAlbum.isVirtualPlaylist) {
                                                    // For virtual playlists, we need to get track data from the model
                                                    if (root.selectedTrackIndices.length > 1) {
                                                        // Add all selected tracks in order
                                                        var indices = root.selectedTrackIndices.slice().sort(function(a, b) { return a - b; });
                                                        for (var i = 0; i < indices.length; i++) {
                                                            var track = root.selectedAlbum.virtualModel.getTrack(indices[i]);
                                                            if (track) MediaPlayer.playTrackNext(track);
                                                        }
                                                    } else {
                                                        MediaPlayer.playTrackNext(trackData);
                                                    }
                                                } else {
                                                    if (root.selectedTrackIndices.length > 1) {
                                                        // Add all selected tracks in order
                                                        var indices = root.selectedTrackIndices.slice().sort(function(a, b) { return a - b; });
                                                        for (var i = 0; i < indices.length; i++) {
                                                            MediaPlayer.playTrackNext(rightPane.currentAlbumTracks[indices[i]]);
                                                        }
                                                    } else {
                                                        MediaPlayer.playTrackNext(trackData);
                                                    }
                                                }
                                            }
                                        }
                                        
                                        StyledMenuItem {
                                            text: root.selectedTrackIndices.length > 1 ? 
                                                  "Play " + root.selectedTrackIndices.length + " Tracks Last" : 
                                                  "Play Last"
                                            onTriggered: {
                                                if (root.selectedAlbum && root.selectedAlbum.isVirtualPlaylist) {
                                                    // For virtual playlists, we need to get track data from the model
                                                    if (root.selectedTrackIndices.length > 1) {
                                                        // Add all selected tracks in order
                                                        var indices = root.selectedTrackIndices.slice().sort(function(a, b) { return a - b; });
                                                        for (var i = 0; i < indices.length; i++) {
                                                            var track = root.selectedAlbum.virtualModel.getTrack(indices[i]);
                                                            if (track) MediaPlayer.playTrackLast(track);
                                                        }
                                                    } else {
                                                        MediaPlayer.playTrackLast(trackData);
                                                    }
                                                } else {
                                                    if (root.selectedTrackIndices.length > 1) {
                                                        // Add all selected tracks in order
                                                        var indices = root.selectedTrackIndices.slice().sort(function(a, b) { return a - b; });
                                                        for (var i = 0; i < indices.length; i++) {
                                                            MediaPlayer.playTrackLast(rightPane.currentAlbumTracks[indices[i]]);
                                                        }
                                                    } else {
                                                        MediaPlayer.playTrackLast(trackData);
                                                    }
                                                }
                                            }
                                        }
                                        
                                        StyledMenuSeparator { 
                                            visible: root.selectedTrackIndices.length === 1
                                            height: visible ? implicitHeight : 0
                                        }
                                        
                                        StyledMenuItem {
                                            text: "Show info"
                                            visible: root.selectedTrackIndices.length === 1
                                            height: visible ? implicitHeight : 0
                                            onTriggered: {
                                                // Select the track first
                                                trackListView.currentIndex = index;
                                                root.selectedTrackForInfo = trackData;
                                                root.showTrackInfoPanel = true;
                                            }
                                        }
                                    }
                                }
                                
                                // Hover effect
                                states: State {
                                    when: trackMouseArea.containsMouse && root.selectedTrackIndex !== index && root.selectedTrackIndices.indexOf(index) === -1
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
                    
                    // Add track button/selector (shown in playlist edit mode)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: {
                            if (!root.playlistEditMode || !root.selectedAlbum || !root.selectedAlbum.isPlaylist || PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title)) {
                                return 0
                            }
                            if (root.showTrackSelector) {
                                // Calculate height based on search results
                                var baseHeight = 52 // Header with toggle button and search bar
                                var resultsHeight = root.trackSelectorResults.length > 0 
                                    ? Math.min(root.trackSelectorResults.length * 60, 300) + 16 // Max 5 results visible, plus more padding
                                    : 50 // Height for "Type to search" message
                                return baseHeight + resultsHeight
                            } else {
                                return 52
                            }
                        }
                        Layout.topMargin: root.playlistEditMode && root.selectedAlbum && root.selectedAlbum.isPlaylist && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title) ? 8 : 0
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.20) // Background color for the track selector
                        radius: 6
                        visible: root.playlistEditMode && root.selectedAlbum && root.selectedAlbum.isPlaylist && !PlaylistManager.isSpecialPlaylist(root.selectedAlbum.title)
                        clip: true
                        
                        Behavior on Layout.preferredHeight {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            
                            // Header with toggle button and search bar
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                Layout.topMargin: 8
                                Layout.bottomMargin: 8
                                spacing: 8
                                
                                // Spacer when collapsed
                                Item {
                                    Layout.fillWidth: true
                                    visible: !root.showTrackSelector
                                }
                                
                                // Search bar (visible when expanded)
                                SearchBar {
                                    id: trackSelectorSearchBar
                                    Layout.fillWidth: true
                                    visible: root.showTrackSelector
                                    opacity: visible ? 1.0 : 0.0
                                    text: root.trackSelectorSearchTerm
                                    placeholderText: "Search for tracks to add..."
                                    
                                    Behavior on opacity {
                                        NumberAnimation { duration: 150 }
                                    }
                                    
                                    onTextChanged: {
                                        root.trackSelectorSearchTerm = text
                                    }
                                    
                                    onSearchRequested: {
                                        root.performTrackSearch()
                                    }
                                    
                                    onClearRequested: {
                                        root.trackSelectorSearchTerm = ""
                                        root.trackSelectorResults = []
                                    }
                                }
                                
                                // Toggle button using cancel.svg icon
                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 4
                                    color: {
                                        if (toggleButtonMouseArea.containsMouse) {
                                            return root.showTrackSelector ? Qt.rgba(1, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.15)
                                        }
                                        return Qt.rgba(1, 1, 1, 0.08)
                                    }
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    
                                    Image {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        source: Theme.isDark ? "qrc:/resources/icons/cancel.svg" : "qrc:/resources/icons/cancel-dark.svg"
                                        sourceSize.width: 36
                                        sourceSize.height: 36
                                        rotation: root.showTrackSelector ? 0 : -45  // 45 degrees for plus sign
                                        
                                        Behavior on rotation {
                                            NumberAnimation { duration: 150 }
                                        }
                                    }
                                    
                                    MouseArea {
                                        id: toggleButtonMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.showTrackSelector) {
                                                // Close
                                                root.showTrackSelector = false
                                                // Don't clear data immediately - let it fade out with the animation
                                            } else {
                                                // Open
                                                root.showTrackSelector = true
                                                root.trackSelectorSearchTerm = ""
                                                root.trackSelectorResults = []
                                                trackSelectorSearchBar.forceActiveFocus()
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Search results
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                Layout.bottomMargin: 8
                                model: root.trackSelectorResults
                                spacing: 4
                                clip: true
                                visible: root.showTrackSelector && root.trackSelectorResults.length > 0
                                
                                ScrollIndicator.vertical: ScrollIndicator { }
                                
                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 56
                                    color: trackItemMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                                    radius: 4
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                    
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 12
                                        
                                        // Track info
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.title || "Unknown Title"
                                                font.pixelSize: 14
                                                font.weight: Font.Medium
                                                color: Theme.primaryText
                                                elide: Text.ElideRight
                                            }
                                            
                                            Label {
                                                Layout.fillWidth: true
                                                text: {
                                                    var artist = modelData.artist || "Unknown Artist"
                                                    var album = modelData.album || "Unknown Album"
                                                    return artist + " - " + album
                                                }
                                                font.pixelSize: 12
                                                color: Theme.tertiaryText
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                        
                                        // Add button with green hover
                                        Rectangle {
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 32
                                            radius: 4
                                            color: addResultMouseArea.containsMouse ? Qt.rgba(0, 1, 0, 0.3) : Qt.rgba(1, 1, 1, 0.1)
                                            
                                            Behavior on color {
                                                ColorAnimation { duration: 150 }
                                            }
                                            
                                            Image {
                                                anchors.centerIn: parent
                                                width: 16
                                                height: 16
                                                source: Theme.isDark ? "qrc:/resources/icons/add.svg" : "qrc:/resources/icons/add-dark.svg"
                                                sourceSize.width: 32
                                                sourceSize.height: 32
                                            }
                                            
                                            MouseArea {
                                                id: addResultMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    // Add track to playlist
                                                    if (!root.editedPlaylistTracks) {
                                                        root.editedPlaylistTracks = []
                                                    }
                                                    root.editedPlaylistTracks.push(modelData)
                                                    
                                                    // Update the view immediately so the track is visible
                                                    rightPane.currentAlbumTracks = root.editedPlaylistTracks.slice()
                                                    // The rightPane's onCurrentAlbumTracksChanged will handle scrolling
                                                    
                                                    // Keep the selector open for adding more tracks
                                                    // Only clear the search term to show they can search for more
                                                    root.trackSelectorSearchTerm = ""
                                                    root.trackSelectorResults = []
                                                }
                                            }
                                        }
                                    }
                                    
                                    MouseArea {
                                        id: trackItemMouseArea
                                        anchors.fill: parent
                                        anchors.rightMargin: 44  // Leave space for the add button
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }
                                }
                            }
                            
                            // Empty state when searching
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredHeight: 50
                                visible: root.trackSelectorResults.length === 0
                                opacity: root.showTrackSelector ? 1.0 : 0.0
                                
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.InOutCubic
                                    }
                                }
                                
                                Label {
                                    anchors.centerIn: parent
                                    text: root.trackSelectorSearchTerm.trim().length > 0 ? "No tracks found" : "Type to search for tracks"
                                    color: Theme.tertiaryText
                                    font.pixelSize: 14
                                }
                            }
                        }
                    }
                    
                    // Track info panel
                    Rectangle {
                        id: trackInfoPanel
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.showTrackInfoPanel && root.trackInfoPanelY < 10 ? 180 : 0
                        Layout.topMargin: root.showTrackInfoPanel && root.trackInfoPanelY < 10 ? 4 : 0
                        Layout.leftMargin: root.showTrackInfoPanel && root.trackInfoPanelY < 10 ? 4 : 0
                        Layout.rightMargin: root.showTrackInfoPanel && root.trackInfoPanelY < 10 ? 4 : 0
                        Layout.bottomMargin: root.showTrackInfoPanel && root.trackInfoPanelY < 10 ? 4 : 0
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.25) // Track info panel background
                        radius: 6
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        clip: true
                        visible: root.showTrackInfoPanel || root.trackInfoPanelAnimating
                        opacity: root.showTrackInfoPanel && root.trackInfoPanelY < 10 ? 1 : 0
                        
                        // Transform for slide animation
                        transform: Translate {
                            y: root.trackInfoPanelY
                        }
                        
                        // Smooth transitions for layout changes
                        Behavior on Layout.preferredHeight {
                            enabled: !root.trackInfoPanelAnimating
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }
                        
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                        
                        // States for shown/hidden
                        states: [
                            State {
                                name: "shown"
                                when: root.showTrackInfoPanel
                                PropertyChanges {
                                    target: root
                                    trackInfoPanelY: 0
                                }
                            },
                            State {
                                name: "hidden"
                                when: !root.showTrackInfoPanel
                                PropertyChanges {
                                    target: root
                                    trackInfoPanelY: 184  // Full height + margins to hide below
                                }
                            }
                        ]
                        
                        // Smooth transition between states
                        transitions: Transition {
                            from: "*"
                            to: "*"
                            SequentialAnimation {
                                PropertyAction {
                                    target: root
                                    property: "trackInfoPanelAnimating"
                                    value: true
                                }
                                NumberAnimation {
                                    target: root
                                    property: "trackInfoPanelY"
                                    duration: 300
                                    easing.type: Easing.OutCubic
                                }
                                PropertyAction {
                                    target: root
                                    property: "trackInfoPanelAnimating"
                                    value: false
                                }
                            }
                        }
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4
                            
                            // Header with title and close button
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 16
                                spacing: 8
                                
                                // Scrolling track title
                                Flickable {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 16
                                    contentHeight: height
                                    interactive: false
                                    clip: true
                                    
                                    // MouseArea to detect hover over the title text
                                    MouseArea {
                                        id: titleHoverArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        property bool animationRunning: false
                                        
                                        onEntered: {
                                            // Start animation on hover if text needs scrolling
                                            if (titleRow.needsScrolling && titleRow.titleText !== "") {
                                                titleRow.startHoverAnimation()
                                            }
                                        }
                                        
                                        onExited: {
                                            // Let current cycle complete, then stop
                                            animationRunning = false
                                        }
                                    }
                                    
                                    // Container for the label with opacity mask
                                    Item {
                                        id: titleLabelContainer
                                        anchors.fill: parent
                                        
                                        // Row containing duplicated text for seamless scrolling
                                        Row {
                                            id: titleRow
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 60  // Gap between duplicates
                                            
                                            // Properties for scrolling
                                            property string titleText: root.selectedTrackForInfo ? (root.selectedTrackForInfo.title || "Unknown") : ""
                                            property bool needsScrolling: titleLabel1.contentWidth > titleLabelContainer.width
                                            property real scrollOffset: 0
                                            property real scrollDuration: Math.max(4000, titleLabel1.contentWidth * 20)  // Speed based on text length
                                            // Function to start hover-based animation
                                            function startHoverAnimation() {
                                                scrollOffset = 0
                                                titleHoverArea.animationRunning = true
                                                titleScrollAnimation.loops = 1  // Run once
                                                titleScrollAnimation.start()
                                            }
                                            
                                            // Position for scrolling
                                            x: needsScrolling ? -scrollOffset : 0
                                            
                                            // Update scrolling when text changes
                                            onTitleTextChanged: {
                                                scrollOffset = 0
                                                titleScrollAnimation.stop()
                                                // Don't auto-start anymore, wait for hover
                                            }
                                            
                                            onNeedsScrollingChanged: {
                                                scrollOffset = 0
                                                titleScrollAnimation.stop()
                                                // Don't auto-start anymore, wait for hover
                                            }
                                            
                                            // First copy of the text
                                            Label {
                                                id: titleLabel1
                                                text: parent.titleText
                                                color: Theme.primaryText
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                            
                                            // Second copy for seamless wrap-around (only visible when scrolling)
                                            Label {
                                                text: parent.titleText
                                                color: Theme.primaryText
                                                font.pixelSize: 12
                                                font.bold: true
                                                visible: parent.needsScrolling
                                            }
                                            
                                            // Scrolling animation (controlled by hover)
                                            SequentialAnimation {
                                                id: titleScrollAnimation
                                                loops: 1  // Default to single loop, changed when hovering
                                                
                                                onStopped: {
                                                    // When animation completes, check if we should continue
                                                    if (titleHoverArea.containsMouse && titleHoverArea.animationRunning) {
                                                        // Mouse is still hovering, run another cycle
                                                        loops = 1
                                                        start()
                                                    } else {
                                                        // Reset for next hover
                                                        titleRow.scrollOffset = 0
                                                        titleHoverArea.animationRunning = false
                                                    }
                                                }
                                                
                                                // Scroll continuously to show second copy
                                                NumberAnimation {
                                                    target: titleRow
                                                    property: "scrollOffset"
                                                    from: 0
                                                    to: titleLabel1.contentWidth + titleRow.spacing  // Scroll one full text width + gap
                                                    duration: titleRow.scrollDuration
                                                    easing.type: Easing.InOutQuad
                                                }
                                                
                                                // Instant reset to beginning (seamless wrap)
                                                PropertyAction {
                                                    target: titleRow
                                                    property: "scrollOffset"
                                                    value: 0
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Close button
                                Rectangle {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    color: closeButtonMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                    radius: 3
                                    
                                    Image {
                                        anchors.centerIn: parent
                                        width: 12
                                        height: 12
                                        source: Theme.isDark ? "qrc:/resources/icons/close-button.svg" : "qrc:/resources/icons/close-button-dark.svg"
                                        sourceSize.width: 24
                                        sourceSize.height: 24
                                        smooth: true
                                        antialiasing: true
                                    }
                                    
                                    MouseArea {
                                        id: closeButtonMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.showTrackInfoPanel = false
                                    }
                                }
                            }
                            
                            // Separator line
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }
                            
                            // Content area
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 2
                                    
                                    // Full-width section for Artist, Album, Album Artist
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        
                                        // Artist
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Label {
                                                text: "Artist:"
                                                color: Theme.secondaryText
                                                font.pixelSize: 10
                                                Layout.preferredWidth: 80
                                            }
                                            Label {
                                                text: root.selectedTrackForInfo ? (root.selectedTrackForInfo.artist || "Unknown") : ""
                                                color: Theme.primaryText
                                                font.pixelSize: 10
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        
                                        // Album
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Label {
                                                text: "Album:"
                                                color: Theme.secondaryText
                                                font.pixelSize: 10
                                                Layout.preferredWidth: 80
                                            }
                                            Label {
                                                text: root.selectedTrackForInfo ? (root.selectedTrackForInfo.album || "Unknown") : ""
                                                color: Theme.primaryText
                                                font.pixelSize: 10
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        
                                        // Album Artist
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Label {
                                                text: "Album Artist:"
                                                color: Theme.secondaryText
                                                font.pixelSize: 10
                                                Layout.preferredWidth: 80
                                            }
                                            Label {
                                                text: root.selectedTrackForInfo ? (root.selectedTrackForInfo.albumArtist || root.selectedTrackForInfo.artist || "Unknown") : ""
                                                color: Theme.primaryText
                                                font.pixelSize: 10
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    
                                    // Separator between full-width and two-column sections
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                        Layout.topMargin: 4
                                        Layout.bottomMargin: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                    }
                                    
                                    // Two-column section
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 16
                                        
                                        // Left column: Track, Year, Genre
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            
                                            // Track Number
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label {
                                                    text: "Track:"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    Layout.preferredWidth: 50
                                                }
                                                Label {
                                                    text: {
                                                        if (!root.selectedTrackForInfo) return ""
                                                        var trackNum = root.selectedTrackForInfo.trackNumber || 0
                                                        var discNum = root.selectedTrackForInfo.discNumber || 0
                                                        if (discNum > 1) {
                                                            return trackNum + " (Disc " + discNum + ")"
                                                        } else if (trackNum > 0) {
                                                            return String(trackNum)
                                                        } else {
                                                            return "Unknown"
                                                        }
                                                    }
                                                    color: Theme.primaryText
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            
                                            // Year
                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: root.selectedTrackForInfo && root.selectedTrackForInfo.year > 0
                                                Label {
                                                    text: "Year:"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    Layout.preferredWidth: 50
                                                }
                                                Label {
                                                    text: root.selectedTrackForInfo ? (root.selectedTrackForInfo.year || "") : ""
                                                    color: Theme.primaryText
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            
                                            // Genre
                                            RowLayout {
                                                Layout.fillWidth: true
                                                visible: root.selectedTrackForInfo && root.selectedTrackForInfo.genre
                                                Label {
                                                    text: "Genre:"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    Layout.preferredWidth: 50
                                                }
                                                Label {
                                                    text: root.selectedTrackForInfo ? (root.selectedTrackForInfo.genre || "") : ""
                                                    color: Theme.primaryText
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                        
                                        // Right column: Duration, Format, File Size
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            
                                            // Duration
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label {
                                                    text: "Duration:"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    Layout.preferredWidth: 60
                                                }
                                                Label {
                                                    text: root.selectedTrackForInfo ? formatDuration(root.selectedTrackForInfo.duration || 0) : ""
                                                    color: Theme.primaryText
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            
                                            // File format (from extension)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label {
                                                    text: "Format:"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    Layout.preferredWidth: 60
                                                }
                                                Label {
                                                    text: {
                                                        if (!root.selectedTrackForInfo || !root.selectedTrackForInfo.filePath) return ""
                                                        var path = root.selectedTrackForInfo.filePath
                                                        var lastDot = path.lastIndexOf('.')
                                                        if (lastDot > 0 && lastDot < path.length - 1) {
                                                            return path.substring(lastDot + 1).toUpperCase()
                                                        }
                                                        return "Unknown"
                                                    }
                                                    color: Theme.primaryText
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            
                                            // File size
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label {
                                                    text: "File Size:"
                                                    color: Theme.secondaryText
                                                    font.pixelSize: 10
                                                    Layout.preferredWidth: 60
                                                }
                                                Label {
                                                    text: root.selectedTrackForInfo ? formatFileSize(root.selectedTrackForInfo.fileSize || 0) : ""
                                                    color: Theme.primaryText
                                                    font.pixelSize: 10
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Separator before file path
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                        Layout.topMargin: 4
                                        Layout.bottomMargin: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                    }
                                    
                                    // Full-width file path section
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            text: "File Path:"
                                            color: Theme.secondaryText
                                            font.pixelSize: 10
                                            Layout.preferredWidth: 80
                                        }
                                        
                                        // Scrolling file path container
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 20  // Increased height to prevent text clipping
                                            clip: true
                                            
                                            // MouseArea to detect hover over the file path text
                                            MouseArea {
                                                id: pathHoverArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                property bool animationRunning: false
                                                
                                                onEntered: {
                                                    // Start animation on hover if text needs scrolling
                                                    if (filePathRow.needsScrolling && filePathRow.pathText !== "") {
                                                        filePathRow.startHoverAnimation()
                                                    }
                                                }
                                                
                                                onExited: {
                                                    // Let current cycle complete, then stop
                                                    animationRunning = false
                                                }
                                            }
                                            
                                            // Container for the label with opacity mask
                                            Item {
                                                id: labelContainer
                                                anchors.fill: parent
                                                
                                                // Row containing duplicated text for seamless scrolling
                                                Row {
                                                    id: filePathRow
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 60  // Gap between duplicates
                                                    
                                                    // Properties for scrolling
                                                    property string pathText: root.selectedTrackForInfo ? (root.selectedTrackForInfo.filePath || "") : ""
                                                    property bool needsScrolling: filePathLabel1.contentWidth > labelContainer.width
                                                    property real scrollOffset: 0
                                                    property real scrollDuration: Math.max(4000, filePathLabel1.contentWidth * 20)  // Speed based on text length
                                                    // Function to start hover-based animation
                                                    function startHoverAnimation() {
                                                        scrollOffset = 0
                                                        pathHoverArea.animationRunning = true
                                                        pathScrollAnimation.loops = 1  // Run once
                                                        pathScrollAnimation.start()
                                                    }
                                                    
                                                    // Position for scrolling
                                                    x: needsScrolling ? -scrollOffset : 0
                                                    
                                                    // Update scrolling when text changes
                                                    onPathTextChanged: {
                                                        scrollOffset = 0
                                                        pathScrollAnimation.stop()
                                                        // Don't auto-start anymore, wait for hover
                                                    }
                                                    
                                                    onNeedsScrollingChanged: {
                                                        scrollOffset = 0
                                                        pathScrollAnimation.stop()
                                                        // Don't auto-start anymore, wait for hover
                                                    }
                                                    
                                                    // First copy of the text
                                                    Label {
                                                        id: filePathLabel1
                                                        text: parent.pathText
                                                        color: Theme.primaryText
                                                        font.pixelSize: 10
                                                    }
                                                    
                                                    // Second copy for seamless wrap-around (only visible when scrolling)
                                                    Label {
                                                        text: parent.pathText
                                                        color: Theme.primaryText
                                                        font.pixelSize: 10
                                                        visible: parent.needsScrolling
                                                    }
                                                    
                                                    // Scrolling animation (controlled by hover)
                                                    SequentialAnimation {
                                                        id: pathScrollAnimation
                                                        loops: 1  // Default to single loop, changed when hovering
                                                        
                                                        onStopped: {
                                                            // When animation completes, check if we should continue
                                                            if (pathHoverArea.containsMouse && pathHoverArea.animationRunning) {
                                                                // Mouse is still hovering, run another cycle
                                                                loops = 1
                                                                start()
                                                            } else {
                                                                // Reset for next hover
                                                                filePathRow.scrollOffset = 0
                                                                pathHoverArea.animationRunning = false
                                                            }
                                                        }
                                                        
                                                        // Scroll continuously to show second copy
                                                        NumberAnimation {
                                                            target: filePathRow
                                                            property: "scrollOffset"
                                                            from: 0
                                                            to: filePathLabel1.contentWidth + filePathRow.spacing  // Scroll one full text width + gap
                                                            duration: filePathRow.scrollDuration
                                                            easing.type: Easing.InOutQuad
                                                        }
                                                        
                                                        // Instant reset to beginning (seamless wrap)
                                                        PropertyAction {
                                                            target: filePathRow
                                                            property: "scrollOffset"
                                                            value: 0
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Spacer at bottom
                                    Item {
                                        Layout.fillHeight: true
                                    }
                                }
                            }
                        }
                    }
                    

                    // Message for when no tracks are available or no album selected
                    Label {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: rightPane.selectedAlbum ? "No tracks found for this album." : "Select an album to view tracks."
                        color: Theme.tertiaryText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        visible: rightPane.currentAlbumTracks.length === 0 && !(root.selectedAlbum && root.selectedAlbum.isVirtualPlaylist)
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
    
    function formatFileSize(bytes) {
        if (!bytes || bytes === 0) return "0 B";
        var units = ['B', 'KB', 'MB', 'GB'];
        var index = 0;
        var size = bytes;
        while (size >= 1024 && index < units.length - 1) {
            size /= 1024;
            index++;
        }
        return size.toFixed(index === 0 ? 0 : 1) + " " + units[index];
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
    
    function restoreSelectedAlbum(albumIdStr) {
        try {
            var albumId = parseInt(albumIdStr)
            if (isNaN(albumId)) return
            
            // Use O(1) lookup from album ID map
            var albumIndex = albumIdToIndexMap[albumId]
            if (albumIndex !== undefined) {
                var album = LibraryManager.albumModel[albumIndex]
                if (!album) return
                
                // If it's a playlist, switch to playlist tab
                if (album.isPlaylist) {
                    currentTab = 1
                    // TODO: Select the playlist in playlist view
                    return
                }
                
                // For regular albums, expand the artist and select the album
                if (album.albumArtist) {
                    // Expand the artist
                    var updatedExpanded = Object.assign({}, expandedArtists)
                    updatedExpanded[album.albumArtist] = true
                    expandedArtists = updatedExpanded
                    
                    // Select the album
                    selectedAlbum = album
                    
                    // Jump to the album in the browser
                    Qt.callLater(function() {
                        albumBrowser.jumpToAlbum(album)
                    })
                }
            }
        } catch (error) {
            console.warn("Error restoring selected album:", error)
        }
    }
    
    function restoreSelectedPlaylist(playlistName) {
        try {
            if (!playlistName) return
            
            // Switch to playlist tab
            currentTab = 1
            
            // Get playlists from PlaylistManager
            var playlists = PlaylistManager.playlists
            
            // Find the playlist with matching name
            for (var i = 0; i < playlists.length; i++) {
                if (playlists[i] === playlistName) {
                    // Create a playlist album object
                    var playlistAlbum = {
                        title: playlistName,
                        albumArtist: "Playlist",
                        artist: "Playlist",
                        year: 0,
                        trackCount: PlaylistManager.getPlaylistTrackCount(playlistName),
                        genre: "",
                        coverArtUrl: "",
                        hasArt: false,
                        isPlaylist: true
                    }
                    
                    // Select the playlist
                    selectedAlbum = playlistAlbum
                    
                    // Select it in the playlist view if it exists
                    if (playlistView) {
                        Qt.callLater(function() {
                            playlistView.selectPlaylist(playlistName)
                        })
                    }
                    
                    break
                }
            }
        } catch (error) {
            console.warn("Error restoring selected playlist:", error)
        }
    }
    
    function performSearch(searchTerm) {
        if (searchTerm.trim().length === 0) {
            clearSearch()
            return
        }
        
        // Switch to Artists tab when searching (search is not supported for playlists)
        if (currentTab === 1) {
            currentTab = 0
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
        // Don't disrupt active navigation
        var isNavigating = navigationMode !== "none"
        
        if (matchType === "artist") {
            // Highlight the artist
            highlightedArtist = bestMatch.name
            
            // Only scroll and expand if not actively navigating
            if (!isNavigating) {
                // Check if already expanded
                if (expandedArtists[bestMatch.name]) {
                    // Already expanded, safe to scroll immediately
                    scrollToArtist(bestMatch.name)
                } else {
                    // Disable animations for expansion
                    isProgrammaticScrolling = true
                    
                    // Expand the artist first
                    var updatedExpanded = Object.assign({}, expandedArtists)
                    updatedExpanded[bestMatch.name] = true
                    expandedArtists = updatedExpanded
                    
                    // Force immediate layout update
                    artistsListView.forceLayout()
                    
                    // Scroll after expansion
                    Qt.callLater(function() {
                        scrollToArtist(bestMatch.name)
                        // Reset flag after animation
                        Qt.callLater(function() {
                            isProgrammaticScrolling = false
                        })
                    })
                }
            }
        } else if (matchType === "album") {
            // Expand the artist to show the album and scroll to it
            var artistName = bestMatch.albumArtist
            if (artistName) {
                highlightedArtist = artistName
                
                // Select the album
                selectedAlbum = bestMatch
                
                // Only scroll and expand if not actively navigating
                if (!isNavigating) {
                    // Check if already expanded
                    if (expandedArtists[artistName]) {
                        // Already expanded, safe to scroll immediately
                        scrollToArtist(artistName)
                    } else {
                        // Disable animations for expansion
                        isProgrammaticScrolling = true
                        
                        // Expand the artist first
                        var updatedExpanded = Object.assign({}, expandedArtists)
                        updatedExpanded[artistName] = true
                        expandedArtists = updatedExpanded
                        
                        // Force immediate layout update
                        artistsListView.forceLayout()
                        
                        // Scroll after expansion
                        Qt.callLater(function() {
                            scrollToArtist(artistName)
                            // Reset flag after animation
                            Qt.callLater(function() {
                                isProgrammaticScrolling = false
                            })
                        })
                    }
                }
            }
        } else if (matchType === "track") {
            // Find the album and artist for this track and expand
            if (bestMatch.album && bestMatch.artist) {
                highlightedArtist = bestMatch.artist
                
                // Try to find and select the album
                // Ensure album cache is populated
                if (!artistAlbumCache[bestMatch.artist]) {
                    updateAlbumCacheForArtist(bestMatch.artist)
                }
                
                // Use O(1) lookup from cache
                var albumMap = artistAlbumCache[bestMatch.artist]
                if (albumMap && albumMap[bestMatch.album]) {
                    selectedAlbum = albumMap[bestMatch.album]
                }
                
                // Only scroll and expand if not actively navigating
                if (!isNavigating) {
                    // Check if already expanded
                    if (expandedArtists[bestMatch.artist]) {
                        // Already expanded, safe to scroll immediately
                        scrollToArtist(bestMatch.artist)
                        // Select the track after scrolling
                        Qt.callLater(function() {
                            selectTrackByMatch(bestMatch)
                        })
                    } else {
                        // Disable animations for expansion
                        isProgrammaticScrolling = true
                        
                        // Expand the artist
                        var updatedExpanded = Object.assign({}, expandedArtists)
                        updatedExpanded[bestMatch.artist] = true
                        expandedArtists = updatedExpanded
                        
                        // Force immediate layout update
                        artistsListView.forceLayout()
                        
                        // Scroll after expansion
                        Qt.callLater(function() {
                            scrollToArtist(bestMatch.artist)
                            // Reset flag after animation
                            Qt.callLater(function() {
                                isProgrammaticScrolling = false
                                // After scrolling completes and album is selected, select the track
                                Qt.callLater(function() {
                                    selectTrackByMatch(bestMatch)
                                })
                            })
                        })
                    }
                }
            }
        }
    }
    
    function scrollToArtist(artistName) {
        // Use O(1) lookup instead of O(n) search
        var artistIndex = artistNameToIndex[artistName]
        if (artistIndex !== undefined) {
            scrollToArtistIndex(artistIndex, true)
        }
    }
    
    // Helper function to calculate artist position manually
    function calculateArtistPosition(index) {
        console.log("calculateArtistPosition called for index:", index)
        if (index < 0 || index >= LibraryManager.artistModel.length) return -1
        
        var position = 0
        var minCellWidth = 130  // Same as in GridView
        var availableWidth = artistsListView.width - 16  // Same calculation as GridView
        var gridColumns = Math.floor(availableWidth / minCellWidth)
        if (gridColumns < 1) gridColumns = 1
        console.log("calculateArtistPosition: Grid columns:", gridColumns)
        
        for (var i = 0; i < index; i++) {
            var artist = LibraryManager.artistModel[i]
            if (artist) {
                position += 40 // Artist header height
                var isExpanded = expandedArtists[artist.name] === true
                if (isExpanded) {
                    console.log("calculateArtistPosition: Artist", artist.name, "at index", i, "is expanded")
                    var albumCount = 0
                    if (artistAlbumCache[artist.name]) {
                        albumCount = Object.keys(artistAlbumCache[artist.name]).length
                    } else {
                        var albums = LibraryManager.getAlbumsForArtist(artist.name)
                        albumCount = albums ? albums.length : 0
                    }
                    
                    if (albumCount > 0) {
                        var gridRows = Math.ceil(albumCount / gridColumns)
                        // Calculate the actual container height from calculateAlbumContainerHeight logic
                        var containerHeight = (gridRows * 150) + 16  // Grid height + padding
                        position += containerHeight + 2  // Container height + margin
                    }
                }
                position += 2 // Spacing between items (from ListView spacing)
            }
        }
        
        console.log("calculateArtistPosition: Final position for index", index, "is", position)
        return Math.max(0, position) // Return exact position
    }
    
    // Helper function to scroll to an artist index with optional smooth animation
    function scrollToArtistIndex(index, smooth) {
        //console.log("scrollToArtistIndex called with index:", index, "smooth:", smooth)
        if (index < 0 || index >= LibraryManager.artistModel.length) {
            console.log("scrollToArtistIndex: Invalid index")
            return
        }
        
        // Stop any ongoing animation first
        scrollAnimation.running = false
        
        // Update currentIndex to ensure synchronization
        artistsListView.currentIndex = index
        
        // Ensure the ListView has updated its internal state
        artistsListView.forceLayout()
        
        if (smooth) {
            // Store the target index for position verification
            var targetIndex = index
            
            // Force layout update to ensure everything is current
            artistsListView.forceLayout()
            
            // Store current position
            var currentPos = artistsListView.contentY
            
            // Use positionViewAtIndex to position the artist at the top
            artistsListView.positionViewAtIndex(targetIndex, ListView.Beginning)
            var destPos = artistsListView.contentY
            
            //console.log("scrollToArtistIndex: Current:", currentPos, "Destination:", destPos)

            // Only animate if we need to move
            if (Math.abs(destPos - currentPos) > 1) {
                // Restore the current position before animating
                artistsListView.contentY = currentPos
                
                // Configure and start animation
                scrollAnimation.from = currentPos
                scrollAnimation.to = destPos
                scrollAnimation.running = true
                
                // Verify position after animation completes
                scrollAnimation.onRunningChanged.connect(function() {
                    if (!scrollAnimation.running) {
                        // Disconnect this handler
                        scrollAnimation.onRunningChanged.disconnect(arguments.callee)
                        
                        // Verify we're at the correct position after a short delay
                        Qt.callLater(function() {
                            artistsListView.positionViewAtIndex(targetIndex, ListView.Beginning)
                            var finalPos = artistsListView.contentY
                            
                            // If position has drifted, correct it
                            if (Math.abs(artistsListView.contentY - finalPos) > 5) {
                                console.log("scrollToArtistIndex: Position drift detected, correcting from", artistsListView.contentY, "to", finalPos)
                                artistsListView.contentY = finalPos
                            }
                        })
                    }
                })
            }
        } else {
            // Immediate positioning for keyboard navigation
            artistsListView.positionViewAtIndex(index, ListView.Contain)
        }
    }
    
    // Function to auto-select the currently playing track
    function autoSelectCurrentTrack() {
        if (!MediaPlayer.currentTrack || !rightPane || !rightPane.currentAlbumTracks) return
        
        var currentTrack = MediaPlayer.currentTrack
        
        // Use O(1) lookup from file path map
        var trackIndex = root.currentTrackFilePathMap[currentTrack.filePath]
        
        if (trackIndex !== undefined) {
            console.log("Auto-selecting track at index:", trackIndex)
            
            // Update selection
            selectedTrackIndex = trackIndex
            if (trackListView) {
                trackListView.currentIndex = trackIndex
                ensureTrackVisible(trackIndex)
            }
            
            // Update track info panel if visible
            if (root.showTrackInfoPanel && rightPane.currentAlbumTracks[trackIndex]) {
                root.selectedTrackForInfo = rightPane.currentAlbumTracks[trackIndex]
            }
        }
    }
    
    // Helper function to select a track based on search match
    function selectTrackByMatch(trackMatch) {
        if (!trackMatch || !rightPane || !rightPane.currentAlbumTracks) return
        
        // Use O(1) lookup from track index map
        var trackKey = trackMatch.title + "|" + trackMatch.artist
        var trackIndex = root.currentTrackIndexMap[trackKey]
        
        if (trackIndex !== undefined && rightPane.currentAlbumTracks[trackIndex]) {
            selectedTrackIndex = trackIndex
            trackListView.currentIndex = trackIndex
            ensureTrackVisible(trackIndex)
            
            // Update track info panel if visible
            if (root.showTrackInfoPanel) {
                root.selectedTrackForInfo = rightPane.currentAlbumTracks[trackIndex]
            }
        }
    }
    
    // Helper function to ensure track is visible with smooth scrolling
    function ensureTrackVisible(index) {
        if (!trackListView || index < 0 || index >= rightPane.currentAlbumTracks.length) return
        
        // Stop any ongoing animation to prevent stacking
        trackScrollAnimation.running = false
        
        // Get current position
        var currentPos = trackListView.contentY
        
        // Use positionViewAtIndex to calculate where we need to scroll
        // For the last item, use ListView.End to show it at the bottom
        var isLastItem = index === rightPane.currentAlbumTracks.length - 1
        trackListView.positionViewAtIndex(index, isLastItem ? ListView.End : ListView.Contain)
        var destPos = trackListView.contentY
        
        // Only animate if we need to scroll
        if (Math.abs(destPos - currentPos) > 1) {
            // Restore original position
            trackListView.contentY = currentPos
            
            // Animate to destination
            trackScrollAnimation.from = currentPos
            trackScrollAnimation.to = destPos
            trackScrollAnimation.running = true
        }
    }
    
    // Helper function to ensure artist is visible with smooth scrolling (for arrow key navigation)
    function ensureArtistVisible(index) {
        if (!artistsListView || index < 0 || index >= LibraryManager.artistModel.length) return
        
        // First, ensure currentIndex is set
        if (artistsListView.currentIndex !== index) {
            artistsListView.currentIndex = index
        }
        
        // Stop any ongoing animation to prevent stacking
        artistScrollAnimation.running = false
        
        // Force layout to ensure delegates are positioned
        artistsListView.forceLayout()
        
        // Try using ListView's built-in positioning first
        var currentPos = artistsListView.contentY
        var viewportHeight = artistsListView.height
        
        // Use positionViewAtIndex to get the ideal position
        var originalY = artistsListView.contentY
        artistsListView.positionViewAtIndex(index, ListView.Contain)
        var idealPos = artistsListView.contentY
        
        // Check if positionViewAtIndex gave us a valid result
        if (idealPos === 0 && index > 0 && originalY > 0) {
            // Positioning failed, fall back to manual calculation
            artistsListView.contentY = originalY  // Restore position
            idealPos = calculateArtistPosition(index)
            
            // Adjust idealPos to ensure item is visible in viewport
            var itemHeight = 40  // Base height
            var selectedArtist = LibraryManager.artistModel[index]
            if (selectedArtist && expandedArtists[selectedArtist.name]) {
                // Add expanded height
                var albumCount = 0
                if (artistAlbumCache[selectedArtist.name]) {
                    albumCount = Object.keys(artistAlbumCache[selectedArtist.name]).length
                } else {
                    var albums = LibraryManager.getAlbumsForArtist(selectedArtist.name)
                    albumCount = albums ? albums.length : 0
                }
                
                if (albumCount > 0) {
                    var minCellWidth = 130  // Same as in GridView
                    var availableWidth = artistsListView.width - 16  // Same calculation as GridView
                    var gridColumns = Math.floor(availableWidth / minCellWidth)
                    if (gridColumns < 1) gridColumns = 1
                    var gridRows = Math.ceil(albumCount / gridColumns)
                    itemHeight += gridRows * 150 + 20
                }
            }
            
            // Check if we need to adjust for viewport
            var itemTop = idealPos
            var itemBottom = idealPos + itemHeight
            var viewportTop = originalY
            var viewportBottom = originalY + viewportHeight
            
            // Only scroll if item is not fully visible
            if (itemTop < viewportTop) {
                // Item is above viewport
                idealPos = Math.max(0, itemTop - 8)
            } else if (itemBottom > viewportBottom) {
                // Item is below viewport
                idealPos = Math.max(0, itemBottom - viewportHeight + 8)
            } else {
                // Item is already visible, no need to scroll
                return
            }
        } else {
            // Restore original position for animation
            artistsListView.contentY = originalY
        }
        
        // Always animate if position will change (lower threshold)
        if (Math.abs(idealPos - currentPos) > 0.5) {
            artistScrollAnimation.from = currentPos
            artistScrollAnimation.to = idealPos
            artistScrollAnimation.running = true
        } else if (idealPos !== currentPos) {
            // Very small change, just set directly
            artistsListView.contentY = idealPos
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
            // If ListView already has a currentIndex, use that
            if (artistsListView.currentIndex >= 0 && artistsListView.currentIndex < LibraryManager.artistModel.length) {
                selectedArtistIndex = artistsListView.currentIndex
                selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
            } else {
                // Otherwise start at the beginning
                selectedArtistIndex = 0
                selectedArtistName = LibraryManager.artistModel[0].name
                artistsListView.currentIndex = 0
                artistsListView.forceLayout()
                artistsListView.positionViewAtIndex(0, ListView.Beginning)
            }
        }
    }
    
    function setupNavigationFromSearch() {
        resetNavigation()
        if (searchResults.bestMatch && searchResults.bestMatchType === "artist") {
            // Use O(1) lookup instead of O(n) linear search
            var artistIndex = artistNameToIndex[searchResults.bestMatch.name]
            if (artistIndex !== undefined) {
                selectedArtistIndex = artistIndex
                selectedArtistName = searchResults.bestMatch.name
                artistsListView.currentIndex = artistIndex  // Sync with ListView
                
                // Check if artist is expanded (it should be from handleSearchResult)
                if (expandedArtists[selectedArtistName]) {
                    // Artist is expanded, start in album navigation mode
                    var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
                    if (albums.length > 0) {
                        navigationMode = "album"
                        selectedAlbumIndex = 0
                        selectedAlbumData = albums[0]
                    } else {
                        // No albums, stay in artist mode
                        navigationMode = "artist"
                    }
                } else {
                    // Not expanded yet, start in artist mode
                    navigationMode = "artist"
                }
                // Don't scroll here - handleSearchResult already took care of it
            }
        } else if (searchResults.bestMatch && searchResults.bestMatchType === "album") {
            // Start with the album's artist expanded and album selected
            var artistName = searchResults.bestMatch.albumArtist
            // Use O(1) lookup instead of O(n) linear search
            var artistIndex = artistNameToIndex[artistName]
            if (artistIndex !== undefined) {
                selectedArtistIndex = artistIndex
                selectedArtistName = artistName
                artistsListView.currentIndex = artistIndex  // Sync with ListView
                // Don't scroll here - handleSearchResult already took care of it
                
                // Ensure artist is expanded
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[artistName] = true
                expandedArtists = updatedExpanded
                
                // Switch to album navigation
                navigationMode = "album"
                
                // Ensure album cache is populated
                if (!artistAlbumCache[artistName]) {
                    updateAlbumCacheForArtist(artistName)
                }
                
                // Use O(1) lookup from cache
                var albumMap = artistAlbumCache[artistName]
                var indexMap = artistAlbumIndexCache[artistName]
                if (albumMap && indexMap && albumMap[searchResults.bestMatch.title] !== undefined) {
                    selectedAlbumData = albumMap[searchResults.bestMatch.title]
                    selectedAlbumIndex = indexMap[searchResults.bestMatch.title]
                }
            }
        } else if (searchResults.bestMatch && searchResults.bestMatchType === "track") {
            // Start with the track's artist expanded and album selected
            var trackMatch = searchResults.bestMatch
            if (trackMatch.artist && trackMatch.album) {
                var artistName = trackMatch.artist
                // Use O(1) lookup instead of O(n) linear search
                var artistIndex = artistNameToIndex[artistName]
                if (artistIndex !== undefined) {
                    selectedArtistIndex = artistIndex
                    selectedArtistName = artistName
                    artistsListView.currentIndex = artistIndex  // Sync with ListView
                    
                    // Ensure artist is expanded
                    var updatedExpanded = Object.assign({}, expandedArtists)
                    updatedExpanded[artistName] = true
                    expandedArtists = updatedExpanded
                    
                    // Find and select the album
                    // Ensure album cache is populated
                    if (!artistAlbumCache[artistName]) {
                        updateAlbumCacheForArtist(artistName)
                    }
                    
                    // Use O(1) lookup from cache
                    var albumMap = artistAlbumCache[artistName]
                    var indexMap = artistAlbumIndexCache[artistName]
                    if (albumMap && indexMap && albumMap[trackMatch.album] !== undefined) {
                        selectedAlbumData = albumMap[trackMatch.album]
                        selectedAlbumIndex = indexMap[trackMatch.album]
                        selectedAlbum = selectedAlbumData  // This triggers track list loading
                    }
                    
                    // Wait for tracks to load, then select the track
                    Qt.callLater(function() {
                        // Use O(1) lookup from track index map
                        var trackKey = trackMatch.title + "|" + trackMatch.artist
                        var trackIndex = root.currentTrackIndexMap[trackKey]
                        
                        if (trackIndex !== undefined) {
                            navigationMode = "track"
                            selectedTrackIndex = trackIndex
                            trackListView.currentIndex = trackIndex
                            ensureTrackVisible(trackIndex)
                            
                            // Update track info panel if visible
                            if (root.showTrackInfoPanel && rightPane.currentAlbumTracks[trackIndex]) {
                                root.selectedTrackForInfo = rightPane.currentAlbumTracks[trackIndex]
                            }
                        }
                    })
                }
            }
        }
    }
    
    function handleNavigationDown() {
        if (navigationMode === "artist") {
            if (selectedArtistIndex < LibraryManager.artistModel.length - 1) {
                selectedArtistIndex++
                selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
                artistsListView.currentIndex = selectedArtistIndex  // Sync with ListView
                ensureArtistVisible(selectedArtistIndex)
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
                    artistsListView.currentIndex = selectedArtistIndex  // Sync with ListView
                    selectedAlbumIndex = -1
                    selectedAlbumData = null
                    ensureArtistVisible(selectedArtistIndex)
                }
            }
        } else if (navigationMode === "track") {
            if (selectedTrackIndex === -1 && rightPane.currentAlbumTracks.length > 0) {
                // First navigation down selects first track
                selectedTrackIndex = 0
                trackListView.currentIndex = 0
                ensureTrackVisible(0)
                // Update track info panel if visible
                if (root.showTrackInfoPanel && rightPane.currentAlbumTracks[0]) {
                    root.selectedTrackForInfo = rightPane.currentAlbumTracks[0]
                }
            } else if (selectedTrackIndex < rightPane.currentAlbumTracks.length - 1) {
                selectedTrackIndex++
                trackListView.currentIndex = selectedTrackIndex
                ensureTrackVisible(selectedTrackIndex)
                // Update track info panel if visible
                if (root.showTrackInfoPanel && rightPane.currentAlbumTracks[selectedTrackIndex]) {
                    root.selectedTrackForInfo = rightPane.currentAlbumTracks[selectedTrackIndex]
                }
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
            // Check if we're in the Playlists tab
            if (currentTab === 1) {
                // From track list in Playlists tab, go back to playlist navigation
                navigationMode = "playlist"
                selectedTrackIndex = -1
                trackListView.currentIndex = -1
                // Focus the playlist view
                if (playlistView) {
                    playlistView.forceActiveFocus()
                }
            } else {
                // From track list in Artists tab, go back to album navigation
                navigationMode = "album"
                selectedTrackIndex = -1
                trackListView.currentIndex = -1
            }
        } else if (navigationMode === "artist") {
            // Already at leftmost navigation level
        } else if (navigationMode === "playlist") {
            // Already at leftmost navigation level in Playlists tab
        }
    }
    
    function handleNavigationRight() {
        if (navigationMode === "artist") {
            // Navigate from artist to albums
            if (expandedArtists[selectedArtistName]) {
                var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
                if (albums.length > 0) {
                    navigationMode = "album"
                    selectedAlbumIndex = 0
                    selectedAlbumData = albums[0]
                    // Clear track selection when moving to albums
                    selectedTrackIndex = -1
                    trackListView.currentIndex = -1
                }
            }
        } else if (navigationMode === "album") {
            // Navigate right within album grid
            var albums = LibraryManager.getAlbumsForArtist(selectedArtistName)
            if (selectedAlbumIndex < albums.length - 1) {
                selectedAlbumIndex++
                selectedAlbumData = albums[selectedAlbumIndex]
            } else if (selectedAlbum && rightPane.currentAlbumTracks.length > 0) {
                // At the end of albums, if an album is already selected, move to tracks
                navigationMode = "track"
                selectedTrackIndex = -1  // Don't auto-select first track
                trackListView.currentIndex = -1
            }
            // If no album is selected yet, do nothing
        } else if (navigationMode === "track") {
            // Already at rightmost navigation level
        }
    }
    
    function handleNavigationUp() {
        if (navigationMode === "artist") {
            if (selectedArtistIndex > 0) {
                selectedArtistIndex--
                selectedArtistName = LibraryManager.artistModel[selectedArtistIndex].name
                artistsListView.currentIndex = selectedArtistIndex  // Sync with ListView
                ensureArtistVisible(selectedArtistIndex)
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
                    artistsListView.currentIndex = selectedArtistIndex  // Sync with ListView
                    selectedAlbumIndex = -1
                    selectedAlbumData = null
                    ensureArtistVisible(selectedArtistIndex)
                    
                    // Don't auto-expand - let user explicitly expand with Enter/Right
                }
            }
        } else if (navigationMode === "track") {
            if (selectedTrackIndex > 0) {
                selectedTrackIndex--
                trackListView.currentIndex = selectedTrackIndex
                ensureTrackVisible(selectedTrackIndex)
                // Update track info panel if visible
                if (root.showTrackInfoPanel && rightPane.currentAlbumTracks[selectedTrackIndex]) {
                    root.selectedTrackForInfo = rightPane.currentAlbumTracks[selectedTrackIndex]
                }
            }
            // Don't allow going to -1 with up arrow - stay at first track
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
                
                // Scroll to position the artist at the top to show albums
                Qt.callLater(function() {
                    scrollToArtist(selectedArtistName)
                })
            }
        } else if (navigationMode === "album") {
            // Select the album and switch to track navigation
            selectedAlbum = selectedAlbumData
            
            // Switch to track navigation
            if (rightPane.currentAlbumTracks.length > 0) {
                navigationMode = "track"
                selectedTrackIndex = -1  // Don't auto-select first track
                trackListView.currentIndex = -1
            }
        } else if (navigationMode === "track") {
            // Play the selected track
            if (selectedAlbumData && selectedTrackIndex >= 0) {
                // Check if this is a playlist
                if (selectedAlbumData.isPlaylist) {
                    // Handle playlist playback
                    var trackItem = trackListView.itemAtIndex(selectedTrackIndex);
                    if (trackItem) {
                        var globalPos = trackItem.mapToGlobal(trackItem.width / 2, trackItem.height / 2);
                        root.playPlaylistWithQueueCheck(selectedAlbumData.title, selectedAlbumData.isVirtualPlaylist || false, selectedTrackIndex, globalPos.x, globalPos.y);
                    } else {
                        root.playPlaylistWithQueueCheck(selectedAlbumData.title, selectedAlbumData.isVirtualPlaylist || false, selectedTrackIndex);
                    }
                } else {
                    // Handle regular album playback
                    var trackItem = trackListView.itemAtIndex(selectedTrackIndex);
                    if (trackItem) {
                        var globalPos = trackItem.mapToGlobal(trackItem.width / 2, trackItem.height / 2);
                        root.playAlbumWithQueueCheck(selectedAlbumData.albumArtist, selectedAlbumData.title, selectedTrackIndex, globalPos.x, globalPos.y);
                    } else {
                        root.playAlbumWithQueueCheck(selectedAlbumData.albumArtist, selectedAlbumData.title, selectedTrackIndex);
                    }
                }
            }
        }
    }
    
    // Helper function to get current album from browser
    function getCurrentAlbum() {
        if (albumBrowser && albumBrowser.selectedAlbum) {
            return albumBrowser.selectedAlbum
        }
        return null
    }
    
    // Helper function to restore album position
    function restoreAlbumPosition() {
        if (albumBrowser) {
            albumBrowser.restoreCarouselPosition()
        }
    }
    
    // Functions for Now Playing Panel integration
    function jumpToArtist(artistName) {
        try {
            console.log("jumpToArtist called with:", artistName)
            if (!artistName || typeof artistName !== "string") return
            
            // Switch to Artists tab if currently showing Playlists
            if (currentTab === 1) {
                currentTab = 0
            }
            
            // Prevent concurrent jump operations
            if (isJumping) {
                console.log("jumpToArtist: Already jumping, ignoring request")
                return
            }
            isJumping = true
            
            // Set programmatic scrolling flag immediately to disable all animations
            isProgrammaticScrolling = true
            
            // Clear search state and highlight the artist
            clearSearch()
            highlightedArtist = artistName
            
            // Use O(1) lookup instead of O(n) search
            var artistIndex = artistNameToIndex[artistName]
            console.log("jumpToArtist: Artist index from lookup:", artistIndex, "Total artists:", LibraryManager.artistModel.length)
            if (artistIndex === undefined) {
                console.log("jumpToArtist: Artist not found in index mapping")
                isJumping = false
                isProgrammaticScrolling = false
                return
            }
            
            // Update navigation state to sync with jump
            selectedArtistIndex = artistIndex
            selectedArtistName = artistName
            artistsListView.currentIndex = artistIndex
            
            // Check if already expanded
            var wasExpanded = expandedArtists[artistName] === true
            console.log("jumpToArtist: Artist was expanded:", wasExpanded)
            
            if (wasExpanded) {
                // Already expanded, safe to scroll immediately
                console.log("jumpToArtist: Artist already expanded, scrolling immediately")
                scrollToArtistIndex(artistIndex, true)
                // Reset flags after animation completes
                Qt.callLater(function() { 
                    isJumping = false
                    isProgrammaticScrolling = false
                })
            } else {
                // Expand the artist synchronously
                console.log("jumpToArtist: Expanding artist")
                var updatedExpanded = Object.assign({}, expandedArtists)
                updatedExpanded[artistName] = true
                expandedArtists = updatedExpanded
                
                // Force immediate layout update
                artistsListView.forceLayout()
                
                // Use dynamic layout stabilization instead of fixed delays
                layoutStabilizationTimer.targetIndex = artistIndex
                layoutStabilizationTimer.start()
                
                // Connect to stop signal to reset flags
                function onTimerStopped() {
                    if (!layoutStabilizationTimer.running) {
                        layoutStabilizationTimer.runningChanged.disconnect(onTimerStopped)
                        // Reset flags after scroll completes
                        Qt.callLater(function() {
                            isJumping = false
                            isProgrammaticScrolling = false
                        })
                    }
                }
                layoutStabilizationTimer.runningChanged.connect(onTimerStopped)
            }
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
        var indexMap = {}
        for (var i = 0; i < albums.length; i++) {
            if (albums[i] && albums[i].title) {
                albumMap[albums[i].title] = albums[i]
                indexMap[albums[i].title] = i
            }
        }
        
        artistAlbumCache[artistName] = albumMap
        artistAlbumIndexCache[artistName] = indexMap
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
    
    // Public function to focus the search bar
    function focusSearchBar() {
        searchBar.forceActiveFocus()
    }
    
    // Helper function to handle album play with queue check
    function playAlbumWithQueueCheck(artist, title, startIndex, mouseX, mouseY) {
        // Check if we should show the dialog
        if (SettingsManager.queueActionDefault === SettingsManager.Ask && MediaPlayer.isQueueModified) {
            // Show dialog for "Ask every time" setting when queue is modified
            queueActionDialog.isPlaylist = false
            queueActionDialog.albumArtist = artist
            queueActionDialog.albumTitle = title
            queueActionDialog.startIndex = startIndex || 0
            queueActionDialog.playlistName = ""
            queueActionDialog.isVirtualPlaylist = false
            
            // Position dialog at cursor location with bounds checking
            if (mouseX !== undefined && mouseY !== undefined) {
                var dialogX = mouseX - queueActionDialog.width / 2
                var dialogY = mouseY - queueActionDialog.height / 2
                
                // Get window dimensions
                var windowWidth = root.Window.window ? root.Window.window.width : root.width
                var windowHeight = root.Window.window ? root.Window.window.height : root.height
                
                // Keep dialog within window bounds with 10px margin
                dialogX = Math.max(10, Math.min(dialogX, windowWidth - queueActionDialog.width - 10))
                dialogY = Math.max(10, Math.min(dialogY, windowHeight - queueActionDialog.height - 10))
                
                queueActionDialog.x = dialogX
                queueActionDialog.y = dialogY
            }
            
            queueActionDialog.open()
        } else {
            // Apply the configured action
            switch (SettingsManager.queueActionDefault) {
                case SettingsManager.Replace:
                    MediaPlayer.playAlbumByName(artist, title, startIndex || 0);
                    break;
                case SettingsManager.Insert:
                    MediaPlayer.playAlbumNext(artist, title);
                    break;
                case SettingsManager.Append:
                    MediaPlayer.playAlbumLast(artist, title);
                    break;
                case SettingsManager.Ask:
                    // If Ask but queue not modified, default to replace
                    MediaPlayer.playAlbumByName(artist, title, startIndex || 0);
                    break;
            }
        }
    }
    
    function playPlaylistWithQueueCheck(playlistName, isVirtualPlaylist, startIndex, mouseX, mouseY) {
        // Special handling for "All Songs" playlist
        var isAllSongs = isVirtualPlaylist && playlistName === "All Songs"
        
        // Check if we should show the dialog
        var shouldShowDialog = false
        
        if (isAllSongs) {
            // For All Songs, show dialog if queue is modified AND (Ask is selected OR Play Next/Last is selected)
            shouldShowDialog = MediaPlayer.isQueueModified && 
                              (SettingsManager.queueActionDefault === SettingsManager.Ask ||
                               SettingsManager.queueActionDefault === SettingsManager.Insert ||
                               SettingsManager.queueActionDefault === SettingsManager.Append)
        } else {
            // For regular playlists, use normal logic
            shouldShowDialog = SettingsManager.queueActionDefault === SettingsManager.Ask && MediaPlayer.isQueueModified
        }
        
        if (shouldShowDialog) {
            // Show dialog for "Ask every time" setting when queue is modified
            queueActionDialog.isPlaylist = true
            queueActionDialog.playlistName = playlistName
            queueActionDialog.isVirtualPlaylist = isVirtualPlaylist || false
            queueActionDialog.albumArtist = ""
            queueActionDialog.albumTitle = ""
            queueActionDialog.startIndex = startIndex || 0
            
            // Position dialog at cursor location with bounds checking
            if (mouseX !== undefined && mouseY !== undefined) {
                var dialogX = mouseX - queueActionDialog.width / 2
                var dialogY = mouseY - queueActionDialog.height / 2
                
                // Get window dimensions
                var windowWidth = root.Window.window ? root.Window.window.width : root.width
                var windowHeight = root.Window.window ? root.Window.window.height : root.height
                
                // Keep dialog within window bounds with 10px margin
                dialogX = Math.max(10, Math.min(dialogX, windowWidth - queueActionDialog.width - 10))
                dialogY = Math.max(10, Math.min(dialogY, windowHeight - queueActionDialog.height - 10))
                
                queueActionDialog.x = dialogX
                queueActionDialog.y = dialogY
            }
            
            queueActionDialog.open()
        } else {
            // Apply the configured action
            var effectiveAction = SettingsManager.queueActionDefault
            
            // For All Songs, if Play Next/Last is selected, fall back to Replace
            if (isAllSongs && (effectiveAction === SettingsManager.Insert || effectiveAction === SettingsManager.Append)) {
                effectiveAction = SettingsManager.Replace
            }
            
            switch (effectiveAction) {
                case SettingsManager.Replace:
                    playPlaylistReplace(playlistName, isVirtualPlaylist, startIndex);
                    break;
                case SettingsManager.Insert:
                    playPlaylistNext(playlistName, isVirtualPlaylist);
                    break;
                case SettingsManager.Append:
                    playPlaylistLast(playlistName, isVirtualPlaylist);
                    break;
                case SettingsManager.Ask:
                    // If Ask but queue not modified, default to replace
                    playPlaylistReplace(playlistName, isVirtualPlaylist, startIndex);
                    break;
            }
        }
    }
    
    function playPlaylistReplace(playlistName, isVirtualPlaylist, startIndex) {
        if (isVirtualPlaylist && playlistName === "All Songs") {
            // Get the virtual playlist model
            var allSongsModel = LibraryManager.getAllSongsPlaylist()
            // Clear queue and load virtual playlist
            MediaPlayer.clearQueue()
            MediaPlayer.loadVirtualPlaylist(allSongsModel)
            // For virtual playlist, handle start index differently
            if (startIndex !== undefined && startIndex > 0) {
                MediaPlayer.playTrackAt(startIndex)
            } else {
                // Start playing respecting shuffle mode
                MediaPlayer.playVirtualPlaylist()
            }
        } else {
            // Play regular playlist using the new C++ method
            // If startIndex is not provided, check shuffle mode
            if (startIndex === undefined || startIndex === null) {
                startIndex = 0
                if (MediaPlayer.shuffleEnabled) {
                    // Get track count first to calculate random index
                    var trackCount = PlaylistManager.getPlaylistTrackCount(playlistName)
                    if (trackCount > 0) {
                        startIndex = Math.floor(Math.random() * trackCount)
                    }
                }
            }
            
            // Use the new playPlaylist method which handles queue state properly
            MediaPlayer.playPlaylist(playlistName, startIndex)
        }
    }
    
    function playPlaylistNext(playlistName, isVirtualPlaylist) {
        if (isVirtualPlaylist && playlistName === "All Songs") {
            var allSongsModel = LibraryManager.getAllSongsPlaylist()
            MediaPlayer.loadVirtualPlaylistNext(allSongsModel)
        } else {
            MediaPlayer.playPlaylistNext(playlistName)
        }
    }
    
    function playPlaylistLast(playlistName, isVirtualPlaylist) {
        if (isVirtualPlaylist && playlistName === "All Songs") {
            var allSongsModel = LibraryManager.getAllSongsPlaylist()
            MediaPlayer.loadVirtualPlaylistLast(allSongsModel)
        } else {
            MediaPlayer.playPlaylistLast(playlistName)
        }
    }
    
    // Function to perform track search for track selector
    function performTrackSearch() {
        if (root.trackSelectorSearchTerm.trim().length === 0) {
            root.trackSelectorResults = []
            return
        }
        
        // Get search results from LibraryManager (search all and filter to tracks only)
        var allResults = LibraryManager.searchAll(root.trackSelectorSearchTerm)
        var trackResults = []
        
        // Filter to include only tracks from the search results
        if (allResults && allResults.tracks) {
            trackResults = allResults.tracks
        }
        
        root.trackSelectorResults = trackResults
    }
}