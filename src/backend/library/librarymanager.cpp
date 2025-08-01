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
#include <QCoreApplication>
#include <QDateTime>
#include <exception>

#ifdef Q_OS_LINUX
#include <malloc.h>
#endif

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
    , m_originalPixmapCacheLimit(QPixmapCache::cacheLimit())
    , m_processingAlbumArt(false)
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
    
    // Cancel album art processing if running
    if (m_processingAlbumArt) {
        qDebug() << "LibraryManager: Album art processing still running, waiting...";
        m_cancelRequested = true;
        // Wait for all thread pool tasks to complete
        QThreadPool::globalInstance()->waitForDone();
        qDebug() << "LibraryManager: Album art processing stopped";
    }
    
    // Clear track cache
    {
        QMutexLocker locker(&m_trackCacheMutex);
        qDeleteAll(m_trackCache);
        m_trackCache.clear();
    }
    
    // Delete virtual playlist objects
    delete m_allSongsPlaylistModel;
    delete m_allSongsPlaylist;
    
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

int LibraryManager::albumArtistCount() const
{
    // qDebug() << "LibraryManager::albumArtistCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        // qDebug() << "LibraryManager::albumArtistCount() - database not ready, returning 0";
        return 0;
    }
    int count = m_databaseManager->getTotalAlbumArtists();
    // qDebug() << "LibraryManager::albumArtistCount() returning" << count;
    return count;
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

