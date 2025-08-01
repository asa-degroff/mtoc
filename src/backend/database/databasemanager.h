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
    
    // Album operations
    int insertOrGetAlbum(const QString& albumName, int albumArtistId, int albumYear = 0);
    QVariantMap getAlbum(int albumId);
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
    
    // Album art operations
    bool insertAlbumArt(int albumId, const QString& fullPath, const QString& hash, 
                       const QByteArray& thumbnail, int width, int height, 
                       const QString& format, qint64 fileSize);
    QVariantMap getAlbumArt(int albumId);
    bool albumArtExists(int albumId);
    QString getAlbumArtPath(int albumId);
    QByteArray getAlbumArtThumbnail(int albumId);

signals:
    void databaseError(const QString& error);
    void trackAdded(int trackId);
    void trackUpdated(int trackId);
    void trackDeleted(int trackId);

private:
    bool createTables();
    bool createIndexes();
    QString getDatabasePath() const;
    void logError(const QString& operation, const QSqlQuery& query);
    
    QSqlDatabase m_db;
    QMutex m_databaseMutex;
    static const QString DB_CONNECTION_NAME;
};

} // namespace Mtoc

#endif // DATABASEMANAGER_H