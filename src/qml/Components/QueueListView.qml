import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Mtoc.Backend 1.0
import ".."

ListView {
    id: root
    focus: true
    
    property var queueModel: []
    property int currentPlayingIndex: -1
    property bool isProgrammaticScrolling: false
    property bool isRapidSkipping: false
    property int lastSkipTime: 0
    property int rapidSkipThreshold: 500 // milliseconds
    property bool forceLightText: false // For dark background contexts like NowPlayingPane
    
    // Drag and drop state
    property int draggedTrackIndex: -1
    property int dropIndex: -1
    property bool isAnimatingDrop: false

    // Timer to complete drop animation and update model
    Timer {
        id: dropAnimationTimer
        interval: 210  // Slightly longer than animation duration (200ms)
        repeat: false
        property int draggedIdx: -1
        property int newIndex: -1
        onTriggered: {
            // Store move info for highlight calculation during finalization
            root.finalizingFromIndex = draggedIdx
            root.finalizingToIndex = newIndex

            // Set finalizing flag to disable offset animations during model update
            root.isFinalizingDrop = true

            // Clear drag state - offsets will snap to 0 instantly (no animation)
            root.draggedTrackIndex = -1
            root.dropIndex = -1
            root.isAnimatingDrop = false

            // Save scroll position before model update (model change can reset it)
            var savedContentY = root.contentY

            // Update model - delegates will be at correct positions with 0 offset
            MediaPlayer.moveTrack(draggedIdx, newIndex)

            // Restore scroll position after model update
            root.contentY = savedContentY

            // Clear finalizing flag after delegates have fully re-bound
            Qt.callLater(function() {
                Qt.callLater(function() {
                    root.isFinalizingDrop = false
                    root.finalizingFromIndex = -1
                    root.finalizingToIndex = -1
                })
            })
            // Qt.callLater(function() {
            //     root.isFinalizingDrop = false
            //     root.finalizingFromIndex = -1
            //     root.finalizingToIndex = -1
            // })
        }
    }

    // Flag to disable offset animations during model update
    property bool isFinalizingDrop: false
    // Store move indices for calculating correct highlights during finalization
    property int finalizingFromIndex: -1
    property int finalizingToIndex: -1

    // Track removal animation state to maintain stable highlights
    property bool isAnimatingRemoval: false
    property int removingAtIndex: -1  // Index of item being removed

    // Calculate adjusted index during removal animation
    // Items below the removed index will shift up after removal
    function getPostRemovalIndex(currentIndex) {
        if (!isAnimatingRemoval || removingAtIndex === -1) return currentIndex
        if (currentIndex === removingAtIndex) return -1  // Being removed
        if (currentIndex > removingAtIndex) return currentIndex - 1
        return currentIndex
    }

    // Auto-scroll during drag
    property bool isDragging: false
    property real draggedItemY: 0
    property real dragStartY: 0  // Viewport Y position where drag started
    property int dragScrollDirection: 0  // -1 = up, 0 = none, 1 = down
    property real dragStartContentY: 0  // contentY when drag started, to track scroll offset
    property real lastContentY: 0  // Track contentY to compensate dragged item position
    property real autoScrollActivationDistance: 30  // Min distance from start before auto-scroll activates

    // Reset drag state when interrupted (focus loss, etc.)
    function resetDragState() {
        if (isDragging || draggedTrackIndex >= 0) {
            // Restore visibility and position of the dragged item
            if (draggedTrackIndex >= 0) {
                var draggedItem = itemAtIndex(draggedTrackIndex)
                if (draggedItem) {
                    draggedItem.opacity = 1.0
                    draggedItem.z = 0
                    // Reset to correct slot position
                    draggedItem.y = draggedTrackIndex * (draggedItem.height + spacing)
                }
            }
            isDragging = false
            draggedTrackIndex = -1
            dropIndex = -1
            dragScrollDirection = 0
            dragScrollAnimation.stop()
            dragScrollTimer.stop()
        }
    }

    // Reset drag state when window loses focus
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && !root.Window.window.active) {
                root.resetDragState()
            }
        }
    }

    // Compensate dragged item position when list scrolls during drag
    onContentYChanged: {
        if (isDragging && draggedTrackIndex >= 0) {
            var delta = contentY - lastContentY
            if (delta !== 0) {
                // Find the dragged delegate and adjust its position
                var draggedItem = itemAtIndex(draggedTrackIndex)
                if (draggedItem) {
                    draggedItem.y += delta
                }
            }
        }
        lastContentY = contentY
    }

    // Smooth scroll animation for drag auto-scroll
    NumberAnimation {
        id: dragScrollAnimation
        target: root
        property: "contentY"
        duration: 300  // Will be adjusted based on scroll speed
        easing.type: Easing.Linear

        onFinished: {
            // Continue scrolling if still in edge zone
            if (root.isDragging && root.dragScrollDirection !== 0) {
                dragScrollTimer.restart()
            }
        }
    }

    Timer {
        id: dragScrollTimer
        interval: 16  // Single frame delay before next scroll segment
        repeat: false
        running: false

        property real edgeThreshold: 60  // Distance from edge where scrolling starts
        property real minScrollAmount: 30  // Slowest scroll (at threshold boundary)
        property real maxScrollAmount: 150  // Fastest scroll (at or past edge)

        onTriggered: {
            if (!root.isDragging) return

            var dragY = root.draggedItemY
            var viewHeight = root.height
            var targetY = root.contentY
            var scrollAmount = minScrollAmount
            var penetration = 0  // How far into the edge zone (0 to 1+)

            // Calculate distance moved from drag start
            var distanceFromStart = Math.abs(dragY - root.dragStartY)

            // Check if near top edge
            if (dragY < edgeThreshold && root.contentY > 0) {
                // Only activate if moved enough from start position, or if we've already started scrolling
                if (distanceFromStart < root.autoScrollActivationDistance && root.dragScrollDirection === 0) {
                    return
                }
                root.dragScrollDirection = -1
                // Calculate penetration: 0 at threshold, 1 at edge, >1 past edge
                penetration = (edgeThreshold - dragY) / edgeThreshold
                scrollAmount = minScrollAmount + (maxScrollAmount - minScrollAmount) * Math.min(penetration, 1.5)
                targetY = Math.max(0, root.contentY - scrollAmount)
            }
            // Check if near bottom edge
            else if (dragY > viewHeight - edgeThreshold &&
                     root.contentY < root.contentHeight - viewHeight) {
                // Only activate if moved enough from start position, or if we've already started scrolling
                if (distanceFromStart < root.autoScrollActivationDistance && root.dragScrollDirection === 0) {
                    return
                }
                root.dragScrollDirection = 1
                // Calculate penetration: 0 at threshold, 1 at edge, >1 past edge
                penetration = (dragY - (viewHeight - edgeThreshold)) / edgeThreshold
                scrollAmount = minScrollAmount + (maxScrollAmount - minScrollAmount) * Math.min(penetration, 1.5)
                targetY = Math.min(root.contentHeight - viewHeight, root.contentY + scrollAmount)
            }
            else {
                root.dragScrollDirection = 0
                return
            }

            dragScrollAnimation.to = targetY
            dragScrollAnimation.start()
        }
    }

    // Calculate what an index will be after the move is applied
    function getPostMoveIndex(currentIndex) {
        if (finalizingFromIndex === -1 || finalizingToIndex === -1) return currentIndex
        if (currentIndex === finalizingFromIndex) return finalizingToIndex
        if (finalizingFromIndex < finalizingToIndex) {
            // Moving down: indices between from and to shift up by 1
            if (currentIndex > finalizingFromIndex && currentIndex <= finalizingToIndex) {
                return currentIndex - 1
            }
        } else {
            // Moving up: indices between to and from shift down by 1
            if (currentIndex >= finalizingToIndex && currentIndex < finalizingFromIndex) {
                return currentIndex + 1
            }
        }
        return currentIndex
    }
    
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
        // Don't auto-scroll during drag-drop reordering
        if (isFinalizingDrop) return;

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
        // Don't auto-scroll during drag-drop reordering
        if (!isFinalizingDrop) {
            Qt.callLater(scrollToCurrentTrack);
        }
        // Clear selection when queue changes
        selectedTrackIndices = [];
        lastSelectedIndex = -1;
        keyboardSelectedIndex = -1;
    }
    
    clip: true
    cacheBuffer: 100000  // Keep all delegates instantiated to avoid recycling issues during drag
    spacing: 2
    
    model: queueModel

    delegate: Rectangle {
        id: queueItemDelegate
        width: root.width
        height: isRemoving ? 0 : 45
        color: {
            // During drop animation or finalization, suppress hover and only show now-playing highlight
            if (root.isAnimatingDrop || root.isFinalizingDrop) {
                // Check if this item will be the now-playing track after the move
                var postMoveIndex = root.getPostMoveIndex(root.currentPlayingIndex)
                if (index === postMoveIndex) {
                    return Theme.selectedBackgroundMediumOpacity  // Currently playing
                }
                return Qt.rgba(1, 1, 1, 0.02)  // Default
            }

            // During removal animation, use post-removal indices for stable highlights
            if (root.isAnimatingRemoval) {
                var postRemovalIndex = root.getPostRemovalIndex(index)
                var postRemovalPlayingIndex = root.getPostRemovalIndex(root.currentPlayingIndex)
                if (postRemovalIndex === postRemovalPlayingIndex && postRemovalIndex !== -1) {
                    return Theme.selectedBackgroundMediumOpacity  // Currently playing
                }
                return Qt.rgba(1, 1, 1, 0.02)  // Default (suppress hover during animation)
            }

            if (root.selectedTrackIndices.indexOf(index) !== -1) {
                return Theme.selectedBackgroundHighOpacity  // Selected
            } else if (index === root.keyboardSelectedIndex) {
                return Theme.selectedBackgroundLowOpacity  // Keyboard selected
            } else if (index === root.currentPlayingIndex) {
                return Theme.selectedBackgroundMediumOpacity  // Currently playing
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
            // During finalization, don't apply any offset - model is being updated
            if (root.isFinalizingDrop) return 0

            // Keep offsets during drop animation until model updates
            if (root.draggedTrackIndex === -1 && !root.isAnimatingDrop) return 0

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

                // Update position for auto-scroll (convert to viewport coordinates)
                root.draggedItemY = y - root.contentY

                // Start auto-scroll if in edge zone and not already scrolling
                var edgeThreshold = 60
                var inEdgeZone = root.draggedItemY < edgeThreshold || root.draggedItemY > root.height - edgeThreshold
                if (inEdgeZone && !dragScrollAnimation.running && !dragScrollTimer.running) {
                    dragScrollTimer.start()
                }
            }
        }
        
        // Animation properties
        property bool isRemoving: false
        property real slideX: 0

        // Drop animation for the dragged item
        Behavior on y {
            id: dropAnimation
            enabled: root.isAnimatingDrop && root.draggedTrackIndex === index
            NumberAnimation {
                id: dropAnimationNumber
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        // Store animation completion data on the delegate
        property var dropAnimData: null

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
                    // Disable animation during finalization so offsets snap instantly
                    enabled: (root.draggedTrackIndex !== -1 || root.isAnimatingDrop) && !root.isRapidSkipping && !root.isFinalizingDrop
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
            
            // Drag handle - Item wrapper to allow full-height hit area
            Item {
                Layout.preferredWidth: 20
                Layout.fillHeight: true

                Image {
                    id: dragHandle
                    anchors.centerIn: parent
                    source: root.forceLightText ? "qrc:/resources/icons/list-drag-handle.svg" :
                            (Theme.isDark ? "qrc:/resources/icons/list-drag-handle.svg" : "qrc:/resources/icons/list-drag-handle-dark.svg")
                    width: 20
                    height: 20
                    sourceSize.width: 40
                    sourceSize.height: 40
                    opacity: 0.5
                }

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
                        root.isDragging = true
                        root.dragStartContentY = root.contentY
                        root.lastContentY = root.contentY
                        // Record starting viewport position for auto-scroll activation
                        root.dragStartY = queueItemDelegate.y - root.contentY
                    }
                    
                    onReleased: {
                        root.isDragging = false
                        dragScrollAnimation.stop()
                        dragScrollTimer.stop()
                        root.dragScrollDirection = 0

                        // Use the pre-calculated drop index
                        var newIndex = root.dropIndex
                        var draggedIdx = root.draggedTrackIndex

                        // Keep track of whether we're actually moving
                        var isMoving = newIndex !== draggedIdx && draggedIdx >= 0

                        // Reset z-index and opacity
                        queueItemDelegate.z = 0
                        queueItemDelegate.opacity = 1.0

                        if (isMoving) {
                            // Calculate the target slot position in content coordinates
                            var targetSlotY = newIndex * (queueItemDelegate.height + root.spacing)

                            // Start the drop animation
                            root.isAnimatingDrop = true
                            dropAnimationTimer.draggedIdx = draggedIdx
                            dropAnimationTimer.newIndex = newIndex
                            dropAnimationTimer.start()
                            queueItemDelegate.y = targetSlotY
                        } else {
                            // No move - reset to the item's correct slot position
                            var originalSlotY = draggedIdx * (queueItemDelegate.height + root.spacing)
                            queueItemDelegate.y = originalSlotY
                            root.draggedTrackIndex = -1
                            root.dropIndex = -1
                        }
                    }
                }
            }
            
            // Track title
            Label {
                text: modelData.title || "Unknown Track"
                color: root.forceLightText ? "#ffffff" : Theme.primaryText
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
                color: root.forceLightText ? "#aaaaaa" : Theme.secondaryText
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
                }

                // MouseArea as direct child of Item to ensure full hit area
                MouseArea {
                    id: removeButtonMouseArea
                    anchors.fill: parent
                    z: 1  // Ensure MouseArea is above the Rectangle
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
                            root.isAnimatingRemoval = true
                            root.removingAtIndex = index
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
            anchors.leftMargin: 38  // Leave space for the drag handle (20px icon + margins)
            anchors.rightMargin: 32  // Leave space for the remove button (24px) + RowLayout margin (8px)
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            
            onClicked: function(mouse) {
                root.forceActiveFocus()  // Ensure list has focus for keyboard shortcuts
                if (mouse.button === Qt.LeftButton) {
                    var hasModifiers = (mouse.modifiers & Qt.ControlModifier) || (mouse.modifiers & Qt.ShiftModifier);

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

                    // If single-click-to-play is enabled and no modifiers, play the track
                    if (SettingsManager.singleClickToPlay && !hasModifiers) {
                        root.trackDoubleClicked(index)
                    }
                }
            }

            onDoubleClicked: function(mouse) {
                // Only handle double-click if single-click-to-play is disabled
                if (!SettingsManager.singleClickToPlay &&
                    mouse.button === Qt.LeftButton &&
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
        
        // Timer to delay removal until after animation completes
        Timer {
            id: removalTimer
            interval: 200  // Immediately after 200ms animation completes
            repeat: false
            onTriggered: {
                // Store references before delegate might be destroyed
                var listView = root
                var indexToRemove = index

                // Perform the actual removal - model and currentQueueIndex update atomically
                listView.removeTrackRequested(indexToRemove)

                // Clear animation state immediately - model has already updated
                listView.isAnimatingRemoval = false
                listView.removingAtIndex = -1
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