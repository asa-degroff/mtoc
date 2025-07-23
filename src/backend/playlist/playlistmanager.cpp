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
#include <QSettings>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSet>

using Mtoc::LibraryManager;
using Mtoc::Track;

PlaylistManager* PlaylistManager::s_instance = nullptr;

PlaylistManager::PlaylistManager(QObject *parent)
    : QObject(parent)
{
    // Initialize special playlists
    m_specialPlaylists << "All Songs";
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
    
    loadPlaylistFoldersConfig();
    ensurePlaylistsDirectory();
    refreshPlaylists();
    setReady(true);
}

void PlaylistManager::ensurePlaylistsDirectory()
{
    if (!m_libraryManager) return;
    
    // If no playlist folders are configured, set up the default
    if (m_playlistFolders.isEmpty()) {
        QStringList musicFolders = m_libraryManager->musicFolders();
        if (musicFolders.isEmpty()) {
            qWarning() << "PlaylistManager: No music folders configured";
            return;
        }
        
        // Use the first music folder as the base for the default playlist directory
        QString baseDir = musicFolders.first();
        QString defaultDir = QDir(baseDir).absoluteFilePath("Playlists");
        
        // Create the default directory if it doesn't exist
        QDir dir(defaultDir);
        if (!dir.exists()) {
            if (!dir.mkpath(".")) {
                qWarning() << "PlaylistManager: Failed to create default playlists directory:" << defaultDir;
                return;
            } else {
                qDebug() << "PlaylistManager: Created default playlists directory:" << defaultDir;
            }
        }
        
        // Add it as the first and default playlist folder
        m_playlistFolders.append(defaultDir);
        m_defaultPlaylistFolder = defaultDir;
        m_playlistsDirectory = defaultDir; // Keep legacy compatibility
        
        savePlaylistFoldersConfig();
        emit playlistFoldersChanged();
        emit defaultPlaylistFolderChanged();
        emit playlistsDirectoryChanged();
    } else {
        // Ensure all configured playlist folders exist
        for (const QString& folder : m_playlistFolders) {
            QDir dir(folder);
            if (!dir.exists()) {
                if (!dir.mkpath(".")) {
                    qWarning() << "PlaylistManager: Failed to create playlist directory:" << folder;
                }
            }
        }
        
        // Update legacy directory to the default folder
        m_playlistsDirectory = m_defaultPlaylistFolder;
        emit playlistsDirectoryChanged();
    }
}

void PlaylistManager::refreshPlaylists()
{
    m_playlists.clear();
    
    // Add special playlists first
    m_playlists.append(m_specialPlaylists);
    
    if (m_playlistFolders.isEmpty()) {
        emit playlistsChanged();
        return;
    }
    
    // Set to track unique playlist names across all folders
    QSet<QString> uniquePlaylists;
    
    // Scan all playlist folders
    for (const QString& folderPath : m_playlistFolders) {
        QDir dir(folderPath);
        if (!dir.exists()) {
            continue;
        }
        
        // Get all .m3u files
        QStringList filters;
        filters << "*.m3u" << "*.m3u8";
        dir.setNameFilters(filters);
        dir.setSorting(QDir::Time); // Sort by modification time, newest first
        
        QStringList files = dir.entryList(QDir::Files);
        for (const QString& file : files) {
            // Remove extension for display
            QString name = file;
            if (name.endsWith(".m3u8")) {
                name.chop(5);
            } else if (name.endsWith(".m3u")) {
                name.chop(4);
            }
            uniquePlaylists.insert(name);
        }
    }
    
    // Add unique playlists to the list
    m_playlists.append(uniquePlaylists.values());
    
    emit playlistsChanged();
}

QString PlaylistManager::generatePlaylistName(const QVariantList& tracks) const
{
    if (tracks.isEmpty()) {
        // Fallback to date-based name if no tracks
        QDateTime now = QDateTime::currentDateTime();
        return now.toString("yyyy-MM-dd_HH-mm-ss");
    }
    
    // Get the first track's title
    QVariantMap firstTrack = tracks.first().toMap();
    QString firstTitle = firstTrack.value("title").toString();
    
    if (firstTitle.isEmpty()) {
        // Fallback to date-based name if no title
        QDateTime now = QDateTime::currentDateTime();
        return now.toString("yyyy-MM-dd_HH-mm-ss");
    }
    
    // Sanitize the title to remove characters not allowed in filenames
    QString sanitizedTitle = firstTitle;
    // Remove or replace problematic characters
    sanitizedTitle.replace("/", "-");
    sanitizedTitle.replace("\\", "-");
    sanitizedTitle.replace(":", "-");
    sanitizedTitle.replace("*", "-");
    sanitizedTitle.replace("?", "-");
    sanitizedTitle.replace("\"", "'");
    sanitizedTitle.replace("<", "-");
    sanitizedTitle.replace(">", "-");
    sanitizedTitle.replace("|", "-");
    sanitizedTitle.remove(QChar('\0')); // Remove null characters
    
    // Trim whitespace and limit length
    sanitizedTitle = sanitizedTitle.trimmed();
    if (sanitizedTitle.length() > 50) {
        sanitizedTitle = sanitizedTitle.left(50).trimmed();
    }
    
    // Calculate number of additional tracks
    int additionalTracks = tracks.size() - 1;
    
    // Generate the name
    QString playlistName;
    if (additionalTracks > 0) {
        playlistName = QString("%1 +%2").arg(sanitizedTitle).arg(additionalTracks);
    } else {
        playlistName = sanitizedTitle;
    }
    
    return playlistName;
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
    
    QString name = generatePlaylistName(queue);
    return savePlaylist(queue, name);
}

