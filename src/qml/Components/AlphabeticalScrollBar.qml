import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    
    property ListView targetListView: null
    property var artistModel: []
    property var expandedArtists: ({})
    
    width: 20
    
    // Track bar for visual feedback
    Rectangle {
        id: track
        anchors.fill: parent
        anchors.margins: 2
        color: Qt.rgba(0, 0, 0, 0.19)
        radius: 4
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.03)
    }
    
    // Fixed-size handle
    Rectangle {
        id: handle
        width: parent.width - 4
        height: 60  // Fixed height
        x: 2
        
        property real dragY: 0
        property real minY: 2
        property real maxY: parent.height - height - 2
        
        y: {
            if (mouseArea.pressed) {
                // When dragging, constrain to bounds
                return Math.max(minY, Math.min(dragY, maxY))
            } else {
                // When not dragging, compute position from scroll
                return computeHandlePosition()
            }
        }
        
        color: mouseArea.pressed ? Qt.rgba(1, 1, 1, 0.25) : mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.19) : Qt.rgba(1, 1, 1, 0.13)
        radius: 4
        border.width: 1
        border.color: mouseArea.pressed ? Qt.rgba(1, 1, 1, 0.38) : "transparent"
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        
        Behavior on y {
            enabled: !mouseArea.pressed
            NumberAnimation { duration: 150 }
        }
    }
    
    // Letter tooltip
    Rectangle {
        id: letterTooltip
        width: 50
        height: 50
        radius: 8
        color: Qt.rgba(0.1, 0.1, 0.1, 0.9)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        visible: mouseArea.pressed
        
        anchors.right: parent.left
        anchors.rightMargin: 10
        y: handle.y + handle.height/2 - height/2
        
        Label {
            anchors.centerIn: parent
            text: currentLetter
            color: "white"
            font.pixelSize: 24
            font.bold: true
        }
    }
    
    property string currentLetter: "A"
    property var letterPositions: ({})
    
    // Calculate letter positions based on artist model
    function updateLetterPositions() {
        var positions = {}
        var firstLetters = []
        
        for (var i = 0; i < artistModel.length; i++) {
            var artist = artistModel[i]
            var firstChar = artist.name.charAt(0).toUpperCase()
            
            // Handle non-alphabetic characters
            if (!/[A-Z]/.test(firstChar)) {
                firstChar = "#"
            }
            
            if (!positions[firstChar]) {
                positions[firstChar] = i
                firstLetters.push(firstChar)
            }
        }
        
        letterPositions = positions
        return firstLetters
    }
    
    // Compute handle position based on current scroll
    function computeHandlePosition() {
        if (!targetListView || targetListView.contentHeight <= targetListView.height) {
            return handle.minY
        }
        
        var scrollRatio = Math.max(0, Math.min(1, targetListView.contentY / (targetListView.contentHeight - targetListView.height)))
        return handle.minY + scrollRatio * (handle.maxY - handle.minY)
    }
    
    // Get letter for a given y position
    function getLetterForPosition(y) {
        var ratio = Math.max(0, Math.min(1, (y - handle.minY) / (handle.maxY - handle.minY)))
        var letters = Object.keys(letterPositions).sort()
        
        if (letters.length === 0) return "A"
        
        // Map ratio to letter index
        var letterIndex = Math.floor(ratio * letters.length)
        letterIndex = Math.min(letterIndex, letters.length - 1)
        
        return letters[letterIndex]
    }
    
    // Find the actual list position for an artist index, accounting for expanded artists
    function getListPositionForArtistIndex(artistIndex) {
        var position = 0
        
        for (var i = 0; i < artistIndex && i < artistModel.length; i++) {
            position++ // Count the artist item itself
            
            // If this artist is expanded, count its albums
            if (expandedArtists[artistModel[i].name]) {
                // We need to get the album count for this artist
                var albums = targetListView.model.getAlbumsForArtist ? 
                    targetListView.model.getAlbumsForArtist(artistModel[i].name) : []
                
                if (albums && albums.length > 0) {
                    // Calculate the height of the albums grid
                    var gridCols = Math.floor((targetListView.width - 8) / 130) // 120 + 10 for cell width
                    var gridRows = Math.ceil(albums.length / gridCols)
                    var albumsHeight = gridRows * 150 + 16 // 140 + 10 for cell height + padding
                    
                    // Convert height to approximate item count
                    position += albumsHeight / 40 // Assuming average item height of 40
                }
            }
        }
        
        return position
    }
    
    // Scroll to a specific letter
    function scrollToLetter(letter) {
        if (!targetListView || !letterPositions[letter]) return
        
        var artistIndex = letterPositions[letter]
        var listPosition = getListPositionForArtistIndex(artistIndex)
        
        // Position at the top of the view
        targetListView.positionViewAtIndex(artistIndex, ListView.Beginning)
        currentLetter = letter
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        
        drag.target: null  // We'll handle dragging manually
        
        onPressed: function(mouse) {
            handle.dragY = mouse.y - handle.height/2
            var letter = getLetterForPosition(mouse.y)
            currentLetter = letter
            scrollToLetter(letter)
        }
        
        onPositionChanged: function(mouse) {
            if (pressed) {
                handle.dragY = mouse.y - handle.height/2
                var letter = getLetterForPosition(mouse.y)
                if (letter !== currentLetter) {
                    currentLetter = letter
                    scrollToLetter(letter)
                }
            }
        }
        
        onReleased: {
            // Ensure handle position is synced after drag
            handle.dragY = handle.y
        }
    }
    
    // Update positions when model changes
    Connections {
        target: root
        function onArtistModelChanged() {
            updateLetterPositions()
        }
    }
    
    // Update handle position when ListView scrolls
    Connections {
        target: targetListView
        function onContentYChanged() {
            if (!mouseArea.pressed) {
                handle.y = computeHandlePosition()
                
                // Update current letter based on what's visible
                if (targetListView.count > 0) {
                    var topIndex = targetListView.indexAt(0, targetListView.contentY)
                    if (topIndex >= 0 && topIndex < artistModel.length) {
                        var artist = artistModel[topIndex]
                        var firstChar = artist.name.charAt(0).toUpperCase()
                        if (!/[A-Z]/.test(firstChar)) {
                            firstChar = "#"
                        }
                        currentLetter = firstChar
                    }
                }
            }
        }
    }
    
    Component.onCompleted: {
        updateLetterPositions()
    }
}