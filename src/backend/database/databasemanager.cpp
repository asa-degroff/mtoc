#include "databasemanager.h"
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QVariant>

namespace Mtoc {

const QString DatabaseManager::DB_CONNECTION_NAME = "MtocMusicLibrary";

DatabaseManager::DatabaseManager(QObject *parent)
    : QObject(parent)
{
}

DatabaseManager::~DatabaseManager()
{
    qDebug() << "DatabaseManager: Destructor called";
    close();
    qDebug() << "DatabaseManager: Destructor completed";
}

bool DatabaseManager::initializeDatabase(const QString& dbPath)
{
    qDebug() << "DatabaseManager: initializeDatabase called";
    
    QString path = dbPath;
    if (path.isEmpty()) {
        path = getDatabasePath();
    }
    
    qDebug() << "DatabaseManager: Database path:" << path;
    
    // Ensure directory exists
    QDir dir = QFileInfo(path).dir();
    if (!dir.exists()) {
        qDebug() << "DatabaseManager: Creating directory:" << dir.path();
        dir.mkpath(".");
    }
    
    m_db = QSqlDatabase::addDatabase("QSQLITE", DB_CONNECTION_NAME);
    m_db.setDatabaseName(path);
    
    if (!m_db.open()) {
        qCritical() << "Failed to open database:" << m_db.lastError().text();
        emit databaseError(m_db.lastError().text());
        return false;
    }
    
    // Enable foreign keys
    QSqlQuery query(m_db);
    query.exec("PRAGMA foreign_keys = ON");
    
    // Optimize SQLite for better performance
    query.exec("PRAGMA journal_mode = WAL");
    query.exec("PRAGMA synchronous = NORMAL");
    query.exec("PRAGMA cache_size = -64000"); // 64MB cache
    query.exec("PRAGMA temp_store = MEMORY");
    
    if (!createTables()) {
        return false;
    }
    
    if (!createIndexes()) {
        return false;
    }
    
    qDebug() << "Database initialized successfully at:" << path;
    return true;
}

bool DatabaseManager::isOpen() const
{
    return m_db.isOpen();
}

void DatabaseManager::close()
{
    if (m_db.isOpen()) {
        qDebug() << "DatabaseManager: Closing database...";
        m_db.close();
    }
    
    // Remove the connection after a small delay to ensure all operations are complete
    if (QSqlDatabase::contains(DB_CONNECTION_NAME)) {
        QSqlDatabase::removeDatabase(DB_CONNECTION_NAME);
        qDebug() << "DatabaseManager: Database connection removed";
    }
}

bool DatabaseManager::createTables()
{
    QSqlQuery query(m_db);
    
    // Artists table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS artists ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT NOT NULL UNIQUE,"
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        ")")) {
        logError("Create artists table", query);
        return false;
    }
    
    // Album artists table (separate to handle compilations properly)
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS album_artists ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT NOT NULL UNIQUE,"
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        ")")) {
        logError("Create album_artists table", query);
        return false;
    }
    
    // Albums table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS albums ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "title TEXT NOT NULL,"
        "album_artist_id INTEGER,"
        "year INTEGER,"
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "FOREIGN KEY (album_artist_id) REFERENCES album_artists(id) ON DELETE SET NULL,"
        "UNIQUE(title, album_artist_id)"
        ")")) {
        logError("Create albums table", query);
        return false;
    }
    
    // Tracks table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS tracks ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "file_path TEXT NOT NULL UNIQUE,"
        "title TEXT,"
        "artist_id INTEGER,"
        "album_id INTEGER,"
        "genre TEXT,"
        "year INTEGER,"
        "track_number INTEGER,"
        "disc_number INTEGER,"
        "duration INTEGER," // in seconds
        "file_size INTEGER,"
        "file_modified TIMESTAMP,"
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "last_played TIMESTAMP,"
        "play_count INTEGER DEFAULT 0,"
        "rating INTEGER DEFAULT 0,"
        "FOREIGN KEY (artist_id) REFERENCES artists(id) ON DELETE SET NULL,"
        "FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE SET NULL"
        ")")) {
        logError("Create tracks table", query);
        return false;
    }
    
    // Playlists table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS playlists ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "name TEXT NOT NULL UNIQUE,"
        "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        ")")) {
        logError("Create playlists table", query);
        return false;
    }
    
    // Playlist tracks table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS playlist_tracks ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "playlist_id INTEGER NOT NULL,"
        "track_id INTEGER NOT NULL,"
        "position INTEGER NOT NULL,"
        "FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,"
        "FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE,"
        "UNIQUE(playlist_id, position)"
        ")")) {
        logError("Create playlist_tracks table", query);
        return false;
    }
    
    return true;
}

