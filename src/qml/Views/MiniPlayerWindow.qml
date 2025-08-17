import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Effects
import Mtoc.Backend 1.0
import "../Components"
import "../"

ApplicationWindow {
    id: miniPlayerWindow
    width: targetWidth
    height: targetHeight
    x: SettingsManager.miniPlayerX >= 0 ? SettingsManager.miniPlayerX : Screen.width / 2 - width / 2
    y: SettingsManager.miniPlayerY >= 0 ? SettingsManager.miniPlayerY : Screen.height / 2 - height / 2
    minimumWidth: targetWidth
    maximumWidth: targetWidth
    minimumHeight: targetHeight
    maximumHeight: targetHeight
    
    // Dynamic dimensions that update when layout changes
    property int targetWidth: SettingsManager.miniPlayerLayout === SettingsManager.Horizontal ? 350 : 220
    property int targetHeight: SettingsManager.miniPlayerLayout === SettingsManager.Horizontal ? 180 : 300
    
    // Recenter window when layout changes (if using default position)
    Connections {
        target: SettingsManager
        function onMiniPlayerLayoutChanged() {
            if (SettingsManager.miniPlayerX < 0 || SettingsManager.miniPlayerY < 0) {
                // Recenter if using default position
                miniPlayerWindow.x = Screen.width / 2 - miniPlayerWindow.width / 2
                miniPlayerWindow.y = Screen.height / 2 - miniPlayerWindow.height / 2
            }
        }
    }
    
    visible: false
    title: SystemInfo.appName + " mini player"
    flags: Qt.Window | Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint
    
    property string currentAlbumId: ""
    property url albumArtUrl: ""
    property url thumbnailUrl: ""
    
    signal maximizeRequested()
    
    // Save position when moved
    onXChanged: if (visible) SettingsManager.miniPlayerX = x
    onYChanged: if (visible) SettingsManager.miniPlayerY = y
    
    // Function to update album art
    function updateAlbumArt() {
        var track = MediaPlayer.currentTrack
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
    
    // Update album art when track changes
    Connections {
        target: MediaPlayer
        
        function onCurrentTrackChanged(track) {
            updateAlbumArt()
        }
    }
    
    // Initialize when window becomes visible
    onVisibleChanged: {
        if (visible) {
            updateAlbumArt()
        }
    }
    
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
        
        scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)
        
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
    
    // Background
    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundColor
    }
    
    // Blurred background
    BlurredBackground {
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 128
        backgroundOpacity: 0.6
    }
    
    // Overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: Theme.overlayColor
        opacity: Theme.nowPlayingOverlayOpacity * 0.7
    }
    
    // Main content - layout depends on setting
    Item {
        anchors.fill: parent
        anchors.margins: 12
        
        // Drag area for moving the window (since it's frameless)
        // This covers the background but not interactive elements
        MouseArea {
            id: dragArea
            anchors.fill: parent
            z: -1  // Behind content but above background
            
            onPressed: function(mouse) {
                // Use the window's built-in drag functionality for frameless windows
                miniPlayerWindow.startSystemMove()
            }
        }
        
        // Vertical layout
        ColumnLayout {
            anchors.fill: parent
            visible: SettingsManager.miniPlayerLayout === SettingsManager.Vertical
            spacing: 12
            
            // Album art - clickable for maximize
            Item {
                Layout.preferredWidth: 140
                Layout.preferredHeight: 140
                Layout.alignment: Qt.AlignHCenter
                
                Image {
                    id: albumArtVertical
                    anchors.fill: parent
                    source: thumbnailUrl
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: Theme.borderColor
                        border.width: 1
                        opacity: 0.3
                    }
                }
                
                // Maximize icon overlay (visible on hover)
                Rectangle {
                    id: maximizeOverlay
                    anchors.fill: parent
                    color: Theme.backgroundColor
                    opacity: 0.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                    
                    Image {
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        source: "qrc:/resources/icons/maximize.svg"
                        sourceSize.width: 64
                        sourceSize.height: 64
                        opacity: 0.9
                    }
                }
                
                // MouseArea for the entire album art
                MouseArea {
                    id: albumClickArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    
                    onEntered: maximizeOverlay.opacity = 0.7
                    onExited: maximizeOverlay.opacity = 0.0
                    onClicked: {
                        console.log("Album art clicked - maximizing")
                        miniPlayerWindow.maximizeRequested()
                    }
                }
            }
            
            // Track info
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                
                Label {
                    Layout.fillWidth: true
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: "#ffffff"  // Always white on dark background
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                
                Label {
                    Layout.fillWidth: true
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                    font.pixelSize: 12
                    color: "#cccccc"  // Light gray for secondary text
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
            
            // Playback controls
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 20
                
                IconButton {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    iconSource: "qrc:/resources/icons/previous-button-normal.svg"
                    iconPressedSource: "qrc:/resources/icons/previous-button-pressed.svg"
                    addShadow: true
                    onClicked: MediaPlayer.previous()
                }
                
                IconButton {
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
                
                IconButton {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    iconSource: "qrc:/resources/icons/skip-button-normal.svg"
                    iconPressedSource: "qrc:/resources/icons/skip-button-pressed.svg"
                    addShadow: true
                    onClicked: MediaPlayer.next()
                }
            }
            
            // Progress bar
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6  // Increased spacing between slider and time labels
                
                Slider {
                    id: progressSliderVertical
                    Layout.fillWidth: true
                    from: 0
                    to: MediaPlayer.duration
                    value: MediaPlayer.position
                    
                    onPressedChanged: {
                        if (!pressed) {
                            MediaPlayer.seek(value)
                        }
                    }
                    
                    background: Rectangle {
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.2)  // More visible on dark background
                        
                        Rectangle {
                            width: progressSliderVertical.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: "#ffffff"  // White progress bar
                        }
                    }
                    
                    handle: Rectangle {
                        x: progressSliderVertical.leftPadding + progressSliderVertical.visualPosition * (progressSliderVertical.availableWidth - width)
                        y: progressSliderVertical.topPadding + progressSliderVertical.availableHeight / 2 - height / 2
                        width: 12
                        height: 12
                        radius: 6
                        color: "#ffffff"  // White handle
                        visible: progressSliderVertical.pressed || progressSliderVertical.hovered
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2  // Small additional margin for visual balance
                    
                    Label {
                        text: formatTime(MediaPlayer.position)
                        font.pixelSize: 10
                        color: "#aaaaaa"  // Light gray for time labels
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Label {
                        text: formatTime(MediaPlayer.duration)
                        font.pixelSize: 10
                        color: "#aaaaaa"  // Light gray for time labels
                    }
                }
            }
            
            Item { Layout.fillHeight: true }
        }
        
        // Horizontal layout
        RowLayout {
            anchors.fill: parent
            visible: SettingsManager.miniPlayerLayout === SettingsManager.Horizontal
            spacing: 12
            
            // Album art - clickable for maximize
            Item {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                Layout.alignment: Qt.AlignVCenter
                
                Image {
                    id: albumArtHorizontal
                    anchors.fill: parent
                    source: thumbnailUrl
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: Theme.borderColor
                        border.width: 1
                        opacity: 0.3
                    }
                }
                
                // Maximize icon overlay (visible on hover)
                Rectangle {
                    id: maximizeOverlayH
                    anchors.fill: parent
                    color: Theme.backgroundColor
                    opacity: 0.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                    
                    Image {
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        source: "qrc:/resources/icons/maximize.svg"
                        sourceSize.width: 64
                        sourceSize.height: 64
                        opacity: 0.9
                    }
                }
                
                // MouseArea for the entire album art
                MouseArea {
                    id: albumClickAreaH
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    
                    onEntered: maximizeOverlayH.opacity = 0.7
                    onExited: maximizeOverlayH.opacity = 0.0
                    onClicked: {
                        console.log("Album art clicked - maximizing")
                        miniPlayerWindow.maximizeRequested()
                    }
                }
            }
            
            // Controls and info
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                
                Item { Layout.fillHeight: true }
                
                // Track info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    Label {
                        Layout.fillWidth: true
                        text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: "#ffffff"  // Always white on dark background
                        elide: Text.ElideRight
                    }
                    
                    Label {
                        Layout.fillWidth: true
                        text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                        font.pixelSize: 12
                        color: "#cccccc"  // Light gray for secondary text
                        elide: Text.ElideRight
                    }
                }
                
                // Playback controls
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14
                    
                    Item { Layout.fillWidth: true }
                    
                    IconButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        iconSource: "qrc:/resources/icons/previous-button-normal.svg"
                        iconPressedSource: "qrc:/resources/icons/previous-button-pressed.svg"
                        addShadow: true
                        onClicked: MediaPlayer.previous()
                    }
                    
                    IconButton {
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
                    
                    IconButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        iconSource: "qrc:/resources/icons/skip-button-normal.svg"
                        iconPressedSource: "qrc:/resources/icons/skip-button-pressed.svg"
                        addShadow: true
                        onClicked: MediaPlayer.next()
                    }
                    
                    Item { Layout.fillWidth: true }
                }
                
                // Progress bar
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6  // Increased spacing between slider and time labels
                    
                    Slider {
                        id: progressSliderHorizontal
                        Layout.fillWidth: true
                        from: 0
                        to: MediaPlayer.duration
                        value: MediaPlayer.position
                        
                        onPressedChanged: {
                            if (!pressed) {
                                MediaPlayer.seek(value)
                            }
                        }
                        
                        background: Rectangle {
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.2)  // More visible on dark background
                            
                            Rectangle {
                                width: progressSliderHorizontal.visualPosition * parent.width
                                height: parent.height
                                radius: 2
                                color: "#ffffff"  // White progress bar
                            }
                        }
                        
                        handle: Rectangle {
                            x: progressSliderHorizontal.leftPadding + progressSliderHorizontal.visualPosition * (progressSliderHorizontal.availableWidth - width)
                            y: progressSliderHorizontal.topPadding + progressSliderHorizontal.availableHeight / 2 - height / 2
                            width: 12
                            height: 12
                            radius: 6
                            color: "#ffffff"  // White handle
                            visible: progressSliderHorizontal.pressed || progressSliderHorizontal.hovered
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2  // Small additional margin for visual balance
                        
                        Label {
                            text: formatTime(MediaPlayer.position)
                            font.pixelSize: 10
                            color: "#aaaaaa"  // Light gray for time labels
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Label {
                            text: formatTime(MediaPlayer.duration)
                            font.pixelSize: 10
                            color: "#aaaaaa"  // Light gray for time labels
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
            }
        }
    }
}