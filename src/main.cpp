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

// Message handler to redirect qDebug output to file and console
void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg) {
    // Filter out unwanted debug messages
    // Only show messages from MetadataExtractor and specific test messages
    if (type == QtDebugMsg && 
        !msg.contains("MetadataExtractor") && 
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

    SystemInfo systemInfo;
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SystemInfo", &systemInfo);

    Mtoc::MetadataExtractor metadataExtractor;
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MetadataExtractor", &metadataExtractor);

    Mtoc::LibraryManager libraryManager;
    qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "LibraryManager", &libraryManager);

    const QUrl url(QStringLiteral("qrc:/src/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        }, Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
