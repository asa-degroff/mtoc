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

    // Flash animation state
    property int flashingPlaylistIndex: -1
    property real flashOpacity: 0.0

    // Inline rename state
    property int renamingPlaylistIndex: -1
    property string renamingOriginalName: ""
    property string renamingNewName: ""

    // Internal ListModel for animated updates
    ListModel {
        id: playlistModel
    }

    // Sync ListModel with PlaylistManager.playlists using incremental updates
    function syncPlaylistModel() {
        var sourceList = PlaylistManager.playlists
        var modelCount = playlistModel.count

        // Build a map of current model items for quick lookup
        var modelItems = {}
        for (var i = 0; i < modelCount; i++) {
            modelItems[playlistModel.get(i).name] = i
        }

        // Build a set of source items
        var sourceSet = {}
        for (var j = 0; j < sourceList.length; j++) {
            sourceSet[sourceList[j]] = true
        }

        // Remove items that are no longer in source (iterate backwards to preserve indices)
        for (var k = modelCount - 1; k >= 0; k--) {
            var itemName = playlistModel.get(k).name
            if (!sourceSet[itemName]) {
                playlistModel.remove(k)
            }
        }

        // Insert new items at correct positions
        for (var m = 0; m < sourceList.length; m++) {
            var name = sourceList[m]
            var currentAtPos = m < playlistModel.count ? playlistModel.get(m).name : null

            if (currentAtPos !== name) {
                // Check if item exists elsewhere in model
                var existingIndex = -1
                for (var n = m + 1; n < playlistModel.count; n++) {
                    if (playlistModel.get(n).name === name) {
                        existingIndex = n
                        break
                    }
                }

                if (existingIndex >= 0) {
                    // Move existing item to correct position
                    playlistModel.move(existingIndex, m, 1)
                } else {
                    // Insert new item
                    playlistModel.insert(m, { "name": name })
                }
            }
        }
    }

    // Sync when playlists change
    Connections {
        target: PlaylistManager
        function onPlaylistsChanged() {
            syncPlaylistModel()
        }
    }

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
    
    // Function to select a playlist by name
    function selectPlaylist(playlistName) {
        var playlists = PlaylistManager.playlists
        for (var i = 0; i < playlists.length; i++) {
            if (playlists[i] === playlistName) {
                keyboardSelectedIndex = i
                ensureKeyboardSelectedVisible()
                return
            }
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

    // Flash animation for newly created playlists
    SequentialAnimation {
        id: flashAnimation

        // First flash
        NumberAnimation {
            target: root
            property: "flashOpacity"
            from: 0.0
            to: 1.0
            duration: 150
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "flashOpacity"
            from: 1.0
            to: 0.0
            duration: 150
            easing.type: Easing.InQuad
        }

        // Brief pause
        PauseAnimation { duration: 100 }

        // Second flash
        NumberAnimation {
            target: root
            property: "flashOpacity"
            from: 0.0
            to: 1.0
            duration: 150
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "flashOpacity"
            from: 1.0
            to: 0.0
            duration: 150
            easing.type: Easing.InQuad
        }

        onFinished: {
            root.flashingPlaylistIndex = -1
        }
    }

    // Function to select a playlist and flash it
    function selectAndFlashPlaylist(playlistName) {
        var playlists = PlaylistManager.playlists
        for (var i = 0; i < playlists.length; i++) {
            if (playlists[i] === playlistName) {
                keyboardSelectedIndex = i
                flashingPlaylistIndex = i
                ensureKeyboardSelectedVisible()
                // Start flash after a brief delay to let navigation complete
                Qt.callLater(function() {
                    flashAnimation.start()
                })
                return
            }
        }
    }

    // Save inline rename
    function saveRename() {
        if (root.renamingPlaylistIndex < 0) return

        var trimmedName = root.renamingNewName.trim()
        var originalName = root.renamingOriginalName

        // Validation
        if (trimmedName.length === 0) {
            cancelRename()
            return
        }
        if (!/^[^<>:"/\\|?*]+$/.test(trimmedName)) {
            cancelRename()
            return
        }
        if (trimmedName !== originalName && PlaylistManager.playlists.indexOf(trimmedName) !== -1) {
            cancelRename()
            return
        }

        // Only rename if changed
        if (trimmedName !== originalName) {
            PlaylistManager.renamePlaylist(originalName, trimmedName)
        }

        // Reset state
        root.renamingPlaylistIndex = -1
        root.renamingOriginalName = ""
        root.renamingNewName = ""
    }

    // Cancel inline rename
    function cancelRename() {
        root.renamingPlaylistIndex = -1
        root.renamingOriginalName = ""
        root.renamingNewName = ""
    }

    ListView {
        id: playlistListView
        anchors.fill: parent
        model: playlistModel
        spacing: 4
        clip: true

        // Animation for newly added items (slides in from top)
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { property: "y"; from: -60; duration: 250; easing.type: Easing.OutQuad }
        }

        // Animation for removed items (fades out)
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 200 }
        }

        // Animation for items displaced by add/remove (slide to new position)
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutQuad }
        }

        delegate: Rectangle {
            width: ListView.view.width - 12  // Account for scrollbar
            height: 60
            color: {
                if (index === root.keyboardSelectedIndex) {
                    return Theme.selectedBackgroundVeryLowOpacity  // Keyboard selected
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

            // Flash highlight overlay
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Theme.selectedBackground
                opacity: index === root.flashingPlaylistIndex ? root.flashOpacity * 0.4 : 0
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
                        text: PlaylistManager.isSpecialPlaylist(model.name) ? "♫" : "♪"
                        font.pixelSize: 24
                        color: PlaylistManager.isSpecialPlaylist(model.name) ? Theme.specialItemColor : Theme.tertiaryText
                    }
                }
                
                // Playlist info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    // Normal display label
                    Label {
                        text: model.name
                        color: Theme.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: index !== root.renamingPlaylistIndex
                    }

                    // Inline rename TextField
                    TextField {
                        id: inlineRenameField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        visible: index === root.renamingPlaylistIndex
                        text: root.renamingNewName
                        color: Theme.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        selectByMouse: true
                        selectionColor: Qt.rgba(0, 0.5, 1, 0.3)
                        selectedTextColor: Theme.primaryText

                        background: Rectangle {
                            color: Theme.inputBackground
                            border.width: 1
                            border.color: inlineRenameField.activeFocus ? Theme.linkColor : Theme.borderColor
                            radius: 4
                        }

                        onTextChanged: {
                            if (index === root.renamingPlaylistIndex) {
                                root.renamingNewName = text
                            }
                        }

                        Keys.onReturnPressed: {
                            root.saveRename()
                        }

                        Keys.onEscapePressed: {
                            root.cancelRename()
                        }

                        onActiveFocusChanged: {
                            if (!activeFocus && index === root.renamingPlaylistIndex) {
                                // Save on focus loss (click outside)
                                root.saveRename()
                            }
                        }

                        onVisibleChanged: {
                            if (visible) {
                                forceActiveFocus()
                                selectAll()
                            }
                        }
                    }

                    Row {
                        spacing: 8
                        Layout.fillWidth: true
                        clip: true
                        
                        Label {
                            text: {
                                var count = PlaylistManager.getPlaylistTrackCount(model.name)
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
                                var duration = PlaylistManager.getPlaylistDuration(model.name)
                                return formatDuration(duration)
                            }
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: "•"
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                            visible: !PlaylistManager.isSpecialPlaylist(model.name)
                        }
                        
                        Label {
                            text: PlaylistManager.getPlaylistModifiedDate(model.name)
                            color: Theme.tertiaryText
                            font.pixelSize: 11
                        }
                    }
                }
                
                // Actions
                Row {
                    spacing: 4
                    z: 10  // Increase z-order to ensure it's above everything

                    // Save button (visible when renaming this item)
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: saveMouseArea.containsMouse ? Qt.rgba(0, 0.7, 0.3, 0.3) : Qt.rgba(0, 0.6, 0.2, 0.2)
                        visible: index === root.renamingPlaylistIndex

                        Text {
                            anchors.centerIn: parent
                            text: "\u2713"  // Checkmark
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: Theme.isDark ? "#60ff80" : "#208040"
                        }

                        MouseArea {
                            id: saveMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            propagateComposedEvents: false
                            onClicked: {
                                root.saveRename()
                                mouse.accepted = true
                            }
                        }
                    }

                    // Rename button (hidden when renaming this item)
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: renameMouseArea.containsMouse ? Qt.rgba(0, 0.5, 1, 0.2) : Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.05)
                        visible: index !== root.renamingPlaylistIndex && (mouseArea.containsMouse || renameMouseArea.containsMouse || deleteMouseArea.containsMouse) && !PlaylistManager.isSpecialPlaylist(model.name)

                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: Theme.isDark ? "qrc:/resources/icons/text-input.svg" : "qrc:/resources/icons/text-input-dark.svg"
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
                                root.renamingPlaylistIndex = index
                                root.renamingOriginalName = model.name
                                root.renamingNewName = model.name
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
                        visible: (mouseArea.containsMouse || renameMouseArea.containsMouse || deleteMouseArea.containsMouse) && !PlaylistManager.isSpecialPlaylist(model.name)
                        
                        Item {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            
                            Image {
                                id: closedLidIcon
                                anchors.fill: parent
                                source: Theme.isDark ? "qrc:/resources/icons/trash-can-closed-lid.svg" : "qrc:/resources/icons/trash-can-closed-lid-dark.svg"
                                sourceSize.width: 32
                                sourceSize.height: 32
                                opacity: deleteMouseArea.containsMouse ? 0 : 1
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }
                            }
                            
                            Image {
                                id: openLidIcon
                                anchors.fill: parent
                                source: Theme.isDark ? "qrc:/resources/icons/trash-can-open-lid.svg" : "qrc:/resources/icons/trash-can-open-lid-dark.svg"
                                sourceSize.width: 32
                                sourceSize.height: 32
                                opacity: deleteMouseArea.containsMouse ? 1 : 0
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }
                            }
                        }
                        
                        MouseArea {
                            id: deleteMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            propagateComposedEvents: false
                            onClicked: {
                                console.log("Delete button clicked for playlist:", model.name)
                                deleteConfirmPopup.playlistName = model.name
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
                
                property string currentPlaylistName: model.name
                
                onClicked: function(mouse) {
                    // Ensure the playlist view has focus for keyboard navigation
                    root.forceActiveFocus()
                    
                    if (mouse.button === Qt.LeftButton) {
                        // Only handle clicks if not clicking on the action buttons area
                        if (mouse.x < width - 68) {  // Account for both rename and delete buttons
                            root.keyboardSelectedIndex = index
                            root.playlistSelected(model.name)
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        // Show context menu
                        root.keyboardSelectedIndex = index
                        playlistContextMenu.playlistName = model.name
                        playlistContextMenu.isAllSongs = model.name === "All Songs"
                        playlistContextMenu.popup()
                    }
                }
                onDoubleClicked: function(mouse) {
                    // Only handle double clicks if not clicking on the action buttons area
                    if (mouse.x < width - 68) {  // Account for both rename and delete buttons
                        root.playlistDoubleClicked(model.name, mouse)
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
        syncPlaylistModel()
        PlaylistManager.refreshPlaylists()
    }
}