import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    
    property string albumArtist: ""
    property string albumTitle: ""
    property int startIndex: 0
    property string playlistName: ""
    property bool isPlaylist: false
    property bool isVirtualPlaylist: false
    
    signal replaceQueue()
    signal playNext()
    signal playLast()
    
    width: 280
    height: 240
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    // Focus management
    property int focusedButtonIndex: 0
    property var visibleButtons: []
    
    // Update visible buttons list when visibility changes
    function updateVisibleButtons() {
        var buttons = []
        buttons.push("replace")  // Always visible
        if (!(isVirtualPlaylist && playlistName === "All Songs")) {
            buttons.push("playNext")
            buttons.push("playLast")
        }
        buttons.push("cancel")  // Always visible
        visibleButtons = buttons
        
        // Ensure focused index is valid
        if (focusedButtonIndex >= visibleButtons.length) {
            focusedButtonIndex = 0
        }
    }
    
    onIsVirtualPlaylistChanged: updateVisibleButtons()
    onPlaylistNameChanged: updateVisibleButtons()
    onOpened: {
        updateVisibleButtons()
        focusedButtonIndex = 0  // Reset to first button when opened
        root.forceActiveFocus()  // Ensure dialog receives keyboard focus
    }
    
    // Semi-transparent background overlay with click handler
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.3)  // Dark overlay for better contrast
        
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }
    
    background: Rectangle {
        color: Qt.rgba(0.12, 0.12, 0.12, 0.5)
        radius: 12
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.15)
        
        // Add a subtle gradient
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.14, 0.14, 0.14, 0.95) }
            GradientStop { position: 1.0; color: Qt.rgba(0.10, 0.10, 0.10, 0.95) }
        }
        
        // Drop shadow effect
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
            shadowBlur: 0.8
            shadowColor: Qt.rgba(0, 0, 0, 0.6)
        }
    }
    
    contentItem: FocusScope {
        focus: true
        
        // Keyboard navigation
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Up) {
                root.focusedButtonIndex = (root.focusedButtonIndex - 1 + root.visibleButtons.length) % root.visibleButtons.length
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                root.focusedButtonIndex = (root.focusedButtonIndex + 1) % root.visibleButtons.length
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Activate the focused button
                var buttonId = root.visibleButtons[root.focusedButtonIndex]
                switch (buttonId) {
                    case "replace":
                        root.replaceQueue()
                        root.close()
                        break
                    case "playNext":
                        root.playNext()
                        root.close()
                        break
                    case "playLast":
                        root.playLast()
                        root.close()
                        break
                    case "cancel":
                        root.close()
                        break
                }
                event.accepted = true
            }
        }
        
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
        
        Label {
            Layout.fillWidth: true
            text: "Queue has been modified"
            font.pixelSize: 16
            font.weight: Font.DemiBold
            color: "white"
            horizontalAlignment: Text.AlignHCenter
        }
        
        Label {
            Layout.fillWidth: true
            Layout.maximumWidth: parent.width - 16
            text: {
                if (root.isPlaylist) {
                    return root.playlistName ? "Playing playlist: " + root.playlistName : "Playing playlist"
                } else {
                    return root.albumTitle ? "Playing: " + root.albumArtist + " - " + root.albumTitle : "What would you like to do?"
                }
            }
            font.pixelSize: 14
            color: "#cccccc"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
        }
        
        Item {
            Layout.fillHeight: true
        }
        
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Button {
                Layout.fillWidth: true
                text: "Replace Queue"
                font.pixelSize: 14
                
                property bool isFocused: root.focusedButtonIndex === 0 && root.visibleButtons[0] === "replace"
                
                background: Rectangle {
                    color: {
                        if (parent.isFocused) return Qt.rgba(0.3, 0.36, 0.61, 1.0)
                        if (parent.hovered) return Qt.rgba(0.23, 0.29, 0.54, 0.9)
                        return Qt.rgba(0.16, 0.23, 0.48, 0.8)
                    }
                    radius: 4
                    border.width: parent.isFocused ? 2 : 1
                    border.color: parent.isFocused ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.15)
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    root.replaceQueue()
                    root.close()
                }
            }
            
            Button {
                Layout.fillWidth: true
                text: "Play Next"
                font.pixelSize: 14
                visible: !(root.isVirtualPlaylist && root.playlistName === "All Songs")
                
                property bool isFocused: {
                    var btnIndex = root.visibleButtons.indexOf("playNext")
                    return btnIndex >= 0 && root.focusedButtonIndex === btnIndex
                }
                
                background: Rectangle {
                    color: {
                        if (parent.isFocused) return Qt.rgba(0.35, 0.35, 0.35, 0.9)
                        if (parent.hovered) return Qt.rgba(0.25, 0.25, 0.25, 0.8)
                        return Qt.rgba(0.2, 0.2, 0.2, 0.7)
                    }
                    radius: 4
                    border.width: parent.isFocused ? 2 : 1
                    border.color: parent.isFocused ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.1)
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    root.playNext()
                    root.close()
                }
            }
            
            Button {
                Layout.fillWidth: true
                text: "Play Last"
                font.pixelSize: 14
                visible: !(root.isVirtualPlaylist && root.playlistName === "All Songs")
                
                property bool isFocused: {
                    var btnIndex = root.visibleButtons.indexOf("playLast")
                    return btnIndex >= 0 && root.focusedButtonIndex === btnIndex
                }
                
                background: Rectangle {
                    color: {
                        if (parent.isFocused) return Qt.rgba(0.35, 0.35, 0.35, 0.9)
                        if (parent.hovered) return Qt.rgba(0.25, 0.25, 0.25, 0.8)
                        return Qt.rgba(0.2, 0.2, 0.2, 0.7)
                    }
                    radius: 4
                    border.width: parent.isFocused ? 2 : 1
                    border.color: parent.isFocused ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.1)
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    root.playLast()
                    root.close()
                }
            }
            
            Item {
                Layout.preferredHeight: 4
            }
            
            Button {
                Layout.fillWidth: true
                text: "Cancel"
                font.pixelSize: 14
                
                property bool isFocused: {
                    var btnIndex = root.visibleButtons.indexOf("cancel")
                    return btnIndex >= 0 && root.focusedButtonIndex === btnIndex
                }
                
                background: Rectangle {
                    color: {
                        if (parent.isFocused) return Qt.rgba(0.33, 0.33, 0.33, 0.7)
                        if (parent.hovered) return Qt.rgba(0.23, 0.23, 0.23, 0.6)
                        return Qt.rgba(0.16, 0.16, 0.16, 0.5)
                    }
                    radius: 4
                    border.width: parent.isFocused ? 2 : 1
                    border.color: parent.isFocused ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.2)
                }
                
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "#cccccc"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    root.close()
                }
            }
        }
        }  // End of ColumnLayout
    }  // End of FocusScope
}