bool LibraryManager::isProcessingAlbumArt() const
{
    return m_processingAlbumArt;
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
            // Portal paths can have different formats:
            // - /run/flatpak/doc/{hash}/{folder_name}
            // - /run/user/{uid}/doc/{hash}/{folder_name}
            // - /run/user/{uid}/doc/{hash}
            
            // Try to resolve symlinks first
            QFileInfo fileInfo(path);
            if (fileInfo.isSymLink()) {
                QString resolvedPath = fileInfo.symLinkTarget();
                if (!resolvedPath.isEmpty()) {
                    displayPath = resolvedPath;
                    qDebug() << "Resolved symlink to:" << displayPath;
                }
            } else {
                // Parse the portal path structure
                QStringList parts = path.split('/');
                if (parts.size() >= 5) {
                    // Look for the actual folder name after the hash
                    if ((parts[2] == "flatpak" && parts[3] == "doc" && parts.size() > 5) ||
                        (parts[2] == "user" && parts[4] == "doc" && parts.size() > 6)) {
                        // The last part should be the actual folder name
                        QString folderName = parts.last();
                        if (!folderName.isEmpty() && folderName.length() < 64) {
                            // Construct a user-friendly path
                            displayPath = QDir::homePath() + "/" + folderName;
                        }
                    }
                }
                
                // If we still have a portal path, use the canonical path
                if (displayPath.startsWith("/run/")) {
                    // Check if canonical path is more meaningful
                    if (!canonicalPath.startsWith("/run/")) {
                        displayPath = canonicalPath;
                    } else {
                        // Last resort: use a generic name with the last directory component
                        QString lastDir = QDir(canonicalPath).dirName();
                        if (!lastDir.isEmpty() && lastDir.length() < 64) {
                            displayPath = "Music: " + lastDir;
                        } else {
                            displayPath = "Music Folder";
                        }
                    }
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
    QString pathToRemove = path;
    
    // Check if this is a display path - if so, get the canonical path
    QString canonicalFromDisplay = getCanonicalPathFromDisplay(path);
    if (!canonicalFromDisplay.isEmpty()) {
        pathToRemove = canonicalFromDisplay;
        qDebug() << "LibraryManager::removeMusicFolder() - found canonical path from display:" << pathToRemove;
    }
    
    // Try to get canonical path from the input
    QDir dir(pathToRemove);
    QString canonicalPath = dir.canonicalPath();
    
    // If canonical path resolution failed or path doesn't exist, 
    // try to match against existing folders directly
    bool removed = false;
    if (canonicalPath.isEmpty() || !dir.exists()) {
        // Try direct match against stored paths
        for (const QString &folder : m_musicFolders) {
            if (folder == path || m_folderDisplayPaths.value(folder) == path) {
                canonicalPath = folder;
                removed = m_musicFolders.removeAll(canonicalPath) > 0;
                break;
            }
        }
    } else {
        removed = m_musicFolders.removeAll(canonicalPath) > 0;
    }
    
    if (removed) {
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
            //qDebug() << "LibraryManager::removeMusicFolder() - cache invalidated, emitting libraryChanged";
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
    
    // Set QPixmapCache limit to prevent excessive memory usage during scan
    m_originalPixmapCacheLimit = QPixmapCache::cacheLimit();
    QPixmapCache::setCacheLimit(10240); // 10MB limit during scan
    qDebug() << "Set QPixmapCache limit from" << m_originalPixmapCacheLimit << "to 10MB for scanning";
    
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
    
    // Scope the database connection to ensure proper cleanup
    {
        QSqlDatabase db = DatabaseManager::createThreadConnection(connectionName);
        
        if (!db.isOpen()) {
            qCritical() << "Failed to create thread database connection";
            DatabaseManager::removeThreadConnection(connectionName);
            return;
        }
    
    // Force WAL checkpoint to ensure this thread connection sees all committed data
    {
        QSqlQuery checkpointQuery(db);
        checkpointQuery.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        checkpointQuery.finish();
        qDebug() << "[scanInBackground] Performed WAL checkpoint to sync with main database";
    }
    
    // Log how many tracks this connection sees
    {
        QSqlQuery countQuery(db);
        if (countQuery.exec("SELECT COUNT(*) FROM tracks")) {
            if (countQuery.next()) {
                qDebug() << "[scanInBackground] Thread connection sees" << countQuery.value(0).toInt() << "tracks in database";
            }
        }
        countQuery.finish();
    }
    
    try {
        // Note: Removed transaction wrapper to fix issue with new files not being detected
        // Each database operation will be auto-committed individually
        
        
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
            pathQuery.finish();
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
                deleteQuery.finish();
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
            cleanupQuery.finish();
            
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
                    // Track already exists in database
                    qDebug() << "[" << connectionName << "] Track already exists in database, skipping:" << filePath;
                    m_filesScanned++;
                    checkQuery.finish();
                    continue;
                } else {
                    // Track not in database, will process
                    qDebug() << "[" << connectionName << "] New track found, will process:" << filePath;
                }
                checkQuery.finish();
            }
            
            // Queue metadata extraction for parallel processing
            QFuture<QVariantMap> future = QtConcurrent::run([filePath, fileInfo]() -> QVariantMap {
                try {
                    // Create a thread-local extractor to avoid threading issues
                    Mtoc::MetadataExtractor localExtractor;
                    // Skip album art extraction during bulk scanning to save memory
                    QVariantMap metadata = localExtractor.extractAsVariantMap(filePath, false);
                    
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
            
            // Periodically clear caches to prevent memory accumulation
            if (i % 500 == 0 && i > 0) {
                // Clear the artist cache if it's getting too large
                if (m_albumsByArtistCache.size() > 100) {
                    QMetaObject::invokeMethod(this, [this]() {
                        m_albumsByArtistCache.clear();
                        qDebug() << "Cleared albumsByArtistCache during scan to free memory";
                    }, Qt::QueuedConnection);
                }
                
                // Clear QPixmapCache periodically
                if (i % 1000 == 0) {
                    QMetaObject::invokeMethod(this, []() {
                        QPixmapCache::clear();
                        qDebug() << "Cleared QPixmapCache during scan to free memory";
                    }, Qt::QueuedConnection);
                }
            }
            
            // Yield to other threads more intelligently based on system load
            if (i % 100 == 0) {
                QThread::yieldCurrentThread();
            }
        }
        
        // Process any remaining extraction futures that haven't been processed
        if (!extractionFutures.isEmpty() && !m_cancelRequested) {
            qDebug() << "Processing remaining" << extractionFutures.size() << "extraction futures";
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
        
        // Process any remaining items in the batch
        if (!batchMetadata.isEmpty() && !m_cancelRequested) {
            qDebug() << "Processing final batch with" << batchMetadata.size() << "tracks";
            insertBatchTracksInThread(db, batchMetadata);
            batchMetadata.clear();
        }
        
        // No longer using transactions - each operation auto-commits
        
        // Log final track count in this connection
        {
            QSqlQuery finalCountQuery(db);
            if (finalCountQuery.exec("SELECT COUNT(*) FROM tracks")) {
                if (finalCountQuery.next()) {
                    qDebug() << "[scanInBackground] Final track count in database:" << finalCountQuery.value(0).toInt();
                }
            }
            finalCountQuery.finish();
        }
        
        qDebug() << "scanInBackground() completed successfully - scanned" << m_filesScanned << "files";
        
    } catch (const std::exception& e) {
        qCritical() << "Exception in scanInBackground():" << e.what();
    } catch (...) {
        qCritical() << "Unknown exception in scanInBackground()";
    }
    
        // Close database before removing connection
        db.close();
    } // End of database scope
    
    // Add a small delay to ensure all queries are fully released
    QThread::msleep(10);
    
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
    
    // Use swap idiom to ensure memory is actually released
    {
        QVariantList emptyList;
        m_cachedAlbumModel.swap(emptyList);
    }
    {
        QVariantList emptyList;
        m_cachedArtistModel.swap(emptyList);
    }
    {
        QHash<QString, QVariantList> emptyCache;
        m_albumsByArtistCache.swap(emptyCache);
    }
    
    qDebug() << "Album and artist model cache invalidated and cleared after scan";
    
    // Force garbage collection in QPixmapCache after scan
    QPixmapCache::clear();
    // Restore original cache limit
    QPixmapCache::setCacheLimit(m_originalPixmapCacheLimit);
    qDebug() << "QPixmapCache cleared and limit restored to" << m_originalPixmapCacheLimit;
    
    // Process events to allow Qt to clean up
    QCoreApplication::processEvents(QEventLoop::ExcludeUserInputEvents);
    
    // Force memory compaction on some platforms
#ifdef Q_OS_LINUX
    // On Linux, we can try to give memory back to the OS
    malloc_trim(0);
#endif
    
    // Use queued connections to ensure signals are emitted from main thread
    QMetaObject::invokeMethod(this, "scanningChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "scanProgressChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "scanProgressTextChanged", Qt::QueuedConnection);
    
    if (m_cancelRequested) {
        QMetaObject::invokeMethod(this, "scanCancelled", Qt::QueuedConnection);
    } else {
        QMetaObject::invokeMethod(this, "scanCompleted", Qt::QueuedConnection);
        
        // Start album art processing as a separate background task
        QThreadPool::globalInstance()->start([this]() {
            processAlbumArtInBackground();
        });
    }
    
    // Refresh all counts and models - ensure these are from main thread
    QMetaObject::invokeMethod(this, "libraryChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "trackCountChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "albumCountChanged", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "albumArtistCountChanged", Qt::QueuedConnection);
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
    emit albumArtistCountChanged();
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
    return m_allTracksModel;
}

AlbumModel* LibraryManager::allAlbumsModel() const
{
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
    
    // Only cache if the result is reasonably small and cache isn't too large
    if (albums.size() < 100 && m_albumsByArtistCache.size() < 200) {
        // If cache is getting full, remove oldest entries (simple FIFO)
        while (m_albumsByArtistCache.size() >= 200) {
            m_albumsByArtistCache.erase(m_albumsByArtistCache.begin());
        }
        m_albumsByArtistCache[artistName] = albums;
    }
    
    return albums;
}

TrackModel* LibraryManager::searchTracks(const QString &query) const
{
    TrackModel *model = new TrackModel(const_cast<LibraryManager*>(this));
    QVariantList results = m_databaseManager->searchTracks(query);
    
    return model;
}

// Stub implementations for remaining methods

TrackModel* LibraryManager::tracksForArtist(const QString &artistName) const
{
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
    return new AlbumModel(const_cast<LibraryManager*>(this));
}

QStringList LibraryManager::searchArtists(const QString &query) const
{
    return QStringList();
}

QVariantMap LibraryManager::searchAll(const QString &query) const
{
    if (!m_databaseManager) {
        return QVariantMap();
    }
    
    return m_databaseManager->searchAll(query);
}


Album* LibraryManager::albumByTitle(const QString &title, const QString &artistName) const
{
    return nullptr;
}

Artist* LibraryManager::artistByName(const QString &name) const
{
    return nullptr;
}

QVariantList LibraryManager::getAlbumsPaginated(int offset, int limit) const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return QVariantList();
    }
    
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
    
    int totalAlbums = albumCount();
    
    if (totalAlbums < 1000) {
        // For small libraries, use the full model
        return albumModel();
    } else {
        qWarning() << "Large library (" << totalAlbums << " albums) - lightweight model not yet implemented";
        return QVariantList();
    }
}

void LibraryManager::saveCarouselPosition(int albumId)
{
    QSettings settings;
    settings.setValue("carouselPosition/albumId", albumId);
    //qDebug() << "LibraryManager: Saved carousel position - album ID:" << albumId;
}

int LibraryManager::loadCarouselPosition() const
{
    QSettings settings;
    int albumId = settings.value("carouselPosition/albumId", -1).toInt();
    qDebug() << "LibraryManager: Loaded carousel position - album ID:" << albumId;
    return albumId;
}

void LibraryManager::savePlaybackState(const QString &filePath, qint64 position, 
                                       const QString &albumArtist, const QString &albumTitle, 
                                       int trackIndex, qint64 duration,
                                       bool queueModified, const QVariantList &queue,
                                       const QVariantMap &virtualPlaylistInfo,
                                       const QVariantMap &playlistInfo)
{
    QSettings settings;
    settings.beginGroup("playbackState");
    
    // Save track info
    settings.setValue("filePath", filePath);
    settings.setValue("position", position);
    settings.setValue("duration", duration);
    settings.setValue("albumArtist", albumArtist);
    settings.setValue("albumTitle", albumTitle);
    settings.setValue("trackIndex", trackIndex);
    settings.setValue("savedTime", QDateTime::currentDateTime());
    
    // Save virtual playlist info if present
    if (!virtualPlaylistInfo.isEmpty() && virtualPlaylistInfo.value("isVirtualPlaylist", false).toBool()) {
        settings.setValue("isVirtualPlaylist", true);
        settings.setValue("virtualPlaylistType", virtualPlaylistInfo.value("virtualPlaylistType"));
        settings.setValue("virtualTrackIndex", virtualPlaylistInfo.value("virtualTrackIndex"));
        settings.setValue("virtualShuffleIndex", virtualPlaylistInfo.value("virtualShuffleIndex"));
        settings.setValue("shuffleEnabled", virtualPlaylistInfo.value("shuffleEnabled"));
        
        // Save track metadata
        settings.setValue("trackTitle", virtualPlaylistInfo.value("trackTitle"));
        settings.setValue("trackArtist", virtualPlaylistInfo.value("trackArtist"));
        settings.setValue("trackAlbum", virtualPlaylistInfo.value("trackAlbum"));
        settings.setValue("trackAlbumArtist", virtualPlaylistInfo.value("trackAlbumArtist"));
    } else {
        settings.setValue("isVirtualPlaylist", false);
    }
    
    // Save playlist info if present
    if (!playlistInfo.isEmpty() && playlistInfo.contains("playlistName")) {
        settings.setValue("playlistName", playlistInfo.value("playlistName"));
    } else {
        settings.remove("playlistName");
    }
    
    // Save queue info if modified
    settings.setValue("queueModified", queueModified);
    if (queueModified && !queue.isEmpty()) {
        settings.beginWriteArray("queue");
        for (int i = 0; i < queue.size(); ++i) {
            settings.setArrayIndex(i);
            QVariantMap trackData = queue[i].toMap();
            settings.setValue("filePath", trackData["filePath"]);
            settings.setValue("title", trackData["title"]);
            settings.setValue("artist", trackData["artist"]);
            settings.setValue("album", trackData["album"]);
            settings.setValue("albumArtist", trackData["albumArtist"]);
            settings.setValue("trackNumber", trackData["trackNumber"]);
            settings.setValue("duration", trackData["duration"]);
        }
        settings.endArray();
    } else {
        // Clear any existing queue data if queue is not modified
        settings.remove("queue");
    }
    
    settings.endGroup();
    settings.sync(); // Force immediate write to disk
    
    // qDebug() << "LibraryManager: Saved playback state - file:" << filePath 
    //          << "position:" << position << "ms"
    //          << "duration:" << duration << "ms"
    //          << "album:" << albumArtist << "-" << albumTitle 
    //          << "track:" << trackIndex
    //          << "queueModified:" << queueModified
    //          << "queueSize:" << queue.size();
}

QVariantMap LibraryManager::loadPlaybackState() const
{
    QSettings settings;
    QVariantMap state;
    
    settings.beginGroup("playbackState");
    
    QString filePath = settings.value("filePath").toString();
    if (!filePath.isEmpty()) {
        // Verify the file still exists
        QFileInfo fileInfo(filePath);
        if (fileInfo.exists()) {
            state["filePath"] = filePath;
            state["position"] = settings.value("position", 0).toLongLong();
            state["duration"] = settings.value("duration", 0).toLongLong();
            state["albumArtist"] = settings.value("albumArtist").toString();
            state["albumTitle"] = settings.value("albumTitle").toString();
            state["trackIndex"] = settings.value("trackIndex", -1).toInt();
            state["savedTime"] = settings.value("savedTime").toDateTime();
            
            // Load virtual playlist info if present
            state["isVirtualPlaylist"] = settings.value("isVirtualPlaylist", false).toBool();
            if (state["isVirtualPlaylist"].toBool()) {
                state["virtualPlaylistType"] = settings.value("virtualPlaylistType").toString();
                state["virtualTrackIndex"] = settings.value("virtualTrackIndex").toInt();
                state["virtualShuffleIndex"] = settings.value("virtualShuffleIndex").toInt();
                state["shuffleEnabled"] = settings.value("shuffleEnabled").toBool();
                
                // Load track metadata
                state["trackTitle"] = settings.value("trackTitle").toString();
                state["trackArtist"] = settings.value("trackArtist").toString();
                state["trackAlbum"] = settings.value("trackAlbum").toString();
                state["trackAlbumArtist"] = settings.value("trackAlbumArtist").toString();
            }
            
            // Load playlist info if present
            QString playlistName = settings.value("playlistName").toString();
            if (!playlistName.isEmpty()) {
                state["playlistName"] = playlistName;
            }
            
            // Load queue info
            state["queueModified"] = settings.value("queueModified", false).toBool();
            
            if (state["queueModified"].toBool()) {
                QVariantList queue;
                int queueSize = settings.beginReadArray("queue");
                for (int i = 0; i < queueSize; ++i) {
                    settings.setArrayIndex(i);
                    QVariantMap trackData;
                    trackData["filePath"] = settings.value("filePath").toString();
                    trackData["title"] = settings.value("title").toString();
                    trackData["artist"] = settings.value("artist").toString();
                    trackData["album"] = settings.value("album").toString();
                    trackData["albumArtist"] = settings.value("albumArtist").toString();
                    trackData["trackNumber"] = settings.value("trackNumber").toInt();
                    trackData["duration"] = settings.value("duration").toInt();
                    
                    // Only add to queue if file still exists
                    QFileInfo trackFile(trackData["filePath"].toString());
                    if (trackFile.exists()) {
                        queue.append(trackData);
                    }
                }
                settings.endArray();
                state["queue"] = queue;
            }
            
            //qDebug() << "LibraryManager: Loaded playback state - file:" << filePath
            //         << "position:" << state["position"].toLongLong() << "ms"
            //         << "queueModified:" << state["queueModified"].toBool()
            //         << "queueSize:" << state["queue"].toList().size();
        } else {
            qDebug() << "LibraryManager: Saved track no longer exists:" << filePath;
            // Clear the invalid saved state
            settings.remove("");
        }
    } else {
        qDebug() << "LibraryManager: No saved playback state found";
    }
    
    settings.endGroup();
    
    return state;
}

void LibraryManager::clearPlaybackState()
{
    QSettings settings;
    settings.beginGroup("playbackState");
    settings.remove(""); // Removes all keys in this group
    settings.endGroup();
    settings.sync();
    
    qDebug() << "LibraryManager: Cleared playback state";
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
            int id = query.value(0).toInt();
            query.finish();
            return id;
        }
        query.finish();
        
        // Insert new artist
        query.prepare("INSERT INTO artists (name) VALUES (:name)");
        query.bindValue(":name", artistName);
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            query.finish();
            return id;
        }
        query.finish();
        
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
            int id = query.value(0).toInt();
            query.finish();
            return id;
        }
        query.finish();
        
        // Insert new album artist
        query.prepare("INSERT INTO album_artists (name) VALUES (:name)");
        query.bindValue(":name", albumArtistName);
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            query.finish();
            return id;
        }
        query.finish();
        
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
            query.finish();
            
            // Update year if provided and not already set
            if (albumYear > 0) {
                QSqlQuery updateQuery(db);
                updateQuery.prepare("UPDATE albums SET year = :year WHERE id = :id AND (year IS NULL OR year = 0)");
                updateQuery.bindValue(":year", albumYear);
                updateQuery.bindValue(":id", existingAlbumId);
                updateQuery.exec();
                updateQuery.finish();
            }
            
            return existingAlbumId;
        }
        query.finish();
        
        // Insert new album with year
        query.prepare("INSERT INTO albums (title, album_artist_id, year) VALUES (:title, :artist_id, :year)");
        query.bindValue(":title", albumName);
        query.bindValue(":artist_id", albumArtistId > 0 ? albumArtistId : QVariant());
        query.bindValue(":year", albumYear > 0 ? albumYear : QVariant());
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            query.finish();
            return id;
        }
        query.finish();
        
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
        
        // Album art processing removed from bulk scanning to save memory
        // Album art will be processed in a separate pass after initial scan
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
    query.finish();
}

