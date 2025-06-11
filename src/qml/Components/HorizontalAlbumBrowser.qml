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
    
    signal albumClicked(var album)
    
    Component.onCompleted: {
        updateSortedIndices()
    }
    
    Connections {
        target: LibraryManager
        function onLibraryChanged() {
            console.log("HorizontalAlbumBrowser: libraryChanged signal received, updating sorted indices");
            updateSortedIndices()
        }
    }
    
    function updateSortedIndices() {
        var sourceAlbums = LibraryManager.albumModel
        console.log("HorizontalAlbumBrowser: updateSortedIndices called, got", sourceAlbums.length, "albums from LibraryManager");
        
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
            // First compare by album artist
            var artistCompare = a.albumArtist.localeCompare(b.albumArtist)
            if (artistCompare !== 0) {
                return artistCompare
            }
            // If same artist, sort by year descending (newest first)
            return b.year - a.year
        })
        
        // Extract just the sorted indices
        sortedAlbumIndices = indexedAlbums.map(function(item) { return item.index })
        
        // Memory usage estimate: only storing integers instead of full album objects
        var memoryEstimate = sortedAlbumIndices.length * 4 // 4 bytes per integer
        // console.log("HorizontalAlbumBrowser: Using approximately", memoryEstimate, "bytes for sorted indices vs", 
        //             (sourceAlbums.length * 200), "bytes estimated for full album copies")
        
        if (sortedAlbumIndices.length > 0 && currentIndex === -1) {
            currentIndex = 0
            selectedAlbum = sourceAlbums[sortedAlbumIndices[0]]
        }
    }
    
    function jumpToAlbum(album) {
        try {
            // Validate album parameter
            if (!album || typeof album !== "object" || typeof album.id === "undefined") {
                console.warn("HorizontalAlbumBrowser.jumpToAlbum: Invalid album parameter:", JSON.stringify(album));
                return;
            }
            
            // Validate sortedAlbumIndices array
            if (!sortedAlbumIndices || !Array.isArray(sortedAlbumIndices)) {
                console.warn("HorizontalAlbumBrowser.jumpToAlbum: sortedAlbumIndices is not a valid array");
                return;
            }
            
            var sourceAlbums = LibraryManager.albumModel
            for (var i = 0; i < sortedAlbumIndices.length; i++) {
                var albumIndex = sortedAlbumIndices[i]
                var currentAlbum = sourceAlbums[albumIndex]
                if (currentAlbum && 
                    typeof currentAlbum === "object" && 
                    typeof currentAlbum.id !== "undefined" && 
                    currentAlbum.id === album.id) {
                    // Animate to the new index instead of jumping
                    listView.currentIndex = i
                    selectedAlbum = currentAlbum
                    break
                }
            }
        } catch (error) {
            console.warn("HorizontalAlbumBrowser.jumpToAlbum error:", error);
        }
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
            boundsBehavior: Flickable.StopAtBounds  // Ensure we can reach the bounds
            
            // Enable delegate recycling and limit cache to prevent memory leaks
            reuseItems: true
            cacheBuffer: 440  // Reduced to 2 items on each side (220px * 2)
            
            // Garbage collection timer for long scrolling sessions
            Timer {
                id: gcTimer
                interval: 5000  // Run every 5 seconds
                running: false
                repeat: true
                onTriggered: {
                    // Force garbage collection by clearing unused image cache
                    gc()
                }
            }
            
            onMovementStarted: gcTimer.running = true
            onMovementEnded: {
                gcTimer.running = false
                // Final cleanup after scrolling stops
                gcTimer.triggered()
            }
            
            property int predictedIndex: -1
            property bool isPredicting: false
            
            // Predictive approach - commented out for now
            /*
            onFlickStarted: {
                // Calculate where we'll end up based on velocity and deceleration
                var velocity = horizontalVelocity
                var deceleration = flickDeceleration
                var currentPos = contentX
                
                // Physics calculation: distance = velocity²/(2*deceleration)
                var distance = (velocity * Math.abs(velocity)) / (2 * deceleration)
                var predictedContentX = currentPos - distance
                
                // Calculate which index this corresponds to
                var itemWidth = 220 + spacing // 220 - 165 = 55 effective width per item
                var centerOffset = width / 2 - 110
                var predictedCenterX = predictedContentX + centerOffset
                var rawIndex = Math.round(predictedCenterX / itemWidth)
                
                // Clamp to valid range
                predictedIndex = Math.max(0, Math.min(allAlbums.length - 1, rawIndex))
                isPredicting = true
            }
            
            onMovementEnded: {
                isPredicting = false
                predictedIndex = -1
            }
            */            
            onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < sortedAlbumIndices.length) {
                    root.currentIndex = currentIndex
                    var albumIndex = sortedAlbumIndices[currentIndex]
                    root.selectedAlbum = LibraryManager.albumModel[albumIndex]
                }
            }
            
            // Mouse wheel support
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true
                onWheel: function(wheel) {
                    if (wheel.angleDelta.y > 0) {
                        listView.decrementCurrentIndex()
                    } else {
                        listView.incrementCurrentIndex()
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
            focus: true
            activeFocusOnTab: true
            
            Keys.onLeftPressed: listView.decrementCurrentIndex()
            Keys.onRightPressed: listView.incrementCurrentIndex()
            Keys.onSpacePressed: {
                if (selectedAlbum) {
                    root.albumClicked(selectedAlbum)
                }
            }
            Keys.onReturnPressed: {
                if (selectedAlbum) {
                    root.albumClicked(selectedAlbum)
                }
            }
            
            delegate: Item {
                id: delegateItem
                width: 220
                height: 370  // Height for album plus reflection
                
                // Get the actual album data from the model using sorted index
                property int sortedIndex: index
                property int albumIndex: sortedIndex < sortedAlbumIndices.length ? sortedAlbumIndices[sortedIndex] : -1
                property var albumData: albumIndex >= 0 && albumIndex < LibraryManager.albumModel.length ? 
                                       LibraryManager.albumModel[albumIndex] : null
                
                // Handle delegate recycling
                ListView.onReused: {
                    // Reset visibility calculations when reused
                    // The bindings will automatically update based on new position
                }
                
                // Cache expensive calculations - only update when contentX changes
                property real centerX: listView.width / 2
                property real itemCenterX: x + width / 2 - listView.contentX
                property real distance: itemCenterX - centerX
                property real absDistance: Math.abs(distance)
                
                // Optimization: Skip expensive calculations for far-away items
                property bool isNearCenter: absDistance < 600
                property bool isVisible: isNearCenter
                
                property real horizontalOffset: {
                    if (!isVisible) return 0
                    
                    // Phase 1: Small slide in dead zone (0-20px)
                    var slideDeadZone = 20
                    var phase1Spacing = 50  // Significantly increased initial slide amount
                    
                    // Phase 3: Additional slide after rotation (60-80px)
                    var phase3Start = 60
                    var phase3End = 80
                    var phase3Spacing = 40  // Increased additional spacing
                    
                    if (absDistance < slideDeadZone) {
                        // Phase 1: Proportional slide in dead zone
                        var phase1Progress = absDistance / slideDeadZone
                        return distance > 0 ? phase1Spacing * phase1Progress : -phase1Spacing * phase1Progress
                    } else if (absDistance < phase3Start) {
                        // Phase 2: Maintain slide during rotation
                        return distance > 0 ? phase1Spacing : -phase1Spacing
                    } else if (absDistance < phase3End) {
                        // Phase 3: Additional slide after rotation
                        var phase3Progress = (absDistance - phase3Start) / (phase3End - phase3Start)
                        var totalSpacing = phase1Spacing + (phase3Spacing * phase3Progress)
                        return distance > 0 ? totalSpacing : -totalSpacing
                    } else {
                        // Final spacing
                        return distance > 0 ? (phase1Spacing + phase3Spacing) : -(phase1Spacing + phase3Spacing)
                    }
                }
                
                property real itemAngle: {
                    if (!isVisible) return distance > 0 ? -65 : 65
                    
                    var slideDeadZone = 10  // Dead zone for sliding only
                    var rotationEnd = 60    // Where rotation completes
                    
                    if (absDistance < slideDeadZone) {
                        // Dead zone - no rotation, only sliding
                        return 0
                    } else if (absDistance < rotationEnd) {
                        // Smooth rotation after dead zone
                        var normalizedDistance = (absDistance - slideDeadZone) / (rotationEnd - slideDeadZone)
                        return distance > 0 ? -normalizedDistance * 65 : normalizedDistance * 65
                    } else {
                        // Fixed angle for all albums outside the rotation zone
                        return distance > 0 ? -65 : 65
                    }
                }
                
                // Reuse cached distance calculation
                property real distanceFromCenter: distance
                
                z: {
                    var absDistance = Math.abs(distanceFromCenter)
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
                        return Math.max(0, 500 - indexDiff * 10)
                    } else {
                        // Albums to the left of center (lower index)
                        // Closer to center = higher z-order
                        return Math.max(0, 500 + indexDiff * 10)
                    }
                }
                
                property real scaleAmount: {
                    if (!isVisible) return 0.85
                    
                    // If this is the predicted destination, start scaling up early
                    if (listView.isPredicting && index === listView.predictedIndex) {
                        return 1.0  // Full size for predicted destination
                    }
                    
                    // Simplified scaling calculation
                    if (absDistance < 20) {
                        return 1.0 - (0.02 * absDistance / 20)
                    } else if (absDistance < 60) {
                        return 0.98 - (0.13 * (absDistance - 20) / 40)
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
                            enabled: Math.abs(distanceFromCenter) < 200 // Only animate near center
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic 
                            }
                        }
                        Behavior on yScale {
                            enabled: Math.abs(distanceFromCenter) < 200 // Only animate near center
                            NumberAnimation { 
                                duration: 300
                                easing.type: Easing.OutCubic 
                            }
                        }
                    },
                    Rotation {
                        // Asymmetric rotation axis - 1/10 from the "front" edge
                        origin.x: {
                            if (distanceFromCenter > 0) {
                                // Moving right
                                return delegateItem.width * 0.75
                            } else if (distanceFromCenter < 0) {
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
                    layer.enabled: false // Disabled to improve performance
                    layer.smooth: false
                    
                    Item {
                        id: albumContainer
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 200
                        height: 200
                            
                        Image {
                            id: albumImage
                            anchors.fill: parent
                            source: (albumData && albumData.hasArt && albumData.id) ? "image://albumart/" + albumData.id + "/thumbnail" : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            antialiasing: true
                            cache: true  // Enable caching to prevent reloading
                            
                            onStatusChanged: {
                                if (status === Image.Error) {
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
                            onClicked: {
                                listView.currentIndex = index
                                root.albumClicked(albumData)
                            }
                            onDoubleClicked: {
                                // Play the album on double-click
                                MediaPlayer.playAlbumByName(albumData.albumArtist, albumData.title, 0)
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
                            sourceItem: albumContainer  // Always keep the source
                            visible: Math.abs(distanceFromCenter) < 900  // Increased to cover all visible albums in max width
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
                            
                            // Update reflection when album image changes
                            Connections {
                                target: albumImage
                                function onStatusChanged() {
                                    if (albumImage.status === Image.Ready) {
                                        reflection.scheduleUpdate()
                                    }
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