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

#include "track.h"
#include "album.h"
#include "artist.h"
#include "trackmodel.h"
#include "albummodel.h"
#include "../utility/metadataextractor.h"
#include "../database/databasemanager.h"
#include "albumartmanager.h"

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
    Q_PROPERTY(int artistCount READ artistCount NOTIFY artistCountChanged)
    Q_PROPERTY(QVariantList artistModel READ artistModel NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList albumModel READ albumModel NOTIFY libraryChanged)

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
    int artistCount() const;
    QVariantList artistModel() const;
    QVariantList albumModel() const;
    
    // Property setters
    void setMusicFolders(const QStringList &folders);
    
    // Library management methods
    Q_INVOKABLE bool addMusicFolder(const QString &path);
    Q_INVOKABLE bool removeMusicFolder(const QString &path);
    Q_INVOKABLE void startScan();
    Q_INVOKABLE void cancelScan();
    Q_INVOKABLE void clearLibrary();
    
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
    
    // Access to database manager (for image provider)
    DatabaseManager* databaseManager() const { return m_databaseManager; }
    
    // Carousel persistence methods
    Q_INVOKABLE void saveCarouselPosition(int albumId);
    Q_INVOKABLE int loadCarouselPosition() const;

signals:
    void scanningChanged();
    void scanProgressChanged();
    void scanProgressTextChanged();
    void scanCompleted();
    void scanCancelled();
    void musicFoldersChanged();
    void trackCountChanged();
    void albumCountChanged();
    void artistCountChanged();
    void libraryChanged();

private slots:
    void onScanFinished();

private:
    // Utility methods
    QStringList findMusicFiles(const QString &dir);
    void processDirectory(const QString &dir, QStringList &musicFiles);
    bool isMusicFile(const QFileInfo &fileInfo) const;
    void initializeDatabase();
    void syncWithDatabase(const QString &filePath);
    void scanInBackground();
    void insertTrackInThread(QSqlDatabase& db, const QVariantMap& metadata);
    void insertBatchTracksInThread(QSqlDatabase& db, const QList<QVariantMap>& batchMetadata);
    void processAlbumArtInBackground();
    
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
    int m_originalPixmapCacheLimit;  // Store original cache limit to restore after scan
};

} // namespace Mtoc

#endif // LIBRARYMANAGER_H