#include "librarymanager.h"
#include <QDebug>
#include <QDirIterator>
#include <QStandardPaths>
#include <QTimer>
#include <QFileInfo>
#include <QThread>
#include <QMutexLocker>
#include <QSqlError>
#include <QSqlQuery>
#include <QSettings>
#include <QSet>
#include <QPixmapCache>
#include <QThreadPool>
#include <exception>

namespace Mtoc {

LibraryManager::LibraryManager(QObject *parent)
    : QObject(parent)
    , m_databaseManager(new DatabaseManager(this))
    , m_albumArtManager(new AlbumArtManager(this))
    , m_allTracksModel(new TrackModel(this))
    , m_allAlbumsModel(new AlbumModel(this))
    , m_scanning(false)
    , m_scanProgress(0)
    , m_totalFilesToScan(0)
    , m_filesScanned(0)
    , m_cancelRequested(false)
    , m_albumModelCacheValid(false)
    , m_cachedAlbumCount(-1)
    , m_albumCountCacheValid(false)
    , m_artistModelCacheValid(false)
{
    qDebug() << "LibraryManager: Constructor started";
    
    // Initialize database
    initializeDatabase();
    
    qDebug() << "LibraryManager: Database initialized";
    
    // Load saved music folders from settings
    QSettings settings;
    m_musicFolders = settings.value("musicFolders", QStringList()).toStringList();
    
    // Load display paths mapping
    settings.beginGroup("musicFolderDisplayPaths");
    QStringList keys = settings.allKeys();
    for (const QString &key : keys) {
        m_folderDisplayPaths[key] = settings.value(key).toString();
    }
    settings.endGroup();
    
    // Default to the user's Music folder if no folders saved
    if (m_musicFolders.isEmpty()) {
        QStringList musicDirs = QStandardPaths::standardLocations(QStandardPaths::MusicLocation);
        if (!musicDirs.isEmpty()) {
            m_musicFolders << musicDirs.first();
            // Save the default folder
            settings.setValue("musicFolders", m_musicFolders);
        }
    }
    
    // Connect database signals
    connect(m_databaseManager, &DatabaseManager::databaseError,
            this, [this](const QString& error) {
        qCritical() << "Database error:" << error;
    });
    
    connect(m_databaseManager, &DatabaseManager::trackAdded,
            this, [this](int trackId) {
        // Refresh models when tracks are added
        QTimer::singleShot(0, this, &LibraryManager::libraryChanged);
    });
    
    connect(m_databaseManager, &DatabaseManager::trackDeleted,
            this, [this](int trackId) {
        // Refresh models when tracks are deleted
        m_albumModelCacheValid = false;
        m_albumCountCacheValid = false;
        m_artistModelCacheValid = false;
        m_albumsByArtistCache.clear();
        QTimer::singleShot(0, this, &LibraryManager::libraryChanged);
    });
    
    // Don't load library data immediately - wait for first access
    // This should speed up startup
    m_albumModelCacheValid = false;
    
    // Connect scan watcher
    connect(&m_scanWatcher, &QFutureWatcher<void>::finished,
            this, &LibraryManager::onScanFinished);
            
    qDebug() << "LibraryManager: Constructor completed";
}

LibraryManager::~LibraryManager()
{
    qDebug() << "LibraryManager: Destructor called";
    
    // Cancel any ongoing scan
    cancelScan();
    
    // Wait for any pending operations
    if (m_scanFuture.isRunning()) {
        qDebug() << "LibraryManager: Waiting for scan to finish...";
        m_scanFuture.waitForFinished();
    }
    
    // Ensure all models are cleared before database cleanup
    m_allTracksModel->clear();
    m_allAlbumsModel->clear();
    
    // Clear the album model cache
    m_albumModelCacheValid = false;
    m_cachedAlbumModel.clear();
    m_artistModelCacheValid = false;
    m_cachedArtistModel.clear();
    
    // Database is automatically closed by DatabaseManager destructor
    
    qDebug() << "LibraryManager: Destructor completed";
}

void LibraryManager::initializeDatabase()
{
    if (!m_databaseManager->initializeDatabase()) {
        qCritical() << "Failed to initialize database!";
    }
}


// Property getters
bool LibraryManager::isScanning() const
{
    // qDebug() << "LibraryManager::isScanning() called, returning" << m_scanning;
    return m_scanning;
}

int LibraryManager::scanProgress() const
{
    return m_scanProgress;
}

QString LibraryManager::scanProgressText() const
{
    if (!m_scanning) {
        return QString();
    }
    
    return QString("%1 of %2 files scanned").arg(m_filesScanned).arg(m_totalFilesToScan);
}

QStringList LibraryManager::musicFolders() const
{
    // qDebug() << "LibraryManager::musicFolders() called, returning" << m_musicFolders.size() << "folders";
    return m_musicFolders;
}

QStringList LibraryManager::musicFoldersDisplay() const
{
    qDebug() << "musicFoldersDisplay() called";
    qDebug() << "Current folders:" << m_musicFolders;
    qDebug() << "Display mappings:" << m_folderDisplayPaths;
    
    QStringList displayPaths;
    for (const QString &folder : m_musicFolders) {
        // Check if we have a display path for this folder
        if (m_folderDisplayPaths.contains(folder)) {
            QString displayPath = m_folderDisplayPaths[folder];
            qDebug() << "Using display path for" << folder << ":" << displayPath;
            displayPaths << displayPath;
        } else {
            // Fall back to the actual path if no display path is stored
            qDebug() << "No display path for" << folder << ", using actual path";
            displayPaths << folder;
        }
    }
    qDebug() << "Returning display paths:" << displayPaths;
    return displayPaths;
}

int LibraryManager::trackCount() const
{
    // qDebug() << "LibraryManager::trackCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        // qDebug() << "LibraryManager::trackCount() - database not ready, returning 0";
        return 0;
    }
    int count = m_databaseManager->getTotalTracks();
    // qDebug() << "LibraryManager::trackCount() returning" << count;
    return count;
}

int LibraryManager::albumCount() const
{
    // qDebug() << "LibraryManager::albumCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        // qDebug() << "LibraryManager::albumCount() - database not ready, returning 0";
        return 0;
    }
    
    // Use cached count if valid
    if (m_albumCountCacheValid) {
        return m_cachedAlbumCount;
    }
    
    // Otherwise fetch from database and cache
    m_cachedAlbumCount = m_databaseManager->getTotalAlbums();
    m_albumCountCacheValid = true;
    // qDebug() << "LibraryManager::albumCount() returning" << m_cachedAlbumCount;
    return m_cachedAlbumCount;
}

