#include "librarymanager.h"
#include <QDebug>
#include <QDirIterator>
#include <QStandardPaths>
#include <QTimer>
#include <QFileInfo>
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
    return m_musicFolders;
}

int LibraryManager::trackCount() const
{
    return m_databaseManager->getTotalTracks();
}

int LibraryManager::albumCount() const
{
    return m_databaseManager->getTotalAlbums();
}

int LibraryManager::artistCount() const
{
    return m_databaseManager->getTotalArtists();
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
    QDir dir(path);
    if (!dir.exists()) {
        qWarning() << "Music folder does not exist:" << path;
        return false;
    }
    
    QString canonicalPath = dir.canonicalPath();
    if (!m_musicFolders.contains(canonicalPath)) {
        m_musicFolders.append(canonicalPath);
        emit musicFoldersChanged();
        return true;
    }
    
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
    if (m_scanning) {
        qDebug() << "Scan already in progress";
        return;
    }
    
    m_scanning = true;
    m_scanProgress = 0;
    m_filesScanned = 0;
    m_cancelRequested = false;
    m_pendingFiles.clear();
    
    emit scanningChanged();
    emit scanProgressChanged();
    emit scanProgressTextChanged();
    
    // Start transaction for better performance
    m_databaseManager->beginTransaction();
    
    // Process files in the main thread to avoid threading issues
    QTimer::singleShot(0, this, [this]() {
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
        
        // Process files one at a time with event processing
        m_filesScanned = 0;
        processNextFile(allFiles);
    });
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
    m_scanning = false;
    m_scanProgress = 100;
    
    // Commit transaction
    m_databaseManager->commitTransaction();
    
    emit scanningChanged();
    emit scanProgressChanged();
    emit scanProgressTextChanged();
    
    if (m_cancelRequested) {
        emit scanCancelled();
    } else {
        emit scanCompleted();
    }
    
    // Refresh all counts and models
    emit libraryChanged();
    emit trackCountChanged();
    emit albumCountChanged();
    emit artistCountChanged();
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
    QFileInfo fileInfo(filePath);
    
    // Check if file still exists
    if (!fileInfo.exists()) {
        // Remove from database if it exists there
        int trackId = m_databaseManager->getTrackIdByPath(filePath);
        if (trackId > 0) {
            m_databaseManager->deleteTrack(trackId);
        }
        return;
    }
    
    // Check if file is already in database and hasn't been modified
    if (m_databaseManager->trackExists(filePath)) {
        // TODO: Check file modification time and update if needed
        return;
    }
    
    // Extract metadata - create a local extractor to avoid thread issues
    Mtoc::MetadataExtractor localExtractor;
    QVariantMap metadata = localExtractor.extractAsVariantMap(filePath);
    
    // Add file info to metadata
    metadata["fileSize"] = fileInfo.size();
    metadata["fileModified"] = fileInfo.lastModified();
    
    // Insert into database
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
    QVariantList artistData = m_databaseManager->getAllArtists();
    
    for (const QVariant &v : artistData) {
        QVariantMap artist = v.toMap();
        artists << artist["name"].toString();
    }
    
    return artists;
}

QVariantList LibraryManager::artistModel() const
{
    return m_databaseManager->getAllArtists();
}

QVariantList LibraryManager::albumModel() const
{
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

void LibraryManager::processNextFile(const QStringList &files)
{
    if (m_cancelRequested || m_filesScanned >= files.size()) {
        // Scanning complete or cancelled
        onScanFinished();
        return;
    }
    
    // Process one file
    const QString &filePath = files.at(m_filesScanned);
    
    try {
        syncWithDatabase(filePath);
    } catch (const std::exception& e) {
        qWarning() << "Error processing file" << filePath << ":" << e.what();
    } catch (...) {
        qWarning() << "Unknown error processing file" << filePath;
    }
    
    m_filesScanned++;
    
    // Update progress
    int newProgress = (m_filesScanned * 100) / m_totalFilesToScan;
    if (newProgress != m_scanProgress) {
        m_scanProgress = newProgress;
        emit scanProgressChanged();
        emit scanProgressTextChanged();
    }
    
    // Process next file after a small delay to prevent UI freezing
    QTimer::singleShot(1, this, [this, files]() {
        processNextFile(files);
    });
}

} // namespace Mtoc