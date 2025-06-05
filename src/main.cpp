#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <iostream>
#include <QLoggingCategory>

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
    
    // Open a file for logging with absolute path
    QFile logFile("/home/asa/code/mtoc/debug_log.txt");
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
    // First, ensure debug output is not disabled
    QLoggingCategory::setFilterRules("*.debug=true");
    
    // Install the custom message handler
    qInstallMessageHandler(messageHandler);
    
    qDebug() << "Application starting...";
    
    QApplication app(argc, argv);
    
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
    
    // Create objects on heap and parent them to the engine for proper lifetime management
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
    
    // Create and register MediaPlayer
    qDebug() << "Main: Creating MediaPlayer...";
    MediaPlayer *mediaPlayer = new MediaPlayer(&engine);
    mediaPlayer->setLibraryManager(libraryManager);
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MediaPlayer", mediaPlayer);
    qDebug() << "Main: MediaPlayer registered";
    
    // Create and initialize MPRIS manager for system media control integration
    qDebug() << "Main: Creating MPRIS manager...";
    MprisManager *mprisManager = new MprisManager(mediaPlayer, &engine);
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
        
        qDebug() << "Main: Cleanup completed";
    });
    
    qDebug() << "Main: Starting event loop...";
    int result = app.exec();
    
    qDebug() << "Main: Event loop ended with result:" << result;
    return result;
}