int LibraryManager::artistCount() const
{
    // qDebug() << "LibraryManager::artistCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        // qDebug() << "LibraryManager::artistCount() - database not ready, returning 0";
        return 0;
    }
    int count = m_databaseManager->getTotalArtists();
    // qDebug() << "LibraryManager::artistCount() returning" << count;
    return count;
}

// Property setters
void LibraryManager::setMusicFolders(const QStringList &folders)
{
    if (m_musicFolders != folders) {
        m_musicFolders = folders;
        emit musicFoldersChanged();
    }
}

// Library management methods
bool LibraryManager::addMusicFolder(const QString &path)
{
    qDebug() << "LibraryManager::addMusicFolder() called with path:" << path;
    QDir dir(path);
    if (!dir.exists()) {
        qWarning() << "Music folder does not exist:" << path;
        return false;
    }
    
    QString canonicalPath = dir.canonicalPath();
    qDebug() << "Canonical path:" << canonicalPath;
    qDebug() << "Original path:" << path;
    
    // For portal paths, try to create a more user-friendly display path
    QString displayPath = path;
    if (path.startsWith("/run/flatpak/doc/") || path.startsWith("/run/user/")) {
        qDebug() << "Detected portal path, trying to create user-friendly display";
        
        // Check if this is the user's home Music folder
        QString musicPath = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
        if (canonicalPath == QDir(musicPath).canonicalPath()) {
            displayPath = musicPath;
            qDebug() << "Portal path matches user's Music folder:" << displayPath;
        } else {
            // Try to extract a meaningful name from the portal path
            // Portal paths often end with the actual folder name
            QStringList parts = path.split('/');
            if (!parts.isEmpty()) {
                QString lastPart = parts.last();
                // If the last part looks like a hash, try to find a better name
                if (lastPart.length() > 20 && !lastPart.contains('.')) {
                    // This might be a portal hash, use a generic name
                    displayPath = "Music Folder";
                } else {
                    // Use the last part as the display name
                    displayPath = QDir::homePath() + "/" + lastPart;
                }
            }
        }
    }
    
    if (!m_musicFolders.contains(canonicalPath)) {
        m_musicFolders.append(canonicalPath);
        
        // Store the display path mapping
        m_folderDisplayPaths[canonicalPath] = displayPath;
        qDebug() << "Stored display path mapping:" << canonicalPath << "->" << displayPath;
        
        // Save to settings
        QSettings settings;
        settings.setValue("musicFolders", m_musicFolders);
        
        // Save display paths mapping
        settings.beginGroup("musicFolderDisplayPaths");
        for (auto it = m_folderDisplayPaths.begin(); it != m_folderDisplayPaths.end(); ++it) {
            settings.setValue(it.key(), it.value());
        }
        settings.endGroup();
        
        qDebug() << "LibraryManager::addMusicFolder() - folder added, emitting signal";
        emit musicFoldersChanged();
        return true;
    }
    
    qDebug() << "LibraryManager::addMusicFolder() - folder already exists";
    return false;
}

bool LibraryManager::removeMusicFolder(const QString &path)
{
    QDir dir(path);
    QString canonicalPath = dir.canonicalPath();
    
    if (m_musicFolders.removeAll(canonicalPath) > 0) {
        // Remove display path mapping
        m_folderDisplayPaths.remove(canonicalPath);
        
        // Save to settings
        QSettings settings;
        settings.setValue("musicFolders", m_musicFolders);
        
        // Update display paths in settings
        settings.beginGroup("musicFolderDisplayPaths");
        settings.remove(""); // Clear the group
        for (auto it = m_folderDisplayPaths.begin(); it != m_folderDisplayPaths.end(); ++it) {
            settings.setValue(it.key(), it.value());
        }
        settings.endGroup();
        
        // Remove all tracks from this folder from the database
        if (m_databaseManager->deleteTracksByFolderPath(canonicalPath)) {
            qDebug() << "LibraryManager::removeMusicFolder() - tracks removed from database";
            // Invalidate cache since we've changed the library
            m_albumModelCacheValid = false;
            m_albumCountCacheValid = false;
            m_artistModelCacheValid = false;
            m_albumsByArtistCache.clear();
            qDebug() << "LibraryManager::removeMusicFolder() - cache invalidated, emitting libraryChanged";
            emit libraryChanged();
        }
        
        emit musicFoldersChanged();
        return true;
    }
    
    return false;
}

void LibraryManager::startScan()
{
    qDebug() << "LibraryManager::startScan() called";
    
    if (m_scanning) {
        qDebug() << "Scan already in progress";
        return;
    }
    
    qDebug() << "Starting scan - checking music folders...";
    if (m_musicFolders.isEmpty()) {
        qWarning() << "No music folders configured for scanning";
        return;
    }
    
    qDebug() << "Setting scan state to true...";
    m_scanning = true;
    m_scanProgress = 0;
    m_filesScanned = 0;
    m_cancelRequested = false;
    
    qDebug() << "Emitting scan state change signals...";
    emit scanningChanged();
    emit scanProgressChanged();
    emit scanProgressTextChanged();
    
    qDebug() << "Starting QtConcurrent task...";
    qDebug() << "Current thread:" << QThread::currentThread();
    // Start async scanning - but serialize all operations to avoid TagLib threading issues
    try {
        m_scanFuture = QtConcurrent::run([this]() {
            qDebug() << "QtConcurrent task started in thread:" << QThread::currentThread();
            try {
                scanInBackground();
            } catch (const std::exception& e) {
                qCritical() << "Exception in QtConcurrent lambda:" << e.what();
            } catch (...) {
                qCritical() << "Unknown exception in QtConcurrent lambda";
            }
        });
        
        qDebug() << "Setting up future watcher...";
        m_scanWatcher.setFuture(m_scanFuture);
        qDebug() << "LibraryManager::startScan() completed successfully";
    } catch (const std::exception& e) {
        qCritical() << "Exception starting scan:" << e.what();
        m_scanning = false;
        emit scanningChanged();
    } catch (...) {
        qCritical() << "Unknown exception starting scan";
        m_scanning = false;
        emit scanningChanged();
    }
}

