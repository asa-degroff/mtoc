#include "playlistmanager.h"
#include "backend/library/librarymanager.h"
#include "backend/library/track.h"
#include "backend/playback/mediaplayer.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QFileInfo>
#include <QDebug>
#include <QDateTime>
#include <QVariantMap>
#include <QUrl>

using Mtoc::LibraryManager;
using Mtoc::Track;

PlaylistManager* PlaylistManager::s_instance = nullptr;

PlaylistManager::PlaylistManager(QObject *parent)
    : QObject(parent)
{
}

PlaylistManager::~PlaylistManager()
{
}

PlaylistManager* PlaylistManager::instance()
{
    if (!s_instance) {
        s_instance = new PlaylistManager();
    }
    return s_instance;
}

void PlaylistManager::setLibraryManager(Mtoc::LibraryManager* manager)
{
    m_libraryManager = manager;
    initialize();
}

void PlaylistManager::initialize()
{
    if (!m_libraryManager) {
        qWarning() << "PlaylistManager: Cannot initialize without LibraryManager";
        return;
    }
    
    ensurePlaylistsDirectory();
    refreshPlaylists();
    setReady(true);
}

void PlaylistManager::ensurePlaylistsDirectory()
{
    if (!m_libraryManager) return;
    
    QStringList musicFolders = m_libraryManager->musicFolders();
    if (musicFolders.isEmpty()) {
        qWarning() << "PlaylistManager: No music folders configured";
        return;
    }
    
    // Use the first music folder as the base
    QString baseDir = musicFolders.first();
    m_playlistsDirectory = QDir(baseDir).absoluteFilePath("Playlists");
    
    QDir dir(m_playlistsDirectory);
    if (!dir.exists()) {
        if (!dir.mkpath(".")) {
            qWarning() << "PlaylistManager: Failed to create playlists directory:" << m_playlistsDirectory;
        } else {
            qDebug() << "PlaylistManager: Created playlists directory:" << m_playlistsDirectory;
        }
    }
    
    emit playlistsDirectoryChanged();
}

void PlaylistManager::refreshPlaylists()
{
    m_playlists.clear();
    
    if (m_playlistsDirectory.isEmpty()) {
        emit playlistsChanged();
        return;
    }
    
    QDir dir(m_playlistsDirectory);
    if (!dir.exists()) {
        emit playlistsChanged();
        return;
    }
    
    // Get all .m3u files
    QStringList filters;
    filters << "*.m3u" << "*.m3u8";
    dir.setNameFilters(filters);
    dir.setSorting(QDir::Time | QDir::Reversed); // Newest first
    
    QStringList files = dir.entryList(QDir::Files);
    for (const QString& file : files) {
        // Remove extension for display
        QString name = file;
        if (name.endsWith(".m3u8")) {
            name.chop(5);
        } else if (name.endsWith(".m3u")) {
            name.chop(4);
        }
        m_playlists.append(name);
    }
    
    emit playlistsChanged();
}

QString PlaylistManager::generatePlaylistName() const
{
    QDateTime now = QDateTime::currentDateTime();
    return now.toString("yyyy-MM-dd_HH-mm-ss");
}

bool PlaylistManager::saveQueueAsPlaylist()
{
    if (!m_mediaPlayer) {
        emit error("MediaPlayer not available");
        return false;
    }
    
    QVariantList queue = m_mediaPlayer->queue();
    if (queue.isEmpty()) {
        emit error("Queue is empty");
        return false;
    }
    
    QString name = generatePlaylistName();
    return savePlaylist(queue, name);
}

bool PlaylistManager::savePlaylist(const QVariantList& tracks, const QString& name)
{
    if (m_playlistsDirectory.isEmpty()) {
        emit error("Playlists directory not configured");
        return false;
    }
    
    QString playlistName = name.isEmpty() ? generatePlaylistName() : name;
    QString filename = playlistName + ".m3u";
    QString filepath = QDir(m_playlistsDirectory).absoluteFilePath(filename);
    
    if (writeM3UFile(filepath, tracks)) {
        refreshPlaylists();
        emit playlistSaved(playlistName);
        return true;
    }
    
    return false;
}

