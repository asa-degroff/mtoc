#ifndef DATABASEMANAGER_H
#define DATABASEMANAGER_H

#include <QObject>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QVariantMap>
#include <QMutex>
#include <memory>

namespace Mtoc {

class DatabaseManager : public QObject
{
    Q_OBJECT
public:
    explicit DatabaseManager(QObject *parent = nullptr);
    ~DatabaseManager();

    // Database initialization
    bool initializeDatabase(const QString& dbPath = QString());
    bool isOpen() const;
    void close();

    // Track operations
    bool insertTrack(const QVariantMap& trackData);
    bool updateTrack(int trackId, const QVariantMap& trackData);
    bool deleteTrack(int trackId);
    bool deleteTracksByFolderPath(const QString& folderPath);
    QVariantMap getTrack(int trackId);
    QVariantList getTracksByAlbum(int albumId);
    QVariantList getTracksByArtist(int artistId);
    QVariantList getTracksByAlbumAndArtist(const QString& albumTitle, const QString& albumArtistName);
    QVariantList getAllTracks(int limit = -1, int offset = 0);
    int getTrackCount();

    // Favorites operations
    bool setTrackFavorite(int trackId, bool favorite);
    bool isTrackFavorite(int trackId);
    QVariantList getFavoriteTracks();
    int getFavoriteTrackCount();
    qint64 getFavoritesTotalDuration();
    int findTrackByMetadata(const QString& artist, const QString& album, const QString& title, int trackNumber);
    
    // Album operations
    int insertOrGetAlbum(const QString& albumName, int albumArtistId, int albumYear = 0);
    bool insertAlbumArtistLinks(int albumId, const QStringList& albumArtistNames);
    QVariantMap getAlbum(int albumId);
    QVariantMap getAlbumByTitleAndArtist(const QString& albumTitle, const QString& albumArtist);
    QVariantList getAllAlbums();
    QVariantList getAlbumsByAlbumArtist(int albumArtistId);
    QVariantList getAlbumsByAlbumArtistName(const QString& albumArtistName);
    int getAlbumIdByArtistAndTitle(const QString& albumArtist, const QString& albumTitle);
    
    // Artist operations
    int insertOrGetArtist(const QString& artistName);
    int insertOrGetAlbumArtist(const QString& albumArtistName);
    QVariantMap getArtist(int artistId);
    QVariantList getAllArtists();
    int getAlbumArtistIdByName(const QString& albumArtistName);
    
    // Search operations
    QVariantList searchTracks(const QString& searchTerm);
    QVariantList searchAlbums(const QString& searchTerm);
    QVariantList searchArtists(const QString& searchTerm);
    
    // Combined search with priority results
    QVariantMap searchAll(const QString& searchTerm);
    
    // Library management
    bool clearDatabase();
    int getTotalTracks();
    int getTotalAlbums();
    int getTotalAlbumArtists();
    int getTotalArtists();
    qint64 getTotalDuration(); // Total duration in seconds
    
    // Check if file already exists in database
    bool trackExists(const QString& filePath);
    int getTrackIdByPath(const QString& filePath);
    QStringList getAllTracksFilePaths();
    
    // Batch operations
    bool beginTransaction();
    bool commitTransaction();
    bool rollbackTransaction();
    
    // Thread-safe operations
    static QSqlDatabase createThreadConnection(const QString& connectionName);
    static void removeThreadConnection(const QString& connectionName);
    
    // Helper for accent-insensitive search
    static QString normalizeForSearch(const QString& text);
    
    // Album art operations
    bool insertAlbumArt(int albumId, const QString& fullPath, const QString& hash,
                       const QByteArray& thumbnail, int width, int height,
                       const QString& format, qint64 fileSize);
    QVariantMap getAlbumArt(int albumId);
    bool albumArtExists(int albumId);
    QString getAlbumArtPath(int albumId);
    QByteArray getAlbumArtThumbnail(int albumId);
    bool updateAlbumThumbnail(int albumId, const QByteArray& thumbnailData);
    QList<int> getAllAlbumIdsWithArt();

    // Listen operations (for local playback history)
    int insertListen(const QVariantMap& listenData);
    QVariantList getRecentListens(int limit = 50, int offset = 0);
    QVariantList getValidRecentListens(int limit = 50);  // Filters out deleted tracks
    int getListenCount();
    bool clearListens();

    // Online scrobbling operations - commented out until online scrobbling is implemented
    // QVariantList getPendingListens(const QString& service);
    // bool markListenSubmitted(int listenId, const QString& service);
    // bool updateListenError(int listenId, const QString& error);
    // int getPendingListenCount(const QString& service);

signals:
    void databaseError(const QString& error);
    void trackAdded(int trackId);
    void trackUpdated(int trackId);
    void trackDeleted(int trackId);

private:
    bool createTables();
    bool createIndexes();
    bool applyMigrations(int currentVersion);
    QString getDatabasePath() const;
    void logError(const QString& operation, const QSqlQuery& query);
    
    QSqlDatabase m_db;
    QMutex m_databaseMutex;
    static const QString DB_CONNECTION_NAME;
};

} // namespace Mtoc

#endif // DATABASEMANAGER_H