void LibraryManager::scanInBackground()
{
    qDebug() << "scanInBackground() starting in thread:" << QThread::currentThread();
    
    // Create a thread-local database connection
    QString connectionName = QString("ScanThread_%1").arg(quintptr(QThread::currentThreadId()));
    QSqlDatabase db = DatabaseManager::createThreadConnection(connectionName);
    
    if (!db.isOpen()) {
        qCritical() << "Failed to create thread database connection";
        return;
    }
    
    try {
        qDebug() << "About to start database transaction...";
        // Start transaction in the background thread
        QSqlQuery query(db);
        if (!query.exec("BEGIN TRANSACTION")) {
            qWarning() << "Failed to start database transaction:" << query.lastError().text();
            DatabaseManager::removeThreadConnection(connectionName);
            return;
        }
        qDebug() << "Transaction started successfully";
        
        // Find all music files
        QStringList allFiles;
        qDebug() << "Scanning music folders:" << m_musicFolders;
        for (const QString &folder : m_musicFolders) {
            QStringList filesInFolder = findMusicFiles(folder);
            qDebug() << "Found" << filesInFolder.size() << "files in" << folder;
            allFiles.append(filesInFolder);
            
            if (m_cancelRequested) {
                break;
            }
        }
        
        m_totalFilesToScan = allFiles.size();
        qDebug() << "Found" << m_totalFilesToScan << "music files to scan";
        if (m_totalFilesToScan > 0) {
            qDebug() << "First few files found:" << allFiles.mid(0, 5);
        }
        
        // Check for deleted files and remove them from database
        qDebug() << "Checking for deleted files...";
        QStringList existingTracksInDB;
        {
            // Get all tracks from database using thread-local connection
            QSqlQuery pathQuery(db);
            pathQuery.prepare("SELECT file_path FROM tracks");
            if (pathQuery.exec()) {
                while (pathQuery.next()) {
                    existingTracksInDB.append(pathQuery.value(0).toString());
                }
            }
        }
        qDebug() << "Found" << existingTracksInDB.size() << "tracks in database";
        
        // Convert allFiles to QSet for faster lookup
        QSet<QString> currentFilesSet = QSet<QString>(allFiles.begin(), allFiles.end());
        QStringList filesToDelete;
        
        for (const QString &dbFilePath : existingTracksInDB) {
            if (!currentFilesSet.contains(dbFilePath)) {
                // File exists in database but not on filesystem
                QFileInfo fileInfo(dbFilePath);
                if (!fileInfo.exists()) {
                    filesToDelete.append(dbFilePath);
                }
            }
        }
        
        if (!filesToDelete.isEmpty()) {
            qDebug() << "Found" << filesToDelete.size() << "deleted files to remove from database";
            for (const QString &deletedFile : filesToDelete) {
                if (m_cancelRequested) break;
                
                QSqlQuery deleteQuery(db);
                deleteQuery.prepare("DELETE FROM tracks WHERE file_path = :path");
                deleteQuery.bindValue(":path", deletedFile);
                if (!deleteQuery.exec()) {
                    qWarning() << "Failed to delete track from database:" << deletedFile 
                              << "-" << deleteQuery.lastError().text();
                } else {
                    qDebug() << "Removed deleted file from database:" << deletedFile;
                }
            }
            
            // Clean up orphaned albums, album artists, and artists after deleting tracks
            qDebug() << "Cleaning up orphaned entries...";
            
            // Delete albums that have no tracks
            QSqlQuery cleanupQuery(db);
            if (!cleanupQuery.exec("DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL)")) {
                qWarning() << "Failed to delete orphaned albums:" << cleanupQuery.lastError().text();
            } else {
                int deletedAlbums = cleanupQuery.numRowsAffected();
                if (deletedAlbums > 0) {
                    qDebug() << "Deleted" << deletedAlbums << "orphaned albums";
                }
            }
            
            // Delete album artists that have no albums
            if (!cleanupQuery.exec("DELETE FROM album_artists WHERE id NOT IN (SELECT DISTINCT album_artist_id FROM albums WHERE album_artist_id IS NOT NULL)")) {
                qWarning() << "Failed to delete orphaned album artists:" << cleanupQuery.lastError().text();
            } else {
                int deletedAlbumArtists = cleanupQuery.numRowsAffected();
                if (deletedAlbumArtists > 0) {
                    qDebug() << "Deleted" << deletedAlbumArtists << "orphaned album artists";
                }
            }
            
            // Delete artists that have no tracks
            if (!cleanupQuery.exec("DELETE FROM artists WHERE id NOT IN (SELECT DISTINCT artist_id FROM tracks WHERE artist_id IS NOT NULL)")) {
                qWarning() << "Failed to delete orphaned artists:" << cleanupQuery.lastError().text();
            } else {
                int deletedArtists = cleanupQuery.numRowsAffected();
                if (deletedArtists > 0) {
                    qDebug() << "Deleted" << deletedArtists << "orphaned artists";
                }
            }
        }
        
        // Create a single metadata extractor for this thread
        Mtoc::MetadataExtractor threadExtractor;
        
        // Process files in batches for better database performance
        const int batchSize = 50; // Batch size for database operations
        const int parallelExtractionBatch = 10; // Number of files to extract metadata in parallel
        QList<QVariantMap> batchMetadata;
        QList<QFuture<QVariantMap>> extractionFutures;
        
        for (int i = 0; i < allFiles.size() && !m_cancelRequested; ++i) {
            const QString &filePath = allFiles[i];
            QFileInfo fileInfo(filePath);
            
            // Check if already in database before extracting metadata
            {
                QSqlQuery checkQuery(db);
                checkQuery.prepare("SELECT 1 FROM tracks WHERE file_path = :path LIMIT 1");
                checkQuery.bindValue(":path", filePath);
                if (!checkQuery.exec()) {
                    qWarning() << "Failed to check track existence:" << checkQuery.lastError().text();
                } else if (checkQuery.next()) {
                    // qDebug() << "Track already exists in database, skipping:" << filePath;
                    m_filesScanned++;
                    continue;
                } else {
                    // Track not in database, will process
                }
            }
            
            // Queue metadata extraction for parallel processing
            QFuture<QVariantMap> future = QtConcurrent::run([filePath, fileInfo]() -> QVariantMap {
                try {
                    // Create a thread-local extractor to avoid threading issues
                    Mtoc::MetadataExtractor localExtractor;
                    QVariantMap metadata = localExtractor.extractAsVariantMap(filePath);
                    
                    // Validate metadata before using
                    if (!metadata.isEmpty() && metadata.contains("filePath")) {
                        // Add file info to metadata
                        metadata["fileSize"] = fileInfo.size();
                        metadata["fileModified"] = fileInfo.lastModified();
                        metadata["filePath"] = filePath;
                        metadata["valid"] = true;
                    } else {
                        metadata["valid"] = false;
                        metadata["filePath"] = filePath;
                    }
                    return metadata;
                } catch (const std::exception& e) {
                    QVariantMap errorMetadata;
                    errorMetadata["valid"] = false;
                    errorMetadata["filePath"] = filePath;
                    errorMetadata["error"] = QString::fromStdString(e.what());
                    return errorMetadata;
                } catch (...) {
                    QVariantMap errorMetadata;
                    errorMetadata["valid"] = false;
                    errorMetadata["filePath"] = filePath;
                    errorMetadata["error"] = "Unknown error";
                    return errorMetadata;
                }
            });
            
            extractionFutures.append(future);
            
            // Process futures when we have enough or at the end of the list
            if (extractionFutures.size() >= parallelExtractionBatch || i == allFiles.size() - 1) {
                // Wait for all futures in this batch to complete
                for (const QFuture<QVariantMap> &f : extractionFutures) {
                    QVariantMap metadata = f.result();
                    if (metadata.value("valid", false).toBool()) {
                        batchMetadata.append(metadata);
                    } else {
                        QString error = metadata.value("error", "Invalid metadata").toString();
                        if (!error.isEmpty() && error != "Invalid metadata") {
                            qWarning() << "Error extracting metadata from" << metadata.value("filePath").toString() << ":" << error;
                        }
                    }
                }
                extractionFutures.clear();
            }
            
            // Update scanned count
            m_filesScanned++;
            
            // Insert batch when it reaches the batch size or at the end
            if (batchMetadata.size() >= batchSize || i == allFiles.size() - 1) {
                if (!batchMetadata.isEmpty()) {
                    // Use prepared statements for better performance
                    insertBatchTracksInThread(db, batchMetadata);
                    batchMetadata.clear();
                }
            }
            
            // Update progress
            int newProgress = (m_filesScanned * 100) / m_totalFilesToScan;
            if (newProgress != m_scanProgress) {
                m_scanProgress = newProgress;
                QMetaObject::invokeMethod(this, "scanProgressChanged", Qt::QueuedConnection);
                QMetaObject::invokeMethod(this, "scanProgressTextChanged", Qt::QueuedConnection);
            }
            
            // Yield to other threads more intelligently based on system load
            if (i % 100 == 0) {
                QThread::yieldCurrentThread();
            }
        }
        
        // Process any remaining items in the batch
        if (!batchMetadata.isEmpty() && !m_cancelRequested) {
            qDebug() << "Processing final batch with" << batchMetadata.size() << "tracks";
            insertBatchTracksInThread(db, batchMetadata);
            batchMetadata.clear();
        }
        
        // Commit the transaction if not cancelled
        if (!m_cancelRequested) {
            QSqlQuery commitQuery(db);
            if (!commitQuery.exec("COMMIT")) {
                qWarning() << "Failed to commit database transaction:" << commitQuery.lastError().text();
            } else {
                qDebug() << "Successfully committed database transaction";
            }
        } else {
            // Rollback if cancelled
            QSqlQuery rollbackQuery(db);
            rollbackQuery.exec("ROLLBACK");
        }
        
        qDebug() << "scanInBackground() completed successfully";
    } catch (const std::exception& e) {
        qCritical() << "Exception in scanInBackground():" << e.what();
        // Rollback transaction on error
        QSqlQuery rollbackQuery(db);
        rollbackQuery.exec("ROLLBACK");
    } catch (...) {
        qCritical() << "Unknown exception in scanInBackground()";
        // Rollback transaction on error
        QSqlQuery rollbackQuery(db);
        rollbackQuery.exec("ROLLBACK");
    }
    
    // Clean up thread-local database connection
    DatabaseManager::removeThreadConnection(connectionName);
}

