#include "databasemanager.h"
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QVariant>
#include <QMutexLocker>
#include <QThread>
#include <algorithm>
#include <QString>
#include <QMap>

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
    query.exec("PRAGMA mmap_size = 268435456"); // 256MB memory-mapped I/O
    query.exec("PRAGMA page_size = 4096"); // 4KB page size
    
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
    
    // Clear the database object to ensure all queries are destroyed
    m_db = QSqlDatabase();
    
    // Now it's safe to remove the connection
    if (QSqlDatabase::contains(DB_CONNECTION_NAME)) {
        QSqlDatabase::removeDatabase(DB_CONNECTION_NAME);
        qDebug() << "DatabaseManager: Database connection removed";
    }
}

bool DatabaseManager::createTables()
{
    QSqlQuery query(m_db);
    
    // Schema version table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS schema_version ("
        "version INTEGER PRIMARY KEY,"
        "applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        ")")) {
        logError("Create schema_version table", query);
        return false;
    }
    
    // Check current version
    int currentVersion = 0;
    query.exec("SELECT MAX(version) FROM schema_version");
    if (query.next()) {
        currentVersion = query.value(0).toInt();
    }
    
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
        "replaygain_track_gain REAL,"
        "replaygain_track_peak REAL,"
        "replaygain_album_gain REAL,"
        "replaygain_album_peak REAL,"
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
    
    // Album art table
    if (!query.exec(
        "CREATE TABLE IF NOT EXISTS album_art ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "album_id INTEGER NOT NULL UNIQUE,"
        "full_path TEXT,"
        "full_hash TEXT,"
        "thumbnail BLOB,"
        "thumbnail_size INTEGER,"
        "width INTEGER,"
        "height INTEGER,"
        "format TEXT,"
        "file_size INTEGER,"
        "extracted_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
        "FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE"
        ")")) {
        logError("Create album_art table", query);
        return false;
    }
    
    // Apply migrations after tables are created
    if (!applyMigrations(currentVersion)) {
        return false;
    }
    
    return true;
}

