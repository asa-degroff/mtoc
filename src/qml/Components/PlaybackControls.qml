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
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        Image {
            id: iconImage
            anchors.fill: parent
            source: buttonRoot.isPressed && buttonRoot.iconPressedSource ? buttonRoot.iconPressedSource : buttonRoot.iconSource
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            smooth: true
            antialiasing: true
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
        spacing: 12
        
        // Playback buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            spacing: 20
            
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
                    implicitHeight: 8
                    width: progressSlider.availableWidth
                    height: implicitHeight
                    radius: 4
                    color: "white"
                    opacity: 0.1
                    
                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 4
                        
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.95) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.85) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.75) }
                        }
                    }
                }
                
                handle: Rectangle {
                    id: sliderHandle
                    x: progressSlider.leftPadding + progressSlider.visualPosition * progressSlider.availableWidth - width / 2
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 8
                    color: "white"
                    
                    property bool shouldShow: progressSlider.hovered || progressSlider.pressed || handleFadeTimer.running
                    opacity: shouldShow ? (progressSlider.pressed ? 1.0 : 0.9) : 0.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
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
                font.pixelSize: 12
            }
        }
    }
}