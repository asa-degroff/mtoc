import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

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
        
        onActiveChanged: {
            console.log("BlurredBackground: Loader active changed to:", active, "source:", root.source);
        }
        
        sourceComponent: Item {
            anchors.fill: parent
            
            Image {
                id: sourceImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                visible: false
                cache: true
                asynchronous: true
                source: root.source
                
                onStatusChanged: {
                    console.log("BlurredBackground: Image status changed to:", status, "for source:", source);
                    if (status === Image.Error) {
                        console.warn("BlurredBackground: Failed to load image:", source);
                    }
                }
            }
            
            FastBlur {
                anchors.fill: parent
                source: sourceImage
                radius: root.blurRadius
                cached: true
                visible: sourceImage.status === Image.Ready
                opacity: root.backgroundOpacity
            }
        }
    }
}