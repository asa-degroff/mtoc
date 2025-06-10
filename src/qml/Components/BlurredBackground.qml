import QtQuick
import QtQuick.Effects

Item {
    id: root
    
    property url source: ""
    property real blurRadius: 256
    property real backgroundOpacity: 0.3
    
    // Base black rectangle as fallback
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: 0
    }
    
    // Only create the image and blur effect if we have a valid source
    Loader {
        id: imageLoader
        anchors.fill: parent
        active: root.source != ""
        z: 1
        
        // Active state changes when source URL is set
        
        sourceComponent: Item {
            anchors.fill: parent
            
            Image {
                id: sourceImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                asynchronous: true
                source: root.source
                visible: false
                
                onStatusChanged: {
                    if (status === Image.Error) {
                        console.warn("BlurredBackground: Failed to load image:", source);
                    }
                }
            }
            
            MultiEffect {
                anchors.fill: parent
                source: sourceImage
                blurEnabled: true
                blur: root.blurRadius / 256.0  // MultiEffect uses 0.0 to 1.0 range
                blurMax: 32
                visible: sourceImage.status === Image.Ready
                opacity: root.backgroundOpacity
            }
        }
    }
}