#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <iostream>
#include <QLoggingCategory>
#include <QIcon>
#include <QSurfaceFormat>
#include <QLocale>
#include <QDir>
#include <QStandardPaths>
#include <QWindow>

#include "backend/systeminfo.h"
#include "backend/utility/metadataextractor.h"
#include "backend/library/librarymanager.h"
#include "backend/library/albumartimageprovider.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/playback/mediaplayer.h"
#include "backend/system/mprismanager.h"
#include "backend/settings/settingsmanager.h"
#include "backend/playlist/playlistmanager.h"

// Message handler to show only QML console.log messages
void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg) {
    // Temporarily show all messages to debug console.log
    // Check if it's a QML message
    bool isQmlMessage = msg.startsWith("qml:") || (context.file && QString(context.file).endsWith(".qml"));
    
    // Format the output simply for console
    switch (type) {
        case QtDebugMsg:
            if (isQmlMessage) {
                fprintf(stderr, "[QML Debug] %s\n", qPrintable(msg));
            } else if (msg.contains("jumpToArtist") || msg.contains("scrollToArtistIndex") || 
                      msg.contains("calculateArtistPosition") || msg.contains("updateArtistIndexMapping") ||
                      msg.contains("MediaPlayer::") || msg.contains("PlaylistManager::") ||
                      msg.contains("[ReplayGain]") || msg.contains("AudioEngine") || msg.contains("rgvolume") ||
                      msg.contains("[AudioEngine] Transition check") || msg.contains("[VirtualPlaylist::]") ||
                      msg.contains("[MediaPlayer::onAboutToFinish]")
                    ) {
                // Also show our specific debug messages even if not properly prefixed
                fprintf(stderr, "[Debug] %s\n", qPrintable(msg));
            }
            break;
        case QtInfoMsg:
            fprintf(stderr, "Info: %s\n", qPrintable(msg));
            break;
        case QtWarningMsg:
            // Always show warnings, they're important
            fprintf(stderr, "[Warning] %s\n", qPrintable(msg));
            break;
        case QtCriticalMsg:
            fprintf(stderr, "Critical: %s\n", qPrintable(msg));
            break;
        case QtFatalMsg:
            fprintf(stderr, "Fatal: %s\n", qPrintable(msg));
            abort();
    }
}

