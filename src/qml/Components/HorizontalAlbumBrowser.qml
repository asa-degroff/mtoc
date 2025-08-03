import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0

Item {
    id: root
    height: 320
    
    property var selectedAlbum: null
    property int currentIndex: -1
    property var sortedAlbumIndices: []  // Array of indices into LibraryManager.albumModel
    property var albumIdToSortedIndex: ({})  // Map album ID to sorted index for O(1) lookup
    
    // Touchpad scrolling properties
    property real scrollVelocity: 0
    property real accumulatedDelta: 0
    property bool isSnapping: false
    property bool isUserScrolling: false
    property int targetJumpIndex: -1  // Index we're jumping to with jumpToAlbum
    
    signal albumClicked(var album)
    signal centerAlbumChanged(var album)
    
    // Track component destruction state
    property bool isDestroying: false
    
    // Queue action dialog
    QueueActionDialog {
        id: queueActionDialog
        
        onReplaceQueue: {
            if (!root.isDestroying && MediaPlayer) {
                MediaPlayer.playAlbumByName(albumArtist, albumTitle, startIndex)
            }
        }
        
        onPlayNext: {
            if (!root.isDestroying && MediaPlayer) {
                MediaPlayer.playAlbumNext(albumArtist, albumTitle)
            }
        }
        
        onPlayLast: {
            if (!root.isDestroying && MediaPlayer) {
                MediaPlayer.playAlbumLast(albumArtist, albumTitle)
            }
        }
    }
    
    // Shared context menu for all album items
    StyledMenu {
        id: sharedAlbumContextMenu
        property var currentAlbumData: null
        
        MenuItem {
            text: "Play"
            onTriggered: {
                if (sharedAlbumContextMenu.currentAlbumData) {
                    var albumData = sharedAlbumContextMenu.currentAlbumData
                    // If shuffle is enabled, start with a random track instead of the first
                    var startIndex = 0;
                    if (MediaPlayer && MediaPlayer.shuffleEnabled && albumData.trackCount > 0) {
                        startIndex = Math.floor(Math.random() * albumData.trackCount);
                    }
                    
                    // Check if we should show the dialog
                    if (SettingsManager && MediaPlayer && SettingsManager.queueActionDefault === SettingsManager.Ask && MediaPlayer.isQueueModified) {
                        // Show dialog for "Ask every time" setting when queue is modified
                        queueActionDialog.albumArtist = albumData.albumArtist
                        queueActionDialog.albumTitle = albumData.title
                        queueActionDialog.startIndex = startIndex
                        queueActionDialog.open()
                    } else if (SettingsManager && MediaPlayer) {
                        // Apply the configured action
                        switch (SettingsManager.queueActionDefault) {
                            case SettingsManager.Replace:
                                MediaPlayer.playAlbumByName(albumData.albumArtist, albumData.title, startIndex);
                                break;
                            case SettingsManager.Insert:
                                MediaPlayer.playAlbumNext(albumData.albumArtist, albumData.title);
                                break;
                            case SettingsManager.Append:
                                MediaPlayer.playAlbumLast(albumData.albumArtist, albumData.title);
                                break;
                            case SettingsManager.Ask:
                                // If Ask but queue not modified, default to replace
                                MediaPlayer.playAlbumByName(albumData.albumArtist, albumData.title, startIndex);
                                break;
                        }
                    }
                }
            }
        }
        
        MenuItem {
            text: "Play Next"
            onTriggered: {
                if (sharedAlbumContextMenu.currentAlbumData && MediaPlayer) {
                    MediaPlayer.playAlbumNext(sharedAlbumContextMenu.currentAlbumData.albumArtist, sharedAlbumContextMenu.currentAlbumData.title)
                }
            }
        }
        
        MenuItem {
            text: "Play Last"
            onTriggered: {
                if (sharedAlbumContextMenu.currentAlbumData && MediaPlayer) {
                    MediaPlayer.playAlbumLast(sharedAlbumContextMenu.currentAlbumData.albumArtist, sharedAlbumContextMenu.currentAlbumData.title)
                }
            }
        }
    }
    
    Component.onCompleted: {
        updateSortedIndices()
        // Restore carousel position after indices are sorted
        restoreCarouselPosition()
    }
    
    Component.onDestruction: {
        // Mark that we're destroying to prevent any further operations
        isDestroying = true
        
        // Stop animations
        snapAnimation.stop()
        contentXBehavior.enabled = false
        
        // Stop all timers to prevent callbacks during destruction
        savePositionTimer.stop()
        velocityTimer.stop()
        snapIndexTimer.stop()
        centerAlbumTimer.stop()
        scrollEndTimer.stop()
        gcTimer.stop()
    }
    
    // Timer to save position after user stops scrolling
    Timer {
        id: savePositionTimer
        interval: 250  // Save 250ms after user stops scrolling
        running: false
        onTriggered: {
            if (isDestroying) {
                savePositionTimer.stop()
                return
            }
            
            if (selectedAlbum && selectedAlbum.id && LibraryManager) {
                LibraryManager.saveCarouselPosition(selectedAlbum.id)
            }
        }
    }
    
    Connections {
        target: LibraryManager
        enabled: !isDestroying
        function onLibraryChanged() {
            if (isDestroying) return
            
            // Save current position before updating
            var currentAlbumId = selectedAlbum ? selectedAlbum.id : -1
            updateSortedIndices()
            
            // Try to restore to the same album if it still exists
            if (currentAlbumId > 0 && LibraryManager) {
                var sourceAlbums = (LibraryManager.albumModel) ? LibraryManager.albumModel : []
                for (var i = 0; i < sourceAlbums.length; i++) {
                    if (sourceAlbums[i].id === currentAlbumId) {
                        jumpToAlbum(sourceAlbums[i])
                        return
                    }
                }
            }
            
            // If album was removed, try to restore saved position
            restoreCarouselPosition()
        }
    }
    
    function updateSortedIndices() {
        if (isDestroying || !LibraryManager) return
        
        var sourceAlbums = (LibraryManager.albumModel) ? LibraryManager.albumModel : []
        // Create array of indices with album data for sorting
        var indexedAlbums = []
        for (var i = 0; i < sourceAlbums.length; i++) {
            indexedAlbums.push({
                index: i,
                albumArtist: sourceAlbums[i].albumArtist || "",
                year: sourceAlbums[i].year || 0
            })
        }
        
        // Sort by artist first, then by year (descending) within each artist
        indexedAlbums.sort(function(a, b) {
            // Get artist names for comparison, removing "The " prefix
            var artistA = a.albumArtist.toLowerCase()
            var artistB = b.albumArtist.toLowerCase()
            
            // Remove "The " prefix for sorting purposes
            if (artistA.indexOf("the ") === 0) {
                artistA = artistA.substring(4)
            }
            if (artistB.indexOf("the ") === 0) {
                artistB = artistB.substring(4)
            }
            
            // First compare by album artist (case-insensitive, without "The " prefix)
            var artistCompare = artistA.localeCompare(artistB)
            if (artistCompare !== 0) {
                return artistCompare
            }
            // If same artist, sort by year descending (newest first)
            return b.year - a.year
        })
        
        // Extract just the sorted indices
        sortedAlbumIndices = indexedAlbums.map(function(item) { return item.index })
        
        // Build the album ID to sorted index mapping for O(1) lookup
        var idToIndex = {}
        for (var i = 0; i < sortedAlbumIndices.length; i++) {
            var albumIndex = sortedAlbumIndices[i]
            var album = sourceAlbums[albumIndex]
            if (album && album.id) {
                idToIndex[album.id] = i
            }
        }
        albumIdToSortedIndex = idToIndex
        
        if (sortedAlbumIndices.length > 0 && currentIndex === -1) {
            currentIndex = 0
            selectedAlbum = sourceAlbums[sortedAlbumIndices[0]]
        }
    }
    
    function restoreCarouselPosition() {
        if (isDestroying || !LibraryManager) return
        
        var savedAlbumId = LibraryManager.loadCarouselPosition()
        if (savedAlbumId > 0) {
            // Find the album with this ID and jump to it
            var sourceAlbums = (LibraryManager.albumModel) ? LibraryManager.albumModel : []
            for (var i = 0; i < sourceAlbums.length; i++) {
                if (sourceAlbums[i].id === savedAlbumId) {
                    console.log("HorizontalAlbumBrowser: Restoring carousel position to album:", sourceAlbums[i].title)
                    jumpToAlbum(sourceAlbums[i])
                    return
                }
            }
            console.log("HorizontalAlbumBrowser: Saved album not found, defaulting to first album")
        }
    }
    
    // Manual memory cleanup function that can be called when needed
    function clearDistantCache() {
        if (isDestroying) return
        
        console.log("HorizontalAlbumBrowser: Clearing distant image cache")
        
        // Force garbage collection
        gc()
        
        // Clear reflection sources for distant items
        var currentIdx = listView.currentIndex
        for (var i = 0; i < listView.contentItem.children.length; i++) {
            var item = listView.contentItem.children[i]
            if (item && item.hasOwnProperty("sortedIndex")) {
                var distance = Math.abs(item.sortedIndex - currentIdx)
                if (distance > 10 && item.reflection) {
                    // Clear reflection source for distant items
                    item.reflection.sourceItem = null
                }
            }
        }
    }
    
    function jumpToAlbum(album) {
        try {
            // Validate album parameter
            if (!album || typeof album !== "object" || typeof album.id === "undefined") {
                console.warn("HorizontalAlbumBrowser.jumpToAlbum: Invalid album parameter:", JSON.stringify(album));
                return;
            }
            
            // Use O(1) lookup to find the sorted index
            var sortedIndex = albumIdToSortedIndex[album.id]
            if (sortedIndex !== undefined && sortedIndex >= 0 && sortedIndex < sortedAlbumIndices.length) {
                // Get the actual album to ensure it still exists
                var albumIndex = sortedAlbumIndices[sortedIndex]
                if (LibraryManager) {
                    var sourceAlbums = (LibraryManager.albumModel) ? LibraryManager.albumModel : []
                        if (albumIndex < sourceAlbums.length) {
                        var currentAlbum = sourceAlbums[albumIndex]
                        if (currentAlbum && currentAlbum.id === album.id) {
                            // Store the target index for preloading
                            root.targetJumpIndex = sortedIndex
                            
                            // Animate to the new index instead of jumping
                            listView.currentIndex = sortedIndex
                            selectedAlbum = currentAlbum
                            
                            // Clear target index after animation completes
                            Qt.callLater(function() {
                                root.targetJumpIndex = -1
                            })
                            return
                        }
                    }
                }
            }
            
            // Fallback: album not found in the mapping (shouldn't happen in normal use)
            console.warn("HorizontalAlbumBrowser.jumpToAlbum: Album not found in sorted index mapping:", album.id);
        } catch (error) {
            console.warn("HorizontalAlbumBrowser.jumpToAlbum error:", error);
        }
    }
    
    // Calculate the contentX position that centers a given index
    function contentXForIndex(index) {
        var itemWidth = 220 + listView.spacing  // 220 - 165 = 55 effective width
        var centerOffset = listView.width / 2 - 110  // Center position
        return index * itemWidth - centerOffset
    }
    
    // Get the minimum allowed contentX value
    function minContentX() {
        // The minimum contentX is when the first item is centered
        return contentXForIndex(0)
    }
    
    // Get the maximum allowed contentX value
    function maxContentX() {
        if (sortedAlbumIndices.length === 0) return 0
        // The maximum contentX is when the last item is centered
        return contentXForIndex(sortedAlbumIndices.length - 1)
    }
    
    // Find the index of the album closest to the center
    function nearestIndex() {
        var itemWidth = 220 + listView.spacing  // 55 effective width
        var centerOffset = listView.width / 2 - 110
        var centerX = listView.contentX + centerOffset
        var index = Math.round(centerX / itemWidth)
        return Math.max(0, Math.min(sortedAlbumIndices.length - 1, index))
    }
    
    Rectangle {
        anchors.fill: parent
        color: "transparent"  // Transparent to show parent's background
        clip: true  // Clip at the component boundary
        
        ListView {
            id: listView
            anchors.fill: parent
            anchors.topMargin: 30      // Increased margin to accommodate rotation
            anchors.bottomMargin: 30    // Bottom margin for reflection and info bar
            model: sortedAlbumIndices.length  // Use length for delegate count
            orientation: ListView.Horizontal
            spacing: -165
            preferredHighlightBegin: width / 2 - 110
            preferredHighlightEnd: width / 2 + 110
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 200  // Smooth animation duration
            currentIndex: root.currentIndex
            clip: false                 // Disable clipping to allow rotated albums to show
            maximumFlickVelocity: 1500  // Limit scroll speed
            flickDeceleration: 3000     // Faster deceleration
            // Ensure we can reach the bounds - remove to allow elastic overscroll
            // Removing this interfers with the cusom touchpad/click+drag scrolling logic, making the first item unreachable
            boundsBehavior: Flickable.StopAtBounds
            
            // Cached value for delegate optimization - calculated once per frame
            readonly property real viewCenterX: width / 2
            
            // Enable delegate recycling with proper safeguards
            cacheBuffer: 880  // 4 items on each side (220px * 4) for smoother scrolling
            reuseItems: true  // Enable delegate recycling for better performance
            
            // Garbage collection timer for long scrolling sessions
            Timer {
                id: gcTimer
                interval: 3000  // Run every 3 seconds (more aggressive)
                running: false
                repeat: true
                property int triggerCount: 0
                
                onTriggered: {
                    if (isDestroying || !root) {
                        gcTimer.stop()
                        return
                    }
                    
                    triggerCount++
                    
                    // Force garbage collection by clearing unused image cache
                    gc()
                    
                    // Every 5th trigger (15 seconds), do a more aggressive cleanup
                    if (triggerCount % 5 === 0) {
                        // Clear pixmap cache of items that are far from view
                        var currentIdx = listView.currentIndex
                        for (var i = 0; i < listView.count; i++) {
                            if (Math.abs(i - currentIdx) > 10) {
                                // This delegate is far from view, its cache can be cleared
                                // The cache will be repopulated when needed
                            }
                        }
                        
                        // Log memory management action
                        console.log("HorizontalAlbumBrowser: Aggressive garbage collection triggered")
                    }
                }
            }
            
            onMovementStarted: {
                if (!isDestroying) {
                    gcTimer.running = true
                }
                root.isUserScrolling = true
            }
            onMovementEnded: {
                if (!isDestroying) {
                    gcTimer.running = false
                    // Final cleanup after scrolling stops
                    gcTimer.triggered()
                }
                
                // Emit signal when user scrolling stops and we have an album
                if (root.isUserScrolling && root.selectedAlbum) {
                    root.centerAlbumChanged(root.selectedAlbum)
                }
                root.isUserScrolling = false
            }
            
            // Smooth velocity animation for touchpad scrolling
            Behavior on contentX {
                id: contentXBehavior
                enabled: false  // Only enable during touchpad scrolling
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutQuad
                }
            }
            
            // Timer to apply velocity-based momentum
            Timer {
                id: velocityTimer
                interval: 16  // ~60fps
                repeat: true
                running: false
                onTriggered: {
                    if (isDestroying || !listView) {
                        velocityTimer.stop()
                        return
                    }
                    
                    if (Math.abs(root.scrollVelocity) > 0.5 && !root.isSnapping) {
                        listView.contentX += root.scrollVelocity
                        root.scrollVelocity *= 0.95  // Damping factor
                        
                        // Clamp to bounds
                        var minX = minContentX()
                        var maxX = maxContentX()
                        if (listView.contentX < minX) {
                            listView.contentX = minX
                            root.scrollVelocity = 0
                        } else if (listView.contentX > maxX) {
                            listView.contentX = maxX
                            root.scrollVelocity = 0
                        }
                    } else if (!root.isSnapping) {
                        // Velocity is low, start snapping to nearest album
                        velocityTimer.stop()
                        root.scrollVelocity = 0
                        root.isSnapping = true
                        
                        // Find nearest album and animate to it
                        var targetIndex = nearestIndex()
                        var targetContentX = contentXForIndex(targetIndex)
                        
                        // Animate to the target position
                        snapAnimation.to = targetContentX
                        snapAnimation.start()
                        
                        // Update current index after a short delay to ensure smooth animation
                        if (!isDestroying) {
                            snapIndexTimer.targetIndex = targetIndex
                            snapIndexTimer.start()
                        }
                    }
                }
            }
            
            // Animation for snapping to nearest album
            NumberAnimation {
                id: snapAnimation
                target: listView
                property: "contentX"
                duration: 300
                easing.type: Easing.OutQuad
                onStopped: {
                    if (root.isDestroying) return
                    
                    root.isSnapping = false
                    // Emit signal when snap animation completes and we have an album
                    if (root.isUserScrolling && root.selectedAlbum) {
                        root.centerAlbumChanged(root.selectedAlbum)
                    }
                    root.isUserScrolling = false
                }
            }
            
            // Timer to update index after snap animation starts
            Timer {
                id: snapIndexTimer
                interval: 50  // Short delay to ensure animation has started
                running: false
                property int targetIndex: -1
                onTriggered: {
                    if (isDestroying || !root) {
                        snapIndexTimer.stop()
                        return
                    }
                    
                    if (targetIndex >= 0 && listView) {
                        listView.currentIndex = targetIndex
                    }
                }
            }
            
            // Timer to emit centerAlbumChanged after currentIndex changes (for mouse wheel/keyboard)
            Timer {
                id: centerAlbumTimer
                interval: 100  // Wait for animation to complete
                running: false
                onTriggered: {
                    if (isDestroying || !root) {
                        centerAlbumTimer.stop()
                        return
                    }
                    
                    if (root.selectedAlbum) {
                        root.centerAlbumChanged(root.selectedAlbum)
                    }
                }
            }
            
            // Timer to detect when touchpad scrolling has stopped
            Timer {
                id: scrollEndTimer
                interval: 100  // Wait 100ms after last scroll event
                running: false
                onTriggered: {
                    if (isDestroying) {
                        scrollEndTimer.stop()
                        return
                    }
                    
                    // If velocity is very low or zero, snap to nearest album
                    if (Math.abs(root.scrollVelocity) < 0.5 && !root.isSnapping) {
                        root.isSnapping = true
                        
                        // Find nearest album and animate to it
                        var targetIndex = nearestIndex()
                        var targetContentX = contentXForIndex(targetIndex)
                        
                        // Animate to the target position
                        snapAnimation.to = targetContentX
                        snapAnimation.start()
                        
                        // Update current index
                        if (!isDestroying) {
                            snapIndexTimer.targetIndex = targetIndex
                            snapIndexTimer.start()
                        }
                    } else if (!root.isSnapping && root.isUserScrolling && root.selectedAlbum) {
                        // If we're not snapping but finished scrolling, emit the signal
                        root.centerAlbumChanged(root.selectedAlbum)
                        root.isUserScrolling = false
                    }
                }
            }
                    
            onCurrentIndexChanged: {
                if (!isDestroying && currentIndex >= 0 && currentIndex < sortedAlbumIndices.length) {
                    root.currentIndex = currentIndex
                    var albumIndex = sortedAlbumIndices[currentIndex]
                    if (LibraryManager && LibraryManager.albumModel) {
                        root.selectedAlbum = LibraryManager.albumModel[albumIndex]
                    }
                    
                    // Save position after a delay
                    if (!isDestroying) {
                        savePositionTimer.restart()
                    }
                    
                    // Emit centerAlbumChanged for mouse wheel and keyboard navigation
                    // Use a timer to debounce and ensure it fires after the animation
                    if (!isDestroying) {
                        centerAlbumTimer.restart()
                    }
                }
            }
            
            // Mouse wheel support
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true
                onClicked: {
                    // Take focus when clicked
                    listView.forceActiveFocus()
                    mouse.accepted = false  // Let the click propagate to album items
                }
                onWheel: function(wheel) {
                    // Mark as user scrolling
                    root.isUserScrolling = true
                    
                    // Different behavior for touchpad vs mouse wheel
                    if (wheel.pixelDelta.y !== 0 || wheel.pixelDelta.x !== 0) {
                        // Touchpad - use direct content manipulation for smooth scrolling
                        var deltaX = wheel.pixelDelta.x;
                        var deltaY = wheel.pixelDelta.y;
                        
                        // Calculate the effective delta (support both horizontal and vertical gestures)
                        var effectiveDelta = 0;
                        if (Math.abs(deltaX) > Math.abs(deltaY)) {
                            effectiveDelta = deltaX * 2; // Horizontal scrolling
                        } else {
                            effectiveDelta = -deltaY * 2; // Vertical scrolling (inverted)
                        }
                        
                        // Accumulate small deltas for smoother micro-movements
                        root.accumulatedDelta += effectiveDelta;
                        
                        // Apply accumulated delta when it's significant enough
                        if (Math.abs(root.accumulatedDelta) >= 1) {
                            // Stop any ongoing velocity animation or snap
                            velocityTimer.stop();
                            snapAnimation.stop();
                            root.isSnapping = false;
                            
                            // Directly update content position
                            var newContentX = listView.contentX - root.accumulatedDelta;
                            
                            // Clamp to bounds
                            newContentX = Math.max(minContentX(), Math.min(maxContentX(), newContentX));
                            
                            // Apply the new position
                            listView.contentX = newContentX;
                            
                            // Update velocity for momentum
                            root.scrollVelocity = -root.accumulatedDelta * 0.3;
                            
                            // Reset accumulator
                            root.accumulatedDelta = 0;
                        }
                        
                        // Restart the scroll end detection timer
                        if (!isDestroying) {
                            scrollEndTimer.restart();
                        }
                        
                        // Start velocity timer for momentum when gesture has velocity
                        if (!isDestroying && !velocityTimer.running && Math.abs(root.scrollVelocity) > 0) {
                            velocityTimer.start();
                        }
                    } else {
                        // Mouse wheel - keep the current per-item scrolling (1 album per notch)
                        if (wheel.angleDelta.y > 0) {
                            listView.decrementCurrentIndex()
                        } else if (wheel.angleDelta.y < 0) {
                            listView.incrementCurrentIndex()
                        }
                    }
                    wheel.accepted = true
                }
                onPressed: function(mouse) {
                    // Ensure ListView has focus when clicked
                    listView.forceActiveFocus()
                    mouse.accepted = false  // Let click events through to delegates
                }
            }
            
            // Keyboard navigation
            activeFocusOnTab: true
            
            // Only handle keyboard events when this component has active focus
            Keys.enabled: activeFocus
            Keys.onLeftPressed: function(event) {
                if (activeFocus) {
                    listView.decrementCurrentIndex()
                    event.accepted = true
                }
            }
            Keys.onRightPressed: function(event) {
                if (activeFocus) {
                    listView.incrementCurrentIndex()
                    event.accepted = true
                }
            }
            Keys.onSpacePressed: function(event) {
                if (activeFocus && selectedAlbum) {
                    root.albumClicked(selectedAlbum)
                    event.accepted = true
                }
            }
            Keys.onReturnPressed: function(event) {
                if (activeFocus && selectedAlbum) {
                    root.albumClicked(selectedAlbum)
                    event.accepted = true
                }
            }
            Keys.onEscapePressed: function(event) {
                if (activeFocus) {
                    // Return focus to parent (library pane)
                    if (parent && parent.parent) {
                        parent.parent.forceActiveFocus()
                    }
                    event.accepted = true
                }
            }
            Keys.onUpPressed: function(event) {
                if (activeFocus) {
                    // Transfer focus back to library pane and let it handle the up key
                    if (parent && parent.parent) {
                        parent.parent.forceActiveFocus()
                    }
                    event.accepted = false  // Let the event propagate to library pane
                }
            }
            Keys.onDownPressed: function(event) {
                if (activeFocus) {
                    // Transfer focus back to library pane and let it handle the down key
                    if (parent && parent.parent) {
                        parent.parent.forceActiveFocus()
                    }
                    event.accepted = false  // Let the event propagate to library pane
                }
            }
            
            delegate: Item {
                id: delegateItem
                width: 220
                height: 320  // Height for album plus reflection
                
                // Get the actual album data from the model using sorted index
                property int sortedIndex: index
                property int albumIndex: {
                    if (sortedIndex < 0 || sortedIndex >= sortedAlbumIndices.length) return -1
                    return sortedAlbumIndices[sortedIndex]
                }
                property var albumData: {
                    if (root.isDestroying || albumIndex < 0 || !LibraryManager) {
                        return null
                    }
                    // Extra null check for delegate recycling
                    if (delegateItem === null || typeof delegateItem === "undefined") {
                        return null
                    }
                    // Check if albumModel exists before accessing it
                    var model = LibraryManager.albumModel
                    if (!model || typeof model === "undefined") {
                        return null
                    }
                    // Safe array access with bounds checking
                    return albumIndex < model.length ? model[albumIndex] : null
                }
                
                // Handle delegate recycling with proper state reset
                ListView.onReused: {
                    // Force update sortedIndex to match new index
                    sortedIndex = index
                    
                    // Reset any animation states
                    if (snapAnimation.running) snapAnimation.stop()
                    
                    // Clear reflection and set to live mode temporarily for recycling
                    if (reflection) {
                        reflection.sourceItem = null
                        reflection.live = true  // Enable live mode during recycling
                    }
                }
                
                // Animation for cleaning up when delegate is removed
                SequentialAnimation {
                    id: removeAnimation
                    PropertyAction { target: delegateItem; property: "ListView.delayRemove"; value: true }
                    ScriptAction {
                        script: {
                            // Clear all references before removal
                            if (reflection) {
                                reflection.sourceItem = null
                            }
                        }
                    }
                    PropertyAction { target: delegateItem; property: "ListView.delayRemove"; value: false }
                }
                
                // Clean up when delegate is about to be recycled
                ListView.onRemove: removeAnimation.start()
                
                Component.onDestruction: {
                    // Final cleanup
                    if (reflection) {
                        reflection.sourceItem = null
                    }
                }
                
                // Cache expensive calculations - only update when contentX changes
                property real itemCenterX: x + width / 2 - listView.contentX
                property real distance: itemCenterX - listView.viewCenterX
                property real absDistance: Math.abs(distance)
                
                // Update reflection when position changes (handles recycling case)
                onXChanged: {
                    if (!root.isDestroying && reflection && reflection.live && reflection.sourceItem) {
                        // Set back to static mode after recycling position update
                        Qt.callLater(function() {
                            if (reflection) {
                                reflection.live = false
                            }
                        })
                    }
                }
                
                // Watch ListView scrolling to update reflections
                Connections {
                    target: listView
                    enabled: !root.isDestroying
                    
                    function onContentXChanged() {
                        // When scrolling, check if this delegate's reflection state should change
                        if (reflection) {
                            var shouldHaveReflection = absDistance < 800
                            var hasReflection = reflection.sourceItem !== null
                            
                            if (shouldHaveReflection !== hasReflection) {
                                // State changed - update reflection
                                reflection.sourceItem = shouldHaveReflection ? albumContainer : null
                                
                                // If enabling reflection and image is ready, update it
                                if (shouldHaveReflection && reflection.sourceItem) {
                                    if (albumImage.status === Image.Ready) {
                                        reflection.scheduleUpdate()
                                    }
                                    // Also ensure it's not in live mode
                                    if (reflection.live) {
                                        reflection.live = false
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Optimization: Skip expensive calculations for far-away items
                property bool isVisible: absDistance < 800
                
                // Track if this delegate is actively being scrolled to
                property bool isTargetDelegate: listView.currentIndex === index
                
                // Check if near the jump target during animation
                property bool isNearJumpTarget: {
                    if (root.targetJumpIndex < 0) return false
                    var indexDistance = Math.abs(index - root.targetJumpIndex)
                    return indexDistance <= 5  // Preload 5 items on each side of target
                }
                
                // Force image loading for target delegates during animation
                property bool forceImageLoad: isTargetDelegate || isNearJumpTarget || (isVisible && absDistance < 400)
                
                property real horizontalOffset: {
                    if (!isVisible) return 0
                    
                    // Constants for phase calculations
                    var phase1Spacing = 50
                    var phase3Spacing = 40
                    var sign = distance > 0 ? 1 : -1
                    
                    if (absDistance < 20) {
                        // Phase 1: Proportional slide in dead zone
                        return sign * phase1Spacing * (absDistance / 20)
                    } else if (absDistance < 60) {
                        // Phase 2: Maintain slide during rotation
                        return sign * phase1Spacing
                    } else if (absDistance < 80) {
                        // Phase 3: Additional slide after rotation
                        return sign * (phase1Spacing + phase3Spacing * ((absDistance - 60) / 20))
                    } else {
                        // Final spacing
                        return sign * (phase1Spacing + phase3Spacing)
                    }
                }
                
                property real itemAngle: {
                    if (!isVisible) return distance > 0 ? -65 : 65
                    
                    if (absDistance < 10) {
                        // Dead zone - no rotation
                        return 0
                    } else if (absDistance < 60) {
                        // Smooth rotation: map 10-60 range to 0-65 degrees
                        var progress = (absDistance - 10) / 50
                        return (distance > 0 ? -1 : 1) * progress * 65
                    } else {
                        // Fixed angle outside rotation zone
                        return distance > 0 ? -65 : 65
                    }
                }
                
                
                z: {
                    // Center album has highest z-order
                    if (absDistance < 5) {
                        return 1000  // Ensure center album is always on top
                    }
                    
                    // Use index-based z-ordering to ensure consistent layering
                    // The visual order should match the index order when viewed from the perspective
                    var centerIndex = listView.currentIndex
                    var indexDiff = index - centerIndex
                    
                    if (indexDiff === 0) {
                        return 1000  // Center album
                    } else if (indexDiff > 0) {
                        // Albums to the right of center (higher index)
                        // Closer to center = higher z-order
                        return (500 - indexDiff * 10) > 0 ? (500 - indexDiff * 10) : 0
                    } else {
                        // Albums to the left of center (lower index)
                        // Closer to center = higher z-order
                        return (500 + indexDiff * 10) > 0 ? (500 + indexDiff * 10) : 0
                    }
                }
                
                property real scaleAmount: {
                    if (!isVisible) return 0.85
                    
                    // Simplified piecewise linear scaling
                    if (absDistance < 20) {
                        return 1.0 - 0.001 * absDistance  // 1.0 to 0.98
                    } else if (absDistance < 60) {
                        return 0.98 - 0.00325 * (absDistance - 20)  // 0.98 to 0.85
                    } else {
                        return 0.85
                    }
                }
                
                transform: [
                    Translate {
                        x: horizontalOffset
                    },
                    Scale {
                        origin.x: delegateItem.width / 2
                        origin.y: delegateItem.height / 2
                        xScale: scaleAmount
                        yScale: scaleAmount
                        
                        Behavior on xScale {
                            enabled: absDistance < 200 && !root.isDestroying // Only animate near center and not during destruction
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on yScale {
                            enabled: absDistance < 200 && !root.isDestroying // Only animate near center and not during destruction
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.OutQuad
                            }
                        }
                    },
                    Rotation {
                        // Asymmetric rotation axis - 1/10 from the "front" edge
                        origin.x: {
                            if (distance > 0) {
                                // Moving right
                                return delegateItem.width * 0.75
                            } else if (distance < 0) {
                                // Moving left
                                return delegateItem.width * 0.25
                            } else {
                                // Center - default to middle
                                return delegateItem.width / 2
                            }
                        }
                        origin.y: delegateItem.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: itemAngle
                    }
                ]
                
                Item {
                    id: visualContainer
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 10  // Small margin to shift the album view up
                    width: 220
                    height: 340  // Height for album + reflection
                    
                    // Conditional layer rendering - only for visible items near center
                    layer.enabled: isVisible && absDistance < 400 // Enable for nearby items to smooth reflections
                    layer.smooth: true // Enable antialiasing for both album and reflection
                    layer.samples: 4 // Multisample antialiasing for best quality
                    
                    Item {
                        id: albumContainer
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 200
                        height: 200
                            
                        Image {
                            id: albumImage
                            anchors.fill: parent
                            source: {
                                // Robust source binding with null checks
                                if (!delegateItem || root.isDestroying) return ""
                                if (!albumData || typeof albumData === "undefined") return ""
                                // Additional safety check for object properties
                                if (typeof albumData.hasArt === "undefined" || !albumData.hasArt) return ""
                                if (typeof albumData.id === "undefined" || !albumData.id) return ""
                                // Force loading for target delegates or nearby visible items
                                if (forceImageLoad || isVisible) {
                                    return "image://albumart/" + albumData.id + "/thumbnail/400"
                                }
                                return ""
                            }
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: !isTargetDelegate  // Load synchronously for target delegate
                            antialiasing: true
                            cache: true  // Enable caching to prevent reloading
                            sourceSize.width: 400  // 2x the display size for retina
                            sourceSize.height: 400
                            
                            onStatusChanged: {
                                if (status === Image.Error && !root.isDestroying) {
                                    console.warn("Failed to load album art for:", albumData ? albumData.id : "unknown")
                                }
                            }
                        
                                Rectangle {
                                    anchors.fill: parent
                                    color: "#444444"
                                    visible: parent.status !== Image.Ready
                                    
                                    Label {
                                        anchors.centerIn: parent
                                        text: "♪"
                                        font.pixelSize: 48
                                        color: "#666666"
                                }
                            }
                        }
                        
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: listView.currentIndex === index ? "#ffffff" : "transparent"
                            border.width: 0 // hidden for now
                            visible: listView.currentIndex === index
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.LeftButton) {
                                    listView.currentIndex = index
                                    root.albumClicked(albumData)
                                } else if (mouse.button === Qt.RightButton) {
                                    // Show shared context menu
                                    sharedAlbumContextMenu.currentAlbumData = albumData
                                    sharedAlbumContextMenu.popup()
                                }
                            }
                            onDoubleClicked: function(mouse) {
                                if (mouse.button === Qt.LeftButton) {
                                    // If shuffle is enabled, start with a random track instead of the first
                                    var startIndex = 0;
                                    if (MediaPlayer && MediaPlayer.shuffleEnabled && albumData && albumData.trackCount > 0) {
                                        startIndex = Math.floor(Math.random() * albumData.trackCount);
                                    }
                                    
                                    // Check if we should show the dialog
                                    if (SettingsManager && MediaPlayer && SettingsManager.queueActionDefault === SettingsManager.Ask && MediaPlayer.isQueueModified) {
                                        // Show dialog for "Ask every time" setting when queue is modified
                                        queueActionDialog.albumArtist = albumData.albumArtist
                                        queueActionDialog.albumTitle = albumData.title
                                        queueActionDialog.startIndex = startIndex
                                        
                                        // Position dialog at album center
                                        var globalPos = parent.mapToGlobal(parent.width / 2, parent.height / 2)
                                        queueActionDialog.x = globalPos.x - queueActionDialog.width / 2
                                        queueActionDialog.y = globalPos.y - queueActionDialog.height / 2
                                        
                                        queueActionDialog.open()
                                    } else if (SettingsManager && MediaPlayer) {
                                        // Apply the configured action
                                        switch (SettingsManager.queueActionDefault) {
                                            case SettingsManager.Replace:
                                                MediaPlayer.playAlbumByName(albumData.albumArtist, albumData.title, startIndex);
                                                break;
                                            case SettingsManager.Insert:
                                                MediaPlayer.playAlbumNext(albumData.albumArtist, albumData.title);
                                                break;
                                            case SettingsManager.Append:
                                                MediaPlayer.playAlbumLast(albumData.albumArtist, albumData.title);
                                                break;
                                            case SettingsManager.Ask:
                                                // If Ask but queue not modified, default to replace
                                                MediaPlayer.playAlbumByName(albumData.albumArtist, albumData.title, startIndex);
                                                break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Reflection container
                    Item {
                        id: reflectionContainer
                        anchors.top: albumContainer.bottom
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: albumContainer.width
                        height: 120
                        
                        // Conditional reflection - only for visible items to reduce GPU load
                        ShaderEffectSource {
                            id: reflection
                            anchors.fill: parent
                            sourceItem: null  // Managed by Connections element
                            visible: sourceItem !== null  // Only visible when sourceItem is set
                            live: false  // Static reflection for better performance
                            recursive: false
                            // Capture the bottom portion of the album for reflection
                            sourceRect: Qt.rect(0, albumContainer.height - 120, albumContainer.width, 120)
                            transform: [
                                Scale {
                                    yScale: -1
                                    origin.y: reflection.height / 2
                                }
                            ]
                            
                            // Clear sourceItem when component is destroyed
                            Component.onDestruction: {
                                sourceItem = null
                            }
                        }
                        
                        // Watch for album image load completion to update reflection
                        Connections {
                            target: albumImage
                            enabled: !root.isDestroying && reflection
                            
                            function onStatusChanged() {
                                if (albumImage.status === Image.Ready && reflection && reflection.sourceItem) {
                                    reflection.scheduleUpdate()
                                }
                            }
                        }
                        
                        // Dark overlay to dim the reflection
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.6)  // Semi-transparent black overlay
                            opacity: 1.0
                        }
                    }
                }
            }
        }
        
    }
}