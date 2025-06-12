import QtQuick 2.15

Item {
    id: root
    
    property real borderWidth: 1.0
    property real borderRadius: 6.0
    property color backgroundColor: Qt.rgba(1, 1, 1, 0.03)
    property color lightColor: Qt.rgba(1, 1, 1, 0.06)
    property color shadowColor: Qt.rgba(0, 0, 0, 0.2)
    property real lightIntensity: 1.0
    property real shadowIntensity: 1.0
    property real lightAngle: -45 * Math.PI / 180  // -45 degrees (top-left light source)
    
    ShaderEffect {
        anchors.fill: parent
        
        property real borderWidth: root.borderWidth
        property real borderRadius: root.borderRadius
        property color backgroundColor: root.backgroundColor
        property color lightColor: root.lightColor
        property color shadowColor: root.shadowColor
        property real lightIntensity: root.lightIntensity
        property real shadowIntensity: root.shadowIntensity
        property real lightAngle: root.lightAngle
        property size itemSize: Qt.size(width, height)
        
        vertexShader: "qrc:/src/qml/shaders/border3d.vert.qsb"
        fragmentShader: "qrc:/src/qml/shaders/border3d.frag.qsb"
    }
}