void LibraryManager::insertBatchTracksInThread(QSqlDatabase& db, const QList<QVariantMap>& batchMetadata)
{
    if (batchMetadata.isEmpty() || m_cancelRequested) {
        return;
    }
    
    qDebug() << "[insertBatchTracksInThread] Starting to insert batch of" << batchMetadata.size() << "tracks";
    int successCount = 0;
    int failCount = 0;
    
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
            query.finish();
            return id;
        }
        query.finish();
        
        // Insert new artist
        query.prepare("INSERT INTO artists (name) VALUES (:name)");
        query.bindValue(":name", artistName);
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            artistCache[artistName] = id;
            query.finish();
            return id;
        }
        query.finish();
        
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
            query.finish();
            return id;
        }
        query.finish();
        
        // Insert new album artist
        query.prepare("INSERT INTO album_artists (name) VALUES (:name)");
        query.bindValue(":name", albumArtistName);
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            albumArtistCache[albumArtistName] = id;
            query.finish();
            return id;
        }
        query.finish();
        
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
            query.finish();
            
            // Update year if provided and not already set
            if (albumYear > 0) {
                QSqlQuery updateQuery(db);
                updateQuery.prepare("UPDATE albums SET year = :year WHERE id = :id AND (year IS NULL OR year = 0)");
                updateQuery.bindValue(":year", albumYear);
                updateQuery.bindValue(":id", existingAlbumId);
                updateQuery.exec();
                updateQuery.finish();
            }
            
            return existingAlbumId;
        }
        query.finish();
        
        // Insert new album with year
        query.prepare("INSERT INTO albums (title, album_artist_id, year) VALUES (:title, :artist_id, :year)");
        query.bindValue(":title", albumName);
        query.bindValue(":artist_id", albumArtistId > 0 ? albumArtistId : QVariant());
        query.bindValue(":year", albumYear > 0 ? albumYear : QVariant());
        
        if (query.exec()) {
            int id = query.lastInsertId().toInt();
            albumCache[key] = id;
            query.finish();
            return id;
        }
        query.finish();
        
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
        
        // Album art processing removed from bulk scanning to save memory
        // Album art will be processed in a separate pass after initial scan
        
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
            failCount++;
        } else {
            successCount++;
        }
    }
    
    // Finish the prepared query to release resources
    trackInsert.finish();
    
    qDebug() << "[insertBatchTracksInThread] Batch complete - Successfully inserted" << successCount 
             << "tracks, failed" << failCount << "tracks";
}