bool DatabaseManager::applyMigrations(int currentVersion)
{
    QSqlQuery query(m_db);
    
    // Migration 1: Add replay gain columns (if not already present)
    if (currentVersion < 1) {
        qDebug() << "Applying migration 1: Adding replay gain columns";
        
        // Check if columns already exist (for existing databases)
        query.exec("PRAGMA table_info(tracks)");
        bool hasReplayGainColumns = false;
        while (query.next()) {
            QString columnName = query.value(1).toString();
            if (columnName == "replaygain_track_gain") {
                hasReplayGainColumns = true;
                break;
            }
        }
        
        if (!hasReplayGainColumns) {
            // Add replay gain columns to existing tracks table
            if (!query.exec("ALTER TABLE tracks ADD COLUMN replaygain_track_gain REAL")) {
                logError("Add replaygain_track_gain column", query);
                return false;
            }
            if (!query.exec("ALTER TABLE tracks ADD COLUMN replaygain_track_peak REAL")) {
                logError("Add replaygain_track_peak column", query);
                return false;
            }
            if (!query.exec("ALTER TABLE tracks ADD COLUMN replaygain_album_gain REAL")) {
                logError("Add replaygain_album_gain column", query);
                return false;
            }
            if (!query.exec("ALTER TABLE tracks ADD COLUMN replaygain_album_peak REAL")) {
                logError("Add replaygain_album_peak column", query);
                return false;
            }
        }
        
        // Record migration
        query.prepare("INSERT INTO schema_version (version) VALUES (:version)");
        query.bindValue(":version", 1);
        if (!query.exec()) {
            logError("Record migration 1", query);
            return false;
        }
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
    query.exec("CREATE INDEX IF NOT EXISTS idx_album_artists_name ON album_artists(name)");
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
    
    // Extract replay gain data
    double replayGainTrackGain = trackData.value("replayGainTrackGain", QVariant()).toDouble();
    double replayGainTrackPeak = trackData.value("replayGainTrackPeak", QVariant()).toDouble();
    double replayGainAlbumGain = trackData.value("replayGainAlbumGain", QVariant()).toDouble();
    double replayGainAlbumPeak = trackData.value("replayGainAlbumPeak", QVariant()).toDouble();
    
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
    }
    
    // Insert track
    QSqlQuery query(m_db);
    query.prepare(
        "INSERT INTO tracks (file_path, title, artist_id, album_id, genre, year, "
        "track_number, disc_number, duration, file_size, file_modified, "
        "replaygain_track_gain, replaygain_track_peak, replaygain_album_gain, replaygain_album_peak) "
        "VALUES (:file_path, :title, :artist_id, :album_id, :genre, :year, "
        ":track_number, :disc_number, :duration, :file_size, :file_modified, "
        ":replaygain_track_gain, :replaygain_track_peak, :replaygain_album_gain, :replaygain_album_peak)"
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
    
    // Bind replay gain values (using null if not present)
    query.bindValue(":replaygain_track_gain", trackData.contains("replayGainTrackGain") ? replayGainTrackGain : QVariant());
    query.bindValue(":replaygain_track_peak", trackData.contains("replayGainTrackPeak") ? replayGainTrackPeak : QVariant());
    query.bindValue(":replaygain_album_gain", trackData.contains("replayGainAlbumGain") ? replayGainAlbumGain : QVariant());
    query.bindValue(":replaygain_album_peak", trackData.contains("replayGainAlbumPeak") ? replayGainAlbumPeak : QVariant());
    
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
            // For updates, we don't have access to year from trackData here
            // We could enhance this later if needed
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
    
    // Handle replay gain fields
    if (trackData.contains("replayGainTrackGain")) {
        setClauses << "replaygain_track_gain = :replaygain_track_gain";
        bindValues[":replaygain_track_gain"] = trackData.value("replayGainTrackGain");
    }
    
    if (trackData.contains("replayGainTrackPeak")) {
        setClauses << "replaygain_track_peak = :replaygain_track_peak";
        bindValues[":replaygain_track_peak"] = trackData.value("replayGainTrackPeak");
    }
    
    if (trackData.contains("replayGainAlbumGain")) {
        setClauses << "replaygain_album_gain = :replaygain_album_gain";
        bindValues[":replaygain_album_gain"] = trackData.value("replayGainAlbumGain");
    }
    
    if (trackData.contains("replayGainAlbumPeak")) {
        setClauses << "replaygain_album_peak = :replaygain_album_peak";
        bindValues[":replaygain_album_peak"] = trackData.value("replayGainAlbumPeak");
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

bool DatabaseManager::deleteTracksByFolderPath(const QString& folderPath)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen()) return false;
    
    // Start a transaction to ensure consistency
    if (!m_db.transaction()) {
        qWarning() << "Failed to start transaction for deleteTracksByFolderPath";
        return false;
    }
    
    QSqlQuery query(m_db);
    
    // Step 1: Delete tracks from the folder
    query.prepare("DELETE FROM tracks WHERE file_path LIKE :path");
    query.bindValue(":path", folderPath + "%");
    
    if (!query.exec()) {
        logError("deleteTracksByFolderPath - delete tracks", query);
        m_db.rollback();
        return false;
    }
    
    int deletedTracks = query.numRowsAffected();
    qDebug() << "DatabaseManager: Deleted" << deletedTracks << "tracks from folder:" << folderPath;
    
    // Step 2: Delete albums that have no tracks (orphaned albums)
    if (!query.exec("DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL)")) {
        logError("deleteTracksByFolderPath - delete orphaned albums", query);
        m_db.rollback();
        return false;
    }
    
    int deletedAlbums = query.numRowsAffected();
    if (deletedAlbums > 0) {
        qDebug() << "DatabaseManager: Deleted" << deletedAlbums << "orphaned albums";
    }
    
    // Step 3: Delete album_artists that have no albums (orphaned album artists)
    if (!query.exec("DELETE FROM album_artists WHERE id NOT IN (SELECT DISTINCT album_artist_id FROM albums WHERE album_artist_id IS NOT NULL)")) {
        logError("deleteTracksByFolderPath - delete orphaned album artists", query);
        m_db.rollback();
        return false;
    }
    
    int deletedAlbumArtists = query.numRowsAffected();
    if (deletedAlbumArtists > 0) {
        qDebug() << "DatabaseManager: Deleted" << deletedAlbumArtists << "orphaned album artists";
    }
    
    // Step 4: Delete artists that have no tracks (orphaned artists)
    if (!query.exec("DELETE FROM artists WHERE id NOT IN (SELECT DISTINCT artist_id FROM tracks WHERE artist_id IS NOT NULL)")) {
        logError("deleteTracksByFolderPath - delete orphaned artists", query);
        m_db.rollback();
        return false;
    }
    
    int deletedArtists = query.numRowsAffected();
    if (deletedArtists > 0) {
        qDebug() << "DatabaseManager: Deleted" << deletedArtists << "orphaned artists";
    }
    
    // Commit the transaction
    if (!m_db.commit()) {
        qWarning() << "Failed to commit transaction for deleteTracksByFolderPath";
        m_db.rollback();
        return false;
    }
    
    qDebug() << "DatabaseManager: Cleanup completed successfully";
    return true;
}

QVariantMap DatabaseManager::getTrack(int trackId)
{
    QMutexLocker locker(&m_databaseMutex);
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
        track["fileSize"] = query.value("file_size");
        track["playCount"] = query.value("play_count");
        track["rating"] = query.value("rating");
        track["lastPlayed"] = query.value("last_played");
    }
    
    return track;
}