bool DatabaseManager::createIndexes()
{
    QSqlQuery query(m_db);
    
    // Performance indexes
    query.exec("CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_albums_artist ON albums(album_artist_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_playlist_tracks ON playlist_tracks(playlist_id, position)");
    
    // Full-text search indexes
    query.exec("CREATE INDEX IF NOT EXISTS idx_tracks_search ON tracks(title, genre)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_artists_name ON artists(name)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_albums_title ON albums(title)");
    
    return true;
}

bool DatabaseManager::insertTrack(const QVariantMap& trackData)
{
    if (!m_db.isOpen()) return false;
    
    // Extract data
    QString filePath = trackData.value("filePath").toString();
    QString title = trackData.value("title").toString();
    QString artist = trackData.value("artist").toString();
    QString albumArtist = trackData.value("albumArtist").toString();
    QString album = trackData.value("album").toString();
    QString genre = trackData.value("genre").toString();
    int year = trackData.value("year").toInt();
    int trackNumber = trackData.value("trackNumber").toInt();
    int discNumber = trackData.value("discNumber").toInt();
    int duration = trackData.value("duration").toInt();
    qint64 fileSize = trackData.value("fileSize", 0).toLongLong();
    QDateTime fileModified = trackData.value("fileModified").toDateTime();
    
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
        albumId = insertOrGetAlbum(album, albumArtistId);
    }
    
    // Insert track
    QSqlQuery query(m_db);
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
        logError("Insert track", query);
        return false;
    }
    
    int trackId = query.lastInsertId().toInt();
    emit trackAdded(trackId);
    
    return true;
}

bool DatabaseManager::updateTrack(int trackId, const QVariantMap& trackData)
{
    if (!m_db.isOpen()) return false;
    
    // Build dynamic update query based on provided fields
    QStringList setClauses;
    QVariantMap bindValues;
    
    if (trackData.contains("title")) {
        setClauses << "title = :title";
        bindValues[":title"] = trackData.value("title");
    }
    
    if (trackData.contains("artist")) {
        QString artist = trackData.value("artist").toString();
        int artistId = artist.isEmpty() ? 0 : insertOrGetArtist(artist);
        setClauses << "artist_id = :artist_id";
        bindValues[":artist_id"] = artistId > 0 ? artistId : QVariant();
    }
    
    if (trackData.contains("album") || trackData.contains("albumArtist")) {
        QString album = trackData.value("album").toString();
        QString albumArtist = trackData.value("albumArtist").toString();
        
        int albumArtistId = 0;
        if (!albumArtist.isEmpty()) {
            albumArtistId = insertOrGetAlbumArtist(albumArtist);
        }
        
        int albumId = 0;
        if (!album.isEmpty()) {
            albumId = insertOrGetAlbum(album, albumArtistId);
        }
        
        setClauses << "album_id = :album_id";
        bindValues[":album_id"] = albumId > 0 ? albumId : QVariant();
    }
    
    if (trackData.contains("genre")) {
        setClauses << "genre = :genre";
        bindValues[":genre"] = trackData.value("genre");
    }
    
    if (trackData.contains("year")) {
        setClauses << "year = :year";
        int year = trackData.value("year").toInt();
        bindValues[":year"] = year > 0 ? year : QVariant();
    }
    
    if (trackData.contains("trackNumber")) {
        setClauses << "track_number = :track_number";
        int trackNumber = trackData.value("trackNumber").toInt();
        bindValues[":track_number"] = trackNumber > 0 ? trackNumber : QVariant();
    }
    
    if (trackData.contains("discNumber")) {
        setClauses << "disc_number = :disc_number";
        int discNumber = trackData.value("discNumber").toInt();
        bindValues[":disc_number"] = discNumber > 0 ? discNumber : QVariant();
    }
    
    if (setClauses.isEmpty()) {
        return true; // Nothing to update
    }
    
    QString sql = QString("UPDATE tracks SET %1 WHERE id = :id").arg(setClauses.join(", "));
    
    QSqlQuery query(m_db);
    query.prepare(sql);
    query.bindValue(":id", trackId);
    
    for (auto it = bindValues.begin(); it != bindValues.end(); ++it) {
        query.bindValue(it.key(), it.value());
    }
    
    if (!query.exec()) {
        logError("Update track", query);
        return false;
    }
    
    emit trackUpdated(trackId);
    return true;
}