void LibraryManager::processAlbumArtInBackground()
{
    qDebug() << "LibraryManager::processAlbumArtInBackground() starting";
    
    // Set processing flag
    QMetaObject::invokeMethod(this, [this]() {
        m_processingAlbumArt = true;
        emit processingAlbumArtChanged();
    }, Qt::QueuedConnection);
    
    // Create a thread-local database connection
    QString connectionName = QString("AlbumArtThread_%1").arg(quintptr(QThread::currentThreadId()));
    
    // Scope the database connection to ensure proper cleanup
    {
        QSqlDatabase db = DatabaseManager::createThreadConnection(connectionName);
        
        if (!db.isOpen()) {
            qCritical() << "Failed to create thread database connection for album art processing";
            DatabaseManager::removeThreadConnection(connectionName);
            // Clear processing flag
            QMetaObject::invokeMethod(this, [this]() {
                m_processingAlbumArt = false;
                emit processingAlbumArtChanged();
            }, Qt::QueuedConnection);
            return;
        }
    
    try {
        // Get all albums that don't have album art yet
        QSqlQuery albumQuery(db);
        albumQuery.prepare(
            "SELECT DISTINCT a.id, a.title, aa.name as album_artist_name "
            "FROM albums a "
            "LEFT JOIN album_artists aa ON a.album_artist_id = aa.id "
            "WHERE a.id NOT IN (SELECT album_id FROM album_art) "
            "ORDER BY a.title"  // Add explicit ordering
        );
        
        if (!albumQuery.exec()) {
            qWarning() << "Failed to query albums without art:" << albumQuery.lastError().text();
            db.close();
            DatabaseManager::removeThreadConnection(connectionName);
            return;
        }
        
        // Store all albums in a list first to avoid query cursor issues
        struct AlbumInfo {
            int id;
            QString title;
            QString albumArtist;
        };
        QList<AlbumInfo> albumsToProcess;
        
        while (albumQuery.next()) {
            AlbumInfo info;
            info.id = albumQuery.value(0).toInt();
            info.title = albumQuery.value(1).toString();
            info.albumArtist = albumQuery.value(2).toString();
            albumsToProcess.append(info);
        }
        
        // Explicitly finish the query to release resources
        albumQuery.finish();
        
        int totalAlbums = albumsToProcess.size();
        
        if (totalAlbums == 0) {
            qDebug() << "LibraryManager::processAlbumArtInBackground() - No albums need art processing";
            
            db.close();
            DatabaseManager::removeThreadConnection(connectionName);
            // Clear processing flag
            QMetaObject::invokeMethod(this, [this]() {
                m_processingAlbumArt = false;
                emit processingAlbumArtChanged();
            }, Qt::QueuedConnection);
            return;
        }
        
        qDebug() << "LibraryManager::processAlbumArtInBackground() - Processing art for" << totalAlbums << "albums";
        
        int processedCount = 0;
        
        // Process albums from the list
        for (const AlbumInfo& albumInfo : albumsToProcess) {
            // Check if we should stop processing
            if (m_cancelRequested) {
                qDebug() << "LibraryManager: Album art processing cancelled";
                break;
            }
            
            int albumId = albumInfo.id;
            QString albumTitle = albumInfo.title;
            QString albumArtist = albumInfo.albumArtist;
            
            // Get a track from this album to extract art from
            QSqlQuery trackQuery(db);
            trackQuery.prepare(
                "SELECT file_path FROM tracks WHERE album_id = :album_id LIMIT 1"
            );
            trackQuery.bindValue(":album_id", albumId);
            
            if (trackQuery.exec() && trackQuery.next()) {
                QString filePath = trackQuery.value(0).toString();
                trackQuery.finish();  // Finish query before processing
                
                try {
                    // Extract album art from this track
                    Mtoc::MetadataExtractor extractor;
                    QByteArray albumArtData = extractor.extractAlbumArt(filePath);
                    
                    if (!albumArtData.isEmpty()) {
                        // Process and store album art
                        AlbumArtManager albumArtManager;
                        AlbumArtManager::ProcessedAlbumArt processed = 
                            albumArtManager.processAlbumArt(albumArtData, albumTitle, 
                                                           albumArtist, "");
                        
                        if (processed.success) {
                            // Insert album art into database
                            QSqlQuery artInsert(db);
                            artInsert.prepare(
                                "INSERT INTO album_art "
                                "(album_id, full_path, full_hash, thumbnail, thumbnail_size, "
                                "width, height, format, file_size) "
                                "VALUES (:album_id, :full_path, :full_hash, :thumbnail, :thumbnail_size, "
                                ":width, :height, :format, :file_size)"
                            );
                            
                            artInsert.bindValue(":album_id", albumId);
                            artInsert.bindValue(":full_path", processed.fullImagePath);
                            artInsert.bindValue(":full_hash", processed.hash);
                            artInsert.bindValue(":thumbnail", processed.thumbnailData);
                            artInsert.bindValue(":thumbnail_size", processed.thumbnailData.size());
                            artInsert.bindValue(":width", processed.originalSize.width());
                            artInsert.bindValue(":height", processed.originalSize.height());
                            artInsert.bindValue(":format", processed.format);
                            artInsert.bindValue(":file_size", processed.fileSize);
                            
                            if (!artInsert.exec()) {
                                qWarning() << "Failed to insert album art for album:" << albumTitle 
                                          << "-" << artInsert.lastError().text();
                            } else {
                                qDebug() << "Successfully processed album art for:" << albumTitle;
                                processedCount++;
                            }
                            artInsert.finish();
                        }
                    }
                    
                    // Clear album art data immediately to free memory
                    albumArtData.clear();
                    albumArtData.squeeze(); // Force deallocation
                } catch (const std::exception& e) {
                    qWarning() << "Exception processing album art for" << albumTitle << ":" << e.what();
                } catch (...) {
                    qWarning() << "Unknown exception processing album art for" << albumTitle;
                }
            } else {
                qDebug() << "No track found for album:" << albumTitle << "- skipping album art";
            }
            
            // Emit update signal periodically (every 10 albums processed)
            if (processedCount > 0 && processedCount % 10 == 0) {
                QMetaObject::invokeMethod(this, [this]() {
                    m_albumModelCacheValid = false;
                    emit libraryChanged();
                    // qDebug() << "LibraryManager: Emitted libraryChanged after processing batch of album art";
                }, Qt::QueuedConnection);
            }
            
            // Add debug logging every 20 albums
            if ((processedCount + 1) % 20 == 0) {
                qDebug() << "Progress: Processed" << processedCount << "of" << totalAlbums << "albums. Current:" << albumTitle;
            }
            
            // Yield to other threads periodically
            QThread::yieldCurrentThread();
        }
        
        qDebug() << "LibraryManager::processAlbumArtInBackground() completed -" << processedCount << "albums processed";
        
        // Emit final update if we processed any albums
        if (processedCount > 0) {
            QMetaObject::invokeMethod(this, [this]() {
                m_albumModelCacheValid = false;
                m_cachedAlbumModel.clear();
                emit libraryChanged();
                // qDebug() << "LibraryManager: Emitted final libraryChanged after album art processing";
            }, Qt::QueuedConnection);
        }
        
    } catch (const std::exception& e) {
        qCritical() << "Exception in processAlbumArtInBackground():" << e.what();
    } catch (...) {
        qCritical() << "Unknown exception in processAlbumArtInBackground()";
    }
    
        // Close database before removing connection
        db.close();
    } // End of database scope
    
    // Add a small delay to ensure all queries are fully released
    QThread::msleep(10);
    
    // Clean up thread-local database connection
    DatabaseManager::removeThreadConnection(connectionName);
    
    // Clear processing flag
    QMetaObject::invokeMethod(this, [this]() {
        m_processingAlbumArt = false;
        emit processingAlbumArtChanged();
    }, Qt::QueuedConnection);
}