void LibraryManager::cancelScan()
{
    if (!m_scanning) {
        return;
    }
    
    m_cancelRequested = true;
    m_scanFuture.waitForFinished();
}

void LibraryManager::onScanFinished()
{
    qDebug() << "LibraryManager::onScanFinished() called";
    
    m_scanning = false;
    m_scanProgress = 100;
    
    // Transaction is now handled in the background thread
    
    // Invalidate cache after scan and clear it to free memory
    m_albumModelCacheValid = false;
    m_albumCountCacheValid = false;
    m_artistModelCacheValid = false;
    m_cachedAlbumModel.clear(); // Clear cached data to free memory
    m_cachedArtistModel.clear(); // Clear cached artist data to free memory
    m_albumsByArtistCache.clear(); // Clear artist-specific caches
    qDebug() << "Album and artist model cache invalidated and cleared after scan";
    
    // Force garbage collection in QPixmapCache after scan
    QPixmapCache::clear();
    qDebug() << "QPixmapCache cleared after scan to prevent memory accumulation";
    
    // Use queued connections to ensure signals are emitted from main thread
    QMetaObject::invokeMethod(this, "scanningChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "scanProgressChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "scanProgressTextChanged", Qt::QueuedConnection);
    
    if (m_cancelRequested) {
        QMetaObject::invokeMethod(this, "scanCancelled", Qt::QueuedConnection);
    } else {
        QMetaObject::invokeMethod(this, "scanCompleted", Qt::QueuedConnection);
    }
    
    // Refresh all counts and models - ensure these are from main thread
    QMetaObject::invokeMethod(this, "libraryChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "trackCountChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "albumCountChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "artistCountChanged", Qt::QueuedConnection);
    
    qDebug() << "LibraryManager::onScanFinished() completed";
}

void LibraryManager::clearLibrary()
{
    // Clear database
    m_databaseManager->clearDatabase();
    
    // Clear models
    m_allTracksModel->clear();
    m_allAlbumsModel->clear();
    
    // Invalidate cache
    m_albumModelCacheValid = false;
    m_albumCountCacheValid = false;
    m_artistModelCacheValid = false;
    m_cachedAlbumModel.clear();
    m_cachedArtistModel.clear();
    m_albumsByArtistCache.clear();
    
    emit libraryChanged();
    emit trackCountChanged();
    emit albumCountChanged();
    emit artistCountChanged();
}

// Utility methods
QStringList LibraryManager::findMusicFiles(const QString &dir)
{
    QStringList musicFiles;
    processDirectory(dir, musicFiles);
    return musicFiles;
}

void LibraryManager::processDirectory(const QString &dir, QStringList &musicFiles)
{
    QDirIterator it(dir, QDirIterator::Subdirectories);
    
    while (it.hasNext() && !m_cancelRequested) {
        it.next();
        QFileInfo fileInfo = it.fileInfo();
        
        if (fileInfo.isFile() && isMusicFile(fileInfo)) {
            musicFiles.append(fileInfo.absoluteFilePath());
        }
    }
}

bool LibraryManager::isMusicFile(const QFileInfo &fileInfo) const
{
    static const QStringList musicExtensions = {
        "mp3", "m4a", "m4p", "mp4", "aac", "ogg", "oga", "opus",
        "flac", "wav", "wma", "ape", "mka", "wv", "tta", "ac3", "dts"
    };
    
    return musicExtensions.contains(fileInfo.suffix().toLower());
}

void LibraryManager::syncWithDatabase(const QString &filePath)
{
    // This method is now primarily used for single file updates, not bulk scanning
    QFileInfo fileInfo(filePath);
    
    // Check if file still exists
    if (!fileInfo.exists()) {
        // Remove from database if it exists there
        QMutexLocker locker(&m_databaseMutex);
        int trackId = m_databaseManager->getTrackIdByPath(filePath);
        if (trackId > 0) {
            m_databaseManager->deleteTrack(trackId);
        }
        return;
    }
    
    // Check if file is already in database and hasn't been modified
    {
        QMutexLocker locker(&m_databaseMutex);
        if (m_databaseManager->trackExists(filePath)) {
            // TODO: Check file modification time and update if needed
            return;
        }
    }
    
    // Extract metadata - create a local extractor to avoid thread issues
    Mtoc::MetadataExtractor localExtractor;
    QVariantMap metadata = localExtractor.extractAsVariantMap(filePath);
    
    // Add file info to metadata
    metadata["fileSize"] = fileInfo.size();
    metadata["fileModified"] = fileInfo.lastModified();
    
    // Insert into database
    QMutexLocker locker(&m_databaseMutex);
    m_databaseManager->insertTrack(metadata);
}

// Data access methods
TrackModel* LibraryManager::allTracksModel() const
{
    // TODO: Implement loading tracks from database into model
    return m_allTracksModel;
}

AlbumModel* LibraryManager::allAlbumsModel() const
{
    // TODO: Implement loading albums from database into model
    return m_allAlbumsModel;
}

QStringList LibraryManager::allArtists() const
{
    QStringList artists;
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return artists;
    }
    
    QVariantList artistData = m_databaseManager->getAllArtists();
    
    for (const QVariant &v : artistData) {
        QVariantMap artist = v.toMap();
        artists << artist["name"].toString();
    }
    
    return artists;
}

