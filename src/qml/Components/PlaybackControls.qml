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
                icon.name: "media-skip-backward"
                icon.width: 24
                icon.height: 24
                onClicked: root.previousClicked()
                
                background: Rectangle {
                    radius: 24
                    color: previousButton.down ? "#303030" : (previousButton.hovered ? "#282828" : "transparent")
                }
            }
            
            Button {
                id: playPauseButton
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                icon.name: MediaPlayer.state === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                icon.width: 32
                icon.height: 32
                onClicked: root.playPauseClicked()
                
                background: Rectangle {
                    radius: 28
                    color: playPauseButton.down ? "#404040" : (playPauseButton.hovered ? "#383838" : "#303030")
                }
            }
            
            Button {
                id: nextButton
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                icon.name: "media-skip-forward"
                icon.width: 24
                icon.height: 24
                enabled: MediaPlayer.hasNext
                onClicked: root.nextClicked()
                
                background: Rectangle {
                    radius: 24
                    color: nextButton.down ? "#303030" : (nextButton.hovered ? "#282828" : "transparent")
                    opacity: nextButton.enabled ? 1.0 : 0.3
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
                value: MediaPlayer.position
                
                onPressedChanged: {
                    if (!pressed && value !== MediaPlayer.position) {
                        root.seekRequested(value)
                    }
                }
                
                background: Rectangle {
                    x: progressSlider.leftPadding
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200
                    implicitHeight: 4
                    width: progressSlider.availableWidth
                    height: implicitHeight
                    radius: 2
                    color: "#202020"
                    
                    Rectangle {
                        width: progressSlider.visualPosition * parent.width
                        height: parent.height
                        color: "#1db954"
                        radius: 2
                    }
                }
                
                handle: Rectangle {
                    x: progressSlider.leftPadding + progressSlider.visualPosition * (progressSlider.availableWidth - width)
                    y: progressSlider.topPadding + progressSlider.availableHeight / 2 - height / 2
                    implicitWidth: 12
                    implicitHeight: 12
                    radius: 6
                    color: progressSlider.pressed ? "#1ed760" : "#ffffff"
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