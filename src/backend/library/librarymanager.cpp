#include "librarymanager.h"
#include <QDebug>
#include <QDirIterator>
#include <QStandardPaths>
#include <QTimer>
#include <QFileInfo>
#include <QThread>
#include <QMutexLocker>
#include <exception>

namespace Mtoc {

LibraryManager::LibraryManager(QObject *parent)
    : QObject(parent)
    , m_databaseManager(new DatabaseManager(this))
    , m_allTracksModel(new TrackModel(this))
    , m_allAlbumsModel(new AlbumModel(this))
    , m_scanning(false)
    , m_scanProgress(0)
    , m_totalFilesToScan(0)
    , m_filesScanned(0)
    , m_cancelRequested(false)
{
    qDebug() << "LibraryManager: Constructor started";
    
    // Initialize database
    initializeDatabase();
    
    qDebug() << "LibraryManager: Database initialized";
    
    // Default to the user's Music folder if available
    QStringList musicDirs = QStandardPaths::standardLocations(QStandardPaths::MusicLocation);
    if (!musicDirs.isEmpty()) {
        m_musicFolders << musicDirs.first();
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
    
    qDebug() << "LibraryManager: About to load library from database";
    
    // Load library from database
    loadLibraryFromDatabase();
    
    qDebug() << "LibraryManager: Library loaded from database";
    
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
    
    // Database is automatically closed by DatabaseManager destructor
    qDebug() << "LibraryManager: Clearing library data...";
    
    // Clear all data
    clearLibrary();
    
    qDebug() << "LibraryManager: Destructor completed";
}

void LibraryManager::initializeDatabase()
{
    if (!m_databaseManager->initializeDatabase()) {
        qCritical() << "Failed to initialize database!";
    }
}

void LibraryManager::loadLibraryFromDatabase()
{
    if (!m_databaseManager->isOpen()) {
        qWarning() << "Database not open, cannot load library";
        return;
    }
    
    // Clear existing in-memory data
    qDeleteAll(m_tracks);
    m_tracks.clear();
    qDeleteAll(m_albums);
    m_albums.clear();
    qDeleteAll(m_artists);
    m_artists.clear();
    
    // For now, we'll load data on-demand rather than loading everything into memory
    // This is more efficient for large libraries
    
    emit libraryChanged();
    emit trackCountChanged();
    emit albumCountChanged();
    emit artistCountChanged();
}

// Property getters
bool LibraryManager::isScanning() const
{
    qDebug() << "LibraryManager::isScanning() called, returning" << m_scanning;
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
    qDebug() << "LibraryManager::musicFolders() called, returning" << m_musicFolders.size() << "folders";
    return m_musicFolders;
}

int LibraryManager::trackCount() const
{
    qDebug() << "LibraryManager::trackCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "LibraryManager::trackCount() - database not ready, returning 0";
        return 0;
    }
    int count = m_databaseManager->getTotalTracks();
    qDebug() << "LibraryManager::trackCount() returning" << count;
    return count;
}

int LibraryManager::albumCount() const
{
    qDebug() << "LibraryManager::albumCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "LibraryManager::albumCount() - database not ready, returning 0";
        return 0;
    }
    int count = m_databaseManager->getTotalAlbums();
    qDebug() << "LibraryManager::albumCount() returning" << count;
    return count;
}

