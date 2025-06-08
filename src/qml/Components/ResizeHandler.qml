import QtQuick 2.15

Item {
    id: root
    
    // Properties
    property int actualWidth: parent.width
    property int actualHeight: parent.height
    property int deferredWidth: actualWidth
    property int deferredHeight: actualHeight
    property int resizeDelay: 300  // ms to wait after resize stops
    property bool isResizing: false
    property bool enablePlaceholder: true
    
    // Signals
    signal resizeStarted()
    signal resizeCompleted(int newWidth, int newHeight)
    
    // Monitor parent size changes
    Connections {
        target: parent
        function onWidthChanged() {
            handleResize()
        }
        function onHeightChanged() {
            handleResize()
        }
    }
    
    // Timer to detect when resizing has stopped
    Timer {
        id: resizeTimer
        interval: resizeDelay
        repeat: false
        onTriggered: {
            // Update deferred dimensions
            deferredWidth = actualWidth
            deferredHeight = actualHeight
            isResizing = false
            resizeCompleted(deferredWidth, deferredHeight)
        }
    }
    
    function handleResize() {
        actualWidth = parent.width
        actualHeight = parent.height
        
        if (!isResizing) {
            isResizing = true
            resizeStarted()
        }
        
        // Reset the timer on each resize event
        resizeTimer.restart()
    }
    
    // Initialize on completion
    Component.onCompleted: {
        deferredWidth = actualWidth
        deferredHeight = actualHeight
    }
}