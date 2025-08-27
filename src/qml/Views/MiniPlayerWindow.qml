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
    property int targetWidth: SettingsManager.miniPlayerLayout === SettingsManager.Horizontal ? 350 : 
                             (SettingsManager.miniPlayerLayout === SettingsManager.CompactBar ? 400 : 220)
    property int targetHeight: SettingsManager.miniPlayerLayout === SettingsManager.Horizontal ? 180 : 
                              (SettingsManager.miniPlayerLayout === SettingsManager.CompactBar ? 70 : 300)
    
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
    
    // Blurred background - full window for vertical/horizontal layouts
    BlurredBackground {
        anchors.fill: parent
        visible: SettingsManager.miniPlayerLayout !== SettingsManager.CompactBar
        source: thumbnailUrl
        blurRadius: 128
        backgroundOpacity: 0.6
    }
    
    // Blurred background - only right side for compact layout
    BlurredBackground {
        anchors.left: parent.left
        anchors.leftMargin: 70  // Start after album art
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: SettingsManager.miniPlayerLayout === SettingsManager.CompactBar
        source: thumbnailUrl
        blurRadius: 128
        backgroundOpacity: 0.6
    }
    
    // Overlay for better contrast - full window for vertical/horizontal
    Rectangle {
        anchors.fill: parent
        visible: SettingsManager.miniPlayerLayout !== SettingsManager.CompactBar
        color: Theme.overlayColor
        opacity: Theme.nowPlayingOverlayOpacity * 0.7
    }
    
    // Overlay for better contrast - only right side for compact
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 70  // Start after album art
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: SettingsManager.miniPlayerLayout === SettingsManager.CompactBar
        color: Theme.overlayColor
        opacity: Theme.nowPlayingOverlayOpacity * 0.7
    }
    
    // Main content - layout depends on setting
    Item {
        anchors.fill: parent
        anchors.margins: 12
        
        // Background drag area that allows events to propagate to children
        MouseArea {
            id: dragArea
            anchors.fill: parent
            propagateComposedEvents: true
            z: -1  // Behind all content
            
            onPressed: function(mouse) {
                // Start window drag
                miniPlayerWindow.startSystemMove()
                // Don't accept the event so it can propagate to children
                mouse.accepted = false
            }
        }
        
        // Vertical layout
        ColumnLayout {
            anchors.fill: parent
            visible: SettingsManager.miniPlayerLayout === SettingsManager.Vertical
            spacing: 8
            
            // Album art - clickable for maximize
            Item {
                Layout.preferredWidth: 150
                Layout.preferredHeight: 150
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                
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
                        source: Theme.isDark ? "qrc:/resources/icons/maximize.svg" : "qrc:/resources/icons/maximize-dark.svg"
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
                spacing: 2
                
                Label {
                    Layout.fillWidth: true
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: Theme.primaryText
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                
                Label {
                    Layout.fillWidth: true
                    text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                    font.pixelSize: 12
                    color: Theme.secondaryText
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
            
            // Playback controls
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 16
                
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
                spacing: 4  // Increased spacing between slider and time labels
                
                Slider {
                    id: progressSliderVertical
                    Layout.fillWidth: true
                    from: 0
                    to: MediaPlayer.duration
                    
                    // Prevent keyboard focus to avoid arrow key conflicts
                    focusPolicy: Qt.NoFocus
                    
                    property real targetValue: 0
                    property bool isSeeking: false
                    
                    // Use Binding for cleaner logic
                    Binding {
                        target: progressSliderVertical
                        property: "value"
                        value: MediaPlayer.position
                        when: !progressSliderVertical.isSeeking
                    }
                    
                    Binding {
                        target: progressSliderVertical
                        property: "value"
                        value: progressSliderVertical.targetValue
                        when: progressSliderVertical.isSeeking
                    }
                    
                    onPressedChanged: {
                        if (pressed) {
                            isSeeking = true
                            targetValue = value
                            seekTimeoutTimerV.stop()
                        } else if (isSeeking) {
                            // Keep showing target value until seek completes
                            MediaPlayer.seek(targetValue)
                            // Start timeout timer as fallback
                            seekTimeoutTimerV.start()
                        }
                    }
                    
                    // Fallback timer to clear seeking state if position doesn't update
                    Timer {
                        id: seekTimeoutTimerV
                        interval: 300
                        onTriggered: progressSliderVertical.isSeeking = false
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
                            if (progressSliderVertical.isSeeking && !progressSliderVertical.pressed) {
                                // Check if position is close to target (within 500ms)
                                var diff = Math.abs(MediaPlayer.position - progressSliderVertical.targetValue)
                                if (diff < 500) {
                                    // Seek completed, stop showing target value
                                    seekTimeoutTimerV.stop()
                                    progressSliderVertical.isSeeking = false
                                }
                            }
                        }
                    }
                    
                    background: Rectangle {
                        x: progressSliderVertical.leftPadding
                        y: progressSliderVertical.topPadding + progressSliderVertical.availableHeight / 2 - height / 2
                        implicitWidth: 200
                        implicitHeight: 8  // Larger hit area for easier clicking
                        width: progressSliderVertical.availableWidth
                        height: implicitHeight
                        color: "transparent"  // Invisible hit area
                        
                        // Visual track (smaller than hit area)
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 3  // Visual height is smaller
                            radius: 1.5
                            color: Qt.rgba(1, 1, 1, 0.15)  // Semi-transparent background
                            
                            Rectangle {
                                width: progressSliderVertical.visualPosition * parent.width
                                height: parent.height
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.7)  // Semi-transparent white progress bar
                            }
                        }
                    }
                    
                    handle: Rectangle {
                        x: progressSliderVertical.leftPadding + progressSliderVertical.visualPosition * (progressSliderVertical.availableWidth - width)
                        y: progressSliderVertical.topPadding + progressSliderVertical.availableHeight / 2 - height / 2
                        width: 10
                        height: 10
                        radius: 5
                        color: Qt.rgba(1, 1, 1, 0.9)  // Semi-transparent white handle
                        opacity: progressSliderVertical.pressed || progressSliderVertical.hovered ? 1.0 : 0.0
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                        }
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2  // Small additional margin for visual balance
                    
                    Label {
                        text: formatTime(MediaPlayer.position)
                        font.pixelSize: 10
                        color: Theme.tertiaryText
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    Label {
                        text: formatTime(MediaPlayer.duration)
                        font.pixelSize: 10
                        color: Theme.tertiaryText
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
                Layout.preferredWidth: 157
                Layout.preferredHeight: 157
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
                        source: Theme.isDark ? "qrc:/resources/icons/maximize.svg" : "qrc:/resources/icons/maximize-dark.svg"
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
                        color: Theme.primaryText
                        elide: Text.ElideRight
                    }
                    
                    Label {
                        Layout.fillWidth: true
                        text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                        font.pixelSize: 12
                        color: Theme.secondaryText
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
                        
                        // Prevent keyboard focus to avoid arrow key conflicts
                        focusPolicy: Qt.NoFocus
                        
                        property real targetValue: 0
                        property bool isSeeking: false
                        
                        // Use Binding for cleaner logic
                        Binding {
                            target: progressSliderHorizontal
                            property: "value"
                            value: MediaPlayer.position
                            when: !progressSliderHorizontal.isSeeking
                        }
                        
                        Binding {
                            target: progressSliderHorizontal
                            property: "value"
                            value: progressSliderHorizontal.targetValue
                            when: progressSliderHorizontal.isSeeking
                        }
                        
                        onPressedChanged: {
                            if (pressed) {
                                isSeeking = true
                                targetValue = value
                                seekTimeoutTimerH.stop()
                            } else if (isSeeking) {
                                // Keep showing target value until seek completes
                                MediaPlayer.seek(targetValue)
                                // Start timeout timer as fallback
                                seekTimeoutTimerH.start()
                            }
                        }
                        
                        // Fallback timer to clear seeking state if position doesn't update
                        Timer {
                            id: seekTimeoutTimerH
                            interval: 300
                            onTriggered: progressSliderHorizontal.isSeeking = false
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
                                if (progressSliderHorizontal.isSeeking && !progressSliderHorizontal.pressed) {
                                    // Check if position is close to target (within 500ms)
                                    var diff = Math.abs(MediaPlayer.position - progressSliderHorizontal.targetValue)
                                    if (diff < 500) {
                                        // Seek completed, stop showing target value
                                        seekTimeoutTimerH.stop()
                                        progressSliderHorizontal.isSeeking = false
                                    }
                                }
                            }
                        }
                        
                        background: Rectangle {
                            x: progressSliderHorizontal.leftPadding
                            y: progressSliderHorizontal.topPadding + progressSliderHorizontal.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 8  // Larger hit area for easier clicking
                            width: progressSliderHorizontal.availableWidth
                            height: implicitHeight
                            color: "transparent"  // Invisible hit area
                            
                            // Visual track (smaller than hit area)
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 3  // Visual height is smaller
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.15)  // Semi-transparent background
                                
                                Rectangle {
                                    width: progressSliderHorizontal.visualPosition * parent.width
                                    height: parent.height
                                    radius: 1.5
                                    color: Qt.rgba(1, 1, 1, 0.7)  // Semi-transparent white progress bar
                                }
                            }
                        }
                        
                        handle: Rectangle {
                            x: progressSliderHorizontal.leftPadding + progressSliderHorizontal.visualPosition * (progressSliderHorizontal.availableWidth - width)
                            y: progressSliderHorizontal.topPadding + progressSliderHorizontal.availableHeight / 2 - height / 2
                            width: 10
                            height: 10
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.9)  // Semi-transparent white handle
                            opacity: progressSliderHorizontal.pressed || progressSliderHorizontal.hovered ? 1.0 : 0.0
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2  // Small additional margin for visual balance
                        
                        Label {
                            text: formatTime(MediaPlayer.position)
                            font.pixelSize: 10
                            color: Theme.tertiaryText
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Label {
                            text: formatTime(MediaPlayer.duration)
                            font.pixelSize: 10
                            color: Theme.tertiaryText
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
            }
        }
        
        // Compact layout
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: -12  // Override parent margin for album art
            anchors.topMargin: -12
            anchors.bottomMargin: -12
            anchors.rightMargin: 0
            visible: SettingsManager.miniPlayerLayout === SettingsManager.CompactBar
            spacing: 12
            
            // Album art - clickable for maximize (full height on left edge)
            Item {
                Layout.preferredWidth: 70
                Layout.preferredHeight: 70
                Layout.alignment: Qt.AlignVCenter
                
                Image {
                    id: albumArtCompact
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
                    id: maximizeOverlayC
                    anchors.fill: parent
                    color: Theme.backgroundColor
                    opacity: 0.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                    
                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: Theme.isDark ? "qrc:/resources/icons/maximize.svg" : "qrc:/resources/icons/maximize-dark.svg"
                        sourceSize.width: 48
                        sourceSize.height: 48
                        opacity: 0.9
                    }
                }
                
                // MouseArea for the entire album art
                MouseArea {
                    id: albumClickAreaC
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    
                    onEntered: maximizeOverlayC.opacity = 0.7
                    onExited: maximizeOverlayC.opacity = 0.0
                    onClicked: {
                        console.log("Album art clicked - maximizing")
                        miniPlayerWindow.maximizeRequested()
                    }
                }
            }
            
            // Track info and progress section
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                
                // Track info row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    // Track title and artist
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        
                        Label {
                            Layout.fillWidth: true
                            text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Theme.primaryText
                            elide: Text.ElideRight
                        }
                        
                        Label {
                            Layout.fillWidth: true
                            text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                            font.pixelSize: 10
                            color: Theme.secondaryText
                            elide: Text.ElideRight
                        }
                    }
                }
                
                // Progress bar with time labels
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    
                    Label {
                        text: formatTime(MediaPlayer.position)
                        font.pixelSize: 9
                        color: Theme.tertiaryText
                    }
                    
                    Slider {
                        id: progressSliderCompact
                        Layout.fillWidth: true
                        from: 0
                        to: MediaPlayer.duration
                        
                        // Prevent keyboard focus to avoid arrow key conflicts
                        focusPolicy: Qt.NoFocus
                        
                        property real targetValue: 0
                        property bool isSeeking: false
                        
                        // Use Binding for cleaner logic
                        Binding {
                            target: progressSliderCompact
                            property: "value"
                            value: MediaPlayer.position
                            when: !progressSliderCompact.isSeeking
                        }
                        
                        Binding {
                            target: progressSliderCompact
                            property: "value"
                            value: progressSliderCompact.targetValue
                            when: progressSliderCompact.isSeeking
                        }
                        
                        onPressedChanged: {
                            if (pressed) {
                                isSeeking = true
                                targetValue = value
                                seekTimeoutTimerC.stop()
                            } else if (isSeeking) {
                                MediaPlayer.seek(targetValue)
                                seekTimeoutTimerC.start()
                            }
                        }
                        
                        Timer {
                            id: seekTimeoutTimerC
                            interval: 300
                            onTriggered: progressSliderCompact.isSeeking = false
                        }
                        
                        onMoved: {
                            if (pressed) {
                                targetValue = value
                            }
                        }
                        
                        Connections {
                            target: MediaPlayer
                            function onPositionChanged() {
                                if (progressSliderCompact.isSeeking && !progressSliderCompact.pressed) {
                                    var diff = Math.abs(MediaPlayer.position - progressSliderCompact.targetValue)
                                    if (diff < 500) {
                                        seekTimeoutTimerC.stop()
                                        progressSliderCompact.isSeeking = false
                                    }
                                }
                            }
                        }
                        
                        background: Rectangle {
                            x: progressSliderCompact.leftPadding
                            y: progressSliderCompact.topPadding + progressSliderCompact.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 8
                            width: progressSliderCompact.availableWidth
                            height: implicitHeight
                            color: "transparent"
                            
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 2
                                radius: 1
                                color: Qt.rgba(1, 1, 1, 0.15)
                                
                                Rectangle {
                                    width: progressSliderCompact.visualPosition * parent.width
                                    height: parent.height
                                    radius: 1
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                }
                            }
                        }
                        
                        handle: Rectangle {
                            x: progressSliderCompact.leftPadding + progressSliderCompact.visualPosition * (progressSliderCompact.availableWidth - width)
                            y: progressSliderCompact.topPadding + progressSliderCompact.availableHeight / 2 - height / 2
                            width: 8
                            height: 8
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.9)
                            opacity: progressSliderCompact.pressed || progressSliderCompact.hovered ? 1.0 : 0.0
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                    
                    Label {
                        text: formatTime(MediaPlayer.duration)
                        font.pixelSize: 9
                        color: Theme.tertiaryText
                    }
                }
            }
            
            // Playback controls
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 8
                
                IconButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    iconSource: "qrc:/resources/icons/previous-button-normal.svg"
                    iconPressedSource: "qrc:/resources/icons/previous-button-pressed.svg"
                    addShadow: true
                    onClicked: MediaPlayer.previous()
                }
                
                IconButton {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
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
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    iconSource: "qrc:/resources/icons/skip-button-normal.svg"
                    iconPressedSource: "qrc:/resources/icons/skip-button-pressed.svg"
                    addShadow: true
                    onClicked: MediaPlayer.next()
                }
            }
        }
    }
}