QVariantList DatabaseManager::getTracksByAlbumAndArtist(const QString& albumTitle, const QString& albumArtistName)
{
    // qDebug() << "[DatabaseManager::getTracksByAlbumAndArtist] Called with album:" << albumTitle << "artist:" << albumArtistName;
    
    QMutexLocker locker(&m_databaseMutex);
    QVariantList tracks;
    if (!m_db.isOpen()) {
        qWarning() << "[DatabaseManager::getTracksByAlbumAndArtist] Database is not open!";
        return tracks;
    }
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT t.*, a.name as artist_name, al.title as album_title, "
        "aa.name as album_artist_name "
        "FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "LEFT JOIN albums al ON t.album_id = al.id "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "WHERE al.title = :album_title AND aa.name = :album_artist "
        "ORDER BY t.disc_number, t.track_number, t.title COLLATE NOCASE"
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
            track["fileSize"] = query.value("file_size");
            tracks.append(track);
        }
    } else {
        qWarning() << "[DatabaseManager::getTracksByAlbumAndArtist] Query execution failed!";
        logError("Get tracks by album and artist", query);
    }
    return tracks;
}

QVariantList DatabaseManager::getAllTracks(int limit, int offset)
{
    QVariantList tracks;
    
    // Check if we're in the main thread or a worker thread
    bool isMainThread = (QThread::currentThread() == this->thread());
    QSqlDatabase db;
    QString connectionName;
    
    if (isMainThread) {
        // Use the main connection with mutex protection
        QMutexLocker locker(&m_databaseMutex);
        if (!m_db.isOpen()) {
            qWarning() << "[DatabaseManager::getAllTracks] Database is not open!";
            return tracks;
        }
        db = m_db;
    } else {
        // Create a thread-specific connection for background threads
        connectionName = QString("MtocThread_%1").arg(quintptr(QThread::currentThreadId()));
        if (QSqlDatabase::contains(connectionName)) {
            db = QSqlDatabase::database(connectionName);
        } else {
            db = createThreadConnection(connectionName);
        }
        
        if (!db.isOpen()) {
            qWarning() << "[DatabaseManager::getAllTracks] Failed to open thread database!";
            return tracks;
        }
    }
    
    QSqlQuery query(db);
    QString queryStr = 
        "SELECT t.*, a.name as artist_name, al.title as album_title, "
        "aa.name as album_artist_name "
        "FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "LEFT JOIN albums al ON t.album_id = al.id "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "WHERE t.title IS NOT NULL AND t.title != '' "
        "AND (a.name IS NOT NULL AND a.name != '' OR t.artist_id IS NULL) "
        "ORDER BY aa.name COLLATE NOCASE, al.title COLLATE NOCASE, "
        "t.disc_number, t.track_number, t.title COLLATE NOCASE";
    
    if (limit > 0) {
        queryStr += " LIMIT :limit";
        if (offset > 0) {
            queryStr += " OFFSET :offset";
        }
    }
    
    query.prepare(queryStr);
    
    if (limit > 0) {
        query.bindValue(":limit", limit);
        if (offset > 0) {
            query.bindValue(":offset", offset);
        }
    }
    
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
            track["fileSize"] = query.value("file_size");
            track["lastPlayed"] = query.value("last_played");
            track["playCount"] = query.value("play_count");
            track["rating"] = query.value("rating");
            tracks.append(track);
        }
    } else {
        qWarning() << "[DatabaseManager::getAllTracks] Query execution failed!";
        logError("Get all tracks", query);
    }
    
    return tracks;
}

int DatabaseManager::getTrackCount()
{
    if (!m_db.isOpen()) {
        qWarning() << "[DatabaseManager::getTrackCount] Database is not open!";
        return 0;
    }
    
    QSqlQuery query(m_db);
    // Match the filtering criteria used in getAllTracks
    query.prepare(
        "SELECT COUNT(*) FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "WHERE t.title IS NOT NULL AND t.title != '' "
        "AND (a.name IS NOT NULL AND a.name != '' OR t.artist_id IS NULL)"
    );
    
    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    
    logError("Get track count", query);
    return 0;
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

int DatabaseManager::insertOrGetAlbum(const QString& albumName, int albumArtistId, int albumYear)
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
        int existingAlbumId = query.value(0).toInt();
        
        // Update year if provided and not already set
        if (albumYear > 0) {
            QSqlQuery updateQuery(m_db);
            updateQuery.prepare("UPDATE albums SET year = :year WHERE id = :id AND (year IS NULL OR year = 0)");
            updateQuery.bindValue(":year", albumYear);
            updateQuery.bindValue(":id", existingAlbumId);
            updateQuery.exec();
        }
        
        return existingAlbumId;
    }
    
    // Insert new album with year
    query.prepare("INSERT INTO albums (title, album_artist_id, year) VALUES (:title, :artist_id, :year)");
    query.bindValue(":title", albumName);
    query.bindValue(":artist_id", albumArtistId > 0 ? albumArtistId : QVariant());
    query.bindValue(":year", albumYear > 0 ? albumYear : QVariant());
    
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

QStringList DatabaseManager::getAllTracksFilePaths()
{
    QStringList filePaths;
    if (!m_db.isOpen()) return filePaths;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT file_path FROM tracks");
    
    if (query.exec()) {
        while (query.next()) {
            filePaths.append(query.value(0).toString());
        }
    } else {
        logError("Get all tracks file paths", query);
    }
    
    return filePaths;
}

