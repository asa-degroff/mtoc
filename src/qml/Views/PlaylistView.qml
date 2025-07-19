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
                        text: "♪"
                        font.pixelSize: 24
                        color: "#808080"
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
                    
                    // Delete button
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: deleteMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : Qt.rgba(1, 1, 1, 0.05)
                        visible: mouseArea.containsMouse || deleteMouseArea.containsMouse
                        
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
                    // Only handle clicks if not clicking on the delete button area
                    if (mouse.x < width - 36) {
                        root.playlistSelected(modelData)
                    }
                }
                onDoubleClicked: {
                    // Only handle double clicks if not clicking on the delete button area
                    if (mouse.x < width - 36) {
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
    
    function formatDuration(milliseconds) {
        if (isNaN(milliseconds) || milliseconds < 0) {
            return "0:00"
        }
        
        var totalSeconds = Math.floor(milliseconds / 1000)
        var hours = Math.floor(totalSeconds / 3600)
        var minutes = Math.floor((totalSeconds % 3600) / 60)
        var seconds = totalSeconds % 60
        
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