QVariantList LibraryManager::artistModel() const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "LibraryManager::artistModel() - database not ready, returning empty list";
        return QVariantList();
    }
    
    // Use cached data if valid
    if (m_artistModelCacheValid) {
        return m_cachedArtistModel;
    }
    
    // Clear previous cache to free memory before allocating new data
    m_cachedArtistModel.clear();
    
    QVariantList newArtistModel = m_databaseManager->getAllArtists();
    
    m_cachedArtistModel = std::move(newArtistModel);
    m_artistModelCacheValid = true;
    return m_cachedArtistModel;
}

QVariantList LibraryManager::albumModel() const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "LibraryManager::albumModel() - database not ready, returning empty list";
        return QVariantList();
    }
    
    // Check if we should use full cache or not based on album count
    int totalAlbums = albumCount();
    
    // For small libraries (< 1000 albums), use the existing full cache approach
    if (totalAlbums < 1000) {
        // Use cached data if valid
        if (m_albumModelCacheValid) {
            return m_cachedAlbumModel;
        }
        
        // Clear previous cache to free memory before allocating new data
        m_cachedAlbumModel.clear();
        
        QVariantList newAlbumModel = m_databaseManager->getAllAlbums();
        
        m_cachedAlbumModel = std::move(newAlbumModel);
        m_albumModelCacheValid = true;
        return m_cachedAlbumModel;
    }
    
    // For large libraries, return a lightweight version with just essential data
    // The UI should use pagination or lazy loading
    qWarning() << "Large library detected (" << totalAlbums << " albums). Consider using getAlbumsPaginated() for better performance.";
    
    // Return empty list and let UI handle pagination
    return QVariantList();
}

QVariantList LibraryManager::getAlbumsForArtist(const QString &artistName) const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return QVariantList();
    }
    
    // Check cache first
    if (m_albumsByArtistCache.contains(artistName)) {
        return m_albumsByArtistCache[artistName];
    }
    
    // Fetch from database and cache
    QVariantList albums = m_databaseManager->getAlbumsByAlbumArtistName(artistName);
    
    // Only cache if the result is reasonably small
    if (albums.size() < 100) {
        m_albumsByArtistCache[artistName] = albums;
    }
    
    return albums;
}

TrackModel* LibraryManager::searchTracks(const QString &query) const
{
    TrackModel *model = new TrackModel(const_cast<LibraryManager*>(this));
    QVariantList results = m_databaseManager->searchTracks(query);
    
    // TODO: Convert QVariantList to Track objects and add to model
    
    return model;
}

// Stub implementations for remaining methods

TrackModel* LibraryManager::tracksForArtist(const QString &artistName) const
{
    // TODO: Implement
    return new TrackModel(const_cast<LibraryManager*>(this));
}

AlbumModel* LibraryManager::albumsForArtist(const QString &artistName) const
{
    AlbumModel *model = new AlbumModel(const_cast<LibraryManager*>(this));
    
    // Get albums from database
    QVariantList albumData = m_databaseManager->getAlbumsByAlbumArtistName(artistName);
    
    // Convert QVariantList to Album objects
    for (const QVariant &v : albumData) {
        QVariantMap albumMap = v.toMap();
        
        // Create Album object with model as parent for proper memory management
        Album *album = new Album(
            albumMap["title"].toString(),
            artistName,  // Use the album artist name
            model  // Set parent to ensure cleanup
        );
        
        // Set additional properties if needed
        if (albumMap.contains("year") && albumMap["year"].toInt() > 0) {
            // Album class might need setYear method
        }
        
        model->addAlbum(album);
    }
    
    return model;
}

TrackModel* LibraryManager::tracksForAlbum(const QString &albumTitle, const QString &artistName) const
{
    // TODO: Implement
    return new TrackModel(const_cast<LibraryManager*>(this));
}

QVariantList LibraryManager::getTracksForAlbumAsVariantList(const QString &artistName, const QString &albumTitle) const
{
    if (!m_databaseManager) {
        qWarning() << "[LibraryManager::getTracksForAlbumAsVariantList] DatabaseManager is null!";
        return QVariantList();
    }
    
    if (!m_databaseManager->isOpen()) {
        qWarning() << "[LibraryManager::getTracksForAlbumAsVariantList] Database is not open!";
        return QVariantList();
    }
    
    return m_databaseManager->getTracksByAlbumAndArtist(albumTitle, artistName);
}

AlbumModel* LibraryManager::searchAlbums(const QString &query) const
{
    // TODO: Implement proper AlbumModel search
    return new AlbumModel(const_cast<LibraryManager*>(this));
}

QStringList LibraryManager::searchArtists(const QString &query) const
{
    // TODO: Implement proper artist search
    return QStringList();
}

QVariantMap LibraryManager::searchAll(const QString &query) const
{
    if (!m_databaseManager) {
        return QVariantMap();
    }
    
    return m_databaseManager->searchAll(query);
}