QVariantList DatabaseManager::searchTracks(const QString& searchTerm)
{
    QVariantList results;
    if (!m_db.isOpen() || searchTerm.isEmpty()) return results;
    
    // Normalize the search term for accent-insensitive search
    QString normalizedSearchTerm = normalizeForSearch(searchTerm);
    
    QSqlQuery query(m_db);
    // Get all tracks and filter in memory for accent-insensitive search
    query.prepare(
        "SELECT t.*, a.name as artist_name, al.title as album_title "
        "FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "LEFT JOIN albums al ON t.album_id = al.id "
        "ORDER BY t.title"
    );
    
    if (query.exec()) {
        while (query.next()) {
            QString trackTitle = query.value("title").toString();
            QString artistName = query.value("artist_name").toString();
            QString albumTitle = query.value("album_title").toString();
            QString genre = query.value("genre").toString();
            
            QString normalizedTrackTitle = normalizeForSearch(trackTitle);
            QString normalizedArtistName = normalizeForSearch(artistName);
            QString normalizedAlbumTitle = normalizeForSearch(albumTitle);
            QString normalizedGenre = normalizeForSearch(genre);
            
            // Check if any normalized field contains the normalized search term
            if (normalizedTrackTitle.contains(normalizedSearchTerm) ||
                normalizedArtistName.contains(normalizedSearchTerm) ||
                normalizedAlbumTitle.contains(normalizedSearchTerm) ||
                normalizedGenre.contains(normalizedSearchTerm)) {
                
                QVariantMap track;
                track["id"] = query.value("id");
                track["title"] = trackTitle;
                track["artist"] = artistName;
                track["album"] = albumTitle;
                track["duration"] = query.value("duration");
                track["filePath"] = query.value("file_path");
                
                // Determine priority for sorting (track title matches are highest priority)
                int priority = 4;
                if (normalizedTrackTitle.contains(normalizedSearchTerm)) {
                    if (normalizedTrackTitle == normalizedSearchTerm) {
                        priority = 1; // Exact track title match
                    } else if (normalizedTrackTitle.startsWith(normalizedSearchTerm)) {
                        priority = 2; // Track title prefix match
                    } else {
                        priority = 3; // Track title contains match
                    }
                }
                track["searchPriority"] = priority;
                
                results.append(track);
            }
        }
        
        // Sort results by priority and then by title
        std::sort(results.begin(), results.end(), [](const QVariant& a, const QVariant& b) {
            QVariantMap mapA = a.toMap();
            QVariantMap mapB = b.toMap();
            int priorityA = mapA["searchPriority"].toInt();
            int priorityB = mapB["searchPriority"].toInt();
            if (priorityA != priorityB) {
                return priorityA < priorityB;
            }
            return mapA["title"].toString().toLower() < mapB["title"].toString().toLower();
        });
        
        // Remove the searchPriority field from results
        for (auto& result : results) {
            QVariantMap map = result.toMap();
            map.remove("searchPriority");
            result = map;
        }
    } else {
        logError("Search tracks", query);
    }
    
    return results;
}

QVariantList DatabaseManager::searchAlbums(const QString& searchTerm)
{
    QVariantList results;
    if (!m_db.isOpen() || searchTerm.isEmpty()) return results;
    
    // Normalize the search term for accent-insensitive search
    QString normalizedSearchTerm = normalizeForSearch(searchTerm);
    
    QSqlQuery query(m_db);
    // Get all albums and filter in memory for accent-insensitive search
    query.prepare(
        "SELECT al.*, aa.name as album_artist_name, "
        "       (SELECT COUNT(*) FROM tracks t WHERE t.album_id = al.id) as track_count, "
        "       (SELECT COUNT(*) FROM album_art art WHERE art.album_id = al.id) > 0 as has_art "
        "FROM albums al "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "ORDER BY al.title"
    );
    
    if (query.exec()) {
        while (query.next()) {
            QString albumTitle = query.value("title").toString();
            QString albumArtist = query.value("album_artist_name").toString();
            QString normalizedAlbumTitle = normalizeForSearch(albumTitle);
            QString normalizedAlbumArtist = normalizeForSearch(albumArtist);
            
            // Check if the normalized album title or artist contains the normalized search term
            if (normalizedAlbumTitle.contains(normalizedSearchTerm) || 
                normalizedAlbumArtist.contains(normalizedSearchTerm)) {
                QVariantMap album;
                album["id"] = query.value("id");
                album["title"] = albumTitle;
                album["albumArtist"] = albumArtist;
                album["year"] = query.value("year");
                album["trackCount"] = query.value("track_count");
                album["hasArt"] = query.value("has_art").toBool();
                
                // Determine priority for sorting
                int priority = 5;
                if (normalizedAlbumTitle == normalizedSearchTerm) {
                    priority = 1; // Exact album title match
                } else if (normalizedAlbumTitle.startsWith(normalizedSearchTerm)) {
                    priority = 2; // Album title prefix match
                } else if (normalizedAlbumArtist == normalizedSearchTerm) {
                    priority = 3; // Exact artist match
                } else if (normalizedAlbumArtist.startsWith(normalizedSearchTerm)) {
                    priority = 4; // Artist prefix match
                }
                album["searchPriority"] = priority;
                
                results.append(album);
            }
        }
        
        // Sort results by priority and then by title
        std::sort(results.begin(), results.end(), [](const QVariant& a, const QVariant& b) {
            QVariantMap mapA = a.toMap();
            QVariantMap mapB = b.toMap();
            int priorityA = mapA["searchPriority"].toInt();
            int priorityB = mapB["searchPriority"].toInt();
            if (priorityA != priorityB) {
                return priorityA < priorityB;
            }
            return mapA["title"].toString().toLower() < mapB["title"].toString().toLower();
        });
        
        // Remove the searchPriority field from results
        for (auto& result : results) {
            QVariantMap map = result.toMap();
            map.remove("searchPriority");
            result = map;
        }
    } else {
        logError("Search albums", query);
    }
    
    return results;
}