VirtualPlaylistModel* LibraryManager::getAllSongsPlaylist()
{
    if (!m_allSongsPlaylistModel) {
        // Create virtual playlist on first access
        m_allSongsPlaylist = new VirtualPlaylist(m_databaseManager, this);
        m_allSongsPlaylistModel = new VirtualPlaylistModel(this);
        m_allSongsPlaylistModel->setVirtualPlaylist(m_allSongsPlaylist);
        
        // Start loading tracks asynchronously
        m_allSongsPlaylist->loadAllTracks();
    }
    
    return m_allSongsPlaylistModel;
}

bool LibraryManager::isTrackInLibrary(const QString &filePath) const
{
    if (filePath.isEmpty()) {
        return false;
    }
    
    // Check cache first
    {
        QMutexLocker locker(&m_trackCacheMutex);
        if (m_trackCache.contains(filePath)) {
            return true;
        }
    }
    
    // Check database
    return m_databaseManager->trackExists(filePath);
}

Track* LibraryManager::trackByPath(const QString &path) const
{
    if (path.isEmpty() || !m_databaseManager || !m_databaseManager->isOpen()) {
        return nullptr;
    }
    
    // Check cache first
    {
        QMutexLocker locker(&m_trackCacheMutex);
        if (m_trackCache.contains(path)) {
            return m_trackCache.value(path);
        }
    }
    
    // Not in cache, load from database
    int trackId = m_databaseManager->getTrackIdByPath(path);
    if (trackId <= 0) {
        return nullptr;
    }
    
    QVariantMap trackData = m_databaseManager->getTrack(trackId);
    if (trackData.isEmpty()) {
        return nullptr;
    }
    
    // Create new track object using fromMetadata with this as parent
    Track* track = Track::fromMetadata(trackData, const_cast<LibraryManager*>(this));
    
    // Add to cache with size limit
    {
        QMutexLocker locker(&m_trackCacheMutex);
        
        // If cache is full, remove oldest entries (simple FIFO)
        if (m_trackCache.size() >= MAX_TRACK_CACHE_SIZE) {
            // Remove about 10% of cache
            int toRemove = MAX_TRACK_CACHE_SIZE / 10;
            auto it = m_trackCache.begin();
            while (toRemove > 0 && it != m_trackCache.end()) {
                delete it.value();
                it = m_trackCache.erase(it);
                toRemove--;
            }
        }
        
        m_trackCache.insert(path, track);
    }
    
    return track;
}

QString LibraryManager::getCanonicalPathFromDisplay(const QString& displayPath) const
{
    // Check if any canonical path maps to this display path
    for (auto it = m_folderDisplayPaths.begin(); it != m_folderDisplayPaths.end(); ++it) {
        if (it.value() == displayPath) {
            return it.key();
        }
    }
    
    // Not found in display mappings
    return QString();
}

} // namespace Mtoc