bool PlaylistManager::savePlaylist(const QVariantList& tracks, const QString& name)
{
    if (m_defaultPlaylistFolder.isEmpty()) {
        emit error("Default playlist folder not configured");
        return false;
    }
    
    QString playlistName = name.isEmpty() ? generatePlaylistName(tracks) : name;
    QString filename = playlistName + ".m3u";
    QString filepath = QDir(m_defaultPlaylistFolder).absoluteFilePath(filename);
    
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
        // MediaPlayer returns duration in milliseconds, but M3U expects seconds
        int duration = track.value("duration").toInt() / 1000;
        
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
    // Handle special playlists
    if (name == "All Songs") {
        // Return empty list - the UI should use LibraryManager.getAllSongsPlaylist() instead
        // This is a virtual playlist that shouldn't be loaded as a regular playlist
        return QVariantList();
    }
    
    QString filename = name;
    if (!name.endsWith(".m3u") && !name.endsWith(".m3u8")) {
        filename = name + ".m3u";
    }
    
    // Search for the playlist in all configured folders
    for (const QString& folderPath : m_playlistFolders) {
        QString filepath = QDir(folderPath).absoluteFilePath(filename);
        if (QFile::exists(filepath)) {
            return readM3UFile(filepath);
        }
        
        // Also try with .m3u8 extension
        if (!filename.endsWith(".m3u8")) {
            QString filepathM3u8 = QDir(folderPath).absoluteFilePath(name + ".m3u8");
            if (QFile::exists(filepathM3u8)) {
                return readM3UFile(filepathM3u8);
            }
        }
    }
    
    // Fallback to legacy directory if not found
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
    QString currentAlbum;
    QString currentAlbumArtist;
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
                        qDebug() << "PlaylistManager: Found track in library:" << track->title() 
                                 << "Album:" << track->album() << "AlbumArtist:" << track->albumArtist();
                        tracks.append(trackMap);
                        continue;
                    } else {
                        qDebug() << "PlaylistManager: Track not found in library:" << resolvedPath;
                    }
                }
                
                // Fallback: create basic track info
                QVariantMap trackMap;
                trackMap["filePath"] = resolvedPath;
                trackMap["title"] = currentTitle.isEmpty() ? QFileInfo(resolvedPath).baseName() : currentTitle;
                trackMap["artist"] = currentArtist;
                trackMap["album"] = currentAlbum;
                trackMap["albumArtist"] = currentAlbumArtist.isEmpty() ? currentArtist : currentAlbumArtist;
                trackMap["duration"] = currentDuration;
                tracks.append(trackMap);
            }
            
            // Reset for next track
            currentTitle.clear();
            currentArtist.clear();
            currentAlbum.clear();
            currentAlbumArtist.clear();
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
    // Prevent deletion of special playlists
    if (isSpecialPlaylist(name)) {
        emit error("Cannot delete special playlist");
        return false;
    }
    
    QString filename = name;
    if (!name.endsWith(".m3u") && !name.endsWith(".m3u8")) {
        filename = name + ".m3u";
    }
    
    // Search for the playlist in all configured folders
    for (const QString& folderPath : m_playlistFolders) {
        QString filepath = QDir(folderPath).absoluteFilePath(filename);
        if (QFile::exists(filepath)) {
            if (QFile::remove(filepath)) {
                refreshPlaylists();
                emit playlistDeleted(name);
                return true;
            }
        }
        
        // Also try with .m3u8 extension
        if (!filename.endsWith(".m3u8")) {
            QString filepathM3u8 = QDir(folderPath).absoluteFilePath(name + ".m3u8");
            if (QFile::exists(filepathM3u8)) {
                if (QFile::remove(filepathM3u8)) {
                    refreshPlaylists();
                    emit playlistDeleted(name);
                    return true;
                }
            }
        }
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

bool PlaylistManager::updatePlaylist(const QString& name, const QVariantList& tracks)
{
    if (name.isEmpty()) {
        emit error("Playlist name cannot be empty");
        return false;
    }
    
    if (m_playlistsDirectory.isEmpty()) {
        emit error("Playlists directory not configured");
        return false;
    }
    
    QString filename = name + ".m3u";
    QString filepath = QDir(m_playlistsDirectory).absoluteFilePath(filename);
    
    // Check if playlist exists
    if (!QFile::exists(filepath)) {
        emit error("Playlist does not exist");
        return false;
    }
    
    // Write the updated playlist
    if (writeM3UFile(filepath, tracks)) {
        refreshPlaylists();  // Refresh to update sort order after modification
        emit playlistSaved(name);
        return true;
    }
    
    return false;
}

QVariantList PlaylistManager::getPlaylistTracks(const QString& name)
{
    return loadPlaylist(name);
}

int PlaylistManager::getPlaylistTrackCount(const QString& name)
{
    // Handle special playlists
    if (name == "All Songs" && m_libraryManager) {
        return m_libraryManager->trackCount();
    }
    
    QVariantList tracks = loadPlaylist(name);
    return tracks.size();
}

int PlaylistManager::getPlaylistDuration(const QString& name)
{
    // Handle special playlists
    if (name == "All Songs" && m_libraryManager) {
        // Get total duration from database
        auto db = m_libraryManager->databaseManager();
        if (db) {
            return db->getTotalDuration();
        }
    }
    
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
    // Handle special playlists
    if (name == "All Songs") {
        // Return empty string or current date for special playlists
        return QString();
    }
    
    QString filename = name;
    if (!name.endsWith(".m3u") && !name.endsWith(".m3u8")) {
        filename = name + ".m3u";
    }
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

bool PlaylistManager::isSpecialPlaylist(const QString& name) const
{
    return m_specialPlaylists.contains(name);
}

bool PlaylistManager::addPlaylistFolder(const QString& path)
{
    if (path.isEmpty()) {
        emit error("Playlist folder path cannot be empty");
        return false;
    }
    
    // Check if folder already exists in the list
    if (m_playlistFolders.contains(path)) {
        emit error("Playlist folder already exists");
        return false;
    }
    
    // Create the directory if it doesn't exist
    QDir dir(path);
    if (!dir.exists()) {
        if (!dir.mkpath(".")) {
            emit error("Failed to create playlist directory: " + path);
            return false;
        }
    }
    
    m_playlistFolders.append(path);
    savePlaylistFoldersConfig();
    refreshPlaylists();
    emit playlistFoldersChanged();
    
    return true;
}

bool PlaylistManager::removePlaylistFolder(const QString& path)
{
    if (path.isEmpty()) {
        emit error("Playlist folder path cannot be empty");
        return false;
    }
    
    // Don't allow removing the default folder
    if (path == m_defaultPlaylistFolder) {
        emit error("Cannot remove the default playlist folder");
        return false;
    }
    
    if (!m_playlistFolders.contains(path)) {
        emit error("Playlist folder not found");
        return false;
    }
    
    m_playlistFolders.removeAll(path);
    savePlaylistFoldersConfig();
    refreshPlaylists();
    emit playlistFoldersChanged();
    
    return true;
}

bool PlaylistManager::setDefaultPlaylistFolder(const QString& path)
{
    if (path.isEmpty()) {
        emit error("Default playlist folder path cannot be empty");
        return false;
    }
    
    // Check if the folder is in our list
    if (!m_playlistFolders.contains(path)) {
        emit error("Folder must be in the playlist folders list");
        return false;
    }
    
    m_defaultPlaylistFolder = path;
    m_playlistsDirectory = path; // Update legacy directory
    savePlaylistFoldersConfig();
    emit defaultPlaylistFolderChanged();
    emit playlistsDirectoryChanged();
    
    return true;
}

void PlaylistManager::savePlaylistFoldersConfig()
{
    QSettings settings;
    
    // Save playlist folders as JSON array
    QJsonArray foldersArray;
    for (const QString& folder : m_playlistFolders) {
        foldersArray.append(folder);
    }
    
    QJsonDocument doc(foldersArray);
    settings.setValue("playlistFolders", doc.toJson());
    
    // Save default playlist folder
    settings.setValue("defaultPlaylistFolder", m_defaultPlaylistFolder);
}

void PlaylistManager::loadPlaylistFoldersConfig()
{
    QSettings settings;
    
    // Load playlist folders
    QByteArray foldersData = settings.value("playlistFolders").toByteArray();
    if (!foldersData.isEmpty()) {
        QJsonDocument doc = QJsonDocument::fromJson(foldersData);
        if (doc.isArray()) {
            QJsonArray foldersArray = doc.array();
            m_playlistFolders.clear();
            for (const QJsonValue& value : foldersArray) {
                if (value.isString()) {
                    m_playlistFolders.append(value.toString());
                }
            }
        }
    }
    
    // Load default playlist folder
    QString defaultFolder = settings.value("defaultPlaylistFolder").toString();
    if (!defaultFolder.isEmpty() && m_playlistFolders.contains(defaultFolder)) {
        m_defaultPlaylistFolder = defaultFolder;
        m_playlistsDirectory = defaultFolder; // Update legacy directory
    } else if (!m_playlistFolders.isEmpty()) {
        // If no default or invalid default, use the first folder
        m_defaultPlaylistFolder = m_playlistFolders.first();
        m_playlistsDirectory = m_defaultPlaylistFolder;
    }
}