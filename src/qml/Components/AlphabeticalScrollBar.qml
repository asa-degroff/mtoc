import QtQuick 2.15
import QtQuick.Controls 2.15
import Mtoc.Backend 1.0

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
        width: parent.width - 6
        height: 60  // Fixed height
        x: 3
        
        property real dragY: 0
        property real minY: 2
        property real maxY: parent.height - height - 2
        property bool isDragging: false
        property real targetY: minY
        
        y: targetY
        
        color: mouseArea.pressed ? Qt.rgba(1, 1, 1, 0.25) : mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.19) : Qt.rgba(1, 1, 1, 0.13)
        radius: 4
        border.width: 1
        border.color: mouseArea.pressed ? Qt.rgba(1, 1, 1, 0.38) : "transparent"
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        
        Behavior on targetY {
            enabled: !handle.isDragging
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
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
    property var letterPositions: ({})  // letter -> contentY position
    property var availableLetters: []   // sorted array of available letters
    property real lastKnownContentHeight: 0
    
    // Calculate letter positions based on actual content positions
    function updateLetterPositions() {
        if (!targetListView || !artistModel || artistModel.length === 0) {
            letterPositions = {}
            availableLetters = []
            return
        }
        
        var positions = {}
        var letters = []
        
        // Use the ListView's contentItem to get actual item positions
        for (var i = 0; i < artistModel.length; i++) {
            var artist = artistModel[i]
            var firstChar = artist.name.charAt(0).toUpperCase()
            
            // Handle non-alphabetic characters
            if (!/[A-Z]/.test(firstChar)) {
                firstChar = "#"
            }
            
            // Only record the first occurrence of each letter
            if (!positions[firstChar]) {
                // Get the actual Y position of this item in the content
                var itemY = getItemContentY(i)
                if (itemY >= 0) {
                    positions[firstChar] = itemY
                    letters.push(firstChar)
                }
            }
        }
        
        // Sort letters alphabetically, with # at the end
        letters.sort(function(a, b) {
            if (a === "#") return 1
            if (b === "#") return -1
            return a.localeCompare(b)
        })
        
        letterPositions = positions
        availableLetters = letters
    }
    
    // Get the contentY position for a given artist index
    function getItemContentY(artistIndex) {
        if (!targetListView || artistIndex < 0 || artistIndex >= artistModel.length) {
            return -1
        }
        
        // Use the actual ListView's itemAtIndex function if available
        // This will get us the real position from the ListView
        try {
            var item = targetListView.itemAtIndex ? targetListView.itemAtIndex(artistIndex) : null
            if (item && typeof item.y !== 'undefined') {
                return item.y
            }
        } catch (error) {
            // Fallback to calculation if itemAtIndex fails
        }
        
        // Fallback: Calculate the accumulated height up to this artist
        var contentY = 0
        var spacing = targetListView.spacing || 0
        
        for (var i = 0; i < artistIndex; i++) {
            // Add artist item height (40px + spacing)
            contentY += 40
            if (i < artistIndex - 1) contentY += spacing
            
            // Add expanded albums height if this artist is expanded
            var artistName = artistModel[i].name
            if (expandedArtists[artistName]) {
                var albumsHeight = getExpandedAlbumsHeight(artistName)
                contentY += albumsHeight
                if (i < artistIndex - 1) contentY += spacing
            }
        }
        
        return contentY
    }
    
    // Calculate the height of expanded albums for an artist
    function getExpandedAlbumsHeight(artistName) {
        try {
            if (!targetListView || typeof LibraryManager === 'undefined' || !LibraryManager.getAlbumsForArtist) {
                return 0
            }
            
            if (!artistName || typeof artistName !== 'string') {
                return 0
            }
            
            // Add safety check to prevent segfault - avoid calling during initialization
            if (typeof LibraryManager.albumModel === 'undefined' || !LibraryManager.albumModel) {
                return 0
            }
            
            var albums
            try {
                albums = LibraryManager.getAlbumsForArtist(artistName)
            } catch (cppError) {
                console.warn("C++ error in getAlbumsForArtist for artist:", artistName, "error:", cppError)
                return 0
            }
            
            if (!albums || !Array.isArray(albums) || albums.length === 0) {
                return 0
            }
            
            // Validate targetListView width
            if (!targetListView.width || targetListView.width <= 0) {
                return 0
            }
            
            // Calculate grid dimensions - same as in LibraryPane.qml
            var availableWidth = targetListView.width - 16 // Accounting for margins
            var cellWidth = 130 // 120 + 10 for padding (matches LibraryPane cellWidth + 10)
            var cellHeight = 150 // 140 + 10 for padding (matches LibraryPane cellHeight + 10)
            var cols = Math.max(1, Math.floor(availableWidth / cellWidth))
            var rows = Math.ceil(albums.length / cols)
            
            // Total height: grid height + container padding (matches LibraryPane calculation)
            return rows * cellHeight + 16
        } catch (error) {
            console.warn("Error in getExpandedAlbumsHeight:", error, "for artist:", artistName)
            return 0
        }
    }
    
    // Get letter for a given handle position
    function getLetterForPosition(y) {
        if (availableLetters.length === 0) return "A"
        
        var ratio = Math.max(0, Math.min(1, (y - handle.minY) / (handle.maxY - handle.minY)))
        var letterIndex = Math.floor(ratio * availableLetters.length)
        letterIndex = Math.min(letterIndex, availableLetters.length - 1)
        
        return availableLetters[letterIndex]
    }
    
    // Get handle position for current letter
    function getPositionForLetter(letter) {
        if (availableLetters.length === 0) return handle.minY
        
        var letterIndex = availableLetters.indexOf(letter)
        if (letterIndex === -1) return handle.minY
        
        var ratio = letterIndex / Math.max(1, availableLetters.length - 1)
        return handle.minY + ratio * (handle.maxY - handle.minY)
    }
    
    // Scroll to a specific letter
    function scrollToLetter(letter) {
        if (!targetListView || !letterPositions[letter]) return
        
        var targetContentY = letterPositions[letter]
        
        // Ensure we don't scroll past the content bounds
        var maxContentY = Math.max(0, targetListView.contentHeight - targetListView.height)
        targetContentY = Math.min(targetContentY, maxContentY)
        
        // Animate to the position
        targetListView.contentY = targetContentY
        currentLetter = letter
        
        // Update handle position immediately
        if (!handle.isDragging) {
            handle.targetY = getPositionForLetter(letter)
        }
    }
    
    // Update handle position based on current scroll position
    function updateHandleFromScroll() {
        if (!targetListView || handle.isDragging || availableLetters.length === 0) return
        
        var currentContentY = targetListView.contentY
        var contentHeight = targetListView.contentHeight
        var viewHeight = targetListView.height
        
        // Prevent invalid scroll positions from breaking the handle
        if (contentHeight <= viewHeight) {
            // No scrolling needed
            handle.targetY = handle.minY
            currentLetter = availableLetters[0] || "A"
            return
        }
        
        // Clamp contentY to valid range
        currentContentY = Math.max(0, Math.min(currentContentY, contentHeight - viewHeight))
        
        // Find which letter section we're currently viewing
        var closestLetter = availableLetters[0] || "A"
        var minDistance = Math.abs(currentContentY - (letterPositions[closestLetter] || 0))
        
        for (var i = 1; i < availableLetters.length; i++) {
            var letter = availableLetters[i]
            var letterY = letterPositions[letter] || 0
            var distance = Math.abs(currentContentY - letterY)
            
            if (distance < minDistance) {
                minDistance = distance
                closestLetter = letter
            }
        }
        
        currentLetter = closestLetter
        var newTargetY = getPositionForLetter(closestLetter)
        
        // Ensure handle position is within valid bounds
        newTargetY = Math.max(handle.minY, Math.min(newTargetY, handle.maxY))
        handle.targetY = newTargetY
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        
        drag.target: null  // We'll handle dragging manually
        
        onPressed: function(mouse) {
            handle.isDragging = true
            handle.dragY = mouse.y - handle.height/2
            handle.targetY = Math.max(handle.minY, Math.min(handle.dragY, handle.maxY))
            
            var letter = getLetterForPosition(mouse.y)
            currentLetter = letter
            scrollToLetter(letter)
        }
        
        onPositionChanged: function(mouse) {
            if (pressed && handle.isDragging) {
                handle.dragY = mouse.y - handle.height/2
                handle.targetY = Math.max(handle.minY, Math.min(handle.dragY, handle.maxY))
                
                var letter = getLetterForPosition(mouse.y)
                if (letter !== currentLetter) {
                    currentLetter = letter
                    scrollToLetter(letter)
                }
            }
        }
        
        onReleased: {
            handle.isDragging = false
            // Handle will stay at its current position due to scrollToLetter
        }
    }
    
    // Update positions when model changes
    Connections {
        target: root
        function onArtistModelChanged() {
            Qt.callLater(updateLetterPositions)
        }
        function onExpandedArtistsChanged() {
            Qt.callLater(updateLetterPositions)
        }
    }
    
    // Timer for debouncing scroll updates
    Timer {
        id: updateTimer
        interval: 50  // 50ms debounce
        repeat: false
        onTriggered: updateHandleFromScroll()
    }
    
    // Timer for debouncing position updates
    Timer {
        id: positionUpdateTimer
        interval: 100  // 100ms debounce for position updates
        repeat: false
        onTriggered: updateLetterPositions()
    }
    
    // Update handle position when ListView scrolls (user-initiated scrolling)
    Connections {
        target: targetListView
        function onContentYChanged() {
            if (!handle.isDragging) {
                updateTimer.restart()
            }
        }
        function onContentHeightChanged() {
            if (targetListView.contentHeight !== lastKnownContentHeight) {
                lastKnownContentHeight = targetListView.contentHeight
                positionUpdateTimer.restart()
            }
        }
    }
    
    Component.onCompleted: {
        Qt.callLater(updateLetterPositions)
    }
}