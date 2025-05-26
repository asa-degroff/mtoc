import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    property alias source: sourceImage.source
    property real blurRadius: 64
    property real backgroundOpacity: 0.3
    
    Image {
        id: sourceImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: false
        cache: false
        asynchronous: true
    }
    
    FastBlur {
        id: blur
        anchors.fill: parent
        source: sourceImage
        radius: root.blurRadius
        cached: true
        visible: false
    }
    
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 1.0 - root.backgroundOpacity
    }
    
    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: blur
        hideSource: true
        visible: sourceImage.status === Image.Ready
    }
}