bool PlaylistManager::writeM3UFile(const QString& filepath, const QVariantList& tracks)
{
    QFile file(filepath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit error("Failed to create playlist file: " + file.errorString());
        return false;
    }
    
    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    
    // Write extended M3U header
    stream << "#EXTM3U\n";
    
    for (const QVariant& trackVar : tracks) {
        QVariantMap track = trackVar.toMap();
        QString filePath = track.value("filePath").toString();
        
        if (filePath.isEmpty()) continue;
        
        // Write extended info if available
        QString title = track.value("title").toString();
        QString artist = track.value("artist").toString();
        int duration = track.value("duration").toInt(); // Already in seconds
        
        if (!title.isEmpty()) {
            stream << "#EXTINF:" << duration << ",";
            if (!artist.isEmpty()) {
                stream << artist << " - ";
            }
            stream << title << "\n";
        }
        
        // Try to make relative path if possible
        QString pathToWrite = makeRelativePath(filePath);
        stream << pathToWrite << "\n";
    }
    
    file.close();
    return true;
}

QString PlaylistManager::makeRelativePath(const QString& filePath) const
{
    if (!m_libraryManager) return filePath;
    
    QStringList musicFolders = m_libraryManager->musicFolders();
    QString playlistDir = QFileInfo(m_playlistsDirectory).canonicalFilePath();
    
    // Check if file is within any music folder
    for (const QString& musicFolder : musicFolders) {
        QString canonicalMusicFolder = QFileInfo(musicFolder).canonicalFilePath();
        QString canonicalFilePath = QFileInfo(filePath).canonicalFilePath();
        
        if (canonicalFilePath.startsWith(canonicalMusicFolder)) {
            // Calculate relative path from playlist directory
            QDir playlistDirObj(playlistDir);
            QString relativePath = playlistDirObj.relativeFilePath(canonicalFilePath);
            
            // Only use relative path if it doesn't go up too many levels
            int upLevels = relativePath.count("../");
            if (upLevels <= 2) {
                return relativePath;
            }
        }
    }
    
    // Use absolute path if not in music folders or too many levels up
    return filePath;
}

QVariantList PlaylistManager::loadPlaylist(const QString& name)
{
    QString filename = name + ".m3u";
    if (!QFileInfo(name).suffix().isEmpty()) {
        filename = name; // Already has extension
    }
    
    QString filepath = QDir(m_playlistsDirectory).absoluteFilePath(filename);
    return readM3UFile(filepath);
}

QVariantList PlaylistManager::readM3UFile(const QString& filepath)
{
    QVariantList tracks;
    
    QFile file(filepath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit error("Failed to open playlist file: " + file.errorString());
        return tracks;
    }
    
    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    
    QString line;
    QString currentTitle;
    QString currentArtist;
    int currentDuration = 0;
    
    while (!stream.atEnd()) {
        line = stream.readLine().trimmed();
        
        if (line.isEmpty() || line.startsWith("#EXTM3U")) {
            continue;
        }
        
        if (line.startsWith("#EXTINF:")) {
            // Parse extended info
            QString info = line.mid(8); // Skip "#EXTINF:"
            int commaPos = info.indexOf(',');
            if (commaPos > 0) {
                currentDuration = info.left(commaPos).toInt(); // Already in seconds
                QString titleInfo = info.mid(commaPos + 1);
                
                // Try to split artist - title
                int dashPos = titleInfo.indexOf(" - ");
                if (dashPos > 0) {
                    currentArtist = titleInfo.left(dashPos);
                    currentTitle = titleInfo.mid(dashPos + 3);
                } else {
                    currentTitle = titleInfo;
                    currentArtist.clear();
                }
            }
        } else if (!line.startsWith("#")) {
            // This is a file path
            QString resolvedPath = resolvePlaylistPath(line, filepath);
            
            if (!resolvedPath.isEmpty() && QFile::exists(resolvedPath)) {
                // Try to get track info from library
                if (m_libraryManager) {
                    Mtoc::Track* track = m_libraryManager->trackByPath(resolvedPath);
                    if (track) {
                        QVariantMap trackMap;
                        trackMap["filePath"] = track->filePath();
                        trackMap["title"] = track->title();
                        trackMap["artist"] = track->artist();
                        trackMap["album"] = track->album();
                        trackMap["albumArtist"] = track->albumArtist();
                        trackMap["trackNumber"] = track->trackNumber();
                        trackMap["duration"] = track->duration();
                        tracks.append(trackMap);
                        continue;
                    }
                }
                
                // Fallback: create basic track info
                QVariantMap trackMap;
                trackMap["filePath"] = resolvedPath;
                trackMap["title"] = currentTitle.isEmpty() ? QFileInfo(resolvedPath).baseName() : currentTitle;
                trackMap["artist"] = currentArtist;
                trackMap["duration"] = currentDuration;
                tracks.append(trackMap);
            }
            
            // Reset for next track
            currentTitle.clear();
            currentArtist.clear();
            currentDuration = 0;
        }
    }
    
    file.close();
    return tracks;
}