bool DatabaseManager::deleteTrack(int trackId)
{
    if (!m_db.isOpen()) return false;
    
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM tracks WHERE id = :id");
    query.bindValue(":id", trackId);
    
    if (!query.exec()) {
        logError("Delete track", query);
        return false;
    }
    
    emit trackDeleted(trackId);
    return true;
}

QVariantMap DatabaseManager::getTrack(int trackId)
{
    QVariantMap track;
    if (!m_db.isOpen()) return track;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT t.*, a.name as artist_name, al.title as album_title, "
        "aa.name as album_artist_name "
        "FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "LEFT JOIN albums al ON t.album_id = al.id "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "WHERE t.id = :id"
    );
    query.bindValue(":id", trackId);
    
    if (query.exec() && query.next()) {
        track["id"] = query.value("id");
        track["filePath"] = query.value("file_path");
        track["title"] = query.value("title");
        track["artist"] = query.value("artist_name");
        track["album"] = query.value("album_title");
        track["albumArtist"] = query.value("album_artist_name");
        track["genre"] = query.value("genre");
        track["year"] = query.value("year");
        track["trackNumber"] = query.value("track_number");
        track["discNumber"] = query.value("disc_number");
        track["duration"] = query.value("duration");
        track["playCount"] = query.value("play_count");
        track["rating"] = query.value("rating");
        track["lastPlayed"] = query.value("last_played");
    }
    
    return track;
}

QVariantList DatabaseManager::getTracksByAlbumAndArtist(const QString& albumTitle, const QString& albumArtistName)
{
    QVariantList tracks;
    if (!m_db.isOpen()) return tracks;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT t.*, a.name as artist_name, al.title as album_title, "
        "aa.name as album_artist_name "
        "FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "LEFT JOIN albums al ON t.album_id = al.id "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "WHERE al.title = :album_title AND aa.name = :album_artist "
        "ORDER BY t.disc_number, t.track_number, t.title"
    );
    query.bindValue(":album_title", albumTitle);
    query.bindValue(":album_artist", albumArtistName);
    
    if (query.exec()) {
        while (query.next()) {
            QVariantMap track;
            track["id"] = query.value("id");
            track["filePath"] = query.value("file_path");
            track["title"] = query.value("title");
            track["artist"] = query.value("artist_name");
            track["album"] = query.value("album_title");
            track["albumArtist"] = query.value("album_artist_name");
            track["genre"] = query.value("genre");
            track["year"] = query.value("year");
            track["trackNumber"] = query.value("track_number");
            track["discNumber"] = query.value("disc_number");
            track["duration"] = query.value("duration");
            tracks.append(track);
        }
    } else {
        logError("Get tracks by album and artist", query);
    }
    
    return tracks;
}

int DatabaseManager::insertOrGetArtist(const QString& artistName)
{
    if (!m_db.isOpen() || artistName.isEmpty()) return 0;
    
    QSqlQuery query(m_db);
    
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
    
    logError("Insert or get artist", query);
    return 0;
}

int DatabaseManager::insertOrGetAlbumArtist(const QString& albumArtistName)
{
    if (!m_db.isOpen() || albumArtistName.isEmpty()) return 0;
    
    QSqlQuery query(m_db);
    
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
    
    logError("Insert or get album artist", query);
    return 0;
}

