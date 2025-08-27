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
    property int thumbnailGeneration: 0  // Incremented when thumbnails are rebuilt to force refresh
    property bool clearingImages: false  // Flag to clear images during size change
    property real stableContentX: -1  // Store the stable position after animations complete

    signal albumClicked(var album)
    signal centerAlbumChanged(var album)
    signal albumTitleClicked(string artistName, string albumTitle)
    
    // Track component destruction state
    property bool isDestroying: false
    // Track initialization state to prevent animations during startup
    property bool isInitializing: true
    
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
        
        StyledMenuItem {
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
        
        StyledMenuItem {
            text: "Play Next"
            onTriggered: {
                if (sharedAlbumContextMenu.currentAlbumData && MediaPlayer) {
                    MediaPlayer.playAlbumNext(sharedAlbumContextMenu.currentAlbumData.albumArtist, sharedAlbumContextMenu.currentAlbumData.title)
                }
            }
        }
        
        StyledMenuItem {
            text: "Play Last"
            onTriggered: {
                if (sharedAlbumContextMenu.currentAlbumData && MediaPlayer) {
                    MediaPlayer.playAlbumLast(sharedAlbumContextMenu.currentAlbumData.albumArtist, sharedAlbumContextMenu.currentAlbumData.title)
                }
            }
        }
    }
    
    // Pixel alignment helper functions
    function snapToPixel(value) {
        return Math.round(value)
    }
    
    function snapToHalfPixel(value) {
        return Math.round(value * 2) / 2
    }
    
    Component.onCompleted: {
        updateSortedIndices()
        // Restore carousel position after indices are sorted
        restoreCarouselPosition()
        // Clear initialization flag after component is ready
        Qt.callLater(function() {
            if (!root || root.isDestroying) return
            isInitializing = false
        })
    }
    
    Connections {
        target: LibraryManager
        function onThumbnailsRebuilt() {
            // Increment generation counter to force image refresh
            thumbnailGeneration++
            console.log("HorizontalAlbumBrowser: Thumbnails rebuilt, forcing refresh")
        }
    }
    
    Connections {
        target: SettingsManager
        function onThumbnailScaleChanged() {
            console.log("HorizontalAlbumBrowser: Thumbnail scale changed, clearing images")
            
            // Set flag to clear images
            clearingImages = true
            
            // Force ListView to recreate all delegates by resetting the model
            var currentIndex = listView.currentIndex
            var tempModel = listView.model
            listView.model = null
            
            // Force garbage collection
            gc()
            
            // Restore model and position after a delay
            Qt.callLater(function() {
                listView.model = tempModel
                listView.currentIndex = currentIndex
                clearingImages = false
                thumbnailGeneration++
                console.log("HorizontalAlbumBrowser: Reloaded with new thumbnail size")
            })
        }
    }
    
    Component.onDestruction: {
        // Mark that we're destroying to prevent any further operations
        isDestroying = true
        
        // Force all delegates to clear their resources
        if (listView && listView.contentItem) {
            for (var i = 0; i < listView.contentItem.children.length; i++) {
                var item = listView.contentItem.children[i]
                if (item) {
                    // Clear reflection
                    if (item.reflection) {
                        item.reflection.sourceItem = null
                        item.reflection.live = false
                    }
                    // Disable connections
                    if (item.listViewConnection) {
                        item.listViewConnection.enabled = false
                    }
                    if (item.albumImageConnection) {
                        item.albumImageConnection.enabled = false
                    }
                    // Disable layer rendering
                    if (item.layer) {
                        item.layer.enabled = false
                        item.layer.effect = null
                    }
                }
            }
        }
        
        // Stop animations
        if (snapAnimation) snapAnimation.stop()
        if (contentXBehavior) contentXBehavior.enabled = false
        
        // Stop all timers to prevent callbacks during destruction
        if (savePositionTimer) savePositionTimer.stop()
        if (velocityTimer) velocityTimer.stop()
        if (snapIndexTimer) snapIndexTimer.stop()
        if (centerAlbumTimer) centerAlbumTimer.stop()
        if (scrollEndTimer) scrollEndTimer.stop()
        if (gcTimer) gcTimer.stop()
    }
    
    // Timer to save position after user stops scrolling
    Timer {
        id: savePositionTimer
        interval: 250  // Save 250ms after user stops scrolling
        running: false
        onTriggered: {
            if (!root || isDestroying) {
                if (savePositionTimer) savePositionTimer.stop()
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
                        jumpToAlbum(sourceAlbums[i], false)  // Use animation for library changes
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
                    // During initialization, jump without animation
                    jumpToAlbum(sourceAlbums[i], isInitializing)
                    return
                }
            }
            console.log("HorizontalAlbumBrowser: Saved album not found, defaulting to first album")
        }
    }
    
    // Manual memory cleanup function that can be called when needed
    function clearDistantCache() {
        if (!root || isDestroying) return
        
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
    
    function jumpToAlbum(album, instant) {
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
                            // Check if we're already at this index to avoid unnecessary repositioning
                            if (listView.currentIndex === sortedIndex) {
                                // Already at the correct position, just update selectedAlbum if needed
                                if (selectedAlbum !== currentAlbum) {
                                    selectedAlbum = currentAlbum
                                }
                                return
                            }
                            
                            // Store the target index for preloading
                            root.targetJumpIndex = sortedIndex
                            
                            if (instant) {
                                // During initialization or when instant jump is requested
                                // Set contentX directly to avoid animation
                                var targetContentX = contentXForIndex(sortedIndex)
                                listView.contentX = targetContentX
                                listView.currentIndex = sortedIndex
                                selectedAlbum = currentAlbum
                                root.currentIndex = sortedIndex
                            } else {
                                // Animate to the new index
                                listView.currentIndex = sortedIndex
                                selectedAlbum = currentAlbum
                            }
                            
                            // Clear target index after animation completes
                            Qt.callLater(function() {
                                if (!root || root.isDestroying) return
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
        // Snap to pixel boundary for sharp rendering
        return snapToPixel(index * itemWidth - centerOffset)
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
        var centerX = snapToPixel(listView.contentX) + centerOffset
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
            anchors.topMargin: 27      // change to slide the carousel up or down
            anchors.bottomMargin: 30    // Bottom margin for reflection and info bar
            model: sortedAlbumIndices.length  // Use length for delegate count
            orientation: ListView.Horizontal
            spacing: -165
            // Calculate highlight range with pixel snapping to match contentXForIndex
            preferredHighlightBegin: snapToPixel(width / 2 - 110)
            preferredHighlightEnd: snapToPixel(width / 2 + 110)
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
                    if (!root || isDestroying) {
                        if (gcTimer) gcTimer.stop()
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
                
                // Store stable position when movement ends
                root.stableContentX = listView.contentX
                
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
                    if (!root || isDestroying || !listView) {
                        if (velocityTimer) velocityTimer.stop()
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
                    // Store the stable position after snapping completes
                    root.stableContentX = listView.contentX

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
                    if (!root || isDestroying) {
                        if (snapIndexTimer) snapIndexTimer.stop()
                        return
                    }
                    
                    if (targetIndex >= 0 && listView) {
                        // Only update if different to avoid unnecessary repositioning
                        if (listView.currentIndex !== targetIndex) {
                            listView.currentIndex = targetIndex
                        }
                    }
                }
            }
            
            // Timer to emit centerAlbumChanged after currentIndex changes (for mouse wheel/keyboard)
            Timer {
                id: centerAlbumTimer
                interval: 100  // Wait for animation to complete
                running: false
                onTriggered: {
                    if (!root || isDestroying) {
                        if (centerAlbumTimer) centerAlbumTimer.stop()
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
                    if (!root || isDestroying) {
                        if (scrollEndTimer) scrollEndTimer.stop()
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
                    
                    // Clear stable position as we're moving to a new index
                    root.stableContentX = -1
                    
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
                    // Take focus when clicked, but only if not already focused
                    if (!listView.activeFocus) {
                        listView.forceActiveFocus()
                    }
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
                            
                            // Directly update content position with pixel snapping
                            var newContentX = listView.contentX - root.accumulatedDelta;
                            
                            // Clamp to bounds
                            newContentX = Math.max(minContentX(), Math.min(maxContentX(), newContentX));
                            
                            // Snap to pixel boundary for sharp rendering during scrolling
                            newContentX = snapToPixel(newContentX);
                            
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
                    // Ensure ListView has focus when clicked, but only if not already focused
                    if (!listView.activeFocus) {
                        listView.forceActiveFocus()
                    }
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
                
                // Calculate if this item needs rotation (for conditional layer rendering)
                property bool needsRotation: Math.abs(itemAngle) > 0.5
                
                // Only enable layer rendering for items that need rotation
                // This ensures the center album renders directly without FBO overhead
                layer.enabled: needsRotation
                layer.samples: needsRotation ? 4 : 0  // 4x multisampling only when rotating
                layer.smooth: true // Always smooth at the delegate level
                
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
                    // Clear old state
                    if (reflection) {
                        reflection.sourceItem = null
                        reflection.live = false
                    }
                    
                    // Reset index for new use
                    sortedIndex = index
                    if (snapAnimation && snapAnimation.running) snapAnimation.stop()
                    
                    // Re-enable connections for the new item
                    if (listViewConnection) listViewConnection.enabled = true
                    if (albumImageConnection) albumImageConnection.enabled = true
                    
                    // Don't touch layer.enabled here - let the binding handle it
                }
                
                // Immediate cleanup when delegate is removed
                ListView.onRemove: {
                    // Just clear the reflection to avoid holding references
                    if (reflection) {
                        reflection.sourceItem = null
                        reflection.live = false
                    }
                }
                
                // Clear all GPU resources when returned to pool
                ListView.onPooled: {
                    // Clear GPU resources when pooled
                    if (reflection) {
                        reflection.sourceItem = null
                        reflection.live = false
                    }
                    // Connections will be re-enabled in onReused
                    if (listViewConnection) listViewConnection.enabled = false
                    if (albumImageConnection) albumImageConnection.enabled = false
                    // Don't force layer.enabled = false, let binding handle it
                }
                
                Component.onDestruction: {
                    // Disable connections first
                    if (listViewConnection) listViewConnection.enabled = false
                    if (albumImageConnection) albumImageConnection.enabled = false
                    
                    // Clear reflection source
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
                            if (!delegateItem || root.isDestroying || !reflection) return
                            reflection.live = false
                        })
                    }
                }
                
                // Watch ListView scrolling to update reflections
                Connections {
                    id: listViewConnection
                    target: listView
                    enabled: !root.isDestroying && !delegateItem.ListView.isPooled
                    
                    function onContentXChanged() {
                        if (root.isDestroying || !delegateItem || delegateItem.ListView.isPooled) return
                        
                        // When scrolling, check if this delegate's reflection state should change
                        if (reflection) {
                            var shouldHaveReflection = absDistance < (listView.width / 2)
                            var hasReflection = reflection.sourceItem !== null
                            
                            if (shouldHaveReflection !== hasReflection) {
                                // State changed - update reflection
                                reflection.sourceItem = shouldHaveReflection ? albumContainer : null
                                
                                // If enabling reflection and image is ready, update it
                                if (shouldHaveReflection && reflection.sourceItem) {
                                    if (albumImage && albumImage.status === Image.Ready) {
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
                property bool isVisible: absDistance < (listView.width / 2)
                
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
                    
                    var offset = 0
                    if (absDistance < 20) {
                        // Phase 1: Proportional slide in dead zone
                        offset = sign * phase1Spacing * (absDistance / 20)
                    } else if (absDistance < 60) {
                        // Phase 2: Maintain slide during rotation
                        offset = sign * phase1Spacing
                    } else if (absDistance < 80) {
                        // Phase 3: Additional slide after rotation
                        offset = sign * (phase1Spacing + phase3Spacing * ((absDistance - 60) / 20))
                    } else {
                        // Final spacing
                        offset = sign * (phase1Spacing + phase3Spacing)
                    }
                    
                    // Round to nearest pixel for sharp rendering
                    return snapToPixel(offset)
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
                    
                    var scale = 1.0
                    // Simplified piecewise linear scaling
                    if (absDistance < 5) {
                        // Near center - always exactly 1.0 for perfect sharpness
                        scale = 1.0
                    } else if (absDistance < 20) {
                        scale = 1.0 - 0.001 * absDistance  // 1.0 to 0.98
                    } else if (absDistance < 60) {
                        scale = 0.98 - 0.00325 * (absDistance - 20)  // 0.98 to 0.85
                    } else {
                        scale = 0.85
                    }
                    
                    // Round to nearest 0.01 for precise but clean scaling
                    return Math.round(scale * 100) / 100
                }
                
                transform: [
                    Translate {
                        x: horizontalOffset
                    },
                    Scale {
                        origin.x: snapToPixel(delegateItem.width / 2)
                        origin.y: snapToPixel(delegateItem.height / 2)
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
                                return snapToPixel(delegateItem.width * 0.75)
                            } else if (distance < 0) {
                                // Moving left
                                return snapToPixel(delegateItem.width * 0.25)
                            } else {
                                // Center - default to middle
                                return snapToPixel(delegateItem.width / 2)
                            }
                        }
                        origin.y: snapToPixel(delegateItem.height / 2)
                        axis { x: 0; y: 1; z: 0 }
                        angle: itemAngle
                    }
                ]
                
                Item {
                    id: visualContainer
                    objectName: "visualContainer"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 10  // Small margin to shift the album view up
                    width: 220
                    height: 320  // Height for album + reflection (reduced from 340)
                    
                    Item {
                        id: albumContainer
                        objectName: "albumContainer"
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 200
                        height: 200
                            
                        Image {
                            id: albumImage
                            objectName: "albumImage"
                            anchors.fill: parent
                            source: {
                                // Clear source when we're resetting for size change
                                if (root.clearingImages) return ""
                                // Robust source binding with null checks
                                if (!delegateItem || root.isDestroying) return ""
                                if (!albumData || typeof albumData === "undefined") return ""
                                // Additional safety check for object properties
                                if (typeof albumData.hasArt === "undefined" || !albumData.hasArt) return ""
                                if (typeof albumData.id === "undefined" || !albumData.id) return ""
                                // Force loading for target delegates or nearby visible items
                                // Request thumbnail at the configured size from settings
                                if (forceImageLoad || isVisible) {
                                    // Get configured thumbnail size (100% = 200px, 150% = 300px, 200% = 400px)
                                    var thumbnailSize = SettingsManager.thumbnailScale * 2
                                    // Add generation counter to force refresh after rebuilds
                                    return "image://albumart/" + albumData.id + "/thumbnail/" + thumbnailSize + "?gen=" + root.thumbnailGeneration
                                }
                                return ""
                            }
                            fillMode: Image.PreserveAspectCrop // Preserve aspect ratio and crop to fit
                            asynchronous: !isTargetDelegate  // Load synchronously for target delegate
                            //smooth: true // redundant with layer.smooth at the delegate level
                            //smooth: needsRotation || absDistance > 5 // non-smoothed center album, results in pixel misalignment in some cases
                            mipmap: false  // Disable mipmapping to avoid softness
                            cache: true  // Enable caching to prevent reloading
                            
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
                                    // Only change currentIndex if it's different to avoid 1px shift
                                    if (listView.currentIndex !== index) {
                                        listView.currentIndex = index
                                    } else if (root.stableContentX !== -1 && Math.abs(listView.contentX - root.stableContentX) <= 1) {
                                        // If we're at the same index and very close to the stable position,
                                        // restore the exact stable position to prevent micro-shifts
                                        listView.contentX = root.stableContentX
                                    }
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
                        anchors.topMargin: 0  // Small overlap to prevent gap
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: albumContainer.width
                        height: 180
                        clip: true  // Ensure clean edges
                        
                        // Conditional reflection - only for visible items to reduce GPU load
                        ShaderEffectSource {
                            id: reflection
                            anchors.fill: parent
                            sourceItem: null  // Managed by Connections element
                            visible: sourceItem !== null  // Only visible when sourceItem is set
                            live: false  // Static reflection for better performance
                            recursive: false
                            smooth: true  // Enable antialiasing for reflection
                            mipmap: false  // Maintain sharpness
                            format: ShaderEffectSource.RGBA8  // High quality format
                            // Double texture resolution for better antialiasing (workaround for FBO limitation)
                            //textureSize: Qt.size(albumContainer.width * 2, 360)
                            samples: 4  // Enable multisampling where supported
                            // Capture the bottom portion of the album for reflection
                            sourceRect: Qt.rect(0, albumContainer.height - 180, albumContainer.width, 180)
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
                            id: albumImageConnection
                            target: albumImage
                            enabled: !root.isDestroying && reflection && !delegateItem.ListView.isPooled
                            
                            function onStatusChanged() {
                                if (root.isDestroying || !delegateItem || delegateItem.ListView.isPooled) return
                                if (albumImage && albumImage.status === Image.Ready && reflection && reflection.sourceItem) {
                                    reflection.scheduleUpdate()
                                }
                            }
                        }
                        
                        // Dark overlay to dim the reflection (60% black)
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.6)  // Semi-transparent black overlay
                        }
                        
                        // Gradient overlay for smooth edge transition
                        // Rectangle {
                        //     anchors.fill: parent
                        //     gradient: Gradient {
                        //         // Feather the top edge from opaque black to transparent
                        //         GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 1.0) }
                        //         GradientStop { position: 0.02; color: Qt.rgba(0, 0, 0, 0.8) }
                        //         GradientStop { position: 0.05; color: Qt.rgba(0, 0, 0, 0.5) }
                        //         GradientStop { position: 0.1; color: Qt.rgba(0, 0, 0, 0.2) }
                        //         GradientStop { position: 0.15; color: Qt.rgba(0, 0, 0, 0.0) }
                        //         GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
                        //     }
                        // }
                    }
                }
            }
        }
        
    }
}