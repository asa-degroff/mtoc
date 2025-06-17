import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Mtoc.Backend 1.0
import "Views/"
import "Components/"

ApplicationWindow {
    id: window
    width: 1920
    height: 1200
    minimumWidth: 800  // Set a reasonable minimum to fit all panes
    minimumHeight: 500
    visible: true
    title: SystemInfo.appName + " - " + SystemInfo.appVersion

    // Property to hold the current track metadata
    property var currentTrack: ({})
    
    // Resize handler for deferred resizing
    ResizeHandler {
        id: resizeHandler
        resizeDelay: 250  // Wait 250ms after resize stops
        
        onResizeStarted: {
            // During resize, we just clip/letterbox the content
            // No need to hide anything
        }
        
        onResizeCompleted: {
            // Apply new dimensions to content
            mainContent.width = newWidth
            mainContent.height = newHeight
            
            // Force garbage collection after resize
            gc()
        }
    }
    
    // Black background for letterboxing effect
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
    }
    
    // Viewport container that clips or letterboxes content
    Item {
        id: viewportContainer
        anchors.fill: parent
        clip: true  // Clip content when window is smaller
        
        // Main content container - stays at deferred size
        Item {
            id: mainContent
            width: resizeHandler.deferredWidth
            height: resizeHandler.deferredHeight
            
            // Center content when window is larger (letterbox)
            x: parent.width > width ? (parent.width - width) / 2 : 0
            y: parent.height > height ? (parent.height - height) / 2 : 0
        
        // Basic two-pane layout
        RowLayout {
            anchors.fill: parent
            spacing: 0  // Remove default spacing

            // Library Pane
            LibraryPane {
                id: libraryPane
                Layout.fillWidth: true
                Layout.preferredWidth: mainContent.width * 0.45 // 45% of content width
                Layout.fillHeight: true
            }


            // Now Playing Pane
            NowPlayingPane {
                id: nowPlayingPane
                Layout.fillWidth: true
                Layout.preferredWidth: mainContent.width * 0.55 // 55% of content width
                Layout.fillHeight: true
                
                // Pass reference to library pane for navigation
                libraryPane: libraryPane
                
                Component.onCompleted: {
                    console.log("NowPlayingPane added to Main.qml");
                }
            }
        }
        }  // mainContent
    }  // viewportContainer

    // Function to format duration in seconds to MM:SS format
    function formatDuration(seconds) {
        var minutes = Math.floor(seconds / 60);
        var remainingSeconds = seconds % 60;
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }
    
    // Timer to check rendering info after window is ready
    Timer {
        id: renderInfoTimer
        interval: 100
        running: true
        repeat: false
        // onTriggered: {
        //     console.log("=== RENDERING DEBUG INFO ===");
        //     var renderInfo = window.rendererInterface;
        //     if (renderInfo) {
        //         console.log("Graphics API Type:", renderInfo.graphicsApi);
        //         console.log("Major Version:", renderInfo.majorVersion);
        //         console.log("Minor Version:", renderInfo.minorVersion);
                
        //         // Map GraphicsApi enum values
        //         var apiName = "";
        //         switch(renderInfo.graphicsApi) {
        //             case 0: apiName = "Unknown"; break;
        //             case 1: apiName = "Software"; break;
        //             case 2: apiName = "OpenGL"; break;
        //             case 3: apiName = "Direct3D12"; break;
        //             case 4: apiName = "OpenVG"; break;
        //             case 5: apiName = "OpenGL ES"; break;
        //             case 6: apiName = "Vulkan"; break;
        //             case 7: apiName = "Metal"; break;
        //             case 8: apiName = "Null"; break;
        //             default: apiName = "Other"; break;
        //         }
        //         console.log("Graphics API Name:", apiName);
                
        //         if (renderInfo.graphicsApi === 1) {
        //             console.warn("WARNING: Using software rendering! This will cause high CPU usage.");
        //             console.warn("Try running with: QSG_RHI_BACKEND=opengl ./build/mtoc_app");
        //             console.warn("Or use the provided run_mtoc.sh script");
        //         } else if (renderInfo.graphicsApi === 2) {
        //             console.log("SUCCESS: Using hardware-accelerated OpenGL rendering");
        //         }
        //     } else {
        //         console.log("rendererInterface not available");
        //     }
        //     console.log("===========================");
        // }
    }
    
    // Initialize the application
    Component.onCompleted: {
        console.log("Main.qml loaded - Initializing application");
        
        try {
            // Initialize LibraryManager
            console.log("Initializing LibraryManager...");
            
            // Music folders are now automatically loaded from settings in LibraryManager constructor
            console.log("Music folders configured:", JSON.stringify(LibraryManager.musicFolders));
            
            // Skip MetadataExtractor test for now
            // This was causing issues during startup
            
            // Don't automatically scan on startup - let user initiate
            console.log("Library contains", LibraryManager.trackCount, "tracks");
        } catch (e) {
            console.error("Error during initialization:", e);
        }
    }
}