int LibraryManager::artistCount() const
{
    qDebug() << "LibraryManager::artistCount() called";
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "LibraryManager::artistCount() - database not ready, returning 0";
        return 0;
    }
    int count = m_databaseManager->getTotalArtists();
    qDebug() << "LibraryManager::artistCount() returning" << count;
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
    if (!m_musicFolders.contains(canonicalPath)) {
        m_musicFolders.append(canonicalPath);
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
        emit musicFoldersChanged();
        // TODO: Remove tracks from this folder from the library
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
    m_pendingFiles.clear();
    
    qDebug() << "Emitting scan state change signals...";
    emit scanningChanged();
    emit scanProgressChanged();
    emit scanProgressTextChanged();
    
    qDebug() << "Starting database transaction...";
    // Start transaction for better performance
    if (!m_databaseManager->beginTransaction()) {
        qWarning() << "Failed to start database transaction";
        m_scanning = false;
        emit scanningChanged();
        return;
    }
    
    // Clear pending tracks
    m_pendingTracks.clear();
    
    qDebug() << "Starting QtConcurrent task...";
    // Start async scanning - but serialize all operations to avoid TagLib threading issues
    try {
        m_scanFuture = QtConcurrent::run([this]() {
            qDebug() << "QtConcurrent task started";
            scanInBackground();
        });
        
        qDebug() << "Setting up future watcher...";
        m_scanWatcher.setFuture(m_scanFuture);
        qDebug() << "LibraryManager::startScan() completed successfully";
    } catch (const std::exception& e) {
        qCritical() << "Exception starting scan:" << e.what();
        m_scanning = false;
        emit scanningChanged();
        m_databaseManager->rollbackTransaction();
    } catch (...) {
        qCritical() << "Unknown exception starting scan";
        m_scanning = false;
        emit scanningChanged();
        m_databaseManager->rollbackTransaction();
    }
}

void LibraryManager::scanInBackground()
{
    qDebug() << "scanInBackground() starting";
    
    try {
        // Find all music files
        QStringList allFiles;
        for (const QString &folder : m_musicFolders) {
            allFiles.append(findMusicFiles(folder));
            
            if (m_cancelRequested) {
                break;
            }
        }
        
        m_totalFilesToScan = allFiles.size();
        qDebug() << "Found" << m_totalFilesToScan << "music files to scan";
        
        // Create a single metadata extractor for this thread
        Mtoc::MetadataExtractor threadExtractor;
        
        // Process files in batches for better database performance
        const int batchSize = 50; // Batch size for database operations
        QList<QVariantMap> batchMetadata;
        
        for (int i = 0; i < allFiles.size() && !m_cancelRequested; ++i) {
            const QString &filePath = allFiles[i];
            QFileInfo fileInfo(filePath);
            
            // Check if file exists
            if (!fileInfo.exists()) {
                continue;
            }
            
            // Check if already in database before extracting metadata
            {
                QMutexLocker locker(&m_databaseMutex);
                if (m_databaseManager->trackExists(filePath)) {
                    m_filesScanned++;
                    continue;
                }
            }
            
            // Extract metadata (serialized to avoid TagLib threading issues)
            try {
                QVariantMap metadata = threadExtractor.extractAsVariantMap(filePath);
                
                // Validate metadata before using
                if (metadata.isEmpty() || !metadata.contains("filePath")) {
                    qWarning() << "Invalid metadata extracted from" << filePath;
                    m_filesScanned++;
                    continue;
                }
                
                // Add file info to metadata
                metadata["fileSize"] = fileInfo.size();
                metadata["fileModified"] = fileInfo.lastModified();
                metadata["filePath"] = filePath;
                
                // Add to batch
                batchMetadata.append(metadata);
            } catch (const std::exception& e) {
                qWarning() << "Error extracting metadata from" << filePath << ":" << e.what();
                m_filesScanned++;
                continue;
            } catch (...) {
                qWarning() << "Unknown error extracting metadata from" << filePath;
                m_filesScanned++;
                continue;
            }
            
            // Update scanned count after successful extraction
            m_filesScanned++;
            
            // Insert batch when it reaches the batch size or at the end
            if (batchMetadata.size() >= batchSize || i == allFiles.size() - 1) {
                // Insert batch into database
                {
                    QMutexLocker locker(&m_databaseMutex);
                    for (const QVariantMap &metadata : batchMetadata) {
                        if (m_cancelRequested) {
                            break;
                        }
                        m_databaseManager->insertTrack(metadata);
                    }
                }
                batchMetadata.clear();
            }
            
            // Update progress
            int newProgress = (m_filesScanned * 100) / m_totalFilesToScan;
            if (newProgress != m_scanProgress) {
                m_scanProgress = newProgress;
                QMetaObject::invokeMethod(this, "scanProgressChanged", Qt::QueuedConnection);
                QMetaObject::invokeMethod(this, "scanProgressTextChanged", Qt::QueuedConnection);
            }
            
            // Occasionally allow other threads to run
            if (i % 100 == 0) {
                QThread::msleep(1);
            }
        }
        
        qDebug() << "scanInBackground() completed successfully";
    } catch (const std::exception& e) {
        qCritical() << "Exception in scanInBackground():" << e.what();
    } catch (...) {
        qCritical() << "Unknown exception in scanInBackground()";
    }
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
    
    // Commit transaction
    m_databaseManager->commitTransaction();
    
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
    
    // Clear in-memory data
    qDeleteAll(m_tracks);
    m_tracks.clear();
    qDeleteAll(m_albums);
    m_albums.clear();
    qDeleteAll(m_artists);
    m_artists.clear();
    
    // Clear models
    m_allTracksModel->clear();
    m_allAlbumsModel->clear();
    
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
        return QVariantList();
    }
    return m_databaseManager->getAllArtists();
}

