#ifndef LIBRARYMANAGER_H
#define LIBRARYMANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QMap>
#include <QDir>
#include <QFileInfo>
#include <QThread>
#include <QMutex>
#include <QFuture>
#include <QFutureWatcher>
#include <QtConcurrent>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QSet>

#include "track.h"
#include "album.h"
#include "artist.h"
#include "trackmodel.h"
#include "albummodel.h"
#include "../utility/metadataextractor.h"
#include "../database/databasemanager.h"
#include "albumartmanager.h"
#include "../playlist/VirtualPlaylist.h"
#include "../playlist/VirtualPlaylistModel.h"

namespace Mtoc {

class LibraryManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool scanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)
    Q_PROPERTY(QString scanProgressText READ scanProgressText NOTIFY scanProgressTextChanged)
    Q_PROPERTY(QStringList musicFolders READ musicFolders WRITE setMusicFolders NOTIFY musicFoldersChanged)
    Q_PROPERTY(QStringList musicFoldersDisplay READ musicFoldersDisplay NOTIFY musicFoldersChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY trackCountChanged)
    Q_PROPERTY(int albumCount READ albumCount NOTIFY albumCountChanged)
    Q_PROPERTY(int albumArtistCount READ albumArtistCount NOTIFY albumArtistCountChanged)
    Q_PROPERTY(int artistCount READ artistCount NOTIFY artistCountChanged)
    Q_PROPERTY(QVariantList artistModel READ artistModel NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList albumModel READ albumModel NOTIFY libraryChanged)
    Q_PROPERTY(bool processingAlbumArt READ isProcessingAlbumArt NOTIFY processingAlbumArtChanged)
    Q_PROPERTY(bool rebuildingThumbnails READ isRebuildingThumbnails NOTIFY rebuildingThumbnailsChanged)
    Q_PROPERTY(int rebuildProgress READ rebuildProgress NOTIFY rebuildProgressChanged)
    Q_PROPERTY(QString rebuildProgressText READ rebuildProgressText NOTIFY rebuildProgressTextChanged)
    Q_PROPERTY(bool autoRefreshOnStartup READ autoRefreshOnStartup WRITE setAutoRefreshOnStartup NOTIFY autoRefreshOnStartupChanged)
    Q_PROPERTY(bool watchFileChanges READ watchFileChanges WRITE setWatchFileChanges NOTIFY watchFileChangesChanged)

public:
    explicit LibraryManager(QObject *parent = nullptr);
    ~LibraryManager();
    
    // Property getters
    bool isScanning() const;
    int scanProgress() const;
    QString scanProgressText() const;
    QStringList musicFolders() const;
    QStringList musicFoldersDisplay() const;
    int trackCount() const;
    int albumCount() const;
    int albumArtistCount() const;
    int artistCount() const;
    QVariantList artistModel() const;
    QVariantList albumModel() const;
    bool isProcessingAlbumArt() const;
    bool isRebuildingThumbnails() const;
    int rebuildProgress() const;
    QString rebuildProgressText() const;
    bool autoRefreshOnStartup() const;
    bool watchFileChanges() const;

    // Property setters
    void setMusicFolders(const QStringList &folders);
    void setAutoRefreshOnStartup(bool enabled);
    void setWatchFileChanges(bool enabled);
    void setForceMetadataUpdate(bool force);

    // Library management methods
    Q_INVOKABLE bool addMusicFolder(const QString &path);
    Q_INVOKABLE bool removeMusicFolder(const QString &path);
    Q_INVOKABLE void startScan();
    Q_INVOKABLE void refreshLibrary();  // Smart incremental scan
    Q_INVOKABLE void cancelScan();
    Q_INVOKABLE void resetLibrary();    // Nuclear option - clears everything
    Q_INVOKABLE void clearLibrary();    // Deprecated - kept for compatibility
    Q_INVOKABLE void rebuildAllThumbnails();
    
    // Data access methods
    Q_INVOKABLE TrackModel* allTracksModel() const;
    Q_INVOKABLE AlbumModel* allAlbumsModel() const;
    Q_INVOKABLE QStringList allArtists() const;
    Q_INVOKABLE TrackModel* tracksForArtist(const QString &artistName) const;
    Q_INVOKABLE AlbumModel* albumsForArtist(const QString &artistName) const;
    Q_INVOKABLE TrackModel* tracksForAlbum(const QString &albumTitle, const QString &artistName = QString()) const;
    Q_INVOKABLE QVariantList getTracksForAlbumAsVariantList(const QString &artistName, const QString &albumTitle) const;
    Q_INVOKABLE QVariantList getAlbumsForArtist(const QString &artistName) const;
    Q_INVOKABLE QVariantList getAlbumsPaginated(int offset, int limit) const;
    Q_INVOKABLE void preloadAlbumsForArtists(const QStringList &artistNames) const;
    Q_INVOKABLE QVariantList getLightweightAlbumModel() const;
    
    // Search methods
    Q_INVOKABLE TrackModel* searchTracks(const QString &query) const;
    Q_INVOKABLE AlbumModel* searchAlbums(const QString &query) const;
    Q_INVOKABLE QStringList searchArtists(const QString &query) const;
    Q_INVOKABLE QVariantMap searchAll(const QString &query) const;
    
    // Direct data access (for advanced usage)
    Q_INVOKABLE Track* trackByPath(const QString &path) const;
    Q_INVOKABLE Album* albumByTitle(const QString &title, const QString &artistName = QString()) const;
    Q_INVOKABLE Artist* artistByName(const QString &name) const;
    
    // Virtual playlist support
    Q_INVOKABLE VirtualPlaylistModel* getAllSongsPlaylist();
    Q_INVOKABLE bool isTrackInLibrary(const QString &filePath) const;
    
    // Access to database manager (for image provider)
    DatabaseManager* databaseManager() const { return m_databaseManager; }
    
    // Carousel persistence methods
    Q_INVOKABLE void saveCarouselPosition(int albumId);
    Q_INVOKABLE int loadCarouselPosition() const;
    
    // Playback state persistence methods
    Q_INVOKABLE void savePlaybackState(const QString &filePath, qint64 position, 
                                       const QString &albumArtist, const QString &albumTitle, 
                                       int trackIndex, qint64 duration,
                                       bool queueModified = false, const QVariantList &queue = QVariantList(),
                                       const QVariantMap &virtualPlaylistInfo = QVariantMap(),
                                       const QVariantMap &playlistInfo = QVariantMap());
    Q_INVOKABLE QVariantMap loadPlaybackState() const;
    Q_INVOKABLE void clearPlaybackState();

