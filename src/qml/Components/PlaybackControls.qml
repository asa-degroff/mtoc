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
    
    // Custom glassmorphic button component
    component GlassmorphicButton: Item {
        id: buttonRoot
        property alias radius: bgCircle.radius
        property alias iconItem: iconLoader.sourceComponent
        property bool isPressed: false
        property bool isHovered: false
        signal clicked()
        
        scale: isPressed ? 0.95 : (isHovered ? 1.05 : 1.0)
        
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        Rectangle {
            id: bgCircle
            anchors.fill: parent
            radius: width / 2
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.2)
            
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, buttonRoot.isPressed ? 0.15 : 0.25) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, buttonRoot.isPressed ? 0.05 : 0.1) }
            }
        }
        
        Loader {
            id: iconLoader
            anchors.centerIn: parent
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
        spacing: 12
        
        // Playback buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            spacing: 20
            
            Item { Layout.fillWidth: true }
            
            GlassmorphicButton {
                id: previousButton
                Layout.preferredWidth: 70
                Layout.preferredHeight: 70
                onClicked: root.previousClicked()
                
                iconItem: Shape {
                    width: 24
                    height: 16
                    anchors.centerIn: parent
                    
                    ShapePath {
                        fillColor: Qt.rgba(1, 1, 1, 0.9)
                        strokeColor: "transparent"
                        PathSvg { path: "M 12 0 L 12 16 L 2 8 Z M 22 0 L 22 16 L 12 8 Z" }
                    }
                }
            }
            
            GlassmorphicButton {
                id: playPauseButton
                Layout.preferredWidth: 90
                Layout.preferredHeight: 90
                onClicked: root.playPauseClicked()
                
                iconItem: Item {
                    width: 40
                    height: 30
                    anchors.centerIn: parent
                    
                    // Play icon
                    Shape {
                        anchors.fill: parent
                        visible: MediaPlayer.state !== MediaPlayer.PlayingState
                        opacity: visible ? 1.0 : 0.0
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
                        }
                        
                        ShapePath {
                            fillColor: Qt.rgba(1, 1, 1, 0.95)
                            strokeColor: "transparent"
                            PathSvg { path: "M 12 4 L 12 26 L 32 15 Z" }
                        }
                    }
                    
                    // Pause icon
                    Shape {
                        anchors.fill: parent
                        visible: MediaPlayer.state === MediaPlayer.PlayingState
                        opacity: visible ? 1.0 : 0.0
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
                        }
                        
                        ShapePath {
                            fillColor: Qt.rgba(1, 1, 1, 0.95)
                            strokeColor: "transparent"
                            PathSvg { path: "M 12 4 L 12 26 L 16 26 L 16 4 Z M 24 4 L 24 26 L 28 26 L 28 4 Z" }
                        }
                    }
                }
            }
            
            GlassmorphicButton {
                id: nextButton
                Layout.preferredWidth: 70
                Layout.preferredHeight: 70
                enabled: MediaPlayer.hasNext
                opacity: enabled ? 1.0 : 0.3
                onClicked: root.nextClicked()
                
                iconItem: Shape {
                    width: 24
                    height: 16
                    anchors.centerIn: parent
                    
                    ShapePath {
                        fillColor: Qt.rgba(1, 1, 1, 0.9)
                        strokeColor: "transparent"
                        PathSvg { path: "M 2 0 L 12 8 L 2 16 Z M 12 0 L 22 8 L 12 16 Z" }
                    }
                }
            }
            
            Item { Layout.fillWidth: true }
        }
        
        // Progress bar with time labels
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 12
            
            Label {
                text: formatTime(progressSlider.value)
                color: "#b0b0b0"
                font.pixelSize: 12
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
                    x: progressSlider.leftPadding
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: progressSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: "white"
                    opacity: 0.15
                    
                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        color: "white"
                        opacity: 0.9
                        radius: 2
                    }
                }
                
                handle: Rectangle {
                    x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 12
                    implicitHeight: 12
                    radius: 6
                    color: "white"
                    opacity: progressSlider.pressed ? 1.0 : 0.9
                    visible: progressSlider.hovered || progressSlider.pressed
                }
            }
            
            Label {
                text: formatTime(MediaPlayer.duration)
                color: "#b0b0b0"
                font.pixelSize: 12
            }
        }
    }
}