QVariantList DatabaseManager::searchArtists(const QString& searchTerm)
{
    QVariantList results;
    if (!m_db.isOpen() || searchTerm.isEmpty()) return results;
    
    // Normalize the search term for accent-insensitive search
    QString normalizedSearchTerm = normalizeForSearch(searchTerm);
    
    QSqlQuery query(m_db);
    // Get all artists and filter in memory for accent-insensitive search
    query.prepare(
        "SELECT a.*, "
        "       (SELECT COUNT(*) FROM albums al WHERE al.album_artist_id = aa.id) as album_count "
        "FROM artists a "
        "LEFT JOIN album_artists aa ON a.name = aa.name "
        "ORDER BY a.name"
    );
    
    if (query.exec()) {
        while (query.next()) {
            QString artistName = query.value("name").toString();
            QString normalizedArtistName = normalizeForSearch(artistName);
            
            // Check if the normalized artist name contains the normalized search term
            if (normalizedArtistName.contains(normalizedSearchTerm)) {
                QVariantMap artist;
                artist["id"] = query.value("id");
                artist["name"] = artistName;
                artist["albumCount"] = query.value("album_count");
                
                // Determine priority for sorting
                int priority = 3;
                if (normalizedArtistName == normalizedSearchTerm) {
                    priority = 1; // Exact match
                } else if (normalizedArtistName.startsWith(normalizedSearchTerm)) {
                    priority = 2; // Prefix match
                }
                artist["searchPriority"] = priority;
                
                results.append(artist);
            }
        }
        
        // Sort results by priority and then by name
        std::sort(results.begin(), results.end(), [](const QVariant& a, const QVariant& b) {
            QVariantMap mapA = a.toMap();
            QVariantMap mapB = b.toMap();
            int priorityA = mapA["searchPriority"].toInt();
            int priorityB = mapB["searchPriority"].toInt();
            if (priorityA != priorityB) {
                return priorityA < priorityB;
            }
            return mapA["name"].toString().toLower() < mapB["name"].toString().toLower();
        });
        
        // Remove the searchPriority field from results
        for (auto& result : results) {
            QVariantMap map = result.toMap();
            map.remove("searchPriority");
            result = map;
        }
    } else {
        logError("Search artists", query);
    }
    
    return results;
}