int DatabaseManager::insertOrGetAlbum(const QString& albumName, int albumArtistId)
{
    if (!m_db.isOpen() || albumName.isEmpty()) return 0;
    
    QSqlQuery query(m_db);
    
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
        return query.value(0).toInt();
    }
    
    // Insert new album
    query.prepare("INSERT INTO albums (title, album_artist_id) VALUES (:title, :artist_id)");
    query.bindValue(":title", albumName);
    query.bindValue(":artist_id", albumArtistId > 0 ? albumArtistId : QVariant());
    
    if (query.exec()) {
        return query.lastInsertId().toInt();
    }
    
    logError("Insert or get album", query);
    return 0;
}

bool DatabaseManager::trackExists(const QString& filePath)
{
    if (!m_db.isOpen()) return false;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT id FROM tracks WHERE file_path = :path");
    query.bindValue(":path", filePath);
    
    return query.exec() && query.next();
}

int DatabaseManager::getTrackIdByPath(const QString& filePath)
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT id FROM tracks WHERE file_path = :path");
    query.bindValue(":path", filePath);
    
    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

QVariantList DatabaseManager::searchTracks(const QString& searchTerm)
{
    QVariantList results;
    if (!m_db.isOpen() || searchTerm.isEmpty()) return results;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT t.*, a.name as artist_name, al.title as album_title "
        "FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "LEFT JOIN albums al ON t.album_id = al.id "
        "WHERE t.title LIKE :search "
        "OR a.name LIKE :search "
        "OR al.title LIKE :search "
        "OR t.genre LIKE :search "
        "ORDER BY t.title"
    );
    
    QString wildcardSearch = "%" + searchTerm + "%";
    query.bindValue(":search", wildcardSearch);
    
    if (query.exec()) {
        while (query.next()) {
            QVariantMap track;
            track["id"] = query.value("id");
            track["title"] = query.value("title");
            track["artist"] = query.value("artist_name");
            track["album"] = query.value("album_title");
            track["duration"] = query.value("duration");
            track["filePath"] = query.value("file_path");
            results.append(track);
        }
    } else {
        logError("Search tracks", query);
    }
    
    return results;
}

bool DatabaseManager::beginTransaction()
{
    return m_db.transaction();
}

bool DatabaseManager::commitTransaction()
{
    return m_db.commit();
}

bool DatabaseManager::rollbackTransaction()
{
    return m_db.rollback();
}

bool DatabaseManager::clearDatabase()
{
    if (!m_db.isOpen()) return false;
    
    QSqlQuery query(m_db);
    
    // Delete all data in correct order due to foreign keys
    query.exec("DELETE FROM playlist_tracks");
    query.exec("DELETE FROM playlists");
    query.exec("DELETE FROM tracks");
    query.exec("DELETE FROM albums");
    query.exec("DELETE FROM album_artists");
    query.exec("DELETE FROM artists");
    
    // Reset autoincrement counters
    query.exec("DELETE FROM sqlite_sequence");
    
    return true;
}

int DatabaseManager::getTotalTracks()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.exec("SELECT COUNT(*) FROM tracks");
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

int DatabaseManager::getTotalAlbums()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.exec("SELECT COUNT(*) FROM albums");
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

int DatabaseManager::getTotalArtists()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.exec("SELECT COUNT(*) FROM artists");
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

qint64 DatabaseManager::getTotalDuration()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.exec("SELECT SUM(duration) FROM tracks");
    
    if (query.next()) {
        return query.value(0).toLongLong();
    }
    
    return 0;
}

QVariantList DatabaseManager::getAllAlbums()
{
    QVariantList albums;
    if (!m_db.isOpen()) return albums;
    
    QSqlQuery query(m_db);
    query.exec(
        "SELECT al.*, aa.name as album_artist_name, "
        "COUNT(t.id) as track_count, SUM(t.duration) as total_duration "
        "FROM albums al "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "LEFT JOIN tracks t ON al.id = t.album_id "
        "GROUP BY al.id "
        "ORDER BY al.title"
    );
    
    while (query.next()) {
        QVariantMap album;
        album["id"] = query.value("id");
        album["title"] = query.value("title");
        album["albumArtist"] = query.value("album_artist_name");
        album["year"] = query.value("year");
        album["trackCount"] = query.value("track_count");
        album["duration"] = query.value("total_duration");
        albums.append(album);
    }
    
    return albums;
}

