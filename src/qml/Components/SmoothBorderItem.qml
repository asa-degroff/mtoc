import QtQuick 2.15

// A component that creates smooth 3D borders using multiple gradient overlays
Item {
    id: root
    
    property color backgroundColor: Qt.rgba(1, 1, 1, 0.03)
    property color highlightColor: Qt.rgba(1, 1, 1, 0.15)
    property color shadowColor: Qt.rgba(0, 0, 0, 0.25)
    property real radius: 6
    property real borderWidth: 1.5
    property alias contentItem: contentContainer.children
    
    // Main background
    Rectangle {
        id: background
        anchors.fill: parent
        color: root.backgroundColor
        radius: root.radius
    }
    
    // Multiple gradient overlays for smooth 3D effect
    // Top edge highlight
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.highlightColor }
            GradientStop { position: 0.1; color: Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, root.highlightColor.a * 0.3) }
            GradientStop { position: 0.9; color: "transparent" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    
    // Left edge highlight
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.highlightColor }
            GradientStop { position: 0.1; color: Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, root.highlightColor.a * 0.3) }
            GradientStop { position: 0.9; color: "transparent" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    
    // Bottom edge shadow
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.1; color: "transparent" }
            GradientStop { position: 0.9; color: Qt.rgba(root.shadowColor.r, root.shadowColor.g, root.shadowColor.b, root.shadowColor.a * 0.3) }
            GradientStop { position: 1.0; color: root.shadowColor }
        }
    }
    
    // Right edge shadow
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.1; color: "transparent" }
            GradientStop { position: 0.9; color: Qt.rgba(root.shadowColor.r, root.shadowColor.g, root.shadowColor.b, root.shadowColor.a * 0.3) }
            GradientStop { position: 1.0; color: root.shadowColor }
        }
    }
    
    // Content container 
    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: 2  // Small margin for content
    }
}