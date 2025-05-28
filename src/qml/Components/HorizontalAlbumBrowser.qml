import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
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
        function onAlbumModelChanged() {
            loadAllAlbums()
        }
    }
    
    function loadAllAlbums() {
        var sourceAlbums = LibraryManager.albumModel
        
        // Create a copy of the array so we can sort it
        var albums = []
        for (var i = 0; i < sourceAlbums.length; i++) {
            albums.push(sourceAlbums[i])
        }
        
        // Sort albums by artist first, then by year within each artist
        albums.sort(function(a, b) {
            // First compare by album artist
            var artistCompare = a.albumArtist.localeCompare(b.albumArtist)
            if (artistCompare !== 0) {
                return artistCompare
            }
            // If same artist, sort by year
            return (a.year || 0) - (b.year || 0)
        })
        
        allAlbums = albums
        if (albums.length > 0 && currentIndex === -1) {
            currentIndex = 0
            selectedAlbum = albums[0]
        }
    }
    
    function jumpToAlbum(album) {
        for (var i = 0; i < allAlbums.length; i++) {
            if (allAlbums[i].id === album.id) {
                // Animate to the new index instead of jumping
                listView.currentIndex = i
                selectedAlbum = album
                break
            }
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
            spacing: -150
            preferredHighlightBegin: width / 2 - 110
            preferredHighlightEnd: width / 2 + 110
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 500  // Smooth animation duration
            currentIndex: root.currentIndex
            clip: false                 // Disable clipping to allow rotated albums to show
            maximumFlickVelocity: 1500  // Limit scroll speed
            flickDeceleration: 3000     // Faster deceleration
            boundsBehavior: Flickable.StopAtBounds  // Ensure we can reach the bounds
            
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
                    mouse.accepted = false  // Let click events through to delegates
                }
            }
            
            // Keyboard navigation
            focus: true
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
                height: 340  // Height for album plus reflection
                
                property real horizontalOffset: {
                    // Create extra spacing around the center album by pushing entire sides outward
                    var centerIndex = listView.currentIndex
                    var indexDiff = index - centerIndex
                    var extraSpacing = 35  // Extra pixels of spacing on each side of center
                    
                    if (indexDiff === 0) {
                        // Center album - no offset
                        return 0
                    } else if (indexDiff > 0) {
                        // Albums to the right - push all of them right uniformly
                        return extraSpacing
                    } else {
                        // Albums to the left - push all of them left uniformly
                        return -extraSpacing
                    }
                }
                
                property real itemAngle: {
                    var centerX = listView.width / 2
                    var itemCenterX = x + width / 2 - listView.contentX
                    // Calculate distance based on original position (before translation)
                    var distance = itemCenterX - centerX - horizontalOffset
                    var absDistance = Math.abs(distance)
                    var deadZone = 5      // Small zone where rotation is exactly 0
                    var transitionEnd = 80 // Where smooth transition ends and fixed angle begins
                    
                    // For adjacent albums, we need to account for the extra spacing
                    // They should rotate as if they're at their visual position, not their logical position
                    // var centerIndex = listView.currentIndex
                    // var indexDiff = index - centerIndex
                    
                    if (absDistance < deadZone) {
                        // Dead zone - no rotation for perfectly centered album
                        return 0
                    } else if (absDistance < transitionEnd) {
                        // Smooth transition from dead zone to fixed angle
                        var normalizedDistance = (absDistance - deadZone) / (transitionEnd - deadZone) 
                    // else if (Math.abs(indexDiff) === 1) {
                    //     // Adjacent albums - use fixed angle immediately
                    //     return indexDiff > 0 ? -65 : 65
                    // } else if (absDistance < 80) {
                    //     // Other albums in transition zone
                    //     var normalizedDistance = (absDistance - deadZone) / (80 - deadZone)
                        return distance > 0 ? -normalizedDistance * 65 : normalizedDistance * 65
                    } else {
                        // Fixed angle for all albums outside the transition zone
                        return distance > 0 ? -65 : 65
                    }
                }
                
                property real distanceFromCenter: {
                    var centerX = listView.width / 2
                    var itemCenterX = x + width / 2 - listView.contentX
                    return itemCenterX - centerX
                }
                
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
                    // Keep center album at full size, scale down others
                    var absDistance = Math.abs(distanceFromCenter)
                    if (absDistance < 5) {
                        return 1.0  // Full size for center
                    } else if (absDistance < 80) {
                        // Smooth transition from full size to scaled down
                        var normalizedDistance = (absDistance - 5) / 75
                        return 1.0 - (0.05 * normalizedDistance)  // Scale down to 95%
                    } else {
                        return 0.95  // 5% smaller for distant albums
                    }
                }
                
                transform: [
                    Translate {
                        x: horizontalOffset
                        
                        Behavior on x {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    },
                    Scale {
                        origin.x: delegateItem.width / 2
                        origin.y: delegateItem.height / 2
                        xScale: scaleAmount
                        yScale: scaleAmount
                        
                        Behavior on xScale {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                        Behavior on yScale {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    },
                    Rotation {
                        origin.x: delegateItem.width / 2
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
                    height: 310  // Height for album + reflection
                    
                    // Enable layer rendering for better antialiasing during rotation
                    layer.enabled: true
                    layer.smooth: true // smoothing the layer looks better than smoothing the image
                    
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
                        height: 90
                        
                        // The reflection itself
                        ShaderEffectSource {
                            id: reflection
                            anchors.fill: parent
                            sourceItem: albumContainer
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
                            GradientStop { position: 0.5; color: Qt.rgba(0.1, 0.1, 0.1, 0.6) }
                            GradientStop { position: 1.0; color: "#000000" }
                        }
                    }
                }
            }
        }
        
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 40
            color: "#0a0a0a"
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                
                Label {
                    text: selectedAlbum ? selectedAlbum.albumArtist + " - " + selectedAlbum.title : ""
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}