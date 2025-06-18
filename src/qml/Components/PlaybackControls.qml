import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Mtoc.Backend 1.0

Item {
    id: root
    
    height: 120
    
    property alias position: progressSlider.value
    property alias duration: progressSlider.to
    
    signal playPauseClicked()
    signal previousClicked()
    signal nextClicked()
    signal seekRequested(real position)
    
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
        }
        
        // Progress bar with time labels
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            spacing: Math.max(4, parent.width * 0.01)  // Dynamic spacing: 1% of width, min 4px
            
            Label {
                text: formatTime(progressSlider.value)
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
                
                value: isSeeking ? targetValue : MediaPlayer.position
                
                onPressedChanged: {
                    if (pressed) {
                        isSeeking = true
                        targetValue = value
                    } else if (isSeeking) {
                        root.seekRequested(targetValue)
                        // Keep isSeeking true briefly to prevent snap-back
                        seekDelayTimer.start()
                    }
                }
                
                onMoved: {
                    if (pressed) {
                        targetValue = value
                    }
                }
                
                Timer {
                    id: seekDelayTimer
                    interval: 100
                    onTriggered: progressSlider.isSeeking = false
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