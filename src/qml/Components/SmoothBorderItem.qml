import QtQuick 2.15

// A component that creates smooth 3D borders with proper corner blending
Rectangle {
    id: root
    
    property color backgroundColor: Qt.rgba(1, 1, 1, 0.03)
    property color highlightColor: Qt.rgba(1, 1, 1, 0.06)
    property color shadowColor: Qt.rgba(0, 0, 0, 0.19)
    property real borderWidth: 1
    property alias contentItem: contentContainer.children
    
    // Main background
    color: root.backgroundColor
    
    // 3D border effect using overlapping borders
    // First layer: shadow (bottom-right)
    border.width: root.borderWidth
    border.color: root.shadowColor
    
    // Second layer: highlight overlay (top-left)
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: root.borderWidth
        anchors.topMargin: root.borderWidth
        color: "transparent"
        radius: parent.radius
        border.width: root.borderWidth
        border.color: root.highlightColor
    }
    
    // Inner background to cover the overlapping borders
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.borderWidth
        color: root.backgroundColor
        radius: parent.radius - root.borderWidth
    }
    
    // Content container 
    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: root.borderWidth + 1
    }
}