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

#include "backend/systeminfo.h"
#include "backend/utility/metadataextractor.h"
#include "backend/library/librarymanager.h"
#include "backend/library/albumartimageprovider.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/playback/mediaplayer.h"
#include "backend/system/mprismanager.h"

// Message handler to redirect qDebug output to file and console
void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg) {
    // Filter out Qt internal event messages
    if (type == QtDebugMsg) {
        if (msg.contains("QEvent::") || 
            msg.contains("QEventPoint") || 
            msg.contains("localPos:") ||
            msg.contains("scenePos:") ||
            msg.contains("wasHovering") ||
            msg.contains("isHovering") ||
            msg.contains("QQuickRectangle") ||
            msg.contains("geometry=") ||
            msg.contains("considering signature") ||
            msg.contains("QQuickItem::") ||
            msg.contains("HorizontalAlbumBrowser_QMLTYPE")) {
            return; // Skip Qt internal debug messages
        }
        
        // Show messages from our components and test messages
        if (!msg.contains("MetadataExtractor") && 
            !msg.contains("DatabaseManager") &&
            !msg.contains("LibraryManager") &&
            !msg.contains("MediaPlayer") &&
            !msg.contains("MPRIS") &&
            !msg.contains("Main:") &&
            !msg.contains("DEBUG TEST") && 
            !msg.contains("STDOUT TEST") && 
            !msg.contains("STDERR TEST") &&
            !msg.contains("qml:") &&  // Include QML console.log messages
            !msg.contains("Track") &&  // Include track-related messages
            !msg.contains("Album")) {  // Include album-related messages
            return; // Skip other unwanted debug messages
        }
    }
    
    // Open a file for logging in the app data directory
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataPath); // Ensure the directory exists
    QFile logFile(QDir(dataPath).filePath("debug_log.txt"));
    // Try to open the file with writing and appending permissions
    if (!logFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        fprintf(stderr, "Failed to open log file!\n");
        return;
    }
    
    QTextStream stream(&logFile);
    QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz");
    
    // Format based on message type
    QString txt;
    switch (type) {
        case QtDebugMsg:
            txt = QString("[%1] Debug: %2").arg(timestamp).arg(msg);
            break;
        case QtInfoMsg:
            txt = QString("[%1] Info: %2").arg(timestamp).arg(msg);
            break;
        case QtWarningMsg:
            txt = QString("[%1] Warning: %2").arg(timestamp).arg(msg);
            break;
        case QtCriticalMsg:
            txt = QString("[%1] Critical: %2").arg(timestamp).arg(msg);
            break;
        case QtFatalMsg:
            txt = QString("[%1] Fatal: %2").arg(timestamp).arg(msg);
            break;
    }
    
    // Write to file
    stream << txt << "\n";
    logFile.close();
    
    // Also output to console
    fprintf(stderr, "%s\n", qPrintable(txt));
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
    
    // Debug rendering backend
    qDebug() << "Main: === GRAPHICS BACKEND INFO ===";
    qDebug() << "Main: Qt Platform:" << QGuiApplication::platformName();
    const char* backend = qgetenv("QSG_RHI_BACKEND").constData();
    qDebug() << "Main: QSG_RHI_BACKEND:" << (backend[0] ? backend : "not set");
    const char* render_loop = qgetenv("QSG_RENDER_LOOP").constData();
    qDebug() << "Main: QSG_RENDER_LOOP:" << (render_loop[0] ? render_loop : "not set");
    
    // Check for OpenGL information if available
    QSurfaceFormat currentFormat = QSurfaceFormat::defaultFormat();
    qDebug() << "Main: OpenGL Version:" << currentFormat.majorVersion() << "." << currentFormat.minorVersion();
    qDebug() << "Main: OpenGL Profile:" << (currentFormat.profile() == QSurfaceFormat::CoreProfile ? "Core" : 
                                            currentFormat.profile() == QSurfaceFormat::CompatibilityProfile ? "Compatibility" : "None");
    
    // Check environment variables that affect rendering
    const char* glx_vendor = qgetenv("__GLX_VENDOR_LIBRARY_NAME").constData();
    qDebug() << "Main: __GLX_VENDOR_LIBRARY_NAME:" << (glx_vendor[0] ? glx_vendor : "not set");
    
    // Note: We already set the format before app creation, so just log if it worked
    if (currentFormat.majorVersion() >= 3) {
        qDebug() << "Main: Successfully using OpenGL" << currentFormat.majorVersion() << "." << currentFormat.minorVersion();
    } else {
        qDebug() << "Main: WARNING: Still using OpenGL" << currentFormat.majorVersion() << "." << currentFormat.minorVersion();
        qDebug() << "Main: This indicates software rendering is being used!";
    }
    
    qDebug() << "Main: ============================";
    
    // Set application metadata
    app.setOrganizationName("mtoc");
    app.setApplicationName("mtoc");
    app.setApplicationDisplayName("mtoc Music Player");
    
    // Set application icon
    app.setWindowIcon(QIcon(":/resources/icons/mtoc-icon-512.png"));
    
    // Increase pixmap cache size for album art (128MB)
    QPixmapCache::setCacheLimit(128 * 1024);

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
    
    // Create objects on heap without parenting to engine since we manage lifetime manually
    SystemInfo *systemInfo = new SystemInfo();
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SystemInfo", systemInfo);

    // Create LibraryManager first to see if it's the issue
    qDebug() << "Main: Creating LibraryManager...";
    Mtoc::LibraryManager *libraryManager = new Mtoc::LibraryManager();
    qDebug() << "Main: LibraryManager created successfully";
    
    qDebug() << "Main: Registering LibraryManager with QML...";
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "LibraryManager", libraryManager);
    qDebug() << "Main: LibraryManager registered";
    
    // MetadataExtractor might not need to be a singleton since it's used by LibraryManager
    Mtoc::MetadataExtractor *metadataExtractor = new Mtoc::MetadataExtractor();
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MetadataExtractor", metadataExtractor);
    
    // Create and register MediaPlayer
    qDebug() << "Main: Creating MediaPlayer...";
    MediaPlayer *mediaPlayer = new MediaPlayer();
    mediaPlayer->setLibraryManager(libraryManager);
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MediaPlayer", mediaPlayer);
    qDebug() << "Main: MediaPlayer registered";
    
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
        
        // Cancel any ongoing scans
        if (libraryManager->isScanning()) {
            libraryManager->cancelScan();
        }
        
        // Explicitly delete objects in the correct order before Qt's automatic cleanup
        // This ensures database is not closed while other objects might still need it
        delete mprisManager;
        mprisManager = nullptr;
        
        delete mediaPlayer;
        mediaPlayer = nullptr;
        
        // Remove the album art provider before deleting library manager
        engine.removeImageProvider("albumart");
        
        delete libraryManager;
        libraryManager = nullptr;
        
        delete metadataExtractor;
        metadataExtractor = nullptr;
        
        delete systemInfo;
        systemInfo = nullptr;
        
        // Process any pending deletions before returning
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        
        qDebug() << "Main: Cleanup completed";
    });
    
    qDebug() << "Main: Starting event loop...";
    int result = app.exec();
    
    qDebug() << "Main: Event loop ended with result:" << result;
    return result;
}
