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

// Message handler to redirect qDebug output to file and console
void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg) {
    // Filter out unwanted debug messages
    // Show messages from our components and test messages
    if (type == QtDebugMsg && 
        !msg.contains("MetadataExtractor") && 
        !msg.contains("DatabaseManager") &&
        !msg.contains("LibraryManager") &&
        !msg.contains("Main:") &&
        !msg.contains("DEBUG TEST") && 
        !msg.contains("STDOUT TEST") && 
        !msg.contains("STDERR TEST")) {
        return; // Skip unwanted debug messages
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
    
    // Print directly to standard output for testing
    std::cout << "STDOUT TEST: This should appear on stdout" << std::endl;
    std::cerr << "STDERR TEST: This should appear on stderr" << std::endl;
    
    // Install the custom message handler
    qInstallMessageHandler(messageHandler);
    
    // Force a debug message to test if the handler is working
    qDebug() << "DEBUG TEST: Application starting...";
    fprintf(stderr, "Direct stderr test message\n");
    
    QApplication app(argc, argv);

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
    
    // Register album art image provider
    qDebug() << "Main: Registering album art image provider...";
    engine.addImageProvider("albumart", new Mtoc::AlbumArtImageProvider(libraryManager->databaseManager()));
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
