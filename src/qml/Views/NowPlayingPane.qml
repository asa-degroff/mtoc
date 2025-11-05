import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Mtoc.Backend 1.0
import "../Components"

Item {
    id: root
    
    property string currentAlbumId: ""
    property url albumArtUrl: ""
    property url thumbnailUrl: ""
    property var libraryPane: null
    property bool queueVisible: false
    property var uniqueAlbumCovers: []
    property bool showPlaylistSavedMessage: false
    property string savedPlaylistName: ""
    property bool lyricsVisible: false
    
    // Keyboard shortcut for undo
    Keys.onPressed: function(event) {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
            if (MediaPlayer.canUndoClear) {
                MediaPlayer.undoClearQueue()
                event.accepted = true
            }
        }
    }
    
    // Enable focus to receive keyboard events
    focus: true
    
    // Debounce timer for album cover updates
    Timer {
        id: albumCoverUpdateTimer
        interval: 300
        repeat: false
        onTriggered: updateUniqueAlbumCovers()
    }
    
    // Timer to hide playlist saved message
    Timer {
        id: playlistSavedMessageTimer
        interval: 2500
        repeat: false
        onTriggered: {
            showPlaylistSavedMessage = false
        }
    }
    
    Component.onCompleted: {
        updateUniqueAlbumCovers()
        
        // Connect to playlist saved signal
        PlaylistManager.playlistSaved.connect(function(name) {
            savedPlaylistName = name
            showPlaylistSavedMessage = true
            playlistSavedMessageTimer.restart()
        })
    }
    
    // Get up to 3 unique album covers from the queue, starting with current track
    function updateUniqueAlbumCovers() {
        var covers = []
        var seenAlbums = new Set()
        
        // First, add the current playing track's album if available
        if (MediaPlayer.currentTrack && MediaPlayer.currentQueueIndex >= 0) {
            var currentTrack = MediaPlayer.currentTrack
            var albumKey = currentTrack.albumArtist + "||" + currentTrack.album
            if (currentTrack.albumArtist && currentTrack.album && !seenAlbums.has(albumKey)) {
                covers.push({
                    albumArtist: currentTrack.albumArtist,
                    album: currentTrack.album,
                    isCurrent: true
                })
                seenAlbums.add(albumKey)
            }
        }
        
        // Then, go through the queue starting from current position to find upcoming unique albums
        var queue = MediaPlayer.queue
        var startIndex = Math.max(0, MediaPlayer.currentQueueIndex)
        
        // Look for unique albums from current position onwards
        for (var i = startIndex; i < queue.length && covers.length < 3; i++) {
            var track = queue[i]
            if (track.albumArtist && track.album) {
                var albumKey = track.albumArtist + "||" + track.album
                if (!seenAlbums.has(albumKey)) {
                    covers.push({
                        albumArtist: track.albumArtist,
                        album: track.album,
                        isCurrent: i === MediaPlayer.currentQueueIndex
                    })
                    seenAlbums.add(albumKey)
                }
            }
        }
        
        uniqueAlbumCovers = covers
    }
    
    function formatQueueDuration(totalSeconds) {
        if (isNaN(totalSeconds) || totalSeconds < 0) {
            return "0:00"
        }
        
        var hours = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        
        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        } else {
            return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
    }
    
    // Temporary debug rectangle
    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundColor
        z: -2
    }
    
    // Update album art when track changes (based on album of the track)
    Connections {
        target: MediaPlayer

        function onCurrentTrackChanged(track) {
            if (track && track.album && track.albumArtist) {
                var newAlbumId = track.albumArtist + "_" + track.album
                if (newAlbumId !== currentAlbumId) {
                    currentAlbumId = newAlbumId
                    // Use the album artist and album title from the track, URL-encoded
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
            // Use debounced update for performance
            albumCoverUpdateTimer.restart()

            // Auto-hide lyrics display if current track has no lyrics
            if (!MediaPlayer.hasCurrentTrackLyrics && root.lyricsVisible) {
                root.lyricsVisible = false
            }
        }

        function onPlaybackQueueChanged() {
            // Use debounced update for performance
            albumCoverUpdateTimer.restart()
        }
    }
    
    // Blurred background
    BlurredBackground {
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 512
        backgroundOpacity: 0.7
    }
    
    // Overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: Theme.overlayColor
        opacity: Theme.nowPlayingOverlayOpacity
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(16, parent.height * 0.04)  // Dynamic margins: 4% of height, min 16px
        spacing: Math.max(8, parent.height * 0.02)  // Dynamic spacing: 2% of height, min 8px
        visible: LibraryManager.trackCount > 0
        
        // Album art and queue container with lyrics (custom animated transition)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: {
                // Calculate fixed height: total height minus fixed components and margins/spacing
                var margins = Math.max(16, parent.height * 0.04) * 2  // top and bottom margins
                var spacing = Math.max(8, parent.height * 0.02) * 3   // 3 gaps between 4 components
                var fixedComponents = 60 + 80 + 24  // track info + controls + bottom spacer
                return Math.max(200, parent.height - margins - spacing - fixedComponents)
            }

            // Album art and queue view
            Item {
                id: albumArtAndQueueContainer
                anchors.fill: parent
                opacity: root.lyricsVisible ? 0 : 1
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutCubic
                    }
                }

                // Use manual positioning instead of RowLayout to avoid layout jumps
                Item {
                    anchors.fill: parent
                    
                    // Album art container
                    Item {
                        id: albumArtContainer
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: queueVisible ? parent.width * 0.24 : parent.width * 0.9
                        
                        // Calculate target width for proper x position calculation
                        property real targetWidth: queueVisible ? parent.width * 0.24 : parent.width * 0.9
                        
                        // Position based on queue visibility - centered when hidden, left-aligned when visible
                        // Use targetWidth instead of current width to ensure smooth simultaneous animation
                        x: queueVisible ? 0 : (parent.width - targetWidth) / 2
                        
                        Behavior on width {
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        
                        Behavior on x {
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        
                        // Column to show multiple album covers when queue is visible
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: parent.height
                            spacing: queueVisible ? 10 : 0
                            opacity: (queueVisible && uniqueAlbumCovers.length > 0) ? 1.0 : 0.0
                            visible: opacity > 0
                            
                            Behavior on spacing {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.InOutCubic
                                }
                            }
                            
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.InOutCubic
                                }
                            }
                            
                            Repeater {
                                model: uniqueAlbumCovers
                                
                                Image {
                                    width: parent.width
                                    height: (parent.height - (parent.spacing * (uniqueAlbumCovers.length - 1))) / uniqueAlbumCovers.length
                                    source: {
                                        if (modelData.albumArtist && modelData.album) {
                                            var encodedArtist = encodeURIComponent(modelData.albumArtist)
                                            var encodedAlbum = encodeURIComponent(modelData.album)
                                            return "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/full"
                                        }
                                        return ""
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    cache: true
                                    
                                    // Drop shadow effect using MultiEffect
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowHorizontalOffset: 0
                                        shadowVerticalOffset: 4
                                        shadowBlur: 0.5
                                        shadowColor: "#80000000"
                                    }
                                    
                                    // Placeholder when no album art
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Theme.panelBackground
                                        visible: parent.status !== Image.Ready || parent.source == ""
                                        
                                        Text {
                                            anchors.centerIn: parent
                                            text: "♪"
                                            font.pixelSize: parent.width * 0.3
                                            color: Theme.inputBackgroundHover
                                        }
                                    }
                                    
                                    // MouseArea to toggle queue on click
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.queueVisible = false
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Single album art when queue is hidden
                        Image {
                            id: albumArt
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: parent.height
                            source: albumArtUrl
                            fillMode: Image.PreserveAspectFit
                            cache: true
                            opacity: (!queueVisible || uniqueAlbumCovers.length === 0) ? 1.0 : 0.0
                            visible: opacity > 0
                            
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.InOutCubic
                                }
                            }
                            
                            // Drop shadow effect using MultiEffect
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 4
                                shadowBlur: 0.5
                                shadowColor: "#80000000"
                            }
                            
                            // Placeholder when no album art
                            Rectangle {
                                anchors.fill: parent
                                color: Theme.panelBackground
                                visible: albumArt.status !== Image.Ready || !albumArtUrl
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "♪"
                                    font.pixelSize: parent.width * 0.3
                                    color: Theme.inputBackgroundHover
                                }
                            }
                        }
                    }
                    
                    // Queue list view
                    Item {
                        id: queueContainer
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: queueVisible ? parent.width * 0.7 - 16 : 0
                        opacity: queueVisible ? 1.0 : 0.0
                        visible: opacity > 0 || width > 1  // Stay visible during animations
                        clip: true
                        
                        Behavior on width {
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        
                        Behavior on opacity {
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.3)
                            radius: 8
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.1)
                            
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8
                            
                            // Queue header
                            QueueHeader {
                                Layout.fillWidth: true
                                showPlaylistSavedMessage: root.showPlaylistSavedMessage
                                forceLightText: true // Always use light text on dark background
                                
                                onClearQueueRequested: {
                                    queueListView.clearAllTracks();
                                }
                            }
                            
                            // Queue list
                            QueueListView {
                                id: queueListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                queueModel: MediaPlayer.queue
                                currentPlayingIndex: MediaPlayer.currentQueueIndex
                                focus: root.queueVisible
                                forceLightText: true // Always use light text on dark background
                                
                                onTrackDoubleClicked: function(index) {
                                    MediaPlayer.playTrackAt(index);
                                }
                                
                                onRemoveTrackRequested: function(index) {
                                    MediaPlayer.removeTrackAt(index);
                                }
                                
                                onRemoveTracksRequested: function(indices) {
                                    MediaPlayer.removeTracks(indices);
                                }
                            }
                        }
                        }
                    }
                }
            }

            // Lyrics view with slide-up animation
            LyricsView {
                id: lyricsView
                anchors.fill: parent
                lyricsText: MediaPlayer.currentTrackLyrics
                opacity: root.lyricsVisible ? 1 : 0
                visible: opacity > 0

                // Slide up from bottom animation
                transform: Translate {
                    y: root.lyricsVisible ? 0 : lyricsView.height * 0.3

                    Behavior on y {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.InOutCubic
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutCubic
                    }
                }
            }
        }
        
        // Track information
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            spacing: 2
            
            // Track title (clickable - jumps to album)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titleLabel.implicitHeight
                
                Label {
                    id: titleLabel
                    anchors.fill: parent
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    color: titleMouseArea.containsMouse ? Theme.primaryText : Theme.secondaryText
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
                
                MouseArea {
                    id: titleMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (libraryPane && MediaPlayer.currentTrack) {
                            var track = MediaPlayer.currentTrack
                            var artistName = ""

                            // Smart navigation: prioritize track artist if different from album artist
                            if (track.artist && track.albumArtist && track.artist !== track.albumArtist) {
                                artistName = track.artist
                            } else {
                                artistName = track.albumArtist || track.artist
                            }

                            var albumTitle = track.album
                            if (artistName && albumTitle) {
                                libraryPane.jumpToAlbum(artistName, albumTitle)
                            }
                        }
                    }
                }
            }
            
            // Artist name (clickable - jumps to artist)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: artistLabel.implicitHeight
                
                Label {
                    id: artistLabel
                    anchors.fill: parent
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                    font.pixelSize: 18
                    color: artistMouseArea.containsMouse ? Theme.secondaryText : Theme.tertiaryText
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
                
                MouseArea {
                    id: artistMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (libraryPane && MediaPlayer.currentTrack) {
                            var track = MediaPlayer.currentTrack
                            var artistToJump = ""

                            // Smart navigation: prioritize track artist if different from album artist
                            // This handles multi-artist albums where individual tracks have unique performers
                            if (track.artist && track.albumArtist && track.artist !== track.albumArtist) {
                                // Track has a unique artist - navigate to track artist
                                artistToJump = track.artist
                            } else {
                                // Use album artist for navigation (standard behavior)
                                artistToJump = track.albumArtist || track.artist
                            }

                            if (artistToJump) {
                                libraryPane.jumpToArtist(artistToJump)
                            }
                        }
                    }
                }
            }
            
            // Album name (clickable - jumps to album)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: albumLabel.implicitHeight
                
                Label {
                    id: albumLabel
                    anchors.fill: parent
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.album : ""
                    font.pixelSize: 16
                    color: albumMouseArea.containsMouse ? Theme.tertiaryText : Theme.tertiaryText
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
                
                MouseArea {
                    id: albumMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (libraryPane && MediaPlayer.currentTrack) {
                            var track = MediaPlayer.currentTrack
                            var artistName = ""

                            // Smart navigation: prioritize track artist if different from album artist
                            if (track.artist && track.albumArtist && track.artist !== track.albumArtist) {
                                artistName = track.artist
                            } else {
                                artistName = track.albumArtist || track.artist
                            }

                            var albumTitle = track.album
                            if (artistName && albumTitle) {
                                libraryPane.jumpToAlbum(artistName, albumTitle)
                            }
                        }
                    }
                }
            }
        }
        
        // Playback controls
        PlaybackControls {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            
            queueVisible: root.queueVisible
            lyricsVisible: root.lyricsVisible
            
            onPlayPauseClicked: MediaPlayer.togglePlayPause()
            onPreviousClicked: MediaPlayer.previous()
            onNextClicked: MediaPlayer.next()
            onSeekRequested: function(position) {
                MediaPlayer.seek(position)
            }
            onQueueToggled: {
                // Auto-hide lyrics when showing queue
                if (!root.queueVisible && root.lyricsVisible) {
                    root.lyricsVisible = false
                }
                root.queueVisible = !root.queueVisible
            }
            onLyricsToggled: {
                // Auto-hide queue when showing lyrics
                if (!root.lyricsVisible && root.queueVisible) {
                    root.queueVisible = false
                }
                root.lyricsVisible = !root.lyricsVisible
            }
            onRepeatToggled: {
                MediaPlayer.repeatEnabled = !MediaPlayer.repeatEnabled
            }
            onShuffleToggled: {
                MediaPlayer.shuffleEnabled = !MediaPlayer.shuffleEnabled
            }
        }
        
        Item {
            Layout.preferredHeight: 24
        }
    }
    
    // Empty library placeholder
    Item {
        anchors.fill: parent
        visible: LibraryManager.trackCount === 0
        
        MouseArea {
            id: placeholderMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            
            onClicked: {
                if (root.libraryPane && root.libraryPane.openLibraryEditor) {
                    root.libraryPane.openLibraryEditor()
                }
            }
            
            Column {
                anchors.centerIn: parent
                spacing: 20
                
                Label {
                    text: "No Music"
                    font.pixelSize: 32
                    font.bold: true
                    color: Theme.primaryText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Label {
                    text: "Add a folder and scan to build your library"
                    font.pixelSize: 16
                    color: placeholderMouseArea.containsMouse ? Theme.primaryText : Theme.secondaryText
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.underline: placeholderMouseArea.containsMouse
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }
        }
    }
}