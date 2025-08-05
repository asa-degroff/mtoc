import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Rectangle {
    id: root
    height: 80
    color: Theme.panelBackground
    
    property string currentAlbumId: ""
    property url albumArtUrl: ""
    property url thumbnailUrl: ""
    property bool queuePopupVisible: false
    property bool albumArtPopupVisible: false
    
    signal albumTitleClicked(string artistName, string albumTitle)
    signal artistClicked(string artistName)
    
    // Update album art when track changes
    Connections {
        target: MediaPlayer
        
        function onCurrentTrackChanged(track) {
            if (track && track.album && track.albumArtist) {
                var newAlbumId = track.albumArtist + "_" + track.album
                if (newAlbumId !== currentAlbumId) {
                    currentAlbumId = newAlbumId
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
    
    // Top border
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.borderColor
    }
    
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 12
        
        // Album art thumbnail (clickable)
        Item {
            Layout.preferredWidth: 60
            Layout.preferredHeight: 60
            
            Image {
                id: albumArtThumb
                anchors.fill: parent
                source: thumbnailUrl
                fillMode: Image.PreserveAspectFit
                
                // Placeholder when no album art
                Rectangle {
                    anchors.fill: parent
                    color: Theme.inputBackground
                    visible: parent.status !== Image.Ready || parent.source == ""
                    
                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        font.pixelSize: 24
                        color: Theme.tertiaryText
                    }
                }
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.albumArtPopupVisible = true
                }
            }
        }
        
        // Track info
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            
            // Track title (clickable)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titleLabel.implicitHeight
                
                Label {
                    id: titleLabel
                    anchors.fill: parent
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: titleMouseArea.containsMouse ? Theme.primaryText : Theme.secondaryText
                    elide: Text.ElideRight
                }
                
                MouseArea {
                    id: titleMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (MediaPlayer.currentTrack) {
                            var artistName = MediaPlayer.currentTrack.albumArtist || MediaPlayer.currentTrack.artist
                            var albumTitle = MediaPlayer.currentTrack.album
                            if (artistName && albumTitle) {
                                root.albumTitleClicked(artistName, albumTitle)
                            }
                        }
                    }
                }
            }
            
            // Artist name (clickable)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: artistLabel.implicitHeight
                
                Label {
                    id: artistLabel
                    anchors.fill: parent
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                    font.pixelSize: 12
                    color: artistMouseArea.containsMouse ? Theme.secondaryText : Theme.tertiaryText
                    elide: Text.ElideRight
                }
                
                MouseArea {
                    id: artistMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (MediaPlayer.currentTrack) {
                            var albumArtist = MediaPlayer.currentTrack.albumArtist || MediaPlayer.currentTrack.artist
                            if (albumArtist) {
                                root.artistClicked(albumArtist)
                            }
                        }
                    }
                }
            }
            
            // Progress bar
            ProgressBar {
                id: progressBar
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                from: 0
                to: MediaPlayer.duration > 0 ? MediaPlayer.duration : 1
                value: MediaPlayer.position
                
                background: Rectangle {
                    color: Theme.inputBackground
                    radius: 2
                }
                
                contentItem: Item {
                    Rectangle {
                        width: progressBar.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.selectedBackground
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) {
                        var position = mouse.x / width * progressBar.to
                        MediaPlayer.seek(position)
                    }
                }
            }
        }
        
        // Playback controls
        RowLayout {
            Layout.fillHeight: true
            spacing: 8
            
            // Previous button
            ToolButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                icon.source: "qrc:/resources/icons/previous.svg"
                icon.width: 16
                icon.height: 16
                onClicked: MediaPlayer.previous()
                
                background: Rectangle {
                    color: parent.hovered ? Theme.inputBackgroundHover : "transparent"
                    radius: 4
                }
            }
            
            // Play/Pause button
            ToolButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                icon.source: MediaPlayer.isPlaying ? "qrc:/resources/icons/pause.svg" : "qrc:/resources/icons/play.svg"
                icon.width: 20
                icon.height: 20
                onClicked: MediaPlayer.togglePlayPause()
                
                background: Rectangle {
                    color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                    radius: 18
                    border.width: 1
                    border.color: Theme.borderColor
                }
            }
            
            // Next button
            ToolButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                icon.source: "qrc:/resources/icons/next.svg"
                icon.width: 16
                icon.height: 16
                onClicked: MediaPlayer.next()
                
                background: Rectangle {
                    color: parent.hovered ? Theme.inputBackgroundHover : "transparent"
                    radius: 4
                }
            }
            
            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.margins: 8
                color: Theme.borderColor
            }
            
            // Queue button
            ToolButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                icon.source: "qrc:/resources/icons/queue.svg"
                icon.width: 16
                icon.height: 16
                checkable: true
                checked: root.queuePopupVisible
                onClicked: root.queuePopupVisible = !root.queuePopupVisible
                
                background: Rectangle {
                    color: parent.checked ? Theme.selectedBackground : (parent.hovered ? Theme.inputBackgroundHover : "transparent")
                    radius: 4
                }
            }
            
            // Repeat button
            ToolButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                icon.source: "qrc:/resources/icons/repeat.svg"
                icon.width: 16
                icon.height: 16
                checkable: true
                checked: MediaPlayer.repeatEnabled
                onClicked: MediaPlayer.repeatEnabled = !MediaPlayer.repeatEnabled
                
                background: Rectangle {
                    color: parent.checked ? Theme.selectedBackground : (parent.hovered ? Theme.inputBackgroundHover : "transparent")
                    radius: 4
                }
            }
            
            // Shuffle button
            ToolButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                icon.source: "qrc:/resources/icons/shuffle.svg"
                icon.width: 16
                icon.height: 16
                checkable: true
                checked: MediaPlayer.shuffleEnabled
                onClicked: MediaPlayer.shuffleEnabled = !MediaPlayer.shuffleEnabled
                
                background: Rectangle {
                    color: parent.checked ? Theme.selectedBackground : (parent.hovered ? Theme.inputBackgroundHover : "transparent")
                    radius: 4
                }
            }
        }
    }
}