QString PlaylistManager::resolvePlaylistPath(const QString& playlistPath, const QString& playlistFile) const
{
    // If absolute path, use as is
    if (QFileInfo(playlistPath).isAbsolute()) {
        return playlistPath;
    }
    
    // Resolve relative to playlist file location
    QDir playlistDir = QFileInfo(playlistFile).dir();
    QString resolved = playlistDir.absoluteFilePath(playlistPath);
    
    // Clean up the path
    return QDir::cleanPath(resolved);
}

bool PlaylistManager::deletePlaylist(const QString& name)
{
    QString filename = name + ".m3u";
    if (!QFileInfo(name).suffix().isEmpty()) {
        filename = name;
    }
    
    QString filepath = QDir(m_playlistsDirectory).absoluteFilePath(filename);
    
    if (QFile::remove(filepath)) {
        refreshPlaylists();
        emit playlistDeleted(name);
        return true;
    }
    
    emit error("Failed to delete playlist");
    return false;
}

bool PlaylistManager::renamePlaylist(const QString& oldName, const QString& newName)
{
    if (newName.isEmpty()) {
        emit error("New name cannot be empty");
        return false;
    }
    
    QString oldFilename = oldName + ".m3u";
    QString newFilename = newName + ".m3u";
    
    QString oldPath = QDir(m_playlistsDirectory).absoluteFilePath(oldFilename);
    QString newPath = QDir(m_playlistsDirectory).absoluteFilePath(newFilename);
    
    if (QFile::exists(newPath)) {
        emit error("A playlist with that name already exists");
        return false;
    }
    
    if (QFile::rename(oldPath, newPath)) {
        refreshPlaylists();
        emit playlistRenamed(oldName, newName);
        return true;
    }
    
    emit error("Failed to rename playlist");
    return false;
}

QVariantList PlaylistManager::getPlaylistTracks(const QString& name)
{
    return loadPlaylist(name);
}

int PlaylistManager::getPlaylistTrackCount(const QString& name)
{
    QVariantList tracks = loadPlaylist(name);
    return tracks.size();
}

int PlaylistManager::getPlaylistDuration(const QString& name)
{
    QVariantList tracks = loadPlaylist(name);
    int totalDuration = 0;
    
    for (const QVariant& trackVar : tracks) {
        QVariantMap track = trackVar.toMap();
        totalDuration += track.value("duration").toInt();
    }
    
    return totalDuration;
}

QString PlaylistManager::getPlaylistModifiedDate(const QString& name)
{
    QString filename = name + ".m3u";
    QString filepath = QDir(m_playlistsDirectory).absoluteFilePath(filename);
    
    QFileInfo info(filepath);
    if (info.exists()) {
        return info.lastModified().toString("yyyy-MM-dd hh:mm");
    }
    
    return QString();
}

void PlaylistManager::setReady(bool ready)
{
    if (m_isReady != ready) {
        m_isReady = ready;
        emit readyChanged(ready);
    }
}