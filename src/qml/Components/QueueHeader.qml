import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Mtoc.Backend 1.0

RowLayout {
    id: root
    
    property bool showPlaylistSavedMessage: false
    property bool forceLightText: false
    
    signal clearQueueRequested()
    
    // Helper function to format queue duration
    function formatQueueDuration(totalSeconds) {
        if (isNaN(totalSeconds) || totalSeconds < 0) {
            return "0:00"
        }
        
        var hours = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        
        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        } else {
            return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
    }
    
    // Build the contextual header text (without "Queue" prefix)
    function getContextText() {
        var contextText = ""
        
        // Add context about what's playing
        if (MediaPlayer.currentPlaylistName) {
            contextText = "Playing from playlist " + MediaPlayer.currentPlaylistName
        } else if (MediaPlayer.queueSourceAlbumName) {
            contextText = "Playing from album " + MediaPlayer.queueSourceAlbumName
            if (MediaPlayer.queueSourceAlbumArtist) {
                contextText += " by " + MediaPlayer.queueSourceAlbumArtist
            }
        }
        
        // Add modified indicator
        if (MediaPlayer.isQueueModified) {
            if (contextText !== "") {
                contextText += " (modified)"
            } else {
                // Queue has individual tracks added, no album/playlist context
                contextText = "(modified)"
            }
        }
        
        return contextText
    }
    
    // Fixed "Queue" label
    Label {
        Layout.alignment: Qt.AlignVCenter
        text: "Queue"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        color: forceLightText ? "#ffffff" : Theme.primaryText
    }
    
    // Scrolling container for context text (always present to maintain layout)
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
        
        Flickable {
            anchors.fill: parent
            contentHeight: height
            interactive: false
            clip: true
            
            // Container for the scrolling text
            Item {
                id: contextTextContainer
                anchors.fill: parent
                
                // Row containing duplicated text for seamless scrolling
                Row {
                    id: contextTextRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 60  // Gap between duplicates
                    
                    // Properties for scrolling
                    property string contextText: getContextText()
                    property bool needsScrolling: contextLabel1.contentWidth > contextTextContainer.width
                    property real scrollOffset: 0
                    property real pauseDuration: 500  // Pause at end in ms
                    property real scrollDuration: Math.max(4000, contextLabel1.contentWidth * 20)  // Speed based on text length
                    
                    // Position for scrolling
                    x: needsScrolling ? -scrollOffset : 0
                    
                    // Update scrolling when text changes
                    onContextTextChanged: {
                        scrollOffset = 0
                        contextScrollAnimation.stop()
                        if (needsScrolling && contextText !== "" && root.visible) {
                            contextScrollAnimation.start()
                        }
                    }
                    
                    onNeedsScrollingChanged: {
                        scrollOffset = 0
                        contextScrollAnimation.stop()
                        if (needsScrolling && contextText !== "" && root.visible) {
                            contextScrollAnimation.start()
                        }
                    }
                    
                    Connections {
                        target: root
                        function onVisibleChanged() {
                            if (root.visible) {
                                // Start animation if needed when becoming visible
                                if (contextTextRow.needsScrolling && contextTextRow.contextText !== "") {
                                    contextScrollAnimation.start()
                                }
                            } else {
                                // Stop animation when becoming invisible
                                contextScrollAnimation.stop()
                            }
                        }
                    }
                    
                    Component.onDestruction: {
                        // Clean up animation when component is destroyed
                        contextScrollAnimation.stop()
                    }
                    
                    // First copy of the text
                    Label {
                        id: contextLabel1
                        text: parent.contextText
                        color: forceLightText ? "#ffffff" : Theme.primaryText
                        opacity: 0.7
                        font.pixelSize: 14
                    }
                    
                    // Second copy for seamless wrap-around (only visible when scrolling)
                    Label {
                        text: parent.contextText
                        color: forceLightText ? "#ffffff" : Theme.primaryText
                        opacity: 0.7
                        font.pixelSize: 14
                        visible: parent.needsScrolling
                    }
                    
                    // Continuous scrolling animation
                    SequentialAnimation {
                        id: contextScrollAnimation
                        loops: Animation.Infinite
                        
                        // Initial pause
                        PauseAnimation {
                            duration: contextTextRow.pauseDuration
                        }
                        
                        // Single smooth scrolling animation with subtle easing
                        NumberAnimation {
                            target: contextTextRow
                            property: "scrollOffset"
                            from: 0
                            to: contextLabel1.contentWidth + contextTextRow.spacing  // Scroll one full text width + gap
                            duration: contextTextRow.scrollDuration
                            easing.type: Easing.InOutQuad  // Smooth acceleration and deceleration
                        }
                        
                        // Brief pause at the wrap point
                        PauseAnimation {
                            duration: contextTextRow.pauseDuration
                        }
                        
                        // Instant reset to beginning (seamless wrap)
                        PropertyAction {
                            target: contextTextRow
                            property: "scrollOffset"
                            value: 0
                        }
                    }
                }
            }
        }
    }
    
    Label {
        Layout.alignment: Qt.AlignVCenter
        text: showPlaylistSavedMessage ? "Playlist Saved" : 
              MediaPlayer.queueLength + " track" + (MediaPlayer.queueLength !== 1 ? "s" : "") + ", " + formatQueueDuration(MediaPlayer.totalQueueDuration)
        font.pixelSize: 12
        color: showPlaylistSavedMessage ? "#60ff60" : (forceLightText ? "#808080" : Theme.secondaryText)
        
        Behavior on color {
            ColorAnimation { duration: 200 }
        }
        
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }
    }
    
    // Save queue button
    Rectangle {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 4
        color: saveQueueMouseArea.containsMouse ? Qt.rgba(0, 1, 0, 0.2) : 
               (forceLightText ? Qt.rgba(1, 1, 1, 0.05) : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(254, 254, 254, 0.5)))
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, forceLightText ? 0.3 : 0.15)
        visible: MediaPlayer.queueLength > 0 && !MediaPlayer.isPlayingVirtualPlaylist
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        
        Image {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: (forceLightText || Theme.isDark) ? "qrc:/resources/icons/save.svg" : "qrc:/resources/icons/save-dark.svg"
            sourceSize.width: 40
            sourceSize.height: 40
            opacity: saveQueueMouseArea.containsMouse ? 0.7 : 1.0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
        
        MouseArea {
            id: saveQueueMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (PlaylistManager.saveQueueAsPlaylist()) {
                    console.log("Queue saved as playlist");
                }
            }
        }
        
        ToolTip {
            visible: saveQueueMouseArea.containsMouse
            text: "Save queue as playlist"
            delay: 500
        }
    }
    
    // Clear queue button
    Rectangle {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 4
        color: clearQueueMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : 
               (forceLightText ? Qt.rgba(1, 1, 1, 0.05) : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(254, 254, 254, 0.5)))
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, forceLightText ? 0.3 : 0.15)
        visible: (MediaPlayer.queueLength > 0 || MediaPlayer.canUndoClear) && !MediaPlayer.isPlayingVirtualPlaylist
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        
        Image {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: MediaPlayer.canUndoClear ? 
                   ((forceLightText || Theme.isDark) ? "qrc:/resources/icons/undo.svg" : "qrc:/resources/icons/undo-dark.svg") : 
                   ((forceLightText || Theme.isDark) ? "qrc:/resources/icons/bomb.svg" : "qrc:/resources/icons/bomb-dark.svg")
            sourceSize.width: 40
            sourceSize.height: 40
            opacity: clearQueueMouseArea.containsMouse ? 0.7 : 1.0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
        
        MouseArea {
            id: clearQueueMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (MediaPlayer.canUndoClear) {
                    MediaPlayer.undoClearQueue();
                } else {
                    root.clearQueueRequested();
                }
            }
        }
        
        ToolTip {
            visible: clearQueueMouseArea.containsMouse
            text: MediaPlayer.canUndoClear ? "Undo clear queue" : "Clear queue"
            delay: 500
        }
    }
}