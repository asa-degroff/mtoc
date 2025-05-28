import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        
        // Playback buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            spacing: 16
            
            Item { Layout.fillWidth: true }
            
            Button {
                id: previousButton
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                onClicked: root.previousClicked()
                
                contentItem: Text {
                    text: "⏮"
                    font.pixelSize: 24
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                background: Rectangle {
                    radius: 24
                    color: previousButton.down ? "white" : (previousButton.hovered ? "white" : "transparent")
                    opacity: previousButton.down ? 0.2 : (previousButton.hovered ? 0.1 : 1.0)
                }
            }
            
            Button {
                id: playPauseButton
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                onClicked: root.playPauseClicked()
                
                contentItem: Item {
                    Text {
                        text: MediaPlayer.state === MediaPlayer.PlayingState ? "⏸" : "▶"
                        font.pixelSize: MediaPlayer.state === MediaPlayer.PlayingState ? 28 : 24
                        color: "white"
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: MediaPlayer.state === MediaPlayer.PlayingState ? 0 : 2
                    }
                }
                
                background: Rectangle {
                    radius: 28
                    color: playPauseButton.down ? "white" : (playPauseButton.hovered ? "white" : "transparent")
                    opacity: playPauseButton.down ? 0.2 : (playPauseButton.hovered ? 0.1 : 1.0)
                    border.color: "white"
                    border.width: 2
                }
            }
            
            Button {
                id: nextButton
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                enabled: MediaPlayer.hasNext
                onClicked: root.nextClicked()
                
                contentItem: Text {
                    text: "⏭"
                    font.pixelSize: 24
                    color: "white"
                    opacity: nextButton.enabled ? 1.0 : 0.3
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                background: Rectangle {
                    radius: 24
                    color: nextButton.down ? "white" : (nextButton.hovered ? "white" : "transparent")
                    opacity: nextButton.enabled ? (nextButton.down ? 0.2 : (nextButton.hovered ? 0.1 : 1.0)) : 0.3
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
                    opacity: 0.2
                    
                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        color: "white"
                        opacity: 0.6
                        radius: 4
                    }
                }
                
                handle: Rectangle {
                    x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 16
                    implicitHeight: 16
                    radius: 8
                    color: "white"
                    opacity: progressSlider.pressed ? 1.0 : 0.8
                    visible: progressSlider.hovered || progressSlider.pressed
                    
                    // Inner glow effect
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: parent.height - 4
                        radius: (width / 2)
                        color: "white"
                        opacity: 0.3
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