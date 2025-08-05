import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Popup {
    id: root
    
    property alias queueModel: queueListView.queueModel
    property alias currentPlayingIndex: queueListView.currentPlayingIndex
    
    width: parent.width * 0.8
    height: parent.height * 0.8
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    // Semi-transparent background overlay
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.5)
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
                    text: MediaPlayer.queueLength + " tracks • " + formatQueueDuration(MediaPlayer.queueDuration)
                    font.pixelSize: 14
                    color: Theme.secondaryText
                }
                
                Item { Layout.fillWidth: true }
                
                // Save queue button
                ToolButton {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    icon.source: "qrc:/resources/icons/save.svg"
                    icon.width: 18
                    icon.height: 18
                    visible: MediaPlayer.queueLength > 0 && !MediaPlayer.isPlayingVirtualPlaylist
                    onClicked: {
                        if (PlaylistManager.saveQueueAsPlaylist()) {
                            console.log("Queue saved as playlist");
                        }
                    }
                    
                    background: Rectangle {
                        color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                        radius: 4
                    }
                    
                    ToolTip {
                        visible: parent.hovered
                        text: "Save queue as playlist"
                        delay: 500
                    }
                }
                
                // Clear queue button
                ToolButton {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    icon.source: MediaPlayer.canUndoClear ? "qrc:/resources/icons/undo.svg" : "qrc:/resources/icons/bomb.svg"
                    icon.width: 18
                    icon.height: 18
                    visible: (MediaPlayer.queueLength > 0 || MediaPlayer.canUndoClear) && !MediaPlayer.isPlayingVirtualPlaylist
                    onClicked: {
                        if (MediaPlayer.canUndoClear) {
                            MediaPlayer.undoClearQueue();
                        } else {
                            queueListView.clearAllTracks();
                        }
                    }
                    
                    background: Rectangle {
                        color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                        radius: 4
                    }
                    
                    ToolTip {
                        visible: parent.hovered
                        text: MediaPlayer.canUndoClear ? "Undo clear queue" : "Clear queue"
                        delay: 500
                    }
                }
                
                // Close button
                ToolButton {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    icon.source: "qrc:/resources/icons/close.svg"
                    icon.width: 18
                    icon.height: 18
                    onClicked: root.close()
                    
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