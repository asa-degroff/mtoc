#ifndef PLAYLISTMANAGER_H
#define PLAYLISTMANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QDateTime>

namespace Mtoc {
class Track;
class LibraryManager;
}

class MediaPlayer;

class PlaylistManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList playlists READ playlists NOTIFY playlistsChanged)
    Q_PROPERTY(QString playlistsDirectory READ playlistsDirectory NOTIFY playlistsDirectoryChanged)
    Q_PROPERTY(QStringList playlistFolders READ playlistFolders NOTIFY playlistFoldersChanged)
    Q_PROPERTY(QStringList playlistFoldersDisplay READ playlistFoldersDisplay NOTIFY playlistFoldersChanged)
    Q_PROPERTY(QString defaultPlaylistFolder READ defaultPlaylistFolder NOTIFY defaultPlaylistFolderChanged)
    Q_PROPERTY(bool isReady READ isReady NOTIFY readyChanged)

public:
    static PlaylistManager* instance();
    
    // Getters
    QStringList playlists() const { return m_playlists; }
    QString playlistsDirectory() const { return m_playlistsDirectory; }
    QStringList playlistFolders() const { return m_playlistFolders; }
    QStringList playlistFoldersDisplay() const;
    QString defaultPlaylistFolder() const { return m_defaultPlaylistFolder; }
    bool isReady() const { return m_isReady; }
    
    void setLibraryManager(Mtoc::LibraryManager* manager);
    void setMediaPlayer(MediaPlayer* player) { m_mediaPlayer = player; }
    
    // Playlist operations
    Q_INVOKABLE bool savePlaylist(const QVariantList& tracks, const QString& name = QString());
    Q_INVOKABLE bool saveQueueAsPlaylist();
    Q_INVOKABLE QVariantList loadPlaylist(const QString& name);
    Q_INVOKABLE bool deletePlaylist(const QString& name);
    Q_INVOKABLE bool renamePlaylist(const QString& oldName, const QString& newName);
    Q_INVOKABLE bool updatePlaylist(const QString& name, const QVariantList& tracks);
    Q_INVOKABLE QVariantList getPlaylistTracks(const QString& name);
    Q_INVOKABLE int getPlaylistTrackCount(const QString& name);
    Q_INVOKABLE int getPlaylistDuration(const QString& name);
    Q_INVOKABLE QString getPlaylistModifiedDate(const QString& name);
    
    // Special playlist support
    Q_INVOKABLE bool isSpecialPlaylist(const QString& name) const;
    
    // Initialize and refresh
    void initialize();
    Q_INVOKABLE void refreshPlaylists();
    
    // Playlist folder management
    Q_INVOKABLE bool addPlaylistFolder(const QString& path);
    Q_INVOKABLE bool removePlaylistFolder(const QString& path);
    Q_INVOKABLE bool setDefaultPlaylistFolder(const QString& path);

signals:
    void playlistsChanged();
    void playlistsDirectoryChanged();
    void playlistFoldersChanged();
    void defaultPlaylistFolderChanged();
    void readyChanged(bool ready);
    void playlistSaved(const QString& name);
    void playlistDeleted(const QString& name);
    void playlistRenamed(const QString& oldName, const QString& newName);
    void error(const QString& message);

private:
    explicit PlaylistManager(QObject *parent = nullptr);
    ~PlaylistManager();
    
    void ensurePlaylistsDirectory();
    QString generatePlaylistName(const QVariantList& tracks) const;
    bool writeM3UFile(const QString& filepath, const QVariantList& tracks);
    QVariantList readM3UFile(const QString& filepath);
    QString makeRelativePath(const QString& filePath) const;
    QString resolvePlaylistPath(const QString& playlistPath, const QString& playlistFile) const;
    void setReady(bool ready);
    void savePlaylistFoldersConfig();
    void loadPlaylistFoldersConfig();
    QString createDisplayPath(const QString& path) const;
    
    static PlaylistManager* s_instance;
    Mtoc::LibraryManager* m_libraryManager = nullptr;
    MediaPlayer* m_mediaPlayer = nullptr;
    QStringList m_playlists;
    QStringList m_specialPlaylists;
    QString m_playlistsDirectory;  // Legacy single directory
    QStringList m_playlistFolders;  // All playlist directories
    QString m_defaultPlaylistFolder;  // Default directory for new playlists
    QHash<QString, QString> m_folderDisplayPaths;  // Maps canonical paths to display paths
    bool m_isReady = false;
};

#endif // PLAYLISTMANAGER_H