signals:
    void scanningChanged();
    void scanProgressChanged();
    void scanProgressTextChanged();
    void scanCompleted();
    void scanCancelled();
    void musicFoldersChanged();
    void trackCountChanged();
    void albumCountChanged();
    void albumArtistCountChanged();
    void artistCountChanged();
    void libraryChanged();
    void processingAlbumArtChanged();
    void rebuildingThumbnailsChanged();
    void rebuildProgressChanged();
    void rebuildProgressTextChanged();
    void thumbnailsRebuilt();
    void autoRefreshOnStartupChanged();
    void watchFileChangesChanged();
    void trackLyricsUpdated(QString filePath, QString lyrics);  // Emitted when track lyrics are updated
    void aboutToInvalidateLibrary();  // Emitted BEFORE clearing virtual playlists during library updates

private slots:
    void onScanFinished();
    void onDirectoryChanged(const QString &path);
    void onFileChanged(const QString &path);
    void onWatcherDebounceTimeout();

private:
    // Utility methods
    QStringList findMusicFiles(const QString &dir);
    void processDirectory(const QString &dir, QStringList &musicFiles);
    bool isMusicFile(const QFileInfo &fileInfo) const;
    void initializeDatabase();
    void syncWithDatabase(const QString &filePath);
    void scanInBackground();
    void scanSpecificPathsInBackground(const QStringList &paths);
    void insertTrackInThread(QSqlDatabase& db, const QVariantMap& metadata);
    void insertBatchTracksInThread(QSqlDatabase& db, const QList<QVariantMap>& batchMetadata, bool forceUpdate = false);
    void processAlbumArtInBackground();
    QString getCanonicalPathFromDisplay(const QString& displayPath) const;
    void rebuildThumbnailsInBackground();
    void setupFileWatcher();
    void updateFileWatcher();
    QStringList getAllSubdirectories(const QString &rootPath) const;
    void updateLyricsForTrack(const QString &audioFilePath);
    void processLrcFileChanges(const QString &directoryPath);
    QStringList findAudioFilesForLrc(const QString &lrcFilePath, const QStringList &audioFiles) const;

    // Private data
    DatabaseManager *m_databaseManager;
    AlbumArtManager *m_albumArtManager;
    QStringList m_musicFolders;
    QMap<QString, QString> m_folderDisplayPaths;  // canonical path -> display path
    mutable QMutex m_databaseMutex;     // Protect database access
    
    // Cache for performance
    mutable QVariantList m_cachedAlbumModel;
    mutable bool m_albumModelCacheValid;
    mutable QHash<QString, QVariantList> m_albumsByArtistCache;  // Artist name -> albums
    mutable int m_cachedAlbumCount;  // Cache the total album count
    mutable bool m_albumCountCacheValid;
    mutable QVariantList m_cachedArtistModel;  // Cache for artist model
    mutable bool m_artistModelCacheValid;
    
    // Track cache for efficiency
    mutable QHash<QString, Track*> m_trackCache;  // FilePath -> Track
    mutable QMutex m_trackCacheMutex;
    static const int MAX_TRACK_CACHE_SIZE = 10000;  // Limit cache size
    
    // Virtual playlist support
    VirtualPlaylist* m_allSongsPlaylist = nullptr;
    VirtualPlaylistModel* m_allSongsPlaylistModel = nullptr;
    
    // Models for UI
    TrackModel *m_allTracksModel;
    AlbumModel *m_allAlbumsModel;
    
    // Scanning state
    bool m_scanning;
    int m_scanProgress;
    int m_totalFilesToScan;
    int m_filesScanned;
    QFuture<void> m_scanFuture;
    QFutureWatcher<void> m_scanWatcher;
    bool m_cancelRequested;
    bool m_forceMetadataUpdate;  // Force re-extraction of metadata for existing files
    int m_originalPixmapCacheLimit;  // Store original cache limit to restore after scan
    bool m_processingAlbumArt;  // Track album art processing status
    
    // Thumbnail rebuild state
    bool m_rebuildingThumbnails;
    int m_rebuildProgress;
    int m_totalAlbumsToRebuild;
    int m_albumsRebuilt;
    QFuture<void> m_rebuildFuture;
    QFutureWatcher<void> m_rebuildWatcher;

    // File watcher for automatic library updates
    QFileSystemWatcher* m_fileWatcher;
    QTimer* m_watcherDebounceTimer;
    QSet<QString> m_pendingChangedPaths;
    bool m_autoRefreshOnStartup;
    bool m_watchFileChanges;
    static const int WATCHER_DEBOUNCE_MS = 2000;
    static const int MAX_WATCHED_DIRS = 5000;  // Practical limit for inotify
};

} // namespace Mtoc

#endif // LIBRARYMANAGER_H