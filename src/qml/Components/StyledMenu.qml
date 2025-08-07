import QtQuick 2.15
import QtQuick.Controls 2.15
import Mtoc.Backend 1.0

Menu {
    id: styledMenu
    
    // Add padding to create space for rounded corners
    topPadding: 6
    bottomPadding: 6
    leftPadding: 6
    rightPadding: 6
    
    // Custom background with rounded corners
    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 40
        radius: 8
        color: Theme.isDark ? Qt.rgba(0.15, 0.15, 0.15, 0.95) : Qt.rgba(1, 1, 1, 0.95)
        border.width: 1
        border.color: Theme.edgeLineColor
        
        // Simple shadow effect using a Rectangle
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            z: -1
            radius: parent.radius + 2
            color: Theme.isDark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.15)
            anchors.verticalCenterOffset: 2
        }
    }
    
    // Use StyledMenuItem as the default delegate for any dynamically created items
    delegate: StyledMenuItem { }
}