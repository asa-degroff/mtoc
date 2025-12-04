import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Mtoc.Backend 1.0

Item {
    id: root
    
    height: 120
    
    // Remove these aliases as they might cause binding loops
    // property alias position: progressSlider.value
    // property alias duration: progressSlider.to
    
    signal playPauseClicked()
    signal previousClicked()
    signal nextClicked()
    signal seekRequested(real position)
    signal queueToggled()
    signal lyricsToggled()
    signal repeatToggled()
    signal shuffleToggled()
    signal favoriteToggled()

    property bool queueVisible: false
    property bool lyricsVisible: false
    property bool repeatEnabled: MediaPlayer.repeatEnabled
    property bool shuffleEnabled: MediaPlayer.shuffleEnabled
    property bool isFavorite: false
    
    function formatTime(milliseconds) {
        if (isNaN(milliseconds) || milliseconds < 0) {
            return "0:00"
        }
        
        var totalSeconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    // Custom icon button component
    component IconButton: Item {
        id: buttonRoot
        property string iconSource: ""
        property string iconPressedSource: ""
        property bool isPressed: false
        property bool isHovered: false
        property bool addShadow: false
        property bool enableTint: false
        property color tintColor: "transparent"
        property real tintAmount: 0.8
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
            
            // Drop shadow for better contrast in light mode, and optional color tint
            layer.enabled: (buttonRoot.addShadow && !Theme.isDark) || buttonRoot.enableTint
            layer.effect: MultiEffect {
                shadowEnabled: buttonRoot.addShadow && !Theme.isDark
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 1
                shadowBlur: 0.3
                shadowColor: "#000000"
                shadowOpacity: 0.5
                colorization: buttonRoot.enableTint ? buttonRoot.tintAmount : 0.0
                colorizationColor: buttonRoot.tintColor
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
    
    ColumnLayout {
        anchors.fill: parent
        spacing: Math.max(8, parent.height * 0.1)  // Dynamic spacing: 10% of height, min 8px
        
        // Playback buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            spacing: Math.max(12, parent.width * 0.02)  // Dynamic spacing: 2% of width, min 12px
            
            // Repeat/Shuffle pill container
            Rectangle {
                Layout.preferredWidth: 94
                Layout.preferredHeight: 31
                Layout.alignment: Qt.AlignVCenter
                radius: 25
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
                            color: root.repeatEnabled ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                        
                        IconButton {
                            id: repeatButton
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            iconSource: "qrc:/resources/icons/repeat.svg"
                            opacity: root.repeatEnabled ? 1.0 : 0.6
                            addShadow: true
                            onClicked: root.repeatToggled()
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200 }
                            }
                        }
                    }
                    
                    // Divider
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
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
                            color: root.shuffleEnabled ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                        
                        IconButton {
                            id: shuffleButton
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            iconSource: "qrc:/resources/icons/shuffle.svg"
                            opacity: root.shuffleEnabled ? 1.0 : 0.6
                            addShadow: true
                            onClicked: root.shuffleToggled()
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200 }
                            }
                        }
                    }
                }
            }
            
            Item { Layout.fillWidth: true }
            
            IconButton {
                id: previousButton
                Layout.preferredWidth: 60
                Layout.preferredHeight: 60
                iconSource: "qrc:/resources/icons/previous-button-normal.svg"
                iconPressedSource: "qrc:/resources/icons/previous-button-pressed.svg"
                onClicked: root.previousClicked()
            }
            
            IconButton {
                id: playPauseButton
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                iconSource: MediaPlayer.state === MediaPlayer.PlayingState ? 
                    "qrc:/resources/icons/pause-button-normal.svg" : 
                    "qrc:/resources/icons/play-button-normal.svg"
                iconPressedSource: MediaPlayer.state === MediaPlayer.PlayingState ? 
                    "qrc:/resources/icons/pause-button-pressed.svg" : 
                    "qrc:/resources/icons/play-button-pressed.svg"
                onClicked: root.playPauseClicked()
            }
            
            IconButton {
                id: nextButton
                Layout.preferredWidth: 60
                Layout.preferredHeight: 60
                enabled: MediaPlayer.hasNext
                opacity: enabled ? 1.0 : 0.3
                iconSource: "qrc:/resources/icons/skip-button-normal.svg"
                iconPressedSource: "qrc:/resources/icons/skip-button-pressed.svg"
                onClicked: root.nextClicked()
            }
            
            Item { Layout.fillWidth: true }
            
            // Favorite, Lyrics and Queue button container
            Item {
                id: rightButtonContainer
                Layout.preferredWidth: 94
                Layout.preferredHeight: 31
                Layout.alignment: Qt.AlignVCenter

                // Favorite and queue are always shown, lyrics is conditional
                // Always reserve space for 3 buttons to keep play/pause centered
                property real buttonSpacing: 8
                property real buttonSize: 26
                property real totalButtonsWidth: 3 * buttonSize + 2 * buttonSpacing // 94px total
                property bool hasLyrics: MediaPlayer.hasCurrentTrackLyrics
                // Width for 2 buttons (when no lyrics)
                property real twoButtonsWidth: 2 * buttonSize + buttonSpacing // 60px

                // Calculate absolute start positions for both states
                property real threeButtonStart: (width - totalButtonsWidth) / 2
                property real twoButtonStart: (width - twoButtonsWidth) / 2

                // Favorite button (leftmost)
                IconButton {
                    id: favoriteButton
                    width: rightButtonContainer.buttonSize
                    height: rightButtonContainer.buttonSize
                    anchors.verticalCenter: parent.verticalCenter
                    x: rightButtonContainer.hasLyrics ? rightButtonContainer.threeButtonStart : rightButtonContainer.twoButtonStart
                    iconSource: root.isFavorite ? "qrc:/resources/icons/heart-normal.svg" : "qrc:/resources/icons/heart-outline.svg"
                    iconPressedSource: "qrc:/resources/icons/heart-pressed.svg"
                    opacity: root.isFavorite ? 1.0 : 0.6
                    addShadow: true
                    enableTint: root.isFavorite
                    tintColor: Theme.systemAccentColor
                    tintAmount: 0.7
                    onClicked: root.favoriteToggled()

                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.InOutCubic }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }

                // Lyrics button (middle, only visible when track has lyrics)
                IconButton {
                    id: lyricsButton
                    width: rightButtonContainer.buttonSize
                    height: rightButtonContainer.buttonSize
                    anchors.verticalCenter: parent.verticalCenter
                    // Absolute position: always in the middle slot
                    x: rightButtonContainer.threeButtonStart + rightButtonContainer.buttonSize + rightButtonContainer.buttonSpacing
                    visible: opacity > 0
                    opacity: rightButtonContainer.hasLyrics ? (root.lyricsVisible ? 1.0 : 0.6) : 0.0
                    iconSource: "qrc:/resources/icons/lyrics-icon.svg"
                    addShadow: true
                    onClicked: root.lyricsToggled()

                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.InOutCubic }
                    }
                }

                // Queue button (rightmost)
                IconButton {
                    id: queueButton
                    width: rightButtonContainer.buttonSize
                    height: rightButtonContainer.buttonSize
                    anchors.verticalCenter: parent.verticalCenter
                    // Absolute position calculated from hasLyrics state directly
                    x: rightButtonContainer.hasLyrics
                        ? (rightButtonContainer.threeButtonStart + 2 * (rightButtonContainer.buttonSize + rightButtonContainer.buttonSpacing))
                        : (rightButtonContainer.twoButtonStart + rightButtonContainer.buttonSize + rightButtonContainer.buttonSpacing)
                    iconSource: "qrc:/resources/icons/queue.svg"
                    opacity: root.queueVisible ? 1.0 : 0.6
                    addShadow: true
                    onClicked: root.queueToggled()

                    Behavior on x {
                        NumberAnimation { duration: 200; easing.type: Easing.InOutCubic }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }
            }
        }
        
        // Progress bar with time labels
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            spacing: Math.max(4, parent.width * 0.01)  // Dynamic spacing: 1% of width, min 4px
            
            Label {
                text: formatTime(MediaPlayer.savedPosition > 0 ? MediaPlayer.savedPosition : progressSlider.value)
                color: Theme.secondaryText
                font.pixelSize: 14
                Layout.preferredWidth: 45  // Fixed width for consistent alignment
                horizontalAlignment: Text.AlignRight
            }
            
            Slider {
                id: progressSlider
                Layout.fillWidth: true
                from: 0
                to: MediaPlayer.duration
                
                // Prevent keyboard focus to avoid arrow key conflicts
                focusPolicy: Qt.NoFocus
                
                property real targetValue: 0
                property bool isSeeking: false
                
                // Debug property to track what's happening
                property bool debugEnabled: false
                
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
                        root.seekRequested(targetValue)
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
                    implicitHeight: 10
                    width: progressSlider.availableWidth - progressSlider.handle.width
                    height: implicitHeight
                    radius: 5
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
                        radius: 5
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
                    implicitWidth: 36
                    implicitHeight: 36
                    
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
            
            Label {
                text: formatTime(MediaPlayer.duration)
                color: Theme.secondaryText
                font.pixelSize: 14
                Layout.preferredWidth: 45  // Fixed width for consistent alignment
                horizontalAlignment: Text.AlignLeft
            }
        }
    }
}