QVariantList LibraryManager::albumModel() const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return QVariantList();
    }
    return m_databaseManager->getAllAlbums();
}

TrackModel* LibraryManager::searchTracks(const QString &query) const
{
    TrackModel *model = new TrackModel();
    QVariantList results = m_databaseManager->searchTracks(query);
    
    // TODO: Convert QVariantList to Track objects and add to model
    
    return model;
}

// Stub implementations for remaining methods
// These would need to be fully implemented based on your specific needs

TrackModel* LibraryManager::tracksForArtist(const QString &artistName) const
{
    // TODO: Implement
    return new TrackModel();
}

AlbumModel* LibraryManager::albumsForArtist(const QString &artistName) const
{
    AlbumModel *model = new AlbumModel();
    
    // Get albums from database
    QVariantList albumData = m_databaseManager->getAlbumsByAlbumArtistName(artistName);
    
    // Convert QVariantList to Album objects
    for (const QVariant &v : albumData) {
        QVariantMap albumMap = v.toMap();
        
        // Create Album object
        Album *album = new Album(
            albumMap["title"].toString(),
            artistName  // Use the album artist name
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
    return new TrackModel();
}

QVariantList LibraryManager::getTracksForAlbumAsVariantList(const QString &artistName, const QString &albumTitle) const
{
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        return QVariantList();
    }
    return m_databaseManager->getTracksByAlbumAndArtist(albumTitle, artistName);
}

AlbumModel* LibraryManager::searchAlbums(const QString &query) const
{
    // TODO: Implement
    return new AlbumModel();
}

QStringList LibraryManager::searchArtists(const QString &query) const
{
    // TODO: Implement
    return QStringList();
}

Track* LibraryManager::trackByPath(const QString &path) const
{
    return m_tracks.value(path, nullptr);
}

Album* LibraryManager::albumByTitle(const QString &title, const QString &artistName) const
{
    QString key = artistName.isEmpty() ? title : artistName + ":" + title;
    return m_albums.value(key, nullptr);
}

Artist* LibraryManager::artistByName(const QString &name) const
{
    return m_artists.value(name, nullptr);
}

Track* LibraryManager::processFile(const QString &filePath)
{
    // This method is now replaced by syncWithDatabase
    return nullptr;
}

void LibraryManager::addTrackToLibrary(Track *track)
{
    // This is now handled by the database
}

Album* LibraryManager::findOrCreateAlbum(const QString &title, const QString &artistName)
{
    // This is now handled by the database
    return nullptr;
}

Artist* LibraryManager::findOrCreateArtist(const QString &name)
{
    // This is now handled by the database
    return nullptr;
}

void LibraryManager::processScannedFiles()
{
    // This is now handled differently with the database approach
}

} // namespace Mtoc