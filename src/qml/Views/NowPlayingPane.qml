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
        color: "#1a1a1a"
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
        }
    }
    
    // Blurred background using thumbnail for efficiency
    BlurredBackground {
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 512
        backgroundOpacity: 0.4
    }
    
    // Dark overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(16, parent.height * 0.04)  // Dynamic margins: 4% of height, min 16px
        spacing: Math.max(8, parent.height * 0.02)  // Dynamic spacing: 2% of height, min 8px
        
        // Album art and queue container
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            RowLayout {
                anchors.fill: parent
                spacing: queueVisible ? 16 : 0
                
                // Album art container
                Item {
                    id: albumArtContainer
                    Layout.preferredWidth: queueVisible ? parent.width * 0.3 : parent.width
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter
                    
                    Behavior on Layout.preferredWidth {
                        NumberAnimation { 
                            duration: 300
                            easing.type: Easing.InOutCubic
                        }
                    }
                    
                    Image {
                        id: albumArt
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        source: albumArtUrl
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
                            color: "#202020"
                            visible: albumArt.status !== Image.Ready || !albumArtUrl
                            
                            Text {
                                anchors.centerIn: parent
                                text: "♪"
                                font.pixelSize: parent.width * 0.3
                                color: "#404040"
                            }
                        }
                    }
                }
                
                // Queue list view
                Item {
                    id: queueContainer
                    Layout.preferredWidth: queueVisible ? parent.width * 0.7 - 16 : 0
                    Layout.fillHeight: true
                    visible: queueVisible || Layout.preferredWidth > 0
                    clip: true
                    
                    Behavior on Layout.preferredWidth {
                        NumberAnimation { 
                            duration: 300
                            easing.type: Easing.InOutCubic
                        }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: queueVisible ? 0 : -width
                        color: Qt.rgba(0, 0, 0, 0.3)
                        radius: 8
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        opacity: queueVisible ? 1.0 : 0.0
                        
                        Behavior on opacity {
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                        
                        Behavior on anchors.leftMargin {
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.InOutCubic
                            }
                        }
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        
                        // Queue header
                        RowLayout {
                            Layout.fillWidth: true
                            
                            Label {
                                text: "Queue"
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                color: "white"
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Label {
                                text: MediaPlayer.queueLength + " track" + (MediaPlayer.queueLength !== 1 ? "s" : "") + ", " + formatQueueDuration(MediaPlayer.totalQueueDuration)
                                font.pixelSize: 12
                                color: "#808080"
                            }
                            
                            // Clear queue button
                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 4
                                color: clearQueueMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                                visible: MediaPlayer.queueLength > 0
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                                
                                Image {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    source: "qrc:/resources/icons/bomb.svg"
                                    sourceSize.width: 40
                                    sourceSize.height: 40
                                    opacity: clearQueueMouseArea.containsMouse ? 0.6 : 0.3
                                    
                                    Behavior on opacity {
                                        NumberAnimation { duration: 150 }
                                    }
                                }
                                
                                MouseArea {
                                    id: clearQueueMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        queueListView.clearAllTracks();
                                    }
                                }
                                
                                ToolTip {
                                    visible: clearQueueMouseArea.containsMouse
                                    text: "Clear queue"
                                    delay: 500
                                }
                            }
                        }
                        
                        // Queue list
                        QueueListView {
                            id: queueListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            queueModel: MediaPlayer.queue
                            currentPlayingIndex: MediaPlayer.currentQueueIndex
                            
                            onTrackDoubleClicked: function(index) {
                                MediaPlayer.playTrackAt(index);
                            }
                            
                            onRemoveTrackRequested: function(index) {
                                MediaPlayer.removeTrackAt(index);
                            }
                        }
                    }
                    }
                }
            }
        }
        
        // Track information
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(60, parent.height * 0.08)  // Dynamic height: 8% of parent, min 60px
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
                    color: titleMouseArea.containsMouse ? "#ffffff" : "#e0e0e0"
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
                            // Use albumArtist for consistency with library organization
                            var artistName = MediaPlayer.currentTrack.albumArtist || MediaPlayer.currentTrack.artist
                            var albumTitle = MediaPlayer.currentTrack.album
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
                    color: artistMouseArea.containsMouse ? "#d0d0d0" : "#b0b0b0"
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
                            // Use album artist for navigation since library is organized by album artist
                            // This ensures the artist exists in the library pane even for featured artists
                            var albumArtist = MediaPlayer.currentTrack.albumArtist || MediaPlayer.currentTrack.artist
                            if (albumArtist) {
                                libraryPane.jumpToArtist(albumArtist)
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
                    color: albumMouseArea.containsMouse ? "#a0a0a0" : "#808080"
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
                            // Use albumArtist for consistency with library organization
                            var artistName = MediaPlayer.currentTrack.albumArtist || MediaPlayer.currentTrack.artist
                            var albumTitle = MediaPlayer.currentTrack.album
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
            Layout.preferredHeight: Math.max(80, parent.height * 0.06)  // Dynamic height: 12% of parent, min 80px
            
            queueVisible: root.queueVisible
            
            onPlayPauseClicked: MediaPlayer.togglePlayPause()
            onPreviousClicked: MediaPlayer.previous()
            onNextClicked: MediaPlayer.next()
            onSeekRequested: function(position) {
                MediaPlayer.seek(position)
            }
            onQueueToggled: root.queueVisible = !root.queueVisible
            onRepeatToggled: {
                // TODO: Implement repeat functionality
                console.log("Repeat toggled")
            }
            onShuffleToggled: {
                // TODO: Implement shuffle functionality
                console.log("Shuffle toggled")
            }
        }
        
        Item {
            Layout.preferredHeight: Math.max(24, parent.height * 0.01)  // Dynamic bottom spacing
        }
    }
}