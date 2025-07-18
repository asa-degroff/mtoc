import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Mtoc.Backend 1.0

ListView {
    id: root
    
    property var queueModel: []
    property int currentPlayingIndex: -1
    property bool isProgrammaticScrolling: false
    
    signal trackDoubleClicked(int index)
    signal removeTrackRequested(int index)
    
    function formatDuration(milliseconds) {
        if (isNaN(milliseconds) || milliseconds < 0) {
            return "0:00"
        }
        
        var totalSeconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    function scrollToCurrentTrack() {
        if (currentPlayingIndex < 0 || currentPlayingIndex >= count) {
            return;
        }
        
        // Calculate the position of the current track
        var itemY = currentPlayingIndex * (45 + spacing); // 45 is delegate height
        var visibleHeight = height;
        var currentY = contentY;
        
        // Check if the item is fully visible
        var itemTop = itemY;
        var itemBottom = itemY + 45;
        var viewTop = currentY;
        var viewBottom = currentY + visibleHeight;
        
        var targetY = -1;
        
        // If item is above the visible area, scroll to show it at the top with some margin
        if (itemTop < viewTop) {
            targetY = Math.max(0, itemTop - 10);
        }
        // If item is below the visible area, scroll to show it at the bottom with some margin
        else if (itemBottom > viewBottom) {
            targetY = itemBottom - visibleHeight + 10;
        }
        
        // Only scroll if needed
        if (targetY >= 0) {
            isProgrammaticScrolling = true;
            scrollAnimation.to = targetY;
            scrollAnimation.start();
        }
    }
    
    // Smooth scrolling animation
    NumberAnimation {
        id: scrollAnimation
        target: root
        property: "contentY"
        duration: 300
        easing.type: Easing.InOutQuad
        
        onRunningChanged: {
            if (!running && root.isProgrammaticScrolling) {
                Qt.callLater(function() {
                    root.isProgrammaticScrolling = false;
                });
            }
        }
    }
    
    // Watch for changes to the current playing index
    onCurrentPlayingIndexChanged: {
        // Delay the scroll slightly to ensure the list has updated
        Qt.callLater(scrollToCurrentTrack);
    }
    
    // Also scroll when the model changes (e.g., when queue is first loaded)
    onModelChanged: {
        Qt.callLater(scrollToCurrentTrack);
    }
    
    clip: true
    spacing: 2
    
    model: queueModel
    
    delegate: Rectangle {
        id: queueItemDelegate
        width: root.width
        height: 45
        color: {
            if (index === root.currentPlayingIndex) {
                return Qt.rgba(0.25, 0.32, 0.71, 0.25)  // Currently playing
            } else if (queueItemMouseArea.containsMouse) {
                return Qt.rgba(1, 1, 1, 0.04)  // Hover
            } else {
                return Qt.rgba(1, 1, 1, 0.02)  // Default
            }
        }
        radius: 4
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.04)
        
        // Drag and drop properties
        property int dragIndex: index
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10
            
            // Drag handle
            Image {
                id: dragHandle
                source: "qrc:/resources/icons/list-drag-handle.svg"
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                sourceSize.width: 40
                sourceSize.height: 40
                opacity: 0.5
                
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    cursorShape: Qt.DragMoveCursor
                    
                    drag.target: queueItemDelegate
                    drag.axis: Drag.YAxis
                    
                    onPressed: {
                        queueItemDelegate.z = 1000
                        queueItemDelegate.opacity = 0.8
                    }
                    
                    onReleased: {
                        queueItemDelegate.z = 0
                        queueItemDelegate.opacity = 1.0
                        // TODO: Implement actual reordering logic
                    }
                }
            }
            
            // Track title
            Label {
                text: modelData.title || "Unknown Track"
                color: "white"
                font.pixelSize: 13
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            
            // Now playing indicator
            Image {
                source: "qrc:/resources/icons/speaker.svg"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                sourceSize.width: 32
                sourceSize.height: 32
                visible: index === root.currentPlayingIndex && MediaPlayer.state === MediaPlayer.PlayingState
                opacity: 0.9
            }
            
            // Duration
            Label {
                text: modelData.duration ? formatDuration(modelData.duration) : "0:00"
                color: "#aaaaaa"
                font.pixelSize: 12
                Layout.preferredWidth: 40
            }
            
            // Remove button
            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                visible: queueItemMouseArea.containsMouse
                
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.1)
                    
                    Label {
                        anchors.centerIn: parent
                        text: "×"
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeTrackRequested(index)
                    }
                }
            }
        }
        
        MouseArea {
            id: queueItemMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            propagateComposedEvents: true
            
            onDoubleClicked: root.trackDoubleClicked(index)
        }
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }
    
    ScrollIndicator.vertical: ScrollIndicator { }
    
    // Empty state
    Label {
        anchors.centerIn: parent
        text: "Queue is empty"
        color: "#666666"
        font.pixelSize: 14
        visible: root.count === 0
    }
}