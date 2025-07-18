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
    
    function clearAllTracks() {
        // Calculate animation duration based on track count
        // Cap total animation time at 2 seconds
        var trackCount = count;
        if (trackCount === 0) return;
        
        var animationDuration = Math.min(300, 2000 / trackCount);
        var staggerDelay = Math.min(50, 500 / trackCount);
        
        // Trigger removal animation for all items with cascading effect
        for (var i = 0; i < trackCount; i++) {
            var item = itemAtIndex(i);
            if (item) {
                (function(delegate, index) {
                    var timer = Qt.createQmlObject('import QtQuick; Timer {}', root);
                    timer.interval = index * staggerDelay;
                    timer.repeat = false;
                    timer.triggered.connect(function() {
                        if (delegate && !delegate.isRemoving) {
                            delegate.isRemoving = true;
                            delegate.slideX = root.width;
                        }
                        timer.destroy();
                    });
                    timer.start();
                })(item, i);
            }
        }
        
        // Clear the queue after all animations complete
        clearQueueTimer.interval = (trackCount * staggerDelay) + animationDuration + 100;
        clearQueueTimer.start();
    }
    
    Timer {
        id: clearQueueTimer
        repeat: false
        onTriggered: {
            MediaPlayer.stop();
            MediaPlayer.clearQueue();
        }
    }
    
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
        height: isRemoving ? 0 : 45
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
        clip: true
        
        // Animation properties
        property bool isRemoving: false
        property real slideX: 0
        
        transform: Translate {
            x: slideX
        }
        
        Behavior on height {
            NumberAnimation { 
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        
        Behavior on slideX {
            NumberAnimation { 
                duration: 300
                easing.type: Easing.InOutQuad
            }
        }
        
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
            
            // Now playing indicator (fixed width to prevent shifting)
            Item {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                
                Image {
                    anchors.fill: parent
                    source: "qrc:/resources/icons/speaker.svg"
                    sourceSize.width: 32
                    sourceSize.height: 32
                    visible: index === root.currentPlayingIndex && MediaPlayer.state === MediaPlayer.PlayingState
                    opacity: 0.9
                }
            }
            
            // Duration (fixed width)
            Label {
                text: modelData.duration ? formatDuration(modelData.duration) : "0:00"
                color: "#aaaaaa"
                font.pixelSize: 12
                Layout.preferredWidth: 45
                horizontalAlignment: Text.AlignRight
            }
            
            // Remove button (fixed width, always present but only visible on hover)
            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                
                Rectangle {
                    id: removeButtonBackground
                    anchors.fill: parent
                    radius: 4
                    color: removeButtonMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                    visible: queueItemMouseArea.containsMouse || removeButtonMouseArea.containsMouse
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    
                    Image {
                        id: removeButton
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: "qrc:/resources/icons/trash-can-closed-lid.svg"
                        sourceSize.width: 32
                        sourceSize.height: 32
                        
                        states: [
                            State {
                                name: "hovered"
                                when: removeButtonMouseArea.containsMouse
                                PropertyChanges {
                                    target: removeButton
                                    source: "qrc:/resources/icons/trash-can-open-lid.svg"
                                    opacity: 1.0
                                }
                            },
                            State {
                                name: ""
                                PropertyChanges {
                                    target: removeButton
                                    opacity: 0.7
                                }
                            }
                        ]
                        
                        transitions: Transition {
                            NumberAnimation { properties: "opacity"; duration: 150 }
                        }
                    }
                    
                    MouseArea {
                        id: removeButtonMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Start removal animation
                            queueItemDelegate.isRemoving = true
                            queueItemDelegate.slideX = root.width
                            
                            // Delay actual removal until animation completes
                            removalTimer.start()
                        }
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
        
        // Timer to delay removal until after animation
        Timer {
            id: removalTimer
            interval: 350  // Slightly longer than slide animation
            repeat: false
            onTriggered: {
                root.removeTrackRequested(index)
            }
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