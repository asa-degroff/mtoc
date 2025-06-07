import QtQuick 2.15
import QtQuick.Effects

// A reusable component that creates a smooth 3D border effect with gradients
Item {
    id: root
    
    property color backgroundColor: Qt.rgba(1, 1, 1, 0.03)
    property color highlightColor: Qt.rgba(1, 1, 1, 0.15) // Light edge color
    property color shadowColor: Qt.rgba(0, 0, 0, 0.25) // Dark edge color
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
    
    // Gradient overlay for smooth 3D effect
    Item {
        anchors.fill: parent
        
        // Create a custom gradient effect using multiple overlapping rectangles
        // Top-left highlight
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.width
            height: parent.height
            radius: root.radius
            color: "transparent"
            
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.highlightColor }
                GradientStop { position: 0.15; color: "transparent" }
            }
        }
        
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.width
            height: parent.height
            radius: root.radius
            color: "transparent"
            
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: root.highlightColor }
                GradientStop { position: 0.15; color: "transparent" }
            }
        }
        
        // Bottom-right shadow
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.width
            height: parent.height
            radius: root.radius
            color: "transparent"
            
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.85; color: "transparent" }
                GradientStop { position: 1.0; color: root.shadowColor }
            }
        }
        
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.width
            height: parent.height
            radius: root.radius
            color: "transparent"
            
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.85; color: "transparent" }
                GradientStop { position: 1.0; color: root.shadowColor }
            }
        }
        
        // Corner blending using radial gradients
        // Top-left corner blend
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: root.radius * 3
            height: root.radius * 3
            color: "transparent"
            
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: Rectangle {
                    width: root.radius * 3
                    height: root.radius * 3
                    radius: root.radius
                }
                
                source: Rectangle {
                    width: root.radius * 3
                    height: root.radius * 3
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.highlightColor }
                        GradientStop { position: 0.7; color: "transparent" }
                    }
                }
            }
        }
        
        // Bottom-right corner blend
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: root.radius * 3
            height: root.radius * 3
            color: "transparent"
            
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: Rectangle {
                    width: root.radius * 3
                    height: root.radius * 3
                    radius: root.radius
                }
                
                source: Rectangle {
                    width: root.radius * 3
                    height: root.radius * 3
                    gradient: Gradient {
                        GradientStop { position: 0.3; color: "transparent" }
                        GradientStop { position: 1.0; color: root.shadowColor }
                    }
                }
            }
        }
    }
    
    // Subtle inner border for definition
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.03)
    }
    
    // Content container
    Item {
        id: contentContainer
        anchors.fill: parent
    }
}