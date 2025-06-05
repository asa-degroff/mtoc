import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt5Compat.GraphicalEffects
import Mtoc.Backend 1.0

Item {
    id: root
    height: 320
    
    property var selectedAlbum: null
    property int currentIndex: -1
    property var allAlbums: []
    
    signal albumClicked(var album)
    
    Component.onCompleted: {
        loadAllAlbums()
    }
    
    Connections {
        target: LibraryManager
        function onLibraryChanged() {
            console.log("HorizontalAlbumBrowser: libraryChanged signal received, reloading albums");
            loadAllAlbums()
        }
    }
    
    function loadAllAlbums() {
        var sourceAlbums = LibraryManager.albumModel
        console.log("HorizontalAlbumBrowser: loadAllAlbums called, got", sourceAlbums.length, "albums from LibraryManager");
        
        // Create safe copies of album objects to avoid stale references
        var albums = []
        for (var i = 0; i < sourceAlbums.length; i++) {
            var sourceAlbum = sourceAlbums[i]
            // Create a deep copy to avoid stale QVariantMap references
            var albumCopy = {
                id: sourceAlbum.id,
                title: sourceAlbum.title,
                albumArtist: sourceAlbum.albumArtist,
                year: sourceAlbum.year,
                trackCount: sourceAlbum.trackCount,
                duration: sourceAlbum.duration,
                hasArt: sourceAlbum.hasArt
            }
            albums.push(albumCopy)
        }
        
        // Sort albums by artist first, then by year (descending) within each artist
        albums.sort(function(a, b) {
            // First compare by album artist
            var artistCompare = a.albumArtist.localeCompare(b.albumArtist)
            if (artistCompare !== 0) {
                return artistCompare
            }
            // If same artist, sort by year descending (newest first)
            return (b.year || 0) - (a.year || 0)
        })
        
        allAlbums = albums
        if (albums.length > 0 && currentIndex === -1) {
            currentIndex = 0
            selectedAlbum = albums[0]
        }
    }
    
    function jumpToAlbum(album) {
        try {
            // Validate album parameter
            if (!album || typeof album !== "object" || typeof album.id === "undefined") {
                console.warn("HorizontalAlbumBrowser.jumpToAlbum: Invalid album parameter:", JSON.stringify(album));
                return;
            }
            
            // Validate allAlbums array
            if (!allAlbums || !Array.isArray(allAlbums)) {
                console.warn("HorizontalAlbumBrowser.jumpToAlbum: allAlbums is not a valid array");
                return;
            }
            
            for (var i = 0; i < allAlbums.length; i++) {
                var currentAlbum = allAlbums[i];
                if (currentAlbum && 
                    typeof currentAlbum === "object" && 
                    typeof currentAlbum.id !== "undefined" && 
                    currentAlbum.id === album.id) {
                    // Animate to the new index instead of jumping
                    listView.currentIndex = i
                    selectedAlbum = currentAlbum  // Use the fresh copy, not the potentially stale reference
                    break
                }
            }
        } catch (error) {
            console.warn("HorizontalAlbumBrowser.jumpToAlbum error:", error);
        }
    }
    
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        clip: true  // Clip at the component boundary
        
        ListView {
            id: listView
            anchors.fill: parent
            anchors.topMargin: 30      // Increased margin to accommodate rotation
            anchors.bottomMargin: 30    // Bottom margin for reflection and info bar
            model: allAlbums
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
            cacheBuffer: 600  // Only cache items within reasonable range
            
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
                if (currentIndex >= 0 && currentIndex < allAlbums.length) {
                    root.currentIndex = currentIndex
                    root.selectedAlbum = allAlbums[currentIndex]
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
                
                // Cache expensive calculations
                property real centerX: listView.width / 2
                property real itemCenterX: x + width / 2 - listView.contentX
                property real distance: itemCenterX - centerX
                property real absDistance: Math.abs(distance)
                
                property real horizontalOffset: {
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
                    // If this is the predicted destination, start scaling up early
                    if (listView.isPredicting && index === listView.predictedIndex) {
                        return 1.0  // Full size for predicted destination
                    }
                    
                    // Scale to enhance perspective illusion with rotation
                    var absDistance = Math.abs(distanceFromCenter)
                    var slideDeadZone = 20
                    var scaleEnd = 60
                    
                    // Calculate perspective-corrected scale based on rotation angle
                    var rotationFactor = Math.abs(itemAngle) / 65  // 0 to 1 based on rotation
                    
                    if (absDistance < slideDeadZone) {
                        // Slight scale down even in dead zone for smooth transition
                        var deadZoneProgress = absDistance / slideDeadZone
                        return 1.0 - (0.02 * deadZoneProgress)  // Up to 2% smaller
                    } else if (absDistance < scaleEnd) {
                        // Scale down during rotation
                        var normalizedDistance = (absDistance - slideDeadZone) / (scaleEnd - slideDeadZone)
                        // Combine distance-based and rotation-based scaling
                        var distanceScale = 0.08 * normalizedDistance  // Up to 8% from distance
                        var rotationScale = 0.05 * rotationFactor      // Up to 5% from rotation
                        return 1.0 - distanceScale - rotationScale
                    } else {
                        // Fixed scale for fully rotated albums - more subtle depth
                        return 0.85  // 15% smaller for rotated albums (changed from 25%)
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
                            NumberAnimation {
                                //duration: listView.isPredicting && index === listView.predictedIndex ? 150 : 300
                                duration: 300
                                easing.type: Easing.OutCubic 
                            }
                        }
                        Behavior on yScale {
                            NumberAnimation { 
                                //duration: listView.isPredicting && index === listView.predictedIndex ? 150 : 300
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
                    layer.enabled: Math.abs(distanceFromCenter) < 400
                    layer.smooth: true
                    
                    Item {
                        id: albumContainer
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 200
                        height: 200
                            
                        Image {
                            id: albumImage
                            anchors.fill: parent
                            source: modelData.hasArt ? "image://albumart/" + modelData.id + "/thumbnail" : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            antialiasing: true
                        
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
                                root.albumClicked(modelData)
                            }
                            onDoubleClicked: {
                                // Play the album on double-click
                                MediaPlayer.playAlbumByName(modelData.albumArtist, modelData.title, 0)
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
                        
                        // Conditional reflection - only for center items to reduce GPU load
                        ShaderEffectSource {
                            id: reflection
                            anchors.fill: parent
                            sourceItem: albumContainer
                            visible: Math.abs(distanceFromCenter) < 1200
                            // Capture the bottom portion of the album for reflection
                            sourceRect: Qt.rect(0, albumContainer.height - 120, albumContainer.width, 120)
                            transform: [
                                Scale {
                                    yScale: -1
                                    origin.y: reflection.height / 2
                                }
                            ]
                        }
                        
                        // Dark overlay to dim the reflection
                        Rectangle {
                            anchors.fill: parent
                            color: "#000000"
                            opacity: 0.6
                        }
                    }
                    
                    // Gradient overlay for reflection
                    Rectangle {
                        anchors.fill: reflectionContainer
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.3; color: Qt.rgba(0.1, 0.1, 0.1, 0.4) }
                            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.85) }
                            GradientStop { position: 1.0; color: "#000000" }
                        }
                    }
                }
            }
        }
        
        // Artist/album text overlaid on the reflections
        Item {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            z: 1  // Ensure text appears above the ListView
            
            Label {
                anchors.centerIn: parent
                anchors.bottomMargin: 12
                text: selectedAlbum ? selectedAlbum.albumArtist + " - " + selectedAlbum.title : ""
                color: "white"
                font.pixelSize: 16
                font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                
                // Add a subtle shadow for better readability
                layer.enabled: true
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 4
                    samples: 9
                    color: "#80000000"
                }
            }
        }
    }
}