import QtQuick
import QtQuick.Effects

Item {
    id: root
    
    property url source: ""
    property real blurRadius: 256
    property real backgroundOpacity: 0.3
    property int currentImageIndex: 0
    property url image1Source: ""
    property url image2Source: ""
    
    // Base black rectangle as fallback
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: 0
    }
    
    // Handle source changes and trigger crossfade
    onSourceChanged: {
        if (source != "") {
            // Update the non-visible layer with the new source
            if (currentImageIndex === 0) {
                // Layer 1 is visible, update layer 2
                // Clear the old source first to release memory
                if (image2Source != "") {
                    image2Source = ""
                }
                image2Source = source
            } else {
                // Layer 2 is visible, update layer 1
                // Clear the old source first to release memory
                if (image1Source != "") {
                    image1Source = ""
                }
                image1Source = source
            }
            // Toggle to the layer with the new image
            currentImageIndex = 1 - currentImageIndex
        } else {
            // Source is empty, clear both images to show black background
            image1Source = ""
            image2Source = ""
            currentImageIndex = 0
        }
    }
    
    // Initialize first image
    Component.onCompleted: {
        if (source != "") {
            image1Source = source
            currentImageIndex = 0
        }
    }
    
    // Only create the image and blur effect if we have a valid source
    Loader {
        id: imageLoader
        anchors.fill: parent
        active: root.source != "" || root.image1Source != "" || root.image2Source != ""
        z: 1
        
        sourceComponent: Item {
            anchors.fill: parent
            clip: true  // Clip the overflowing content
            
            // Image layer 1
            Item {
                id: imageLayer1
                anchors.fill: parent
                
                // Composition layer with black padding
                Item {
                    id: compositionLayer1
                    anchors.centerIn: parent
                    width: parent.width + 80
                    height: parent.height + 80
                    visible: false
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                    }
                    
                    Image {
                        id: sourceImage1
                        anchors.fill: parent
                        anchors.margins: 40
                        fillMode: Image.PreserveAspectCrop
                        cache: false  // Don't cache blurred backgrounds
                        asynchronous: true
                        source: root.image1Source
                        sourceSize.width: 512
                        sourceSize.height: 512
                        
                        onStatusChanged: {
                            if (status === Image.Error) {
                                console.warn("BlurredBackground: Failed to load image:", source);
                            }
                        }
                    }
                }
                
                ShaderEffectSource {
                    id: textureSource1
                    anchors.centerIn: parent
                    width: compositionLayer1.width
                    height: compositionLayer1.height
                    sourceItem: compositionLayer1
                    visible: false
                    live: true
                    hideSource: true
                }
                
                MultiEffect {
                    id: effect1
                    anchors.centerIn: parent
                    width: textureSource1.width
                    height: textureSource1.height
                    source: textureSource1
                    blurEnabled: true
                    blur: Math.min(1.0, root.blurRadius / 256.0)
                    blurMax: 64
                    visible: sourceImage1.status === Image.Ready || sourceImage1.status === Image.Loading
                    opacity: root.currentImageIndex === 0 ? root.backgroundOpacity : 0
                    autoPaddingEnabled: false
                    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
            
            // Image layer 2
            Item {
                id: imageLayer2
                anchors.fill: parent
                
                // Composition layer with black padding
                Item {
                    id: compositionLayer2
                    anchors.centerIn: parent
                    width: parent.width + 80
                    height: parent.height + 80
                    visible: false
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                    }
                    
                    Image {
                        id: sourceImage2
                        anchors.fill: parent
                        anchors.margins: 40
                        fillMode: Image.PreserveAspectCrop
                        cache: false  // Don't cache blurred backgrounds
                        asynchronous: true
                        source: root.image2Source
                        sourceSize.width: 512
                        sourceSize.height: 512
                        
                        onStatusChanged: {
                            if (status === Image.Error) {
                                console.warn("BlurredBackground: Failed to load image:", source);
                            }
                        }
                    }
                }
                
                ShaderEffectSource {
                    id: textureSource2
                    anchors.centerIn: parent
                    width: compositionLayer2.width
                    height: compositionLayer2.height
                    sourceItem: compositionLayer2
                    visible: false
                    live: true
                    hideSource: true
                }
                
                MultiEffect {
                    id: effect2
                    anchors.centerIn: parent
                    width: textureSource2.width
                    height: textureSource2.height
                    source: textureSource2
                    blurEnabled: true
                    blur: Math.min(1.0, root.blurRadius / 256.0)
                    blurMax: 64
                    visible: sourceImage2.status === Image.Ready || sourceImage2.status === Image.Loading
                    opacity: root.currentImageIndex === 1 ? root.backgroundOpacity : 0
                    autoPaddingEnabled: false
                    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }
    }
}