Track* LibraryManager::trackByPath(const QString &path) const
{
    // TODO: Implement database lookup
    return nullptr;
}

Album* LibraryManager::albumByTitle(const QString &title, const QString &artistName) const
{
    // TODO: Implement database lookup
    return nullptr;
}

Artist* LibraryManager::artistByName(const QString &name) const
{
    // TODO: Implement database lookup
    return nullptr;
}


void LibraryManager::saveCarouselPosition(int albumId)
{
    QSettings settings;
    settings.setValue("carouselPosition/albumId", albumId);
    qDebug() << "LibraryManager: Saved carousel position - album ID:" << albumId;
}

int LibraryManager::loadCarouselPosition() const
{
    QSettings settings;
    int albumId = settings.value("carouselPosition/albumId", -1).toInt();
    qDebug() << "LibraryManager: Loaded carousel position - album ID:" << albumId;
    return albumId;
}

QVariantList LibraryManager::getAlbumsPaginated(int offset, int limit) const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return QVariantList();
    }
    
    // Delegate to database manager with pagination
    // TODO: Add pagination support to DatabaseManager
    // For now, return empty list
    qDebug() << "LibraryManager::getAlbumsPaginated - offset:" << offset << "limit:" << limit;
    return QVariantList();
}

void LibraryManager::preloadAlbumsForArtists(const QStringList &artistNames) const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return;
    }
    
    // Preload albums for multiple artists in a batch to improve performance
    for (const QString &artistName : artistNames) {
        // Skip if already cached
        if (m_albumsByArtistCache.contains(artistName)) {
            continue;
        }
        
        // This will cache the albums
        getAlbumsForArtist(artistName);
    }
}

QVariantList LibraryManager::getLightweightAlbumModel() const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return QVariantList();
    }
    
    // For now, check album count and decide strategy
    int totalAlbums = albumCount();
    
    if (totalAlbums < 1000) {
        // For small libraries, use the full model
        return albumModel();
    } else {
        // For large libraries, we should implement a lightweight query
        // that only fetches essential album data (id, title, artist, year, hasArt)
        // TODO: Implement lightweight query in DatabaseManager
        qWarning() << "Large library (" << totalAlbums << " albums) - lightweight model not yet implemented";
        return QVariantList();
    }
}

void LibraryManager::saveCarouselPosition(int albumId)
{
    QSettings settings;
    settings.setValue("carouselPosition/albumId", albumId);
    qDebug() << "LibraryManager: Saved carousel position - album ID:" << albumId;
}

int LibraryManager::loadCarouselPosition() const
{
    QSettings settings;
    int albumId = settings.value("carouselPosition/albumId", -1).toInt();
    qDebug() << "LibraryManager: Loaded carousel position - album ID:" << albumId;
    return albumId;
}

