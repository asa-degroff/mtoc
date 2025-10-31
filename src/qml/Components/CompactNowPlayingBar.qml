import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Rectangle {
    id: root
    height: 90
    color: Theme.backgroundColor
    clip: true
    
    property string currentAlbumId: ""
    property url albumArtUrl: ""
    property url thumbnailUrl: ""
    property bool queuePopupVisible: false
    property bool albumArtPopupVisible: false
    property bool lyricsPopupVisible: false
    
    signal albumTitleClicked(string artistName, string albumTitle)
    signal artistClicked(string artistName)
    
    function formatTime(milliseconds) {
        if (isNaN(milliseconds) || milliseconds < 0) {
            return "0:00"
        }
        
        var totalSeconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    // Custom icon button component (from PlaybackControls)
    component IconButton: Item {
        id: buttonRoot
        property string iconSource: ""
        property string iconPressedSource: ""
        property bool isPressed: false
        property bool isHovered: false
        property bool addShadow: false
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
            
            // Drop shadow for better contrast in light mode
            layer.enabled: buttonRoot.addShadow && !Theme.isDark
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 1
                shadowBlur: 0.3
                shadowColor: "#000000"
                shadowOpacity: 0.5
            }
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
    
    // Blurred background
    BlurredBackground {
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 256
        backgroundOpacity: 0.8
    }
    
    // Overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: Theme.overlayColor
        opacity: Theme.nowPlayingOverlayOpacity
    }
    
    // Top border
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.borderColor
        opacity: 0.5
    }
    
    // Main centered content
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 65
        spacing: 12
        
        // Album art thumbnail (clickable)
        Item {
            Layout.preferredWidth: 65
            Layout.preferredHeight: 65
            Layout.alignment: Qt.AlignVCenter
            
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
                    // Close other popups if open
                    if (root.queuePopupVisible) {
                        root.queuePopupVisible = false
                    }
                    if (root.lyricsPopupVisible) {
                        root.lyricsPopupVisible = false
                    }
                    root.albumArtPopupVisible = !root.albumArtPopupVisible
                }
            }
        }
        
        // Middle section with track info, progress bar and time
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            // Track info at top
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 4
                spacing: 2
                
                // Track title (clickable)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleLabel.implicitHeight
                    
                    Label {
                        id: titleLabel
                        anchors.fill: parent
                        text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                        font.pixelSize: 15
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
                        font.pixelSize: 13
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
                                var track = MediaPlayer.currentTrack
                                var artistToJump = ""

                                // Smart navigation: prioritize track artist if different from album artist
                                if (track.artist && track.albumArtist && track.artist !== track.albumArtist) {
                                    artistToJump = track.artist
                                } else {
                                    artistToJump = track.albumArtist || track.artist
                                }

                                if (artistToJump) {
                                    root.artistClicked(artistToJump)
                                }
                            }
                        }
                    }
                }
            }
            
            // Time display at bottom right
            Label {
                id: timeLabel
                anchors.right: parent.right
                anchors.bottom: progressSlider.top
                anchors.bottomMargin: 1
                text: formatTime(MediaPlayer.savedPosition > 0 ? MediaPlayer.savedPosition : progressSlider.value) + " / " + formatTime(MediaPlayer.duration)
                font.pixelSize: 11
                color: Theme.tertiaryText
            }
            
            // Progress bar at bottom
            Slider {
                id: progressSlider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 20
                from: 0
                to: MediaPlayer.duration
                
                // Prevent keyboard focus to avoid arrow key conflicts
                focusPolicy: Qt.NoFocus
                
                property real targetValue: 0
                property bool isSeeking: false
                
                // Use Binding for cleaner logic
                Binding {
                    target: progressSlider
                    property: "value"
                    value: MediaPlayer.position
                    when: !progressSlider.isSeeking && MediaPlayer.savedPosition === 0
                }
                
                Binding {
                    target: progressSlider
                    property: "value"
                    value: MediaPlayer.savedPosition
                    when: !progressSlider.isSeeking && MediaPlayer.savedPosition > 0
                }
                
                Binding {
                    target: progressSlider
                    property: "value"
                    value: progressSlider.targetValue
                    when: progressSlider.isSeeking
                }
                
                onPressedChanged: {
                    if (pressed) {
                        isSeeking = true
                        targetValue = value
                        seekTimeoutTimer.stop()
                    } else if (isSeeking) {
                        // Keep showing target value until seek completes
                        MediaPlayer.seek(targetValue)
                        // Start timeout timer as fallback
                        seekTimeoutTimer.start()
                    }
                }
                
                // Fallback timer to clear seeking state if position doesn't update
                Timer {
                    id: seekTimeoutTimer
                    interval: 300
                    onTriggered: progressSlider.isSeeking = false
                }
                
                onMoved: {
                    if (pressed) {
                        targetValue = value
                    }
                }
                
                // Monitor position changes to detect when seek completes
                Connections {
                    target: MediaPlayer
                    function onPositionChanged() {
                        if (progressSlider.isSeeking && !progressSlider.pressed) {
                            // Check if position is close to target (within 500ms)
                            var diff = Math.abs(MediaPlayer.position - progressSlider.targetValue)
                            if (diff < 500) {
                                // Seek completed, stop showing target value
                                seekTimeoutTimer.stop()
                                progressSlider.isSeeking = false
                            }
                        }
                    }
                }
                
                background: Rectangle {
                    x: progressSlider.leftPadding + progressSlider.handle.width / 2
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 6
                    width: progressSlider.availableWidth - progressSlider.handle.width
                    height: implicitHeight
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.19) }
                        GradientStop { position: 0.5; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.17) : Qt.rgba(0, 0, 0, 0.17) }
                        GradientStop { position: 1.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.19) : Qt.rgba(0, 0, 0, 0.15) }
                    }
                    opacity: 0.8
                    
                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 3
                        opacity: 0.6
                        
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(0, 0, 0, 0.25) }
                            GradientStop { position: 0.5; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.35) }
                            GradientStop { position: 1.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.4) }
                        }
                    }
                }
                
                handle: Item {
                    id: sliderHandle
                    x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 20
                    implicitHeight: 20
                    
                    property bool shouldShow: progressSlider.hovered || progressSlider.pressed || handleFadeTimer.running
                    opacity: shouldShow ? 1.0 : 0.0
                    scale: progressSlider.pressed ? 0.9 : 1.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    Image {
                        anchors.fill: parent
                        source: progressSlider.pressed ? 
                            "qrc:/resources/icons/drag-handle-pressed.svg" : 
                            "qrc:/resources/icons/drag-handle-normal.svg"
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        smooth: true
                        antialiasing: true
                    }
                    
                    Timer {
                        id: handleFadeTimer
                        interval: 1000
                        running: false
                    }
                    
                    Connections {
                        target: progressSlider
                        function onHoveredChanged() {
                            if (!progressSlider.hovered && !progressSlider.pressed) {
                                handleFadeTimer.restart()
                            } else if (progressSlider.hovered) {
                                handleFadeTimer.stop()
                            }
                        }
                    }
                }
            }
        }
        
        // Playback controls
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
            
            // Previous button
            IconButton {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                iconSource: "qrc:/resources/icons/previous-button-normal.svg"
                iconPressedSource: "qrc:/resources/icons/previous-button-pressed.svg"
                addShadow: true
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
                addShadow: true
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
                addShadow: true
                onClicked: MediaPlayer.next()
            }
            
            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                color: Theme.borderColor
            }
            
            // Repeat/Shuffle pill container
            Rectangle {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 14
                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)
                border.width: 1
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 0
                    
                    // Repeat button
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.height / 2
                            color: MediaPlayer.repeatEnabled ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                        
                        IconButton {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            iconSource: "qrc:/resources/icons/repeat.svg"
                            opacity: MediaPlayer.repeatEnabled ? 1.0 : 0.6
                            addShadow: true
                            onClicked: MediaPlayer.repeatEnabled = !MediaPlayer.repeatEnabled
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200 }
                            }
                        }
                    }
                    
                    // Divider
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)
                    }
                    
                    // Shuffle button
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.height / 2
                            color: MediaPlayer.shuffleEnabled ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                        
                        IconButton {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            iconSource: "qrc:/resources/icons/shuffle.svg"
                            opacity: MediaPlayer.shuffleEnabled ? 1.0 : 0.6
                            addShadow: true
                            onClicked: MediaPlayer.shuffleEnabled = !MediaPlayer.shuffleEnabled
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200 }
                            }
                        }
                    }
                }
            }

            // Queue button (toggle)
            IconButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                iconSource: "qrc:/resources/icons/queue.svg"
                opacity: root.queuePopupVisible ? 1.0 : 0.6
                addShadow: true
                onClicked: {
                    // Close other popups if open
                    if (root.albumArtPopupVisible) {
                        root.albumArtPopupVisible = false
                    }
                    if (root.lyricsPopupVisible) {
                        root.lyricsPopupVisible = false
                    }
                    root.queuePopupVisible = !root.queuePopupVisible
                }

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }

            // Lyrics button (toggle) - only visible when track has lyrics
            IconButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                visible: MediaPlayer.hasCurrentTrackLyrics
                iconSource: Theme.isDark ? "qrc:/resources/icons/lyrics-icon.svg" : "qrc:/resources/icons/lyrics-icon-dark.svg"
                opacity: root.lyricsPopupVisible ? 1.0 : 0.6
                addShadow: true
                onClicked: {
                    // Close other popups if open
                    if (root.albumArtPopupVisible) {
                        root.albumArtPopupVisible = false
                    }
                    if (root.queuePopupVisible) {
                        root.queuePopupVisible = false
                    }
                    root.lyricsPopupVisible = !root.lyricsPopupVisible
                }

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }
        }
    }
}