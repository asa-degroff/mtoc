import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    
    property string albumArtist: ""
    property string albumTitle: ""
    property int startIndex: 0
    
    signal replaceQueue()
    signal playNext()
    signal playLast()
    
    width: 280
    height: 200
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    
    // Semi-transparent background overlay
    Overlay.modal: Rectangle {
        color: "#80000000"
    }
    
    background: Rectangle {
        color: "#2a2a2a"
        radius: 8
        border.width: 1
        border.color: "#404040"
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
            text: "What would you like to do?"
            font.pixelSize: 14
            color: "#cccccc"
            horizontalAlignment: Text.AlignHCenter
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
                    color: parent.hovered ? "#3a4a8a" : "#2a3a7a"
                    radius: 4
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
                    color: parent.hovered ? "#404040" : "#333333"
                    radius: 4
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
                    color: parent.hovered ? "#404040" : "#333333"
                    radius: 4
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
        }
    }
}