QVariantList DatabaseManager::getAllArtists()
{
    QVariantList artists;
    if (!m_db.isOpen()) return artists;
    
    QSqlQuery query(m_db);
    // Get album artists instead of track artists to avoid clutter
    query.exec(
        "SELECT aa.*, COUNT(DISTINCT al.id) as album_count, "
        "COUNT(DISTINCT t.id) as track_count "
        "FROM album_artists aa "
        "LEFT JOIN albums al ON aa.id = al.album_artist_id "
        "LEFT JOIN tracks t ON al.id = t.album_id "
        "GROUP BY aa.id "
        "ORDER BY "
        "CASE "
        "  WHEN LOWER(SUBSTR(aa.name, 1, 1)) BETWEEN 'a' AND 'z' THEN 0 "
        "  ELSE 1 "
        "END, "
        "LOWER(aa.name)"
    );
    
    while (query.next()) {
        QVariantMap artist;
        artist["id"] = query.value("id");
        artist["name"] = query.value("name");
        artist["albumCount"] = query.value("album_count");
        artist["trackCount"] = query.value("track_count");
        artists.append(artist);
    }
    
    return artists;
}

QVariantList DatabaseManager::getAlbumsByAlbumArtist(int albumArtistId)
{
    QVariantList albums;
    if (!m_db.isOpen()) return albums;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT al.*, aa.name as album_artist_name, "
        "COUNT(t.id) as track_count, SUM(t.duration) as total_duration "
        "FROM albums al "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "LEFT JOIN tracks t ON al.id = t.album_id "
        "WHERE al.album_artist_id = :artist_id "
        "GROUP BY al.id "
        "ORDER BY al.year DESC, al.title"
    );
    query.bindValue(":artist_id", albumArtistId);
    
    if (query.exec()) {
        while (query.next()) {
            QVariantMap album;
            album["id"] = query.value("id");
            album["title"] = query.value("title");
            album["albumArtist"] = query.value("album_artist_name");
            album["year"] = query.value("year");
            album["trackCount"] = query.value("track_count");
            album["duration"] = query.value("total_duration");
            albums.append(album);
        }
    } else {
        logError("Get albums by album artist", query);
    }
    
    return albums;
}

QVariantList DatabaseManager::getAlbumsByAlbumArtistName(const QString& albumArtistName)
{
    int artistId = getAlbumArtistIdByName(albumArtistName);
    if (artistId > 0) {
        return getAlbumsByAlbumArtist(artistId);
    }
    return QVariantList();
}

int DatabaseManager::getAlbumArtistIdByName(const QString& albumArtistName)
{
    if (!m_db.isOpen() || albumArtistName.isEmpty()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT id FROM album_artists WHERE name = :name");
    query.bindValue(":name", albumArtistName);
    
    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

QString DatabaseManager::getDatabasePath() const
{
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return QDir(dataPath).filePath("mtoc_library.db");
}

QSqlDatabase DatabaseManager::createThreadConnection(const QString& connectionName)
{
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QString dbPath = QDir(dataPath).filePath("mtoc_library.db");
    
    QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
    db.setDatabaseName(dbPath);
    
    if (!db.open()) {
        qCritical() << "Failed to open thread database connection:" << db.lastError().text();
        return db;
    }
    
    // Enable foreign keys and optimizations
    QSqlQuery query(db);
    query.exec("PRAGMA foreign_keys = ON");
    query.exec("PRAGMA journal_mode = WAL");
    query.exec("PRAGMA synchronous = NORMAL");
    query.exec("PRAGMA cache_size = -64000");
    query.exec("PRAGMA temp_store = MEMORY");
    
    return db;
}

void DatabaseManager::removeThreadConnection(const QString& connectionName)
{
    QSqlDatabase::removeDatabase(connectionName);
}

void DatabaseManager::logError(const QString& operation, const QSqlQuery& query)
{
    QString error = QString("Database error in %1: %2").arg(operation, query.lastError().text());
    qCritical() << error;
    qCritical() << "SQL:" << query.lastQuery();
    emit databaseError(error);
}

} // namespace Mtoc