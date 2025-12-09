#include "favoritesmanager.h"
#include "backend/database/databasemanager.h"
#include <QStandardPaths>
#include <QDir>
#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>

namespace Mtoc {

const QString FavoritesManager::BACKUP_DB_CONNECTION_NAME = "MtocFavoritesBackup";

FavoritesManager::FavoritesManager(DatabaseManager* dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
    initializeBackupDatabase();
}

FavoritesManager::~FavoritesManager()
{
    if (m_backupDb.isOpen()) {
        m_backupDb.close();
    }
    QSqlDatabase::removeDatabase(BACKUP_DB_CONNECTION_NAME);
}

QString FavoritesManager::getBackupDatabasePath() const
{
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return dataPath + "/favorites.db";
}

void FavoritesManager::initializeBackupDatabase()
{
    m_backupDbPath = getBackupDatabasePath();

    // Ensure directory exists
    QDir dir = QFileInfo(m_backupDbPath).dir();
    if (!dir.exists()) {
        dir.mkpath(".");
    }

    m_backupDb = QSqlDatabase::addDatabase("QSQLITE", BACKUP_DB_CONNECTION_NAME);
    m_backupDb.setDatabaseName(m_backupDbPath);

    if (!m_backupDb.open()) {
        qCritical() << "FavoritesManager: Failed to open backup database:" << m_backupDb.lastError().text();
        return;
    }

    // Create schema
    QSqlQuery query(m_backupDb);
    bool success = query.exec(
        "CREATE TABLE IF NOT EXISTS favorites ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "file_path TEXT NOT NULL,"
        "artist TEXT,"
        "album TEXT,"
        "title TEXT,"
        "track_number INTEGER,"
        "added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        ")"
    );

    if (!success) {
        qCritical() << "FavoritesManager: Failed to create favorites table:" << query.lastError().text();
        return;
    }

    // Create unique index on file_path
    query.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_path ON favorites(file_path)");

    qDebug() << "FavoritesManager: Backup database initialized at" << m_backupDbPath;
}

void FavoritesManager::toggleFavorite(int trackId)
{
    bool currentState = isFavorite(trackId);
    setFavorite(trackId, !currentState);
}

void FavoritesManager::setFavorite(int trackId, bool favorite)
{
    if (!m_dbManager) return;

    // Update main database
    bool success = m_dbManager->setTrackFavorite(trackId, favorite);
    if (!success) {
        qWarning() << "FavoritesManager: Failed to update favorite state for track" << trackId;
        return;
    }

    // Update backup database
    if (favorite) {
        addToBackup(trackId);
    } else {
        removeFromBackup(trackId);
    }

    emit favoriteChanged(trackId, favorite);
    emit countChanged();
}

bool FavoritesManager::isFavorite(int trackId) const
{
    if (!m_dbManager) return false;
    return m_dbManager->isTrackFavorite(trackId);
}

int FavoritesManager::count() const
{
    if (!m_dbManager) return 0;
    return m_dbManager->getFavoriteTrackCount();
}

FavoritesManager::TrackInfo FavoritesManager::getTrackInfo(int trackId) const
{
    TrackInfo info;
    if (!m_dbManager) return info;

    QVariantMap trackData = m_dbManager->getTrack(trackId);
    if (trackData.isEmpty()) return info;

    info.filePath = trackData.value("filePath").toString();
    info.artist = trackData.value("artist").toString();
    info.album = trackData.value("album").toString();
    info.title = trackData.value("title").toString();
    info.trackNumber = trackData.value("trackNumber").toInt();

    return info;
}

void FavoritesManager::addToBackup(int trackId)
{
    if (!m_backupDb.isOpen()) return;

    TrackInfo info = getTrackInfo(trackId);
    if (info.filePath.isEmpty()) return;

    QSqlQuery query(m_backupDb);
    query.prepare(
        "INSERT OR REPLACE INTO favorites (file_path, artist, album, title, track_number, added_at) "
        "VALUES (:filePath, :artist, :album, :title, :trackNumber, CURRENT_TIMESTAMP)"
    );
    query.bindValue(":filePath", info.filePath);
    query.bindValue(":artist", info.artist);
    query.bindValue(":album", info.album);
    query.bindValue(":title", info.title);
    query.bindValue(":trackNumber", info.trackNumber);

    if (!query.exec()) {
        qWarning() << "FavoritesManager: Failed to add to backup:" << query.lastError().text();
    }
}

void FavoritesManager::removeFromBackup(int trackId)
{
    if (!m_backupDb.isOpen()) return;

    TrackInfo info = getTrackInfo(trackId);
    if (info.filePath.isEmpty()) return;

    QSqlQuery query(m_backupDb);
    query.prepare("DELETE FROM favorites WHERE file_path = :filePath");
    query.bindValue(":filePath", info.filePath);

    if (!query.exec()) {
        qWarning() << "FavoritesManager: Failed to remove from backup:" << query.lastError().text();
    }
}

void FavoritesManager::restoreFromBackup()
{
    if (!m_backupDb.isOpen() || !m_dbManager) {
        qWarning() << "FavoritesManager: Cannot restore - database not available";
        return;
    }

    qDebug() << "FavoritesManager: Restoring favorites from backup...";

    QSqlQuery query(m_backupDb);
    query.exec("SELECT file_path, artist, album, title, track_number FROM favorites ORDER BY added_at ASC");

    int restoredCount = 0;
    int notFoundCount = 0;

    while (query.next()) {
        QString filePath = query.value("file_path").toString();
        QString artist = query.value("artist").toString();
        QString album = query.value("album").toString();
        QString title = query.value("title").toString();
        int trackNumber = query.value("track_number").toInt();

        // Try to find track by file path first
        int trackId = m_dbManager->getTrackIdByPath(filePath);

        // If not found, try metadata fallback
        if (trackId <= 0) {
            trackId = m_dbManager->findTrackByMetadata(artist, album, title, trackNumber);
        }

        if (trackId > 0) {
            // Restore favorite status (directly to DB, don't update backup)
            m_dbManager->setTrackFavorite(trackId, true);
            restoredCount++;
        } else {
            notFoundCount++;
            qDebug() << "FavoritesManager: Could not find track for favorite:" << filePath;
        }
    }

    qDebug() << "FavoritesManager: Restored" << restoredCount << "favorites," << notFoundCount << "not found";

    if (restoredCount > 0) {
        emit favoritesRestored(restoredCount);
        emit countChanged();
    }
}

void FavoritesManager::clearBackup()
{
    if (!m_backupDb.isOpen()) return;

    QSqlQuery query(m_backupDb);
    if (!query.exec("DELETE FROM favorites")) {
        qWarning() << "FavoritesManager: Failed to clear backup:" << query.lastError().text();
    } else {
        qDebug() << "FavoritesManager: Backup cleared";
    }
}

} // namespace Mtoc
