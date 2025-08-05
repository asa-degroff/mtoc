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
    
    // Custom icon button component (from PlaybackControls)
    component IconButton: Item {
        id: buttonRoot
        property string iconSource: ""
        property string iconPressedSource: ""
        property bool isPressed: false
        property bool isHovered: false
        signal clicked()
        
        scale: isPressed ? 0.9 : (isHovered ? 1.1 : 1.0)
        
        Behavior on scale {
            enabled: buttonRoot.isHovered || buttonRoot.isPressed
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        Image {
            id: iconImage
            anchors.fill: parent
            source: buttonRoot.isPressed && buttonRoot.iconPressedSource ? buttonRoot.iconPressedSource : buttonRoot.iconSource
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            smooth: true
            antialiasing: false
            fillMode: Image.PreserveAspectFit
        }
        
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: buttonRoot.isHovered = true
            onExited: buttonRoot.isHovered = false
            onPressed: buttonRoot.isPressed = true
            onReleased: buttonRoot.isPressed = false
            onClicked: buttonRoot.clicked()
        }
    }
    
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
            IconButton {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                iconSource: "qrc:/resources/icons/previous-button-normal.svg"
                iconPressedSource: "qrc:/resources/icons/previous-button-pressed.svg"
                onClicked: MediaPlayer.previous()
            }
            
            // Play/Pause button
            IconButton {
                id: playPauseButton
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                iconSource: MediaPlayer.state === MediaPlayer.PlayingState ? 
                    "qrc:/resources/icons/pause-button-normal.svg" : 
                    "qrc:/resources/icons/play-button-normal.svg"
                iconPressedSource: MediaPlayer.state === MediaPlayer.PlayingState ? 
                    "qrc:/resources/icons/pause-button-pressed.svg" : 
                    "qrc:/resources/icons/play-button-pressed.svg"
                onClicked: MediaPlayer.togglePlayPause()
            }
            
            // Next button
            IconButton {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                iconSource: "qrc:/resources/icons/skip-button-normal.svg"
                iconPressedSource: "qrc:/resources/icons/skip-button-pressed.svg"
                enabled: MediaPlayer.hasNext
                opacity: enabled ? 1.0 : 0.3
                onClicked: MediaPlayer.next()
            }
            
            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.margins: 8
                color: Theme.borderColor
            }
            
            // Queue button
            IconButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                iconSource: Theme.isDark ? "qrc:/resources/icons/queue.svg" : "qrc:/resources/icons/queue-dark.svg"
                opacity: root.queuePopupVisible ? 1.0 : 0.6
                onClicked: root.queuePopupVisible = !root.queuePopupVisible
                
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
            
            // Repeat button
            IconButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                iconSource: Theme.isDark ? "qrc:/resources/icons/repeat.svg" : "qrc:/resources/icons/repeat-dark.svg"
                opacity: MediaPlayer.repeatEnabled ? 1.0 : 0.6
                onClicked: MediaPlayer.repeatEnabled = !MediaPlayer.repeatEnabled
                
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
            
            // Shuffle button
            IconButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                iconSource: Theme.isDark ? "qrc:/resources/icons/shuffle.svg" : "qrc:/resources/icons/shuffle-dark.svg"
                opacity: MediaPlayer.shuffleEnabled ? 1.0 : 0.6
                onClicked: MediaPlayer.shuffleEnabled = !MediaPlayer.shuffleEnabled
                
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
        }
    }
}