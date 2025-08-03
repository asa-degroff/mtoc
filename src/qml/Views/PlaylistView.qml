import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0
import "../Components"

Item {
    id: root
    focus: true
    
    // Keyboard navigation state
    property int keyboardSelectedIndex: -1
    
    signal playlistSelected(string playlistName)
    signal playlistDoubleClicked(string playlistName, var event)
    signal playlistPlayRequested(string playlistName)
    signal playlistPlayNextRequested(string playlistName)
    signal playlistPlayLastRequested(string playlistName)
    signal navigateToTracks()  // Signal to move focus to track list
    
    // Keyboard navigation handler
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Down) {
            // Navigate down
            if (keyboardSelectedIndex === -1 && playlistListView.count > 0) {
                // First navigation down selects first item
                keyboardSelectedIndex = 0
                ensureKeyboardSelectedVisible()
            } else if (keyboardSelectedIndex < playlistListView.count - 1) {
                keyboardSelectedIndex++
                ensureKeyboardSelectedVisible()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            // Navigate up
            if (keyboardSelectedIndex > 0) {
                keyboardSelectedIndex--
                ensureKeyboardSelectedVisible()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // Select/activate playlist
            if (keyboardSelectedIndex >= 0 && keyboardSelectedIndex < playlistListView.count) {
                var playlistName = PlaylistManager.playlists[keyboardSelectedIndex]
                root.playlistSelected(playlistName)
                // Navigate to track list after selecting
                root.navigateToTracks()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            // Clear selection
            keyboardSelectedIndex = -1
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            // Navigate to track list if a playlist is selected
            if (keyboardSelectedIndex >= 0 && keyboardSelectedIndex < playlistListView.count) {
                root.navigateToTracks()
            }
            event.accepted = true
        }
    }
    
    // Function to ensure keyboard selected item is visible
    function ensureKeyboardSelectedVisible() {
        if (keyboardSelectedIndex < 0 || keyboardSelectedIndex >= playlistListView.count) {
            return
        }
        
        // Calculate the position of the selected item (60 is item height, 4 is spacing)
        var itemY = keyboardSelectedIndex * (60 + 4)
        var visibleHeight = playlistListView.height
        var currentY = playlistListView.contentY
        
        // Check if the item is fully visible
        var itemTop = itemY
        var itemBottom = itemY + 60
        var viewTop = currentY
        var viewBottom = currentY + visibleHeight
        
        var targetY = -1
        
        // If item is above the visible area, scroll to show it at the top with some margin
        if (itemTop < viewTop) {
            targetY = Math.max(0, itemTop - 10)
        }
        // If item is below the visible area, scroll to show it at the bottom with some margin
        else if (itemBottom > viewBottom) {
            targetY = itemBottom - visibleHeight + 10
        }
        
        // Only scroll if needed
        if (targetY >= 0) {
            scrollAnimation.stop()
            scrollAnimation.to = targetY
            scrollAnimation.start()
        }
    }
    
    // Smooth scrolling animation
    NumberAnimation {
        id: scrollAnimation
        target: playlistListView
        property: "contentY"
        duration: 200
        easing.type: Easing.InOutQuad
    }
    
    ListView {
        id: playlistListView
        anchors.fill: parent
        model: PlaylistManager.playlists
        spacing: 4
        clip: true
        
        delegate: Rectangle {
            width: ListView.view.width - 12  // Account for scrollbar
            height: 60
            color: {
                if (index === root.keyboardSelectedIndex) {
                    return Theme.isDark ? Qt.rgba(0.25, 0.32, 0.71, 0.15) : Qt.rgba(0.25, 0.32, 0.71, 0.08)  // Keyboard selected
                } else if (mouseArea.containsMouse) {
                    return Theme.hoverBackground  // Hover
                } else {
                    return Theme.isDark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02)  // Default
                }
            }
            radius: 6
            border.width: 1
            border.color: index === root.keyboardSelectedIndex ? Theme.selectedBackground : Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.08)
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12
                
                // Playlist icon
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                    radius: 4
                    
                    Text {
                        anchors.centerIn: parent
                        text: PlaylistManager.isSpecialPlaylist(modelData) ? "♫" : "♪"
                        font.pixelSize: 24
                        color: PlaylistManager.isSpecialPlaylist(modelData) ? "#4a9eff" : Theme.tertiaryText
                    }
                }
                
                // Playlist info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    Label {
                        text: modelData
                        color: Theme.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    
                    Row {
                        spacing: 8
                        Layout.fillWidth: true
                        clip: true
                        
                        Label {
                            text: {
                                var count = PlaylistManager.getPlaylistTrackCount(modelData)
                                return count + " track" + (count !== 1 ? "s" : "")
                            }
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: "•"
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: {
                                var duration = PlaylistManager.getPlaylistDuration(modelData)
                                return formatDuration(duration)
                            }
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: "•"
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: PlaylistManager.getPlaylistModifiedDate(modelData)
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                    }
                }
                
                // Actions
                Row {
                    spacing: 4
                    z: 10  // Increase z-order to ensure it's above everything
                    
                    // Rename button
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: renameMouseArea.containsMouse ? Qt.rgba(0, 0.5, 1, 0.2) : Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                        visible: (mouseArea.containsMouse || renameMouseArea.containsMouse || deleteMouseArea.containsMouse) && !PlaylistManager.isSpecialPlaylist(modelData)
                        
                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "qrc:/resources/icons/text-input.svg"
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }
                        
                        MouseArea {
                            id: renameMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            propagateComposedEvents: false
                            onClicked: {
                                console.log("Rename button clicked for playlist:", modelData)
                                renamePopup.playlistName = modelData
                                renamePopup.newPlaylistName = modelData
                                renamePopup.visible = true
                                mouse.accepted = true
                            }
                        }
                    }
                    
                    // Delete button
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: deleteMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                        visible: (mouseArea.containsMouse || renameMouseArea.containsMouse || deleteMouseArea.containsMouse) && !PlaylistManager.isSpecialPlaylist(modelData)
                        
                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: deleteMouseArea.containsMouse ? "qrc:/resources/icons/trash-can-open-lid.svg" : "qrc:/resources/icons/trash-can-closed-lid.svg"
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }
                        
                        MouseArea {
                            id: deleteMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            propagateComposedEvents: false
                            onClicked: {
                                console.log("Delete button clicked for playlist:", modelData)
                                deleteConfirmPopup.playlistName = modelData
                                deleteConfirmPopup.visible = true
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }
            
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: -1  // Put below other elements
                
                property string currentPlaylistName: modelData
                
                onClicked: function(mouse) {
                    // Ensure the playlist view has focus for keyboard navigation
                    root.forceActiveFocus()
                    
                    if (mouse.button === Qt.LeftButton) {
                        // Only handle clicks if not clicking on the action buttons area
                        if (mouse.x < width - 68) {  // Account for both rename and delete buttons
                            root.keyboardSelectedIndex = index
                            root.playlistSelected(modelData)
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        // Show context menu
                        root.keyboardSelectedIndex = index
                        playlistContextMenu.playlistName = modelData
                        playlistContextMenu.isAllSongs = modelData === "All Songs"
                        playlistContextMenu.popup()
                    }
                }
                onDoubleClicked: function(mouse) {
                    // Only handle double clicks if not clicking on the action buttons area
                    if (mouse.x < width - 68) {  // Account for both rename and delete buttons
                        root.playlistDoubleClicked(modelData, mouse)
                    }
                }
            }
        }
        
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        
        // Empty state
        Label {
            anchors.centerIn: parent
            text: "No playlists yet\n\nSave the current queue to create your first playlist"
            color: Theme.tertiaryText
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            visible: playlistListView.count === 0
        }
    }
    
    // Context menu for playlists
    StyledMenu {
        id: playlistContextMenu
        
        property string playlistName: ""
        property bool isAllSongs: false
        
        MenuItem {
            text: "Play"
            onTriggered: {
                root.playlistPlayRequested(playlistContextMenu.playlistName)
            }
        }
        
        MenuItem {
            text: "Play Next"
            visible: !playlistContextMenu.isAllSongs  // Hide for "All Songs"
            height: visible ? implicitHeight : 0
            onTriggered: {
                root.playlistPlayNextRequested(playlistContextMenu.playlistName)
            }
        }
        
        MenuItem {
            text: "Play Last"
            visible: !playlistContextMenu.isAllSongs  // Hide for "All Songs"
            height: visible ? implicitHeight : 0
            onTriggered: {
                root.playlistPlayLastRequested(playlistContextMenu.playlistName)
            }
        }
    }
    
    function formatDuration(seconds) {
        if (isNaN(seconds) || seconds < 0) {
            return "0:00"
        }
        
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        var seconds = seconds % 60
        
        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        } else {
            return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
        }
    }
    
    // Rename popup
    Rectangle {
        id: renamePopup
        visible: false
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        
        property string playlistName: ""
        property string newPlaylistName: ""
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                // Close popup if clicking outside
                renamePopup.visible = false
            }
        }
        
        Rectangle {
            anchors.centerIn: parent
            width: 360
            height: 180
            radius: 8
            color: Theme.isDark ? Qt.rgba(0.1, 0.1, 0.1, 0.95) : Qt.rgba(0.95, 0.95, 0.95, 0.95)
            border.width: 1
            border.color: Theme.borderColor
            
            MouseArea {
                anchors.fill: parent
                // Prevent clicks from propagating to the background
            }
            
            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                
                Label {
                    text: "Rename playlist"
                    color: Theme.primaryText
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                TextField {
                    id: renameTextField
                    width: parent.width
                    text: renamePopup.newPlaylistName
                    color: Theme.primaryText
                    font.pixelSize: 14
                    selectByMouse: true
                    selectionColor: Qt.rgba(0, 0.5, 1, 0.3)
                    selectedTextColor: Theme.primaryText
                    placeholderText: "Enter new playlist name"
                    placeholderTextColor: Theme.tertiaryText
                    
                    background: Rectangle {
                        color: Theme.inputBackground
                        border.width: 1
                        border.color: renameTextField.activeFocus ? Theme.linkColor : Theme.borderColor
                        radius: 4
                    }
                    
                    onTextChanged: {
                        renamePopup.newPlaylistName = text
                    }
                    
                    Keys.onReturnPressed: {
                        if (text.trim().length > 0) {
                            renameButton.clicked()
                        }
                    }
                    
                    Keys.onEscapePressed: {
                        renamePopup.visible = false
                    }
                    
                    Component.onCompleted: {
                        // Select all text when popup opens
                        selectAll()
                        forceActiveFocus()
                    }
                }
                
                Label {
                    text: {
                        var trimmedName = renamePopup.newPlaylistName.trim()
                        if (trimmedName.length === 0) {
                            return "Playlist name cannot be empty"
                        } else if (trimmedName !== renamePopup.playlistName && PlaylistManager.playlists.indexOf(trimmedName) !== -1) {
                            return "A playlist with this name already exists"
                        } else if (!/^[^<>:"/\\|?*]+$/.test(trimmedName)) {
                            return "Invalid characters in playlist name"
                        }
                        return ""
                    }
                    color: "#ff6060"
                    font.pixelSize: 12
                    visible: text.length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    
                    // Cancel button
                    Rectangle {
                        width: 100
                        height: 36
                        radius: 4
                        color: cancelRenameMouseArea.containsMouse ? Theme.hoverBackground : Theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Label {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.primaryText
                            font.pixelSize: 13
                        }
                        
                        MouseArea {
                            id: cancelRenameMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                renamePopup.visible = false
                            }
                        }
                    }
                    
                    // Rename button
                    Rectangle {
                        id: renameButton
                        width: 100
                        height: 36
                        radius: 4
                        color: {
                            var trimmedName = renamePopup.newPlaylistName.trim()
                            var isValid = trimmedName.length > 0 && 
                                         (trimmedName === renamePopup.playlistName || PlaylistManager.playlists.indexOf(trimmedName) === -1) &&
                                         /^[^<>:"/\\|?*]+$/.test(trimmedName)
                            
                            if (!isValid) {
                                return Qt.rgba(0.3, 0.3, 0.3, 0.3)
                            }
                            return confirmRenameMouseArea.containsMouse ? Qt.rgba(0, 0.6, 1, 0.8) : Qt.rgba(0, 0.5, 1, 0.6)
                        }
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Label {
                            anchors.centerIn: parent
                            text: "Rename"
                            color: Theme.primaryText
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        
                        MouseArea {
                            id: confirmRenameMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: {
                                var trimmedName = renamePopup.newPlaylistName.trim()
                                var isValid = trimmedName.length > 0 && 
                                             (trimmedName === renamePopup.playlistName || PlaylistManager.playlists.indexOf(trimmedName) === -1) &&
                                             /^[^<>:"/\\|?*]+$/.test(trimmedName)
                                return isValid ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                            }
                            onClicked: {
                                var trimmedName = renamePopup.newPlaylistName.trim()
                                var isValid = trimmedName.length > 0 && 
                                             (trimmedName === renamePopup.playlistName || PlaylistManager.playlists.indexOf(trimmedName) === -1) &&
                                             /^[^<>:"/\\|?*]+$/.test(trimmedName)
                                
                                if (isValid && trimmedName !== renamePopup.playlistName) {
                                    // Rename the playlist
                                    if (PlaylistManager.renamePlaylist(renamePopup.playlistName, trimmedName)) {
                                        console.log("Playlist renamed from", renamePopup.playlistName, "to", trimmedName)
                                    } else {
                                        console.error("Failed to rename playlist")
                                    }
                                }
                                renamePopup.visible = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Delete confirmation popup
    Rectangle {
        id: deleteConfirmPopup
        visible: false
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        
        property string playlistName: ""
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                // Close popup if clicking outside
                deleteConfirmPopup.visible = false
            }
        }
        
        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: 140
            radius: 8
            color: Theme.isDark ? Qt.rgba(0.1, 0.1, 0.1, 0.95) : Qt.rgba(0.95, 0.95, 0.95, 0.95)
            border.width: 1
            border.color: Theme.borderColor
            
            MouseArea {
                anchors.fill: parent
                // Prevent clicks from propagating to the background
            }
            
            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20
                
                Label {
                    text: "Delete playlist \"" + deleteConfirmPopup.playlistName + "\"?"
                    color: Theme.primaryText
                    font.pixelSize: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    
                    // Cancel button
                    Rectangle {
                        width: 100
                        height: 36
                        radius: 4
                        color: cancelButtonMouseArea.containsMouse ? Theme.hoverBackground : Theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.1)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Label {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.primaryText
                            font.pixelSize: 13
                        }
                        
                        MouseArea {
                            id: cancelButtonMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                deleteConfirmPopup.visible = false
                            }
                        }
                    }
                    
                    // Confirm delete button
                    Rectangle {
                        width: 100
                        height: 36
                        radius: 4
                        color: confirmDeleteMouseArea.containsMouse ? Qt.rgba(0.8, 0, 0, 0.8) : Qt.rgba(0.6, 0, 0, 0.6)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Label {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: Theme.primaryText
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        
                        MouseArea {
                            id: confirmDeleteMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Delete the playlist
                                PlaylistManager.deletePlaylist(deleteConfirmPopup.playlistName)
                                deleteConfirmPopup.visible = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Background mouse area to capture clicks and set focus
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: {
            root.forceActiveFocus()
            mouse.accepted = false  // Let the click propagate to items
        }
    }
    
    Component.onCompleted: {
        PlaylistManager.refreshPlaylists()
    }
}