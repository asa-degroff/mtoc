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
    
    // Build the contextual header text
    function getHeaderText() {
        var baseText = "Queue"
        var contextText = ""
        
        // Add context about what's playing
        if (MediaPlayer.currentPlaylistName) {
            contextText = " - Playing from playlist " + MediaPlayer.currentPlaylistName
        } else if (MediaPlayer.queueSourceAlbumName) {
            contextText = " - Playing from album " + MediaPlayer.queueSourceAlbumName
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
                contextText = " (modified)"
            }
        }
        
        return baseText + contextText
    }
    
    Label {
        text: getHeaderText()
        font.pixelSize: 16
        font.weight: Font.DemiBold
        color: forceLightText ? "#ffffff" : Theme.primaryText
    }
    
    Item { Layout.fillWidth: true }
    
    Label {
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