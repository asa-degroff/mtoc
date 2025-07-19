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
    Q_PROPERTY(bool isReady READ isReady NOTIFY readyChanged)

public:
    static PlaylistManager* instance();
    
    // Getters
    QStringList playlists() const { return m_playlists; }
    QString playlistsDirectory() const { return m_playlistsDirectory; }
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
    
    // Initialize and refresh
    void initialize();
    Q_INVOKABLE void refreshPlaylists();

signals:
    void playlistsChanged();
    void playlistsDirectoryChanged();
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
    
    static PlaylistManager* s_instance;
    Mtoc::LibraryManager* m_libraryManager = nullptr;
    MediaPlayer* m_mediaPlayer = nullptr;
    QStringList m_playlists;
    QString m_playlistsDirectory;
    bool m_isReady = false;
};

#endif // PLAYLISTMANAGER_H