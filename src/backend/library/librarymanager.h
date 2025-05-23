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

namespace Mtoc {

class LibraryManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool scanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)
    Q_PROPERTY(QString scanProgressText READ scanProgressText NOTIFY scanProgressTextChanged)
    Q_PROPERTY(QStringList musicFolders READ musicFolders WRITE setMusicFolders NOTIFY musicFoldersChanged)
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
    
    // Search methods
    Q_INVOKABLE TrackModel* searchTracks(const QString &query) const;
    Q_INVOKABLE AlbumModel* searchAlbums(const QString &query) const;
    Q_INVOKABLE QStringList searchArtists(const QString &query) const;
    
    // Direct data access (for advanced usage)
    Q_INVOKABLE Track* trackByPath(const QString &path) const;
    Q_INVOKABLE Album* albumByTitle(const QString &title, const QString &artistName = QString()) const;
    Q_INVOKABLE Artist* artistByName(const QString &name) const;

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
    
    // Detailed signals for UI updates during scanning
    void trackAdded(Track *track);
    void albumAdded(Album *album);
    void artistAdded(Artist *artist);

private slots:
    void processScannedFiles();
    void onScanFinished();

private:
    // Utility methods
    QStringList findMusicFiles(const QString &dir);
    void processDirectory(const QString &dir, QStringList &musicFiles);
    bool isMusicFile(const QFileInfo &fileInfo) const;
    Track* processFile(const QString &filePath);
    void addTrackToLibrary(Track *track);
    Album* findOrCreateAlbum(const QString &title, const QString &artistName);
    Artist* findOrCreateArtist(const QString &name);
    void initializeDatabase();
    void loadLibraryFromDatabase();
    void syncWithDatabase(const QString &filePath);
    void scanInBackground();
    void insertTrackInThread(QSqlDatabase& db, const QVariantMap& metadata);
    
    // Private data
    MetadataExtractor m_metadataExtractor;
    DatabaseManager *m_databaseManager;
    QStringList m_musicFolders;
    QMap<QString, Track*> m_tracks;      // Path -> Track
    QMap<QString, Album*> m_albums;      // "Artist:Album" -> Album
    QMap<QString, Artist*> m_artists;    // Name -> Artist
    mutable QMutex m_databaseMutex;     // Protect database access
    QList<QVariantMap> m_pendingTracks; // Tracks waiting to be inserted
    mutable QMutex m_pendingTracksMutex; // Protect pending tracks list
    
    // Models for UI
    TrackModel *m_allTracksModel;
    AlbumModel *m_allAlbumsModel;
    
    // Scanning state
    bool m_scanning;
    int m_scanProgress;
    int m_totalFilesToScan;
    int m_filesScanned;
    QStringList m_pendingFiles;
    QMutex m_pendingFilesMutex;
    QFuture<void> m_scanFuture;
    QFutureWatcher<void> m_scanWatcher;
    bool m_cancelRequested;
};

} // namespace Mtoc

#endif // LIBRARYMANAGER_H