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
        spacing: 12
        
        // Playback buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            spacing: 20
            
            Item { Layout.fillWidth: true }
            
            Button {
                id: previousButton
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                onClicked: root.previousClicked()
                
                contentItem: Text {
                    text: "⏮"
                    font.pixelSize: 24
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                background: Item {
                    // Outer glow effect
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 6
                        height: parent.height + 6
                        radius: width / 2
                        color: "transparent"
                        border.color: "#30ffffff"
                        border.width: 1
                        opacity: previousButton.hovered ? 0.4 : 0.2
                    }
                    
                    // Main glassmorphic surface
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: previousButton.down ? "#20ffffff" : (previousButton.hovered ? "#35ffffff" : "#25ffffff")
                            }
                            GradientStop { 
                                position: 0.6
                                color: previousButton.down ? "#10ffffff" : (previousButton.hovered ? "#20ffffff" : "#15ffffff")
                            }
                            GradientStop { 
                                position: 1.0
                                color: previousButton.down ? "#05ffffff" : (previousButton.hovered ? "#10ffffff" : "#08ffffff")
                            }
                        }
                        
                        border.color: "#25ffffff"
                        border.width: 1
                    }
                    
                    // Top highlight for 3D effect
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: width / 2
                        
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: previousButton.down ? "#08ffffff" : "#20ffffff"
                            }
                            GradientStop { 
                                position: 0.5
                                color: "transparent"
                            }
                        }
                    }
                }
            }
            
            Button {
                id: playPauseButton
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                onClicked: root.playPauseClicked()
                
                contentItem: Item {
                    Text {
                        text: MediaPlayer.state === MediaPlayer.PlayingState ? "⏸" : "▶"
                        font.pixelSize: MediaPlayer.state === MediaPlayer.PlayingState ? 32 : 28
                        color: "white"
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: MediaPlayer.state === MediaPlayer.PlayingState ? 0 : 3
                    }
                }
                
                background: Item {
                    // Outer glow effect
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8
                        height: parent.height + 8
                        radius: width / 2
                        color: "transparent"
                        border.color: "#40ffffff"
                        border.width: 1.5
                        opacity: playPauseButton.hovered ? 0.5 : 0.3
                    }
                    
                    // Main glassmorphic surface
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: playPauseButton.down ? "#25ffffff" : (playPauseButton.hovered ? "#40ffffff" : "#30ffffff")
                            }
                            GradientStop { 
                                position: 0.6
                                color: playPauseButton.down ? "#15ffffff" : (playPauseButton.hovered ? "#25ffffff" : "#18ffffff")
                            }
                            GradientStop { 
                                position: 1.0
                                color: playPauseButton.down ? "#08ffffff" : (playPauseButton.hovered ? "#15ffffff" : "#10ffffff")
                            }
                        }
                        
                        border.color: "#35ffffff"
                        border.width: 1.5
                    }
                    
                    // Enhanced top highlight for 3D effect
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: width / 2
                        
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: playPauseButton.down ? "#10ffffff" : "#30ffffff"
                            }
                            GradientStop { 
                                position: 0.4
                                color: playPauseButton.down ? "#05ffffff" : "#10ffffff"
                            }
                            GradientStop { 
                                position: 1.0
                                color: "transparent"
                            }
                        }
                    }
                    
                    // Inner shadow for depth
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: width / 2
                        color: "transparent"
                        border.color: playPauseButton.down ? "#15000000" : "#08000000"
                        border.width: 1
                    }
                }
            }
            
            Button {
                id: nextButton
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                enabled: MediaPlayer.hasNext
                onClicked: root.nextClicked()
                
                contentItem: Text {
                    text: "⏭"
                    font.pixelSize: 24
                    color: "white"
                    opacity: nextButton.enabled ? 1.0 : 0.4
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                background: Item {
                    opacity: nextButton.enabled ? 1.0 : 0.4
                    
                    // Outer glow effect
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 6
                        height: parent.height + 6
                        radius: width / 2
                        color: "transparent"
                        border.color: "#30ffffff"
                        border.width: 1
                        opacity: nextButton.hovered ? 0.4 : 0.2
                    }
                    
                    // Main glassmorphic surface
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: nextButton.down ? "#20ffffff" : (nextButton.hovered ? "#35ffffff" : "#25ffffff")
                            }
                            GradientStop { 
                                position: 0.6
                                color: nextButton.down ? "#10ffffff" : (nextButton.hovered ? "#20ffffff" : "#15ffffff")
                            }
                            GradientStop { 
                                position: 1.0
                                color: nextButton.down ? "#05ffffff" : (nextButton.hovered ? "#10ffffff" : "#08ffffff")
                            }
                        }
                        
                        border.color: "#25ffffff"
                        border.width: 1
                    }
                    
                    // Top highlight for 3D effect
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: width / 2
                        
                        gradient: Gradient {
                            GradientStop { 
                                position: 0.0
                                color: nextButton.down ? "#08ffffff" : "#20ffffff"
                            }
                            GradientStop { 
                                position: 0.5
                                color: "transparent"
                            }
                        }
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
                        opacity: 0.8
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