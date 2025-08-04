import QtQuick 2.15
import QtQuick.Controls 2.15
import Mtoc.Backend 1.0

MenuItem {
    id: menuItem
    
    // Custom content item for consistent styling
    contentItem: Text {
        text: menuItem.text
        color: Theme.isDark ? (menuItem.hovered ? "white" : "#e0e0e0") : (menuItem.hovered ? Theme.primaryText : Theme.secondaryText)
        font.pixelSize: 13
        verticalAlignment: Text.AlignVCenter
        leftPadding: 12
        rightPadding: 12
    }
    
    // Custom background for hover effect with rounded corners
    background: Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        implicitHeight: 32
        radius: 4
        color: menuItem.hovered ? Theme.hoverBackground : "transparent"
    }
}