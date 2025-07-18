import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
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
    signal repeatToggled()
    signal shuffleToggled()
    
    property bool queueVisible: false
    property bool repeatEnabled: false
    property bool shuffleEnabled: false
    
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
                Layout.preferredWidth: 90
                Layout.preferredHeight: 37.5
                Layout.alignment: Qt.AlignVCenter
                radius: 25
                color: Qt.rgba(1, 1, 1, 0.1)
                border.color: Qt.rgba(1, 1, 1, 0.2)
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
                            color: root.repeatEnabled ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                        
                        IconButton {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            iconSource: "qrc:/resources/icons/repeat.svg"
                            opacity: root.repeatEnabled ? 1.0 : 0.6
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
                        color: Qt.rgba(1, 1, 1, 0.2)
                    }
                    
                    // Shuffle button
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.height / 2
                            color: root.shuffleEnabled ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                        
                        IconButton {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            iconSource: "qrc:/resources/icons/shuffle.svg"
                            opacity: root.shuffleEnabled ? 1.0 : 0.6
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
            
            // Queue button container (matching repeat/shuffle width)
            Item {
                Layout.preferredWidth: 90
                Layout.preferredHeight: 37.5
                Layout.alignment: Qt.AlignVCenter
                
                // Queue button
                IconButton {
                    id: queueButton
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    iconSource: "qrc:/resources/icons/queue.svg"
                    opacity: root.queueVisible ? 1.0 : 0.6
                    onClicked: root.queueToggled()
                    
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
                color: "#b0b0b0"
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
                    color: "white"
                    opacity: 0.1
                    
                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 6
                        
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.95) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.85) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.75) }
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
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    Image {
                        anchors.fill: parent
                        source: progressSlider.pressed ? 
                            "qrc:/resources/icons/drag-handle-pressed.svg" : 
                            "qrc:/resources/icons/drag-handle-normal.svg"
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        smooth: true
                        antialiasing: false
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
                color: "#b0b0b0"
                font.pixelSize: 14
                Layout.preferredWidth: 45  // Fixed width for consistent alignment
                horizontalAlignment: Text.AlignLeft
            }
        }
    }
}