#include "librarymanager.h"
#include <QDebug>
#include <QDirIterator>
#include <QStandardPaths>
#include <QTimer>

namespace Mtoc {

LibraryManager::LibraryManager(QObject *parent)
    : QObject(parent)
    , m_allTracksModel(new TrackModel(this))
    , m_allAlbumsModel(new AlbumModel(this))
    , m_scanning(false)
    , m_scanProgress(0)
    , m_totalFilesToScan(0)
    , m_filesScanned(0)
    , m_cancelRequested(false)
{
    // Default to the user's Music folder if available
    QStringList musicDirs = QStandardPaths::standardLocations(QStandardPaths::MusicLocation);
    if (!musicDirs.isEmpty()) {
        m_musicFolders << musicDirs.first();
    }
    
    // Load any previously saved library
    // loadLibraryFromDisk(); // Uncomment when implemented
}

LibraryManager::~LibraryManager()
{
    // Cancel any ongoing scan
    cancelScan();
    
    // Save library state
    // saveLibraryToDisk(); // Uncomment when implemented
    
    // Clear all data
    clearLibrary();
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

QStringList LibraryManager::musicFolders() const
{
    return m_musicFolders;
}

int LibraryManager::trackCount() const
{
    return m_tracks.count();
}

int LibraryManager::albumCount() const
{
    return m_albums.count();
}

int LibraryManager::artistCount() const
{
    return m_artists.count();
}

QVariantList LibraryManager::artistModel() const
{
    QVariantList result;
    
    // Create a sorted list of artists (alphabetically by name)
    QStringList artistNames = m_artists.keys();
    std::sort(artistNames.begin(), artistNames.end(), [](const QString &a, const QString &b) {
        return a.toLower() < b.toLower(); // Case-insensitive sorting
    });
    
    // Convert to a list of artist objects with needed properties
    for (const QString &name : artistNames) {
        Artist *artist = m_artists.value(name);
        if (artist) {
            QVariantMap artistMap;
            artistMap["name"] = artist->name();
            artistMap["albumCount"] = artist->albumCount();
            artistMap["trackCount"] = artist->trackCount();
            
            // Get the image from the first album if available
            QList<Album*> albums = artist->albums();
            if (!albums.isEmpty()) {
                artistMap["image"] = albums.first()->coverArtUrl().toString();
            } else {
                artistMap["image"] = "";
            }
            
            // Add this artist to the result
            result.append(artistMap);
        }
    }
    
    return result;
}

QVariantList LibraryManager::albumModel() const
{
    QVariantList result;
    
    // Collect all albums
    QList<Album*> albums = m_albums.values();
    
    // Sort albums by artist (alphabetically) then by year (newest first)
    std::sort(albums.begin(), albums.end(), [](Album *a, Album *b) {
        // First sort by artist name (case insensitive)
        int artistCompare = a->artist().toLower().compare(b->artist().toLower());
        if (artistCompare != 0) {
            return artistCompare < 0;
        }
        
        // Then sort by year (newest first)
        if (a->year() != b->year()) {
            return a->year() > b->year();
        }
        
        // If same year, sort by title
        return a->title().toLower() < b->title().toLower();
    });
    
    // Convert to list of album objects
    for (Album *album : albums) {
        QVariantMap albumMap;
        albumMap["title"] = album->title();
        albumMap["artist"] = album->artist();
        albumMap["year"] = album->year();
        albumMap["trackCount"] = album->trackCount();
        albumMap["image"] = album->coverArtUrl().toString();
        
        result.append(albumMap);
    }
    
    return result;
}

QString LibraryManager::scanProgressText() const
{
    if (!m_scanning) {
        return QString();
    }
    
    if (m_totalFilesToScan == 0) {
        return tr("Finding files...");
    }
    
    return tr("%1 of %2 files processed").arg(m_filesScanned).arg(m_totalFilesToScan);
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
        qWarning() << "Cannot add non-existent folder:" << path;
        return false;
    }
    
    if (!m_musicFolders.contains(path)) {
        m_musicFolders.append(path);
        emit musicFoldersChanged();
        return true;
    }
    
    return false; // Already in the list
}

bool LibraryManager::removeMusicFolder(const QString &path)
{
    if (m_musicFolders.removeOne(path)) {
        emit musicFoldersChanged();
        return true;
    }
    
    return false; // Not in the list
}

void LibraryManager::startScan()
{
    if (m_scanning) {
        qWarning() << "Scan already in progress";
        return;
    }
    
    if (m_musicFolders.isEmpty()) {
        qWarning() << "No music folders to scan";
        return;
    }
    
    m_scanning = true;
    m_cancelRequested = false;
    m_scanProgress = 0;
    m_totalFilesToScan = 0;
    m_filesScanned = 0;
    m_pendingFiles.clear();
    
    emit scanningChanged();
    emit scanProgressChanged();
    emit scanProgressTextChanged();
    
    // Find all music files in background thread
    m_scanFuture = QtConcurrent::run([this]() {
        QStringList allMusicFiles;
        
        // Find all music files in all folders
        for (const QString &folder : m_musicFolders) {
            if (m_cancelRequested)
                break;
            
            processDirectory(folder, allMusicFiles);
        }
        
        if (!m_cancelRequested) {
            m_totalFilesToScan = allMusicFiles.count();
            
            // Process files in batches
            m_pendingFilesMutex.lock();
            m_pendingFiles = allMusicFiles;
            m_pendingFilesMutex.unlock();
            
            // Start processing files
            QMetaObject::invokeMethod(this, "processScannedFiles", Qt::QueuedConnection);
        }
    });
    
    // Use QFutureWatcher to monitor the scan operation
    m_scanWatcher.setFuture(m_scanFuture);
    connect(&m_scanWatcher, &QFutureWatcher<void>::finished, this, &LibraryManager::onScanFinished);
}

void LibraryManager::cancelScan()
{
    if (!m_scanning)
        return;
    
    m_cancelRequested = true;
    
    // Wait for the future to complete
    if (m_scanFuture.isRunning()) {
        // Disconnect watcher to prevent onScanFinished from being called
        disconnect(&m_scanWatcher, &QFutureWatcher<void>::finished, this, &LibraryManager::onScanFinished);
        // Wait for the future to complete
        m_scanWatcher.waitForFinished();
    }
    
    m_scanning = false;
    emit scanningChanged();
    emit scanCancelled();
}

void LibraryManager::clearLibrary()
{
    // Cancel any ongoing scan
    cancelScan();
    
    // Clear all models
    m_allTracksModel->clear();
    m_allAlbumsModel->clear();
    
    // Delete all tracks, albums, and artists
    qDeleteAll(m_tracks);
    qDeleteAll(m_albums);
    qDeleteAll(m_artists);
    
    // Clear the maps
    m_tracks.clear();
    m_albums.clear();
    m_artists.clear();
    
    emit trackCountChanged();
    emit albumCountChanged();
    emit artistCountChanged();
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
    return m_artists.keys();
}

TrackModel* LibraryManager::tracksForArtist(const QString &artistName) const
{
    Artist *artist = artistByName(artistName);
    if (!artist)
        return nullptr;
    
    TrackModel *model = new TrackModel();
    
    // Add all tracks from all albums by this artist
    for (Album *album : artist->albums()) {
        for (Track *track : album->tracks()) {
            model->addTrack(track);
        }
    }
    
    // Sort by album, then track number
    model->sortByAlbum();
    
    return model;
}

AlbumModel* LibraryManager::albumsForArtist(const QString &artistName) const
{
    Artist *artist = artistByName(artistName);
    if (!artist)
        return nullptr;
    
    AlbumModel *model = new AlbumModel();
    
    // Add all albums by this artist
    for (Album *album : artist->albums()) {
        model->addAlbum(album);
    }
    
    // Sort by year (newer first)
    model->sortByYear();
    
    return model;
}

TrackModel* LibraryManager::tracksForAlbum(const QString &albumTitle, const QString &artistName) const
{
    Album *album = albumByTitle(albumTitle, artistName);
    if (!album)
        return nullptr;
    
    TrackModel *model = new TrackModel();
    
    // Add all tracks from this album
    for (Track *track : album->tracks()) {
        model->addTrack(track);
    }
    
    // Sort by track number
    model->sortByTrackNumber();
    
    return model;
}

// Search methods
TrackModel* LibraryManager::searchTracks(const QString &query) const
{
    if (query.isEmpty())
        return nullptr;
    
    TrackModel *results = new TrackModel();
    QString lowerQuery = query.toLower();
    
    // Search all tracks
    for (Track *track : m_tracks.values()) {
        if (track->title().toLower().contains(lowerQuery) ||
            track->artist().toLower().contains(lowerQuery) ||
            track->album().toLower().contains(lowerQuery) ||
            track->genre().toLower().contains(lowerQuery))
        {
            results->addTrack(track);
        }
    }
    
    return results;
}

AlbumModel* LibraryManager::searchAlbums(const QString &query) const
{
    if (query.isEmpty())
        return nullptr;
    
    AlbumModel *results = new AlbumModel();
    QString lowerQuery = query.toLower();
    
    // Search all albums
    for (Album *album : m_albums.values()) {
        if (album->title().toLower().contains(lowerQuery) ||
            album->artist().toLower().contains(lowerQuery) ||
            album->genre().toLower().contains(lowerQuery))
        {
            results->addAlbum(album);
        }
    }
    
    return results;
}

QStringList LibraryManager::searchArtists(const QString &query) const
{
    if (query.isEmpty())
        return QStringList();
    
    QStringList results;
    QString lowerQuery = query.toLower();
    
    // Search all artist names
    for (const QString &artistName : m_artists.keys()) {
        if (artistName.toLower().contains(lowerQuery)) {
            results.append(artistName);
        }
    }
    
    return results;
}

// Direct data access methods
Track* LibraryManager::trackByPath(const QString &path) const
{
    return m_tracks.value(path, nullptr);
}

Album* LibraryManager::albumByTitle(const QString &title, const QString &artistName) const
{
    if (artistName.isEmpty()) {
        // Look for albums with matching title (might have duplicates from different artists)
        for (Album *album : m_albums.values()) {
            if (album->title() == title) {
                return album;
            }
        }
        return nullptr;
    }
    
    // Look for specific album by title and artist
    QString key = artistName + ":" + title;
    return m_albums.value(key, nullptr);
}

Artist* LibraryManager::artistByName(const QString &name) const
{
    return m_artists.value(name, nullptr);
}

// Private slots
void LibraryManager::processScannedFiles()
{
    if (m_cancelRequested) {
        return;
    }
    
    constexpr int BATCH_SIZE = 10; // Process 10 files at a time
    
    QStringList filesToProcess;
    m_pendingFilesMutex.lock();
    for (int i = 0; i < BATCH_SIZE && !m_pendingFiles.isEmpty(); ++i) {
        filesToProcess.append(m_pendingFiles.takeFirst());
    }
    m_pendingFilesMutex.unlock();
    
    if (filesToProcess.isEmpty()) {
        // All files processed
        if (!m_cancelRequested) {
            m_scanning = false;
            m_scanProgress = 100;
            emit scanningChanged();
            emit scanProgressChanged();
            emit scanCompleted();
            emit libraryChanged();
        }
        return;
    }
    
    // Process the batch of files
    for (const QString &filePath : filesToProcess) {
        if (m_cancelRequested)
            break;
        
        Track *track = processFile(filePath);
        if (track) {
            addTrackToLibrary(track);
        }
        
        m_filesScanned++;
        
        // Update progress
        int newProgress = (m_totalFilesToScan > 0) ? 
            static_cast<int>((static_cast<double>(m_filesScanned) / m_totalFilesToScan) * 100) : 0;
            
        if (newProgress != m_scanProgress) {
            m_scanProgress = newProgress;
            emit scanProgressChanged();
            emit scanProgressTextChanged();
        }
    }
    
    // Schedule next batch
    if (!m_cancelRequested) {
        QTimer::singleShot(0, this, &LibraryManager::processScannedFiles);
    }
}

void LibraryManager::onScanFinished()
{
    // If cancelled, just update UI state
    if (m_cancelRequested) {
        m_scanning = false;
        emit scanningChanged();
        emit scanCancelled();
    }
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
    while (it.hasNext()) {
        if (m_cancelRequested)
            break;
            
        QString filePath = it.next();
        QFileInfo fileInfo(filePath);
        
        if (fileInfo.isFile() && isMusicFile(fileInfo)) {
            musicFiles.append(filePath);
        }
    }
}

bool LibraryManager::isMusicFile(const QFileInfo &fileInfo) const
{
    // List of common audio file extensions
    static const QStringList audioExtensions = {
        "mp3", "m4a", "flac", "ogg", "wav", "aac", "wma", "aiff", "ape", "opus"
    };
    
    return audioExtensions.contains(fileInfo.suffix().toLower());
}

Track* LibraryManager::processFile(const QString &filePath)
{
    // Skip if track already exists
    if (m_tracks.contains(filePath))
        return m_tracks[filePath];
    
    // Extract metadata using our MetadataExtractor
    QVariantMap metadata = m_metadataExtractor.extractAsVariantMap(filePath);
    
    // Create Track object from metadata
    Track *track = Track::fromMetadata(metadata, this);
    
    // Ensure track has a valid file URL
    if (track->fileUrl().isEmpty()) {
        track->setFileUrl(QUrl::fromLocalFile(filePath));
    }
    
    return track;
}

void LibraryManager::addTrackToLibrary(Track *track)
{
    if (!track || !track->isValid())
        return;
    
    // Skip if already in library
    QString trackPath = track->filePath();
    if (m_tracks.contains(trackPath))
        return;
    
    // Add to tracks map
    m_tracks[trackPath] = track;
    
    // Add to all tracks model
    m_allTracksModel->addTrack(track);
    
    // Organize into album and artist
    Album *album = findOrCreateAlbum(track->album(), track->albumArtist());
    album->addTrack(track);
    
    // Add to all albums model if new album
    if (!m_allAlbumsModel->albums().contains(album)) {
        m_allAlbumsModel->addAlbum(album);
    }
    
    // Emit signals
    emit trackAdded(track);
    emit trackCountChanged();
}

Album* LibraryManager::findOrCreateAlbum(const QString &title, const QString &artistName)
{
    // Skip if title or artist is empty
    if (title.isEmpty() || artistName.isEmpty())
        return nullptr;
    
    // Create a unique key for the album
    QString key = artistName + ":" + title;
    
    // Return existing album if found
    if (m_albums.contains(key))
        return m_albums[key];
    
    // Create a new album
    Album *album = new Album(title, artistName, this);
    m_albums[key] = album;
    
    // Find or create the artist and add this album
    Artist *artist = findOrCreateArtist(artistName);
    artist->addAlbum(album);
    
    // Emit signal
    emit albumAdded(album);
    emit albumCountChanged();
    
    return album;
}

Artist* LibraryManager::findOrCreateArtist(const QString &name)
{
    // Skip if name is empty
    if (name.isEmpty())
        return nullptr;
    
    // Return existing artist if found
    if (m_artists.contains(name))
        return m_artists[name];
    
    // Create a new artist
    Artist *artist = new Artist(name, this);
    m_artists[name] = artist;
    
    // Emit signal
    emit artistAdded(artist);
    emit artistCountChanged();
    
    return artist;
}

void LibraryManager::saveLibraryToDisk()
{
    // TODO: Implement library persistence
    // This could save a list of folders, tracks, and organization structure
    // For v1 this could be skipped and implemented in a future version
}

void LibraryManager::loadLibraryFromDisk()
{
    // TODO: Implement library loading from disk
    // This would restore a previously saved library
    // For v1 this could be skipped and implemented in a future version
}

} // namespace Mtoc