QVariantMap DatabaseManager::searchAll(const QString& searchTerm)
{
    QVariantMap results;
    if (!m_db.isOpen() || searchTerm.isEmpty()) return results;
    
    // Search artists first (highest priority)
    QVariantList artists = searchArtists(searchTerm);
    results["artists"] = artists;
    
    // Search albums second
    QVariantList albums = searchAlbums(searchTerm);
    results["albums"] = albums;
    
    // Search tracks third
    QVariantList tracks = searchTracks(searchTerm);
    results["tracks"] = tracks;
    
    // Determine best match based on priority: artists -> albums -> tracks
    QVariantMap bestMatch;
    QString bestMatchType;
    
    if (!artists.isEmpty()) {
        bestMatch = artists.first().toMap();
        bestMatchType = "artist";
    } else if (!albums.isEmpty()) {
        bestMatch = albums.first().toMap();
        bestMatchType = "album";
    } else if (!tracks.isEmpty()) {
        bestMatch = tracks.first().toMap();
        bestMatchType = "track";
    }
    
    results["bestMatch"] = bestMatch;
    results["bestMatchType"] = bestMatchType;
    
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
    query.prepare("SELECT COUNT(*) FROM tracks");
    
    if (!query.exec()) {
        qWarning() << "Failed to get track count:" << query.lastError().text();
        return 0;
    }
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

int DatabaseManager::getTotalAlbums()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT COUNT(*) FROM albums");
    
    if (!query.exec()) {
        qWarning() << "Failed to get album count:" << query.lastError().text();
        return 0;
    }
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

int DatabaseManager::getTotalAlbumArtists()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT COUNT(*) FROM album_artists");
    
    if (!query.exec()) {
        qWarning() << "Failed to get album artist count:" << query.lastError().text();
        return 0;
    }
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

int DatabaseManager::getTotalArtists()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT COUNT(*) FROM artists");
    
    if (!query.exec()) {
        qWarning() << "Failed to get artist count:" << query.lastError().text();
        return 0;
    }
    
    if (query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

qint64 DatabaseManager::getTotalDuration()
{
    if (!m_db.isOpen()) return 0;
    
    QSqlQuery query(m_db);
    // Match the filtering criteria used in getAllTracks
    query.exec(
        "SELECT SUM(t.duration) FROM tracks t "
        "LEFT JOIN artists a ON t.artist_id = a.id "
        "WHERE t.title IS NOT NULL AND t.title != '' "
        "AND (a.name IS NOT NULL AND a.name != '' OR t.artist_id IS NULL)"
    );
    
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
    query.prepare(
        "SELECT al.id, al.title, al.year, aa.name as album_artist_name, "
        "COUNT(t.id) as track_count, SUM(t.duration) as total_duration, "
        "CASE WHEN art.id IS NOT NULL THEN 1 ELSE 0 END as has_art "
        "FROM albums al "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "INNER JOIN tracks t ON al.id = t.album_id "
        "LEFT JOIN album_art art ON al.id = art.album_id "
        "GROUP BY al.id, al.title, al.year, aa.name, art.id "
        "HAVING COUNT(t.id) > 0 "
        "ORDER BY al.title COLLATE NOCASE"
    );
    
    if (!query.exec()) {
        qWarning() << "Failed to get all albums:" << query.lastError().text();
        return albums;
    }
    
    while (query.next()) {
        QVariantMap album;
        album["id"] = query.value("id");
        album["title"] = query.value("title");
        album["albumArtist"] = query.value("album_artist_name");
        album["year"] = query.value("year");
        album["trackCount"] = query.value("track_count");
        album["duration"] = query.value("total_duration");
        album["hasArt"] = query.value("has_art").toBool();
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
    // Note: We fetch without ORDER BY and sort in C++ for locale-aware sorting
    query.exec(
        "SELECT aa.*, COUNT(DISTINCT al.id) as album_count, "
        "COUNT(DISTINCT t.id) as track_count "
        "FROM album_artists aa "
        "INNER JOIN albums al ON aa.id = al.album_artist_id "
        "INNER JOIN tracks t ON al.id = t.album_id "
        "GROUP BY aa.id "
        "HAVING COUNT(t.id) > 0"
    );
    
    while (query.next()) {
        QVariantMap artist;
        artist["id"] = query.value("id");
        artist["name"] = query.value("name");
        artist["albumCount"] = query.value("album_count");
        artist["trackCount"] = query.value("track_count");
        artists.append(artist);
    }
    
    // Sort using locale-aware comparison to match JavaScript's localeCompare
    std::sort(artists.begin(), artists.end(), [](const QVariant& a, const QVariant& b) {
        QVariantMap artistA = a.toMap();
        QVariantMap artistB = b.toMap();
        QString nameA = artistA["name"].toString().toLower();
        QString nameB = artistB["name"].toString().toLower();
        
        // Remove "the " prefix for sorting (case-insensitive)
        if (nameA.startsWith("the ")) {
            nameA = nameA.mid(4);
        }
        if (nameB.startsWith("the ")) {
            nameB = nameB.mid(4);
        }
        
        // First, separate letters from non-letters (numbers/symbols go last)
        bool aStartsWithLetter = !nameA.isEmpty() && nameA[0].isLetter();
        bool bStartsWithLetter = !nameB.isEmpty() && nameB[0].isLetter();
        
        if (aStartsWithLetter != bStartsWithLetter) {
            return aStartsWithLetter; // Letters come before non-letters
        }
        
        // Use locale-aware comparison for consistent sorting with accented characters
        return nameA.localeAwareCompare(nameB) < 0;
    });
    
    return artists;
}

QVariantList DatabaseManager::getAlbumsByAlbumArtist(int albumArtistId)
{
    QMutexLocker locker(&m_databaseMutex);
    QVariantList albums;
    if (!m_db.isOpen()) return albums;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT al.*, aa.name as album_artist_name, "
        "COUNT(t.id) as track_count, SUM(t.duration) as total_duration, "
        "art.thumbnail as art_thumbnail, art.full_path as art_path "
        "FROM albums al "
        "LEFT JOIN album_artists aa ON al.album_artist_id = aa.id "
        "LEFT JOIN tracks t ON al.id = t.album_id "
        "LEFT JOIN album_art art ON al.id = art.album_id "
        "WHERE al.album_artist_id = :artist_id "
        "GROUP BY al.id "
        "ORDER BY al.year DESC, al.title COLLATE NOCASE"
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
            album["hasArt"] = !query.value("art_thumbnail").isNull();
            album["artThumbnail"] = query.value("art_thumbnail");
            album["artPath"] = query.value("art_path");
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

int DatabaseManager::getAlbumIdByArtistAndTitle(const QString& albumArtist, const QString& albumTitle)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen() || albumArtist.isEmpty() || albumTitle.isEmpty()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT al.id FROM albums al "
        "JOIN album_artists aa ON al.album_artist_id = aa.id "
        "WHERE aa.name = :artist AND al.title = :title"
    );
    query.bindValue(":artist", albumArtist);
    query.bindValue(":title", albumTitle);
    
    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    
    return 0;
}

int DatabaseManager::getAlbumArtistIdByName(const QString& albumArtistName)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen() || albumArtistName.isEmpty()) return 0;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT id FROM album_artists WHERE name = :name");
    query.bindValue(":name", albumArtistName);
    
    if (query.exec()) {
        if (query.next()) {
            return query.value(0).toInt();
        }
    } else {
        logError("Get album artist ID by name", query);
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
    query.exec("PRAGMA mmap_size = 268435456");
    query.exec("PRAGMA page_size = 4096");
    
    // Force WAL checkpoint to ensure this connection sees all committed data
    query.exec("PRAGMA wal_checkpoint(TRUNCATE)");
    
    // Enable read uncommitted to see latest data from other connections
    query.exec("PRAGMA read_uncommitted = 1");
    
    qDebug() << "[DatabaseManager] Created thread connection:" << connectionName 
             << "WAL checkpoint result:" << query.lastError().text();
    
    return db;
}

void DatabaseManager::removeThreadConnection(const QString& connectionName)
{
    // Get the database connection
    {
        QSqlDatabase db = QSqlDatabase::database(connectionName, false);
        if (db.isValid() && db.isOpen()) {
            // Close the connection before removing it
            db.close();
        }
    }
    // Remove the connection from Qt's registry
    QSqlDatabase::removeDatabase(connectionName);
}

QString DatabaseManager::normalizeForSearch(const QString& text)
{
    // Convert to lowercase and remove accents/diacritics for accent-insensitive search
    QString normalized = text.toLower();
    
    // Map of accented characters to their base forms
    static const QMap<QChar, QChar> accentMap = {
        // A variants
        {QChar(L'à'), QChar('a')}, {QChar(L'á'), QChar('a')}, {QChar(L'â'), QChar('a')}, 
        {QChar(L'ã'), QChar('a')}, {QChar(L'ä'), QChar('a')}, {QChar(L'å'), QChar('a')},
        {QChar(L'À'), QChar('a')}, {QChar(L'Á'), QChar('a')}, {QChar(L'Â'), QChar('a')}, 
        {QChar(L'Ã'), QChar('a')}, {QChar(L'Ä'), QChar('a')}, {QChar(L'Å'), QChar('a')},
        // E variants
        {QChar(L'è'), QChar('e')}, {QChar(L'é'), QChar('e')}, {QChar(L'ê'), QChar('e')}, {QChar(L'ë'), QChar('e')},
        {QChar(L'È'), QChar('e')}, {QChar(L'É'), QChar('e')}, {QChar(L'Ê'), QChar('e')}, {QChar(L'Ë'), QChar('e')},
        // I variants
        {QChar(L'ì'), QChar('i')}, {QChar(L'í'), QChar('i')}, {QChar(L'î'), QChar('i')}, {QChar(L'ï'), QChar('i')},
        {QChar(L'Ì'), QChar('i')}, {QChar(L'Í'), QChar('i')}, {QChar(L'Î'), QChar('i')}, {QChar(L'Ï'), QChar('i')},
        // O variants
        {QChar(L'ò'), QChar('o')}, {QChar(L'ó'), QChar('o')}, {QChar(L'ô'), QChar('o')}, 
        {QChar(L'õ'), QChar('o')}, {QChar(L'ö'), QChar('o')}, {QChar(L'ø'), QChar('o')},
        {QChar(L'Ò'), QChar('o')}, {QChar(L'Ó'), QChar('o')}, {QChar(L'Ô'), QChar('o')}, 
        {QChar(L'Õ'), QChar('o')}, {QChar(L'Ö'), QChar('o')}, {QChar(L'Ø'), QChar('o')},
        // U variants
        {QChar(L'ù'), QChar('u')}, {QChar(L'ú'), QChar('u')}, {QChar(L'û'), QChar('u')}, {QChar(L'ü'), QChar('u')},
        {QChar(L'Ù'), QChar('u')}, {QChar(L'Ú'), QChar('u')}, {QChar(L'Û'), QChar('u')}, {QChar(L'Ü'), QChar('u')},
        // Y variants
        {QChar(L'ý'), QChar('y')}, {QChar(L'ÿ'), QChar('y')}, {QChar(L'Ý'), QChar('y')}, {QChar(L'Ÿ'), QChar('y')},
        // N variants
        {QChar(L'ñ'), QChar('n')}, {QChar(L'Ñ'), QChar('n')},
        // C variants
        {QChar(L'ç'), QChar('c')}, {QChar(L'Ç'), QChar('c')},
        // AE/OE ligatures
        {QChar(L'æ'), QChar('a')}, {QChar(L'Æ'), QChar('a')}, {QChar(L'œ'), QChar('o')}, {QChar(L'Œ'), QChar('o')}
    };
    
    // Replace accented characters with their base forms
    for (int i = 0; i < normalized.length(); ++i) {
        QChar ch = normalized[i];
        if (accentMap.contains(ch)) {
            normalized[i] = accentMap[ch];
        }
    }
    
    return normalized;
}

bool DatabaseManager::insertAlbumArt(int albumId, const QString& fullPath, const QString& hash, 
                                   const QByteArray& thumbnail, int width, int height, 
                                   const QString& format, qint64 fileSize)
{
    if (!m_db.isOpen()) return false;
    
    QSqlQuery query(m_db);
    query.prepare(
        "INSERT OR REPLACE INTO album_art "
        "(album_id, full_path, full_hash, thumbnail, thumbnail_size, "
        "width, height, format, file_size) "
        "VALUES (:album_id, :full_path, :full_hash, :thumbnail, :thumbnail_size, "
        ":width, :height, :format, :file_size)"
    );
    
    query.bindValue(":album_id", albumId);
    query.bindValue(":full_path", fullPath);
    query.bindValue(":full_hash", hash);
    query.bindValue(":thumbnail", thumbnail);
    query.bindValue(":thumbnail_size", thumbnail.size());
    query.bindValue(":width", width);
    query.bindValue(":height", height);
    query.bindValue(":format", format);
    query.bindValue(":file_size", fileSize);
    
    if (!query.exec()) {
        logError("Insert album art", query);
        return false;
    }
    
    return true;
}

QVariantMap DatabaseManager::getAlbumArt(int albumId)
{
    QVariantMap result;
    if (!m_db.isOpen()) return result;
    
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT * FROM album_art WHERE album_id = :album_id"
    );
    query.bindValue(":album_id", albumId);
    
    if (query.exec() && query.next()) {
        result["id"] = query.value("id");
        result["albumId"] = query.value("album_id");
        result["fullPath"] = query.value("full_path");
        result["fullHash"] = query.value("full_hash");
        result["thumbnail"] = query.value("thumbnail");
        result["thumbnailSize"] = query.value("thumbnail_size");
        result["width"] = query.value("width");
        result["height"] = query.value("height");
        result["format"] = query.value("format");
        result["fileSize"] = query.value("file_size");
        result["extractedDate"] = query.value("extracted_date");
    }
    
    return result;
}

