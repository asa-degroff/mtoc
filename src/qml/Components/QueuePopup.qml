import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Popup {
    id: root
    
    property alias queueModel: queueListView.queueModel
    property alias currentPlayingIndex: queueListView.currentPlayingIndex
    property bool showPlaylistSavedMessage: false
    property string savedPlaylistName: ""
    
    width: parent.width * 0.8
    height: parent.height * 0.8
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    // Slide up animation on enter
    enter: Transition {
        NumberAnimation {
            property: "y"
            from: parent.height
            to: (parent.height - height) / 2
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    
    // Slide down animation on exit
    exit: Transition {
        NumberAnimation {
            property: "y"
            from: (parent.height - height) / 2
            to: parent.height
            duration: 300
            easing.type: Easing.InCubic
        }
    }
    
    // Timer to hide playlist saved message
    Timer {
        id: playlistSavedMessageTimer
        interval: 2500
        repeat: false
        onTriggered: {
            showPlaylistSavedMessage = false
        }
    }
    
    Component.onCompleted: {
        // Connect to playlist saved signal
        PlaylistManager.playlistSaved.connect(function(name) {
            savedPlaylistName = name
            showPlaylistSavedMessage = true
            playlistSavedMessageTimer.restart()
        })
    }
    
    // Semi-transparent background overlay with fade animation
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: root.visible ? 1.0 : 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.InOutCubic
            }
        }
    }
    
    background: Rectangle {
        color: Theme.backgroundColor
        radius: 8
        
        // Drop shadow
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
            shadowBlur: 0.5
            shadowColor: "#80000000"
        }
    }
    
    contentItem: ColumnLayout {
        spacing: 0
        
        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: Theme.panelBackground
            radius: 8
            
            // Bottom corners square
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 8
                color: parent.color
            }
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                
                Label {
                    text: "Queue"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.primaryText
                }
                
                Label {
                    text: showPlaylistSavedMessage ? "Playlist Saved" :
                          MediaPlayer.queueLength + " tracks • " + formatQueueDuration(MediaPlayer.totalQueueDuration)
                    font.pixelSize: 14
                    color: showPlaylistSavedMessage ? "#60ff60" : Theme.secondaryText
                    
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                // Save queue button
                Item {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    visible: MediaPlayer.queueLength > 0 && !MediaPlayer.isPlayingVirtualPlaylist
                    
                    Rectangle {
                        id: saveButtonBackground
                        anchors.fill: parent
                        radius: 4
                        color: saveButtonMouseArea.containsMouse ? Qt.rgba(0, 1, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.3)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Image {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: Theme.isDark ? "qrc:/resources/icons/save.svg" : "qrc:/resources/icons/save-dark.svg"
                            sourceSize.width: 36
                            sourceSize.height: 36
                            fillMode: Image.PreserveAspectFit
                            opacity: saveButtonMouseArea.containsMouse ? 0.7 : 1.0
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }
                        }
                        
                        MouseArea {
                            id: saveButtonMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (PlaylistManager.saveQueueAsPlaylist()) {
                                    console.log("Queue saved as playlist");
                                }
                            }
                        }
                    }
                    
                    ToolTip {
                        visible: saveButtonMouseArea.containsMouse
                        text: "Save queue as playlist"
                        delay: 500
                    }
                }
                
                // Clear queue button
                Item {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    visible: (MediaPlayer.queueLength > 0 || MediaPlayer.canUndoClear) && !MediaPlayer.isPlayingVirtualPlaylist
                    
                    Rectangle {
                        id: clearButtonBackground
                        anchors.fill: parent
                        radius: 4
                        color: clearButtonMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.3)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Image {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: MediaPlayer.canUndoClear ? "qrc:/resources/icons/undo.svg" : Theme.isDark ? "qrc:/resources/icons/bomb.svg" : "qrc:/resources/icons/bomb-dark.svg"
                            sourceSize.width: 36
                            sourceSize.height: 36
                            fillMode: Image.PreserveAspectFit
                            opacity: clearButtonMouseArea.containsMouse ? 0.7 : 1.0
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }
                        }
                        
                        MouseArea {
                            id: clearButtonMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (MediaPlayer.canUndoClear) {
                                    MediaPlayer.undoClearQueue();
                                } else {
                                    queueListView.clearAllTracks();
                                }
                            }
                        }
                    }
                    
                    ToolTip {
                        visible: clearButtonMouseArea.containsMouse
                        text: MediaPlayer.canUndoClear ? "Undo clear queue" : "Clear queue"
                        delay: 500
                    }
                }
                
                // Close button
                ToolButton {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    onClicked: root.close()
                    
                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Theme.isDark ? "qrc:/resources/icons/close-button.svg" : "qrc:/resources/icons/close-button-dark.svg"
                        sourceSize.width: 36
                        sourceSize.height: 36
                        fillMode: Image.PreserveAspectFit
                        opacity: Theme.isDark ? 1.0 : 0.8
                    }
                    
                    background: Rectangle {
                        color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                        radius: 4
                    }
                }
            }
        }
        
        // Queue list
        QueueListView {
            id: queueListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            
            onTrackDoubleClicked: function(index) {
                MediaPlayer.playTrackAt(index);
                root.close();
            }
            
            onRemoveTrackRequested: function(index) {
                MediaPlayer.removeTrackAt(index);
            }
            
            onRemoveTracksRequested: function(indices) {
                MediaPlayer.removeTracks(indices);
            }
        }
    }
    
    function formatQueueDuration(totalSeconds) {
        if (isNaN(totalSeconds) || totalSeconds < 0) {
            return "0:00"
        }
        
        var hours = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        
        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        } else {
            return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
    }
}