void LibraryManager::insertTrackInThread(QSqlDatabase& db, const QVariantMap& metadata)
{
    // Extract data
    QString filePath = metadata.value("filePath").toString();
    QString title = metadata.value("title").toString();
    QString artist = metadata.value("artist").toString();
    QString albumArtist = metadata.value("albumArtist").toString();
    QString album = metadata.value("album").toString();
    QString genre = metadata.value("genre").toString();
    int year = metadata.value("year").toInt();
    int trackNumber = metadata.value("trackNumber").toInt();
    int discNumber = metadata.value("discNumber").toInt();
    int duration = metadata.value("duration").toInt();
    qint64 fileSize = metadata.value("fileSize", 0).toLongLong();
    QDateTime fileModified = metadata.value("fileModified").toDateTime();
    
    // Helper function to insert or get artist
    auto insertOrGetArtist = [&db](const QString& artistName) -> int {
        if (artistName.isEmpty()) return 0;
        
        QSqlQuery query(db);
        
        // Try to find existing artist
        query.prepare("SELECT id FROM artists WHERE name = :name");
        query.bindValue(":name", artistName);
        
        if (query.exec() && query.next()) {
            return query.value(0).toInt();
        }
        
        // Insert new artist
        query.prepare("INSERT INTO artists (name) VALUES (:name)");
        query.bindValue(":name", artistName);
        
        if (query.exec()) {
            return query.lastInsertId().toInt();
        }
        
        return 0;
    };
    
    // Helper function to insert or get album artist
    auto insertOrGetAlbumArtist = [&db](const QString& albumArtistName) -> int {
        if (albumArtistName.isEmpty()) return 0;
        
        QSqlQuery query(db);
        
        // Try to find existing album artist
        query.prepare("SELECT id FROM album_artists WHERE name = :name");
        query.bindValue(":name", albumArtistName);
        
        if (query.exec() && query.next()) {
            return query.value(0).toInt();
        }
        
        // Insert new album artist
        query.prepare("INSERT INTO album_artists (name) VALUES (:name)");
        query.bindValue(":name", albumArtistName);
        
        if (query.exec()) {
            return query.lastInsertId().toInt();
        }
        
        return 0;
    };
    
    // Helper function to insert or get album
    auto insertOrGetAlbum = [&db](const QString& albumName, int albumArtistId, int albumYear) -> int {
        if (albumName.isEmpty()) return 0;
        
        QSqlQuery query(db);
        
        // Try to find existing album
        if (albumArtistId > 0) {
            query.prepare("SELECT id FROM albums WHERE title = :title AND album_artist_id = :artist_id");
            query.bindValue(":title", albumName);
            query.bindValue(":artist_id", albumArtistId);
        } else {
            query.prepare("SELECT id FROM albums WHERE title = :title AND album_artist_id IS NULL");
            query.bindValue(":title", albumName);
        }
        
        if (query.exec() && query.next()) {
            int existingAlbumId = query.value(0).toInt();
            
            // Update year if provided and not already set
            if (albumYear > 0) {
                QSqlQuery updateQuery(db);
                updateQuery.prepare("UPDATE albums SET year = :year WHERE id = :id AND (year IS NULL OR year = 0)");
                updateQuery.bindValue(":year", albumYear);
                updateQuery.bindValue(":id", existingAlbumId);
                updateQuery.exec();
            }
            
            return existingAlbumId;
        }
        
        // Insert new album with year
        query.prepare("INSERT INTO albums (title, album_artist_id, year) VALUES (:title, :artist_id, :year)");
        query.bindValue(":title", albumName);
        query.bindValue(":artist_id", albumArtistId > 0 ? albumArtistId : QVariant());
        query.bindValue(":year", albumYear > 0 ? albumYear : QVariant());
        
        if (query.exec()) {
            return query.lastInsertId().toInt();
        }
        
        return 0;
    };
    
    // Get or create artist
    int artistId = 0;
    if (!artist.isEmpty()) {
        artistId = insertOrGetArtist(artist);
    }
    
    // Get or create album artist
    int albumArtistId = 0;
    if (!albumArtist.isEmpty()) {
        albumArtistId = insertOrGetAlbumArtist(albumArtist);
    } else if (!artist.isEmpty()) {
        // Fallback to artist if no album artist specified
        albumArtistId = insertOrGetAlbumArtist(artist);
    }
    
    // Get or create album
    int albumId = 0;
    if (!album.isEmpty()) {
        albumId = insertOrGetAlbum(album, albumArtistId, year);
        
        // Process album art if we have it and it's not already stored
        if (albumId > 0 && metadata.contains("hasAlbumArt") && metadata.value("hasAlbumArt").toBool()) {
            // Check if album art already exists
            QSqlQuery artCheckQuery(db);
            artCheckQuery.prepare("SELECT 1 FROM album_art WHERE album_id = :album_id LIMIT 1");
            artCheckQuery.bindValue(":album_id", albumId);
            
            if (artCheckQuery.exec() && !artCheckQuery.next()) {
                // Album art doesn't exist, process and store it
                QByteArray albumArtData = metadata.value("albumArtData").toByteArray();
                QString mimeType = metadata.value("albumArtMimeType").toString();
                
                if (!albumArtData.isEmpty()) {
                    // Process album art
                    AlbumArtManager albumArtManager;
                    AlbumArtManager::ProcessedAlbumArt processed = 
                        albumArtManager.processAlbumArt(albumArtData, album, 
                                                       albumArtistId > 0 ? albumArtist : artist,
                                                       mimeType);
                    
                    if (processed.success) {
                        // Insert album art into database
                        QSqlQuery artQuery(db);
                        artQuery.prepare(
                            "INSERT INTO album_art "
                            "(album_id, full_path, full_hash, thumbnail, thumbnail_size, "
                            "width, height, format, file_size) "
                            "VALUES (:album_id, :full_path, :full_hash, :thumbnail, :thumbnail_size, "
                            ":width, :height, :format, :file_size)"
                        );
                        
                        artQuery.bindValue(":album_id", albumId);
                        artQuery.bindValue(":full_path", processed.fullImagePath);
                        artQuery.bindValue(":full_hash", processed.hash);
                        artQuery.bindValue(":thumbnail", processed.thumbnailData);
                        artQuery.bindValue(":thumbnail_size", processed.thumbnailData.size());
                        artQuery.bindValue(":width", processed.originalSize.width());
                        artQuery.bindValue(":height", processed.originalSize.height());
                        artQuery.bindValue(":format", processed.format);
                        artQuery.bindValue(":file_size", processed.fileSize);
                        
                        if (!artQuery.exec()) {
                            qWarning() << "Failed to insert album art for album:" << album 
                                      << "-" << artQuery.lastError().text();
                        }
                    }
                }
            }
        }
    }
    
    // Insert track
    QSqlQuery query(db);
    query.prepare(
        "INSERT INTO tracks (file_path, title, artist_id, album_id, genre, year, "
        "track_number, disc_number, duration, file_size, file_modified) "
        "VALUES (:file_path, :title, :artist_id, :album_id, :genre, :year, "
        ":track_number, :disc_number, :duration, :file_size, :file_modified)"
    );
    
    query.bindValue(":file_path", filePath);
    query.bindValue(":title", title);
    query.bindValue(":artist_id", artistId > 0 ? artistId : QVariant());
    query.bindValue(":album_id", albumId > 0 ? albumId : QVariant());
    query.bindValue(":genre", genre);
    query.bindValue(":year", year > 0 ? year : QVariant());
    query.bindValue(":track_number", trackNumber > 0 ? trackNumber : QVariant());
    query.bindValue(":disc_number", discNumber > 0 ? discNumber : QVariant());
    query.bindValue(":duration", duration > 0 ? duration : QVariant());
    query.bindValue(":file_size", fileSize > 0 ? fileSize : QVariant());
    query.bindValue(":file_modified", fileModified.isValid() ? fileModified : QVariant());
    
    if (!query.exec()) {
        qWarning() << "Failed to insert track:" << filePath << "-" << query.lastError().text();
        qWarning() << "SQL:" << query.lastQuery();
        qWarning() << "Bound values:" << query.boundValues();
    }
}