bool DatabaseManager::albumArtExists(int albumId)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen()) return false;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT 1 FROM album_art WHERE album_id = :album_id LIMIT 1");
    query.bindValue(":album_id", albumId);
    
    return query.exec() && query.next();
}

QString DatabaseManager::getAlbumArtPath(int albumId)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen()) return QString();
    
    QSqlQuery query(m_db);
    query.prepare("SELECT full_path FROM album_art WHERE album_id = :album_id");
    query.bindValue(":album_id", albumId);
    
    if (query.exec() && query.next()) {
        return query.value(0).toString();
    }
    
    return QString();
}

QByteArray DatabaseManager::getAlbumArtThumbnail(int albumId)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen()) return QByteArray();
    
    QSqlQuery query(m_db);
    query.prepare("SELECT thumbnail FROM album_art WHERE album_id = :album_id");
    query.bindValue(":album_id", albumId);
    
    if (query.exec() && query.next()) {
        return query.value(0).toByteArray();
    }
    
    return QByteArray();
}

bool DatabaseManager::updateAlbumThumbnail(int albumId, const QByteArray& thumbnailData)
{
    QMutexLocker locker(&m_databaseMutex);
    if (!m_db.isOpen()) return false;
    
    QSqlQuery query(m_db);
    query.prepare("UPDATE album_art SET thumbnail = :thumbnail, thumbnail_size = :size WHERE album_id = :album_id");
    query.bindValue(":thumbnail", thumbnailData);
    query.bindValue(":size", thumbnailData.size());
    query.bindValue(":album_id", albumId);
    
    if (!query.exec()) {
        logError("updateAlbumThumbnail", query);
        return false;
    }
    
    return query.numRowsAffected() > 0;
}

QList<int> DatabaseManager::getAllAlbumIdsWithArt()
{
    QMutexLocker locker(&m_databaseMutex);
    QList<int> albumIds;
    
    if (!m_db.isOpen()) return albumIds;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT album_id FROM album_art WHERE thumbnail IS NOT NULL");
    
    if (query.exec()) {
        while (query.next()) {
            albumIds.append(query.value(0).toInt());
        }
    } else {
        logError("getAllAlbumIdsWithArt", query);
    }
    
    return albumIds;
}

void DatabaseManager::logError(const QString& operation, const QSqlQuery& query)
{
    QString error = QString("Database error in %1: %2").arg(operation, query.lastError().text());
    qCritical() << error;
    qCritical() << "SQL:" << query.lastQuery();
    emit databaseError(error);
}

} // namespace Mtoc