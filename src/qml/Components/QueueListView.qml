import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Mtoc.Backend 1.0

ListView {
    id: root
    focus: true
    
    property var queueModel: []
    property int currentPlayingIndex: -1
    property bool isProgrammaticScrolling: false
    property bool isRapidSkipping: false
    property int lastSkipTime: 0
    property int rapidSkipThreshold: 500 // milliseconds
    
    // Drag and drop state
    property int draggedTrackIndex: -1
    property int dropIndex: -1
    
    // Multi-selection state
    property var selectedTrackIndices: []
    property int lastSelectedIndex: -1
    
    // Keyboard navigation state
    property int keyboardSelectedIndex: -1
    
    signal trackDoubleClicked(int index)
    signal removeTrackRequested(int index)
    signal removeTracksRequested(var indices)
    
    // Keyboard shortcuts
    Keys.onPressed: function(event) {
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_A) {
                // Select all
                selectedTrackIndices = []
                for (var i = 0; i < count; i++) {
                    selectedTrackIndices.push(i)
                }
                selectedTrackIndices = selectedTrackIndices.slice() // Force binding update
                event.accepted = true
            }
        } else if (event.key === Qt.Key_Down) {
            // Navigate down
            if (keyboardSelectedIndex === -1 && count > 0) {
                // First navigation down selects first track
                keyboardSelectedIndex = 0
                ensureKeyboardSelectedVisible()
            } else if (keyboardSelectedIndex < count - 1) {
                keyboardSelectedIndex++
                ensureKeyboardSelectedVisible()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            // Navigate up
            if (keyboardSelectedIndex > 0) {
                keyboardSelectedIndex--
                ensureKeyboardSelectedVisible()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // Play selected track
            if (keyboardSelectedIndex >= 0 && keyboardSelectedIndex < count) {
                trackDoubleClicked(keyboardSelectedIndex)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            // Clear selection
            selectedTrackIndices = []
            lastSelectedIndex = -1
            keyboardSelectedIndex = -1
            event.accepted = true
        } else if (event.key === Qt.Key_Delete && selectedTrackIndices.length > 0) {
            // Delete selected tracks
            removeTracksRequested(selectedTrackIndices.slice())
            selectedTrackIndices = []
            event.accepted = true
        }
    }
    
    // Timer to ensure final scroll position after rapid skipping
    Timer {
        id: finalPositionTimer
        interval: 300
        repeat: false
        onTriggered: {
            isRapidSkipping = false;
            scrollToCurrentTrack();
        }
    }
    
    property var clearingItems: []
    property int clearAnimationIndex: 0
    
    function clearAllTracks() {
        var trackCount = count;
        if (trackCount === 0) return;
        
        // Store all indices to be cleared
        clearingItems = [];
        for (var i = 0; i < trackCount; i++) {
            clearingItems.push(i);
        }
        
        // Start the clearing animation
        clearAnimationIndex = 0;
        clearAnimationTimer.start();
    }
    
    Timer {
        id: clearAnimationTimer
        interval: 30  // Process items quickly
        repeat: true
        onTriggered: {
            if (clearAnimationIndex >= clearingItems.length) {
                // All items have been animated, stop the timer and clear the queue
                stop();
                clearQueueTimer.start();
                return;
            }
            
            // Get the current item to animate
            var currentIndex = clearingItems[clearAnimationIndex];
            var item = itemAtIndex(currentIndex);
            
            // If item is visible, animate it
            if (item && !item.isRemoving) {
                item.isRemoving = true;
                item.slideX = root.width;
            } else if (!item) {
                // Item is not visible, ensure it's in view first
                positionViewAtIndex(currentIndex, ListView.Center);
                // Try again on next timer tick
                return;
            }
            
            clearAnimationIndex++;
            
            // Auto-scroll to keep animated items visible
            if (clearAnimationIndex < clearingItems.length) {
                var nextIndex = clearingItems[clearAnimationIndex];
                // Check if next item is visible
                var nextItem = itemAtIndex(nextIndex);
                if (!nextItem) {
                    // Scroll to make it visible
                    positionViewAtIndex(nextIndex, ListView.Center);
                }
            }
        }
    }
    
    Timer {
        id: clearQueueTimer
        interval: 400  // Wait for slide animations to complete
        repeat: false
        onTriggered: {
            MediaPlayer.clearQueueForUndo();
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
            
            // During rapid skipping, use immediate positioning
            if (isRapidSkipping) {
                scrollAnimation.stop();
                contentY = targetY;
                isProgrammaticScrolling = false;
            } else {
                // Stop any existing animation first
                if (scrollAnimation.running) {
                    scrollAnimation.stop();
                }
                scrollAnimation.to = targetY;
                scrollAnimation.start();
            }
        }
    }
    
    function ensureKeyboardSelectedVisible() {
        if (keyboardSelectedIndex < 0 || keyboardSelectedIndex >= count) {
            return;
        }
        
        // Calculate the position of the selected track
        var itemY = keyboardSelectedIndex * (45 + spacing); // 45 is delegate height
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
            
            // Stop any existing animation first
            if (scrollAnimation.running) {
                scrollAnimation.stop();
            }
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
        var currentTime = Date.now();
        var timeSinceLastSkip = currentTime - lastSkipTime;
        
        // Detect rapid skipping
        if (timeSinceLastSkip < rapidSkipThreshold) {
            isRapidSkipping = true;
            finalPositionTimer.restart();
        } else {
            isRapidSkipping = false;
        }
        
        lastSkipTime = currentTime;
        
        // Delay the scroll slightly to ensure the list has updated
        Qt.callLater(scrollToCurrentTrack);
    }
    
    // Also scroll when the model changes (e.g., when queue is first loaded)
    onModelChanged: {
        Qt.callLater(scrollToCurrentTrack);
        // Clear selection when queue changes
        selectedTrackIndices = [];
        lastSelectedIndex = -1;
        keyboardSelectedIndex = -1;
    }
    
    clip: true
    spacing: 2
    
    model: queueModel
    
    delegate: Rectangle {
        id: queueItemDelegate
        width: root.width
        height: isRemoving ? 0 : 45
        color: {
            if (root.selectedTrackIndices.indexOf(index) !== -1) {
                return Qt.rgba(0.25, 0.32, 0.71, 0.35)  // Selected
            } else if (index === root.keyboardSelectedIndex) {
                return Qt.rgba(0.25, 0.32, 0.71, 0.15)  // Keyboard selected
            } else if (index === root.currentPlayingIndex) {
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
        
        
        property real verticalOffset: {
            if (root.draggedTrackIndex === -1) return 0
            
            var dragIdx = root.draggedTrackIndex
            var dropIdx = root.dropIndex
            
            if (dragIdx === index || dropIdx === -1) return 0  // Don't offset the dragged item
            
            if (dragIdx < dropIdx) {
                // Dragging down: items between drag and drop move up
                if (index > dragIdx && index <= dropIdx) {
                    return -(height + root.spacing)
                }
            } else if (dragIdx > dropIdx) {
                // Dragging up: items between drop and drag move down
                if (index >= dropIdx && index < dragIdx) {
                    return height + root.spacing
                }
            }
            
            return 0
        }
        
        // Update drop position in real-time while dragging
        onYChanged: {
            if (dragArea.drag.active && root.draggedTrackIndex === index) {
                // Calculate potential drop position based on current Y
                var dragDistance = y - dragArea.originalY
                var itemsMoved = Math.round(dragDistance / (height + root.spacing))
                var potentialIndex = root.draggedTrackIndex + itemsMoved
                potentialIndex = Math.max(0, Math.min(potentialIndex, root.count - 1))
                
                // Update drop index if it changed
                if (potentialIndex !== root.dropIndex) {
                    root.dropIndex = potentialIndex
                }
            }
        }
        
        // Animation properties
        property bool isRemoving: false
        property real slideX: 0
        
        Behavior on height {
            enabled: !root.isRapidSkipping
            NumberAnimation { 
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        
        Behavior on slideX {
            enabled: !root.isRapidSkipping
            NumberAnimation { 
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        
        // Combined transforms for removal slide and drag feedback
        transform: [
            Translate {
                x: slideX
            },
            Translate {
                y: queueItemDelegate.verticalOffset
                Behavior on y {
                    enabled: root.draggedTrackIndex !== -1 && !root.isRapidSkipping
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        ]
        
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
                    
                    property int originalY: 0
                    
                    onPressed: {
                        root.draggedTrackIndex = index
                        root.dropIndex = index
                        originalY = queueItemDelegate.y
                        queueItemDelegate.z = 1000
                        queueItemDelegate.opacity = 0.8
                    }
                    
                    onReleased: {
                        // Use the pre-calculated drop index
                        var newIndex = root.dropIndex
                        var draggedIdx = root.draggedTrackIndex
                        
                        // Keep track of whether we're actually moving
                        var isMoving = newIndex !== draggedIdx && draggedIdx >= 0
                        
                        // Reset visual properties
                        queueItemDelegate.z = 0
                        queueItemDelegate.opacity = 1.0
                        queueItemDelegate.y = dragArea.originalY
                        
                        // Reset drag state to remove all visual offsets
                        root.draggedTrackIndex = -1
                        root.dropIndex = -1
                        
                        // Perform the reorder after a brief delay to allow visual reset
                        if (isMoving) {
                            Qt.callLater(function() {
                                MediaPlayer.moveTrack(draggedIdx, newIndex)
                            })
                        }
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
                color: Theme.isDark ? "#aaaaaa" : "#ffffffff"
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
                    color: removeButtonMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.08)
                    opacity: (queueItemMouseArea.containsMouse || removeButtonMouseArea.containsMouse) ? 1.0 : 0.0
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                    
                    Item {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        
                        Image {
                            id: closedLidIcon
                            anchors.fill: parent
                            source: "qrc:/resources/icons/trash-can-closed-lid.svg"
                            sourceSize.width: 32
                            sourceSize.height: 32
                            opacity: removeButtonMouseArea.containsMouse ? 0 : 1
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }
                        }
                        
                        Image {
                            id: openLidIcon
                            anchors.fill: parent
                            source: "qrc:/resources/icons/trash-can-open-lid.svg"
                            sourceSize.width: 32
                            sourceSize.height: 32
                            opacity: removeButtonMouseArea.containsMouse ? 1 : 0
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 150 }
                            }
                        }
                    }
                    
                    MouseArea {
                        id: removeButtonMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Check if this track is selected and there are multiple selections
                            if (root.selectedTrackIndices.length > 1 && root.selectedTrackIndices.indexOf(index) !== -1) {
                                // Remove all selected tracks
                                root.removeTracksRequested(root.selectedTrackIndices.slice())
                                root.selectedTrackIndices = []
                            } else {
                                // Single track removal with animation
                                queueItemDelegate.isRemoving = true
                                queueItemDelegate.slideX = root.width
                                
                                // Delay actual removal until animation completes
                                removalTimer.start()
                            }
                        }
                    }
                }
            }
        }
        
        MouseArea {
            id: queueItemMouseArea
            anchors.fill: parent
            anchors.leftMargin: 38  // Leave space for the drag handle (20px icon + margins)
            anchors.rightMargin: 24  // Leave space for the remove button
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            
            onClicked: function(mouse) {
                root.forceActiveFocus()  // Ensure list has focus for keyboard shortcuts
                if (mouse.button === Qt.LeftButton) {
                    if (mouse.modifiers & Qt.ControlModifier) {
                        // Ctrl+Click: Toggle selection
                        var idx = root.selectedTrackIndices.indexOf(index)
                        if (idx !== -1) {
                            // Deselect
                            root.selectedTrackIndices.splice(idx, 1)
                            root.selectedTrackIndices = root.selectedTrackIndices.slice() // Force binding update
                        } else {
                            // Select
                            root.selectedTrackIndices.push(index)
                            root.selectedTrackIndices = root.selectedTrackIndices.slice() // Force binding update
                        }
                        root.lastSelectedIndex = index
                    } else if (mouse.modifiers & Qt.ShiftModifier && root.lastSelectedIndex !== -1) {
                        // Shift+Click: Range selection
                        root.selectedTrackIndices = []
                        var start = Math.min(root.lastSelectedIndex, index)
                        var end = Math.max(root.lastSelectedIndex, index)
                        for (var i = start; i <= end; i++) {
                            root.selectedTrackIndices.push(i)
                        }
                        root.selectedTrackIndices = root.selectedTrackIndices.slice() // Force binding update
                    } else {
                        // Regular click: Select only this track
                        root.selectedTrackIndices = [index]
                        root.lastSelectedIndex = index
                        root.keyboardSelectedIndex = index
                    }
                }
            }
            
            onDoubleClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton && 
                    !(mouse.modifiers & Qt.ControlModifier) && 
                    !(mouse.modifiers & Qt.ShiftModifier)) {
                    root.trackDoubleClicked(index)
                }
            }
        }
        
        Behavior on color {
            enabled: !root.isRapidSkipping
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
        text: {
            if (MediaPlayer.isPlayingVirtualPlaylist && MediaPlayer.virtualPlaylistName) {
                return "Playing from " + MediaPlayer.virtualPlaylistName
            } else {
                return "Queue is empty"
            }
        }
        color: "#666666"
        font.pixelSize: 14
        visible: root.count === 0
    }
    
    // Background mouse area to capture clicks and set focus
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: {
            root.forceActiveFocus()
            mouse.accepted = false  // Let the click propagate to items
        }
    }
}