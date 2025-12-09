#ifndef FAVORITESMANAGER_H
#define FAVORITESMANAGER_H

#include <QObject>
#include <QString>
#include <QSqlDatabase>

namespace Mtoc {

class DatabaseManager;

class FavoritesManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit FavoritesManager(DatabaseManager* dbManager, QObject *parent = nullptr);
    ~FavoritesManager();

    // Main favorites operations
    Q_INVOKABLE void toggleFavorite(int trackId);
    Q_INVOKABLE void setFavorite(int trackId, bool favorite);
    Q_INVOKABLE bool isFavorite(int trackId) const;

    // Count property
    int count() const;

    // Backup database operations
    void restoreFromBackup();
    void clearBackup();

signals:
    void favoriteChanged(int trackId, bool isFavorite);
    void favoritesRestored(int count);
    void countChanged();

private:
    void initializeBackupDatabase();
    void addToBackup(int trackId);
    void removeFromBackup(int trackId);
    QString getBackupDatabasePath() const;

    // Get track info for backup storage
    struct TrackInfo {
        QString filePath;
        QString artist;
        QString album;
        QString title;
        int trackNumber;
    };
    TrackInfo getTrackInfo(int trackId) const;

    DatabaseManager* m_dbManager;
    QSqlDatabase m_backupDb;
    QString m_backupDbPath;
    static const QString BACKUP_DB_CONNECTION_NAME;
};

} // namespace Mtoc

#endif // FAVORITESMANAGER_H