int main(int argc, char *argv[])
{
    // First, ensure debug output is not disabled for our code but disable verbose Qt internals
    QLoggingCategory::setFilterRules("*.debug=true\n"
                                    "qt.qml.typeresolution.debug=false\n"
                                    "qt.qml.import.debug=false\n"
                                    "qt.qml.binding.debug=false\n"
                                    "qt.qml.compiler.debug=false\n"
                                    "qt.quick.hover.debug=false\n"
                                    "qt.quick.mouse.debug=false\n"
                                    "qt.quick.pointer.debug=false\n"
                                    "qt.quick.events.debug=false");
    
    // Install the custom message handler
    qInstallMessageHandler(messageHandler);
    
    qDebug() << "Application starting...";
    
    // Set OpenGL attributes before creating QApplication
    // QCoreApplication::setAttribute(Qt::AA_UseDesktopOpenGL);
    
    // // Request a specific OpenGL context before app creation
    // QSurfaceFormat format;
    // format.setVersion(3, 3);
    // format.setProfile(QSurfaceFormat::CoreProfile);
    // format.setDepthBufferSize(24);
    // format.setStencilBufferSize(8);
    // format.setSamples(0); // Disable multisampling
    // format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    // QSurfaceFormat::setDefaultFormat(format);
    
    QApplication app(argc, argv);
    
    // Set up locale for proper string comparison
    // Check if user has set a specific locale via environment variable
    const char* locale_override = qgetenv("MTOC_LOCALE").constData();
    if (locale_override[0]) {
        QLocale::setDefault(QLocale(QString::fromUtf8(locale_override)));
        qDebug() << "Main: Using user-specified locale:" << locale_override;
    } else {
        // Use system locale
        QLocale::setDefault(QLocale::system());
        qDebug() << "Main: Using system locale:" << QLocale().name();
    }
    
    // Set application metadata
    app.setOrganizationName("mtoc");
    app.setApplicationName("mtoc");
    
    // Set application icon
    // Check if running in Flatpak
    QString flatpakId = qgetenv("FLATPAK_ID");
    if (!flatpakId.isEmpty()) {
        // Running in Flatpak - use the desktop ID for the icon
        app.setWindowIcon(QIcon::fromTheme(flatpakId));
        // Also set desktop file name for better integration
        app.setDesktopFileName(flatpakId);
    } else {
        // Not in Flatpak - use resource icon
        app.setWindowIcon(QIcon(":/resources/icons/mtoc-icon-512.png"));
    }
    
    // Configure pixmap cache for album art with dynamic sizing
    // Get available system memory (this is a rough estimate)
    qint64 totalMemory = 0;
    
#ifdef Q_OS_LINUX
    QFile meminfo("/proc/meminfo");
    if (meminfo.open(QIODevice::ReadOnly)) {
        QString line = meminfo.readLine();
        while (!line.isEmpty()) {
            if (line.startsWith("MemTotal:")) {
                QStringList parts = line.split(' ', Qt::SkipEmptyParts);
                if (parts.size() >= 2) {
                    totalMemory = parts[1].toLongLong() * 1024; // Convert from KB to bytes
                    break;
                }
            }
            line = meminfo.readLine();
        }
        meminfo.close();
    }
#endif
    
    // Calculate cache size based on available memory
    // Use 5-10% of total memory for image cache, with min/max limits
    int minCacheSize = 128 * 1024; // 128MB minimum
    int maxCacheSize = 1024 * 1024; // 1GB maximum
    int dynamicCacheSize = 256 * 1024; // Default 256MB
    
    if (totalMemory > 0) {
        // Use 7.5% of total memory for cache
        qint64 suggestedSize = totalMemory / 1024 * 75 / 1000; // 7.5% in KB
        dynamicCacheSize = qBound(minCacheSize, static_cast<int>(suggestedSize), maxCacheSize);
    }
    
    // Create SettingsManager early to get thumbnail scale
    SettingsManager *settingsManager = SettingsManager::instance();
    
    // Scale cache size based on thumbnail scale setting
    // 100% = 1.0x multiplier, 150% = 1.5x multiplier, 200% = 2.0x multiplier
    float cacheMultiplier = settingsManager->thumbnailScale() / 100.0f;
    int scaledCacheSize = static_cast<int>(dynamicCacheSize * cacheMultiplier);
    
    // Apply the same max limit after scaling
    scaledCacheSize = qMin(scaledCacheSize, maxCacheSize);
    
    QPixmapCache::setCacheLimit(scaledCacheSize);
    
    // Log cache configuration
    qDebug() << "System memory:" << totalMemory / 1024 / 1024 << "MB";
    qDebug() << "Thumbnail scale:" << settingsManager->thumbnailScale() << "%";
    qDebug() << "Cache multiplier:" << cacheMultiplier << "x";
    qDebug() << "QPixmapCache configured with dynamic limit:" << scaledCacheSize / 1024 << "MB";
    
    // Connect to thumbnail scale changes to dynamically adjust cache size
    QObject::connect(settingsManager, &SettingsManager::thumbnailScaleChanged,
                     [dynamicCacheSize, maxCacheSize](int newScale) {
        float newMultiplier = newScale / 100.0f;
        int newCacheSize = static_cast<int>(dynamicCacheSize * newMultiplier);
        newCacheSize = qMin(newCacheSize, maxCacheSize);
        QPixmapCache::setCacheLimit(newCacheSize);
        qDebug() << "QPixmapCache resized for thumbnail scale" << newScale << "%:" 
                 << newCacheSize / 1024 << "MB";
    });

    QQmlApplicationEngine engine;

    // Register SystemInfo as a QML Singleton
    // This makes SystemInfo accessible directly in QML after importing the module
    // The third argument is a function pointer that returns a QObject* (or derived).
    // Qt will manage the lifetime of the singleton instance if it's parented to the engine
    // or if it's a QObject created on the heap and returned by the lambda without explicit parent.
    // For simplicity and to ensure it's available, we'll create it as a stack variable
    // in main and pass its pointer, but for more complex apps, heap allocation or
    // engine ownership might be considered.
    // However, qmlRegisterSingletonInstance is the modern way for uncreatable types.

    // Register types for QML
    qmlRegisterType<Mtoc::Track>("Mtoc.Backend", 1, 0, "Track");
    qmlRegisterType<Mtoc::Album>("Mtoc.Backend", 1, 0, "Album");
    
    // Create objects and parent them to the QML engine for automatic cleanup
    SystemInfo *systemInfo = new SystemInfo(&engine);
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SystemInfo", systemInfo);

    // Create LibraryManager first to see if it's the issue
    qDebug() << "Main: Creating LibraryManager...";
    Mtoc::LibraryManager *libraryManager = new Mtoc::LibraryManager(&engine);
    qDebug() << "Main: LibraryManager created successfully";
    
    qDebug() << "Main: Registering LibraryManager with QML...";
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "LibraryManager", libraryManager);
    qDebug() << "Main: LibraryManager registered";
    
    // MetadataExtractor might not need to be a singleton since it's used by LibraryManager
    Mtoc::MetadataExtractor *metadataExtractor = new Mtoc::MetadataExtractor(&engine);
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MetadataExtractor", metadataExtractor);
    
    // Register SettingsManager singleton (already created earlier for cache configuration)
    qDebug() << "Main: Registering SettingsManager...";
    settingsManager->setParent(&engine);  // Parent to engine for cleanup
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SettingsManager", settingsManager);
    qDebug() << "Main: SettingsManager registered";
    
    // Create and register MediaPlayer
    qDebug() << "Main: Creating MediaPlayer...";
    MediaPlayer *mediaPlayer = new MediaPlayer(&engine);
    mediaPlayer->setLibraryManager(libraryManager);
    mediaPlayer->setSettingsManager(settingsManager);
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MediaPlayer", mediaPlayer);
    qDebug() << "Main: MediaPlayer registered";
    
    // Register PlaylistManager singleton
    qDebug() << "Main: Creating PlaylistManager...";
    PlaylistManager *playlistManager = PlaylistManager::instance();
    playlistManager->setParent(&engine);  // Parent to engine for cleanup
    playlistManager->setLibraryManager(libraryManager);
    playlistManager->setMediaPlayer(mediaPlayer);
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "PlaylistManager", playlistManager);
    qDebug() << "Main: PlaylistManager registered";
    
    // Create and initialize MPRIS manager for system media control integration
    qDebug() << "Main: Creating MPRIS manager...";
    MprisManager *mprisManager = new MprisManager(mediaPlayer);
    mprisManager->setLibraryManager(libraryManager);
    if (mprisManager->initialize()) {
        qDebug() << "Main: MPRIS manager initialized successfully";
    } else {
        qWarning() << "Main: Failed to initialize MPRIS manager";
    }
    
    // Register album art image provider
    qDebug() << "Main: Registering album art image provider...";
    engine.addImageProvider("albumart", new Mtoc::AlbumArtImageProvider(libraryManager));
    qDebug() << "Main: Album art image provider registered";

    // Register QML singletons
    qmlRegisterSingletonType(QUrl("qrc:/src/qml/Theme.qml"), "Mtoc.Backend", 1, 0, "Theme");

    qDebug() << "Main: About to load QML...";
    
    const QUrl url(QStringLiteral("qrc:/src/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject *obj, const QUrl &objUrl) {
            qDebug() << "Main: QML object created:" << (obj ? "success" : "failed");
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        }, Qt::QueuedConnection);
        
    qDebug() << "Main: Loading QML from:" << url;
    engine.load(url);
    
    // Connect to application aboutToQuit signal for cleanup
    QObject::connect(&app, &QApplication::aboutToQuit, [&]() {
        qDebug() << "Main: Application about to quit, performing cleanup...";
        
        // First, close all top-level windows to trigger QML cleanup
        const auto topLevelWindows = QGuiApplication::topLevelWindows();
        for (QWindow *window : topLevelWindows) {
            window->close();
        }
        
        // Process events to allow QML components to clean up naturally
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        
        // Save playback state before cleanup
        if (mediaPlayer) {
            mediaPlayer->saveState();
        }
        
        // Cancel any ongoing scans or background operations
        if (libraryManager) {
            if (libraryManager->isScanning()) {
                libraryManager->cancelScan();
            }
            // This will wait for album art processing to complete
        }
        
        // Note: Carousel position is automatically saved when it changes
        // The QML timer handles this, no need for explicit save here
        
        // Now it's safe to remove the image provider after QML cleanup
        engine.removeImageProvider("albumart");
        
        // Only delete objects that are NOT registered with QML
        // QML-registered singletons will be cleaned up by the QML engine
        delete mprisManager;
        mprisManager = nullptr;
        
        // Do NOT delete QML-registered singletons here - let QML engine handle them:
        // - mediaPlayer
        // - playlistManager  
        // - libraryManager
        // - metadataExtractor
        // - settingsManager
        // - systemInfo
        
        // Process any pending deletions before returning
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        
        qDebug() << "Main: Cleanup completed";
    });
    
    qDebug() << "Main: Starting event loop...";
    int result = app.exec();
    
    qDebug() << "Main: Event loop ended with result:" << result;
    
    // Additional cleanup after event loop ends
    // This ensures Qt's automatic cleanup has completed
    qDebug() << "Main: Performing final cleanup...";
    
    // Ensure all timers are stopped
    if (mediaPlayer) {
        mediaPlayer->saveState();
    }
    
    // Give Qt time to process any final events
    QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
    
    qDebug() << "Main: Application exit complete";
    return result;
}
