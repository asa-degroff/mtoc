import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0

Item {
    id: root
    height: 200
    
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
        color: "#1a1a1a"
        clip: true  // Clip at the component boundary
        
        ListView {
            id: listView
            anchors.fill: parent
            anchors.topMargin: 30      // Increased margin to accommodate rotation
            anchors.bottomMargin: 50    // Also increase bottom margin for symmetry
            model: allAlbums
            orientation: ListView.Horizontal
            spacing: -60
            preferredHighlightBegin: width / 2 - 70
            preferredHighlightEnd: width / 2 + 70
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 500  // Smooth animation duration
            currentIndex: root.currentIndex
            clip: false                 // Disable clipping to allow rotated albums to show
            maximumFlickVelocity: 1500  // Limit scroll speed
            flickDeceleration: 3000     // Faster deceleration
            
            onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < allAlbums.length) {
                    root.currentIndex = currentIndex
                    root.selectedAlbum = allAlbums[currentIndex]
                }
            }
            
            // Mouse wheel support
            MouseArea {
                anchors.fill: parent
                onWheel: function(wheel) {
                    if (wheel.angleDelta.y > 0) {
                        listView.decrementCurrentIndex()
                    } else {
                        listView.incrementCurrentIndex()
                    }
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
                width: 140
                height: 140
                
                property real itemAngle: {
                    var centerX = listView.width / 2
                    var itemCenterX = x + width / 2 - listView.contentX
                    var distance = itemCenterX - centerX
                    var threshold = 70  // Distance from center where rotation starts
                    
                    if (Math.abs(distance) < threshold) {
                        // Smooth transition in the center area
                        return -(distance / threshold) * 60
                    } else {
                        // Fixed angle for all albums outside the center
                        return distance > 0 ? -60 : 60
                    }
                }
                
                z: Math.round((1 - Math.abs(itemAngle) / 60) * 10)
                
                transform: [
                    Rotation {
                        origin.x: delegateItem.width / 2
                        origin.y: delegateItem.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: itemAngle
                    }
                ]
                
                Item {
                    id: albumContainer
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    
                    Image {
                        id: albumImage
                        anchors.fill: parent
                        source: modelData.hasArt ? "image://albumart/" + modelData.id + "/thumbnail" : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        antialiasing: true
                        smooth: true
                        
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
                        border.color: listView.currentIndex === index ? "#3f51b5" : "transparent"
                        border.width: 2
                        visible: listView.currentIndex === index
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            listView.currentIndex = index
                            root.albumClicked(modelData)
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