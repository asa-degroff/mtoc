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
    
    contentItem: ColumnLayout {
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
            wrapMode: Text.WordWrap
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
                
                background: Rectangle {
                    color: parent.hovered ? Qt.rgba(0.23, 0.29, 0.54, 0.9) : Qt.rgba(0.16, 0.23, 0.48, 0.8)
                    radius: 4
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)
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
                
                background: Rectangle {
                    color: parent.hovered ? Qt.rgba(0.25, 0.25, 0.25, 0.8) : Qt.rgba(0.2, 0.2, 0.2, 0.7)
                    radius: 4
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)
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
                
                background: Rectangle {
                    color: parent.hovered ? Qt.rgba(0.25, 0.25, 0.25, 0.8) : Qt.rgba(0.2, 0.2, 0.2, 0.7)
                    radius: 4
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)
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
                
                background: Rectangle {
                    color: parent.hovered ? Qt.rgba(0.23, 0.23, 0.23, 0.6) : Qt.rgba(0.16, 0.16, 0.16, 0.5)
                    radius: 4
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.2)
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
    }
}