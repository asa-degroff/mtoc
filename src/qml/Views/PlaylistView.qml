import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0

Item {
    id: root
    
    signal playlistSelected(string playlistName)
    signal playlistDoubleClicked(string playlistName)
    
    ListView {
        id: playlistListView
        anchors.fill: parent
        model: PlaylistManager.playlists
        spacing: 4
        clip: true
        
        delegate: Rectangle {
            width: ListView.view.width - 12  // Account for scrollbar
            height: 60
            color: mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)
            radius: 6
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)
            
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
                    color: Qt.rgba(1, 1, 1, 0.05)
                    radius: 4
                    
                    Text {
                        anchors.centerIn: parent
                        text: PlaylistManager.isSpecialPlaylist(modelData) ? "♫" : "♪"
                        font.pixelSize: 24
                        color: PlaylistManager.isSpecialPlaylist(modelData) ? "#4a9eff" : "#808080"
                    }
                }
                
                // Playlist info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    
                    Label {
                        text: modelData
                        color: "white"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    
                    RowLayout {
                        spacing: 8
                        
                        Label {
                            text: {
                                var count = PlaylistManager.getPlaylistTrackCount(modelData)
                                return count + " track" + (count !== 1 ? "s" : "")
                            }
                            color: "#808080"
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: "•"
                            color: "#606060"
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: {
                                var duration = PlaylistManager.getPlaylistDuration(modelData)
                                return formatDuration(duration)
                            }
                            color: "#808080"
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: "•"
                            color: "#606060"
                            font.pixelSize: 11
                        }
                        
                        Label {
                            text: PlaylistManager.getPlaylistModifiedDate(modelData)
                            color: "#808080"
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
                        color: renameMouseArea.containsMouse ? Qt.rgba(0, 0.5, 1, 0.2) : Qt.rgba(1, 1, 1, 0.05)
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
                        color: deleteMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
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
                acceptedButtons: Qt.LeftButton
                z: -1  // Put below other elements
                onClicked: {
                    // Only handle clicks if not clicking on the action buttons area
                    if (mouse.x < width - 68) {  // Account for both rename and delete buttons
                        root.playlistSelected(modelData)
                    }
                }
                onDoubleClicked: {
                    // Only handle double clicks if not clicking on the action buttons area
                    if (mouse.x < width - 68) {  // Account for both rename and delete buttons
                        root.playlistDoubleClicked(modelData)
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
            color: "#808080"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            visible: playlistListView.count === 0
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
            color: Qt.rgba(0.1, 0.1, 0.1, 0.95)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.1)
            
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
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                TextField {
                    id: renameTextField
                    width: parent.width
                    text: renamePopup.newPlaylistName
                    color: "white"
                    font.pixelSize: 14
                    selectByMouse: true
                    selectionColor: Qt.rgba(0, 0.5, 1, 0.3)
                    selectedTextColor: "white"
                    placeholderText: "Enter new playlist name"
                    placeholderTextColor: "#606060"
                    
                    background: Rectangle {
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: renameTextField.activeFocus ? Qt.rgba(0, 0.5, 1, 0.5) : Qt.rgba(1, 1, 1, 0.1)
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
                        color: cancelRenameMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.1)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Label {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "white"
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
                            color: "white"
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
            color: Qt.rgba(0.1, 0.1, 0.1, 0.95)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.1)
            
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
                    color: "white"
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
                        color: cancelButtonMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.1)
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Label {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "white"
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
                            color: "white"
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
    
    Component.onCompleted: {
        PlaylistManager.refreshPlaylists()
    }
}