void LibraryManager::insertBatchTracksInThread(QSqlDatabase& db, const QList<QVariantMap>& batchMetadata)
{
    if (batchMetadata.isEmpty() || m_cancelRequested) {
        return;
    }
    
    // Use maps to cache artist/album lookups within this batch
    QHash<QString, int> artistCache;
    QHash<QString, int> albumArtistCache;
    QHash<QPair<QString, int>, int> albumCache; // (album title, album artist id) -> album id
    
    // Helper lambdas with caching
    auto getCachedArtist = [&db, &artistCache](const QString& artistName) -> int {
        if (artistName.isEmpty()) return 0;
        
        if (artistCache.contains(artistName)) {
            return artistCache[artistName];
        }
        
        QSqlQuery query(db);
        query.prepare("SELECT id FROM artists WHERE name = :name");
        query.bindValue(":name", artistName);
        
        if (query.exec() && query.next()) {
            int id = query.value(0).toInt();
            artistCache[artistName] = id;
            return id;
        }
        
        // Insert new artist
        query.prepare("INSERT INTO artists (name) VALUES (:name)");
        query.bindValue(":name", artistName);
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            artistCache[artistName] = id;
            return id;
        }
        
        return 0;
    };
    
    auto getCachedAlbumArtist = [&db, &albumArtistCache](const QString& albumArtistName) -> int {
        if (albumArtistName.isEmpty()) return 0;
        
        if (albumArtistCache.contains(albumArtistName)) {
            return albumArtistCache[albumArtistName];
        }
        
        QSqlQuery query(db);
        query.prepare("SELECT id FROM album_artists WHERE name = :name");
        query.bindValue(":name", albumArtistName);
        
        if (query.exec() && query.next()) {
            int id = query.value(0).toInt();
            albumArtistCache[albumArtistName] = id;
            return id;
        }
        
        // Insert new album artist
        query.prepare("INSERT INTO album_artists (name) VALUES (:name)");
        query.bindValue(":name", albumArtistName);
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            albumArtistCache[albumArtistName] = id;
            return id;
        }
        
        return 0;
    };
    
    auto getCachedAlbum = [&db, &albumCache](const QString& albumName, int albumArtistId, int albumYear) -> int {
        if (albumName.isEmpty()) return 0;
        
        QPair<QString, int> key(albumName, albumArtistId);
        if (albumCache.contains(key)) {
            return albumCache[key];
        }
        
        QSqlQuery query(db);
        
        // Try to find existing album
        if (albumArtistId > 0) {
            query.prepare("SELECT id FROM albums WHERE title = :title AND album_artist_id = :artist_id");
            query.bindValue(":title", albumName);
            query.bindValue(":artist_id", albumArtistId);
        } else {
            query.prepare("SELECT id FROM albums WHERE title = :title AND album_artist_id IS NULL");
            query.bindValue(":title", albumName);
        }
        
        if (query.exec() && query.next()) {
            int existingAlbumId = query.value(0).toInt();
            albumCache[key] = existingAlbumId;
            
            // Update year if provided and not already set
            if (albumYear > 0) {
                QSqlQuery updateQuery(db);
                updateQuery.prepare("UPDATE albums SET year = :year WHERE id = :id AND (year IS NULL OR year = 0)");
                updateQuery.bindValue(":year", albumYear);
                updateQuery.bindValue(":id", existingAlbumId);
                updateQuery.exec();
            }
            
            return existingAlbumId;
        }
        
        // Insert new album with year
        query.prepare("INSERT INTO albums (title, album_artist_id, year) VALUES (:title, :artist_id, :year)");
        query.bindValue(":title", albumName);
        query.bindValue(":artist_id", albumArtistId > 0 ? albumArtistId : QVariant());
        query.bindValue(":year", albumYear > 0 ? albumYear : QVariant());
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            albumCache[key] = id;
            return id;
        }
        
        return 0;
    };
    
    // Prepare track insert statement once
    QSqlQuery trackInsert(db);
    trackInsert.prepare(
        "INSERT INTO tracks (file_path, title, artist_id, album_id, genre, year, "
        "track_number, disc_number, duration, file_size, file_modified) "
        "VALUES (:file_path, :title, :artist_id, :album_id, :genre, :year, "
        ":track_number, :disc_number, :duration, :file_size, :file_modified)"
    );
    
    // Process each track in the batch
    for (const QVariantMap &metadata : batchMetadata) {
        if (m_cancelRequested) {
            break;
        }
        
        // Extract data
        QString filePath = metadata.value("filePath").toString();
        QString title = metadata.value("title").toString();
        QString artist = metadata.value("artist").toString();
        QString albumArtist = metadata.value("albumArtist").toString();
        QString album = metadata.value("album").toString();
        QString genre = metadata.value("genre").toString();
        int year = metadata.value("year").toInt();
        int trackNumber = metadata.value("trackNumber").toInt();
        int discNumber = metadata.value("discNumber").toInt();
        int duration = metadata.value("duration").toInt();
        qint64 fileSize = metadata.value("fileSize", 0).toLongLong();
        QDateTime fileModified = metadata.value("fileModified").toDateTime();
        
        // Get or create artist (using cache)
        int artistId = getCachedArtist(artist);
        
        // Get or create album artist (using cache)
        int albumArtistId = 0;
        if (!albumArtist.isEmpty()) {
            albumArtistId = getCachedAlbumArtist(albumArtist);
        } else if (!artist.isEmpty()) {
            albumArtistId = getCachedAlbumArtist(artist);
        }
        
        // Get or create album (using cache)
        int albumId = getCachedAlbum(album, albumArtistId, year);
        
        // Process album art if needed (only for new albums)
        if (albumId > 0 && metadata.contains("hasAlbumArt") && metadata.value("hasAlbumArt").toBool()) {
            // Check if album art already exists
            QSqlQuery artCheckQuery(db);
            artCheckQuery.prepare("SELECT 1 FROM album_art WHERE album_id = :album_id LIMIT 1");
            artCheckQuery.bindValue(":album_id", albumId);
            
            if (artCheckQuery.exec() && !artCheckQuery.next()) {
                // Album art doesn't exist, process and store it
                QByteArray albumArtData = metadata.value("albumArtData").toByteArray();
                QString mimeType = metadata.value("albumArtMimeType").toString();
                
                if (!albumArtData.isEmpty()) {
                    // Process album art
                    AlbumArtManager albumArtManager;
                    AlbumArtManager::ProcessedAlbumArt processed = 
                        albumArtManager.processAlbumArt(albumArtData, album, 
                                                       albumArtistId > 0 ? albumArtist : artist,
                                                       mimeType);
                    
                    if (processed.success) {
                        // Insert album art into database
                        QSqlQuery artQuery(db);
                        artQuery.prepare(
                            "INSERT INTO album_art "
                            "(album_id, full_path, full_hash, thumbnail, thumbnail_size, "
                            "width, height, format, file_size) "
                            "VALUES (:album_id, :full_path, :full_hash, :thumbnail, :thumbnail_size, "
                            ":width, :height, :format, :file_size)"
                        );
                        
                        artQuery.bindValue(":album_id", albumId);
                        artQuery.bindValue(":full_path", processed.fullImagePath);
                        artQuery.bindValue(":full_hash", processed.hash);
                        artQuery.bindValue(":thumbnail", processed.thumbnailData);
                        artQuery.bindValue(":thumbnail_size", processed.thumbnailData.size());
                        artQuery.bindValue(":width", processed.originalSize.width());
                        artQuery.bindValue(":height", processed.originalSize.height());
                        artQuery.bindValue(":format", processed.format);
                        artQuery.bindValue(":file_size", processed.fileSize);
                        
                        if (!artQuery.exec()) {
                            qWarning() << "Failed to insert album art for album:" << album 
                                      << "-" << artQuery.lastError().text();
                        }
                    }
                }
            }
        }
        
        // Insert track using prepared statement
        trackInsert.bindValue(":file_path", filePath);
        trackInsert.bindValue(":title", title);
        trackInsert.bindValue(":artist_id", artistId > 0 ? artistId : QVariant());
        trackInsert.bindValue(":album_id", albumId > 0 ? albumId : QVariant());
        trackInsert.bindValue(":genre", genre);
        trackInsert.bindValue(":year", year > 0 ? year : QVariant());
        trackInsert.bindValue(":track_number", trackNumber > 0 ? trackNumber : QVariant());
        trackInsert.bindValue(":disc_number", discNumber > 0 ? discNumber : QVariant());
        trackInsert.bindValue(":duration", duration > 0 ? duration : QVariant());
        trackInsert.bindValue(":file_size", fileSize > 0 ? fileSize : QVariant());
        trackInsert.bindValue(":file_modified", fileModified.isValid() ? fileModified : QVariant());
        
        if (!trackInsert.exec()) {
            qWarning() << "Failed to insert track:" << filePath << "-" << trackInsert.lastError().text();
        }
    }
}

} // namespace Mtoc