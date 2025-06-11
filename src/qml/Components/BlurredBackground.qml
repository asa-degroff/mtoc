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
            clip: true  // Clip the overflowing content
            
            // Composition layer with black padding
            Item {
                id: compositionLayer
                // Make it larger than parent to push black border outside visible area
                anchors.centerIn: parent
                width: parent.width + 160  // Extend beyond parent bounds
                height: parent.height + 160
                visible: false
                
                // Full black background
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }
                
                // Image inset from edges to create black border
                Image {
                    id: sourceImage
                    anchors.fill: parent
                    anchors.margins: 80  // This creates the black border width
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    asynchronous: true
                    source: root.source
                    
                    onStatusChanged: {
                        if (status === Image.Error) {
                            console.warn("BlurredBackground: Failed to load image:", source);
                        }
                    }
                }
            }
            
            // Capture the composition into a texture
            ShaderEffectSource {
                id: textureSource
                anchors.centerIn: parent
                width: compositionLayer.width
                height: compositionLayer.height
                sourceItem: compositionLayer
                visible: false
                live: true
                hideSource: true
            }
            
            MultiEffect {
                anchors.centerIn: parent
                width: textureSource.width
                height: textureSource.height
                source: textureSource
                blurEnabled: true
                blur: root.blurRadius / 256.0  // MultiEffect uses 0.0 to 1.0 range
                blurMax: 32
                visible: sourceImage.status === Image.Ready
                opacity: root.backgroundOpacity
                autoPaddingEnabled: false
            }
        }
    }
}