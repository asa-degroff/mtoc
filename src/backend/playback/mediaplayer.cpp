#include "mediaplayer.h"
#include "backend/library/track.h"
#include "backend/library/album.h"
#include "backend/library/librarymanager.h"
#include <QDebug>
#include <QFile>
#include <QDateTime>
#include <QTextStream>
#include <QStandardPaths>
#include <QDir>

QString MediaPlayer::getDebugLogPath()
{
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataPath); // Ensure the directory exists
    return QDir(dataPath).filePath("debug_log.txt");
}

MediaPlayer::MediaPlayer(QObject *parent)
    : QObject(parent)
    , m_audioEngine(std::make_unique<AudioEngine>(this))
{
    setupConnections();
    
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() << " - MediaPlayer initialized" << Qt::endl;
    }
}

MediaPlayer::~MediaPlayer()
{
    // Clean up any remaining tracks in the queue
    clearQueue();
}

void MediaPlayer::setupConnections()
{
    connect(m_audioEngine.get(), &AudioEngine::stateChanged,
            this, &MediaPlayer::onEngineStateChanged);
    
    connect(m_audioEngine.get(), &AudioEngine::positionChanged,
            this, &MediaPlayer::positionChanged);
    
    connect(m_audioEngine.get(), &AudioEngine::durationChanged,
            this, &MediaPlayer::durationChanged);
    
    connect(m_audioEngine.get(), &AudioEngine::trackFinished,
            this, &MediaPlayer::handleTrackFinished);
    
    connect(m_audioEngine.get(), &AudioEngine::error,
            this, &MediaPlayer::error);
}

MediaPlayer::State MediaPlayer::state() const
{
    return m_state;
}

qint64 MediaPlayer::position() const
{
    return m_audioEngine->position();
}

qint64 MediaPlayer::duration() const
{
    return m_audioEngine->duration();
}

float MediaPlayer::volume() const
{
    return m_audioEngine->volume();
}

void MediaPlayer::setVolume(float volume)
{
    m_audioEngine->setVolume(volume);
    emit volumeChanged(volume);
}

bool MediaPlayer::hasNext() const
{
    return m_currentQueueIndex >= 0 && m_currentQueueIndex < m_playbackQueue.size() - 1;
}

bool MediaPlayer::hasPrevious() const
{
    // Only return true if we can actually go to a previous track
    // (i.e., we're not on the first track)
    return m_currentQueueIndex > 0 && m_playbackQueue.size() > 0;
}

void MediaPlayer::play()
{
    if (m_state == PausedState) {
        m_audioEngine->play();
    } else if (m_currentTrack && m_state == StoppedState) {
        m_audioEngine->loadTrack(m_currentTrack->filePath());
        m_audioEngine->play();
    }
}

void MediaPlayer::pause()
{
    if (m_state == PlayingState) {
        m_audioEngine->pause();
    }
}

void MediaPlayer::stop()
{
    m_audioEngine->stop();
    m_currentQueueIndex = -1;
    clearQueue();
}

void MediaPlayer::togglePlayPause()
{
    if (m_state == PlayingState) {
        pause();
    } else {
        play();
    }
}

void MediaPlayer::next()
{
    if (hasNext()) {
        m_currentQueueIndex++;
        Mtoc::Track* nextTrack = m_playbackQueue[m_currentQueueIndex];
        playTrack(nextTrack);
        emit playbackQueueChanged();
    }
}

void MediaPlayer::previous()
{
    if (position() > 3000) {
        seek(0);
    } else if (hasPrevious()) {
        m_currentQueueIndex--;
        Mtoc::Track* prevTrack = m_playbackQueue[m_currentQueueIndex];
        playTrack(prevTrack);
        emit playbackQueueChanged();
    } else {
        seek(0);
    }
}

void MediaPlayer::seek(qint64 position)
{
    m_audioEngine->seek(position);
}

void MediaPlayer::playTrack(Mtoc::Track* track)
{
    if (!track) {
        qWarning() << "MediaPlayer::playTrack called with null track";
        return;
    }
    
    // Log to file only to reduce overhead
    // qDebug() << "MediaPlayer::playTrack called with track:" << track->title() 
    //          << "by" << track->artist() 
    //          << "path:" << track->filePath();
    
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Playing track: " << track->title() 
               << " by " << track->artist() << Qt::endl;
    }
    
    updateCurrentTrack(track);
    
    QString filePath = track->filePath();
    if (filePath.isEmpty()) {
        qWarning() << "Track has empty file path!";
        return;
    }
    
    // qDebug() << "Loading track into audio engine:" << filePath;
    m_audioEngine->loadTrack(filePath);
    m_audioEngine->play();
}

void MediaPlayer::playAlbum(Mtoc::Album* album, int startIndex)
{
    if (!album || album->tracks().isEmpty()) {
        return;
    }
    
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Playing album: " << album->title() 
               << " by " << album->artist() << Qt::endl;
    }
    
    clearQueue();
    
    m_currentAlbum = album;
    emit currentAlbumChanged(m_currentAlbum);
    
    m_playbackQueue = album->tracks();
    m_currentQueueIndex = qBound(0, startIndex, m_playbackQueue.size() - 1);
    
    emit playbackQueueChanged();
    
    if (!m_playbackQueue.isEmpty()) {
        playTrack(m_playbackQueue[m_currentQueueIndex]);
    }
}

void MediaPlayer::clearQueue()
{
    // Clean up any tracks we created
    for (auto track : m_playbackQueue) {
        if (track && track->parent() == this) {
            track->deleteLater();
        }
    }
    m_playbackQueue.clear();
    m_currentQueueIndex = -1;
    emit playbackQueueChanged();
}

void MediaPlayer::playAlbumByName(const QString& artist, const QString& title, int startIndex)
{
    qDebug() << "MediaPlayer::playAlbumByName called with artist:" << artist << "title:" << title << "startIndex:" << startIndex;
    
    if (!m_libraryManager) {
        qWarning() << "LibraryManager not set on MediaPlayer";
        return;
    }
    
    // Debug: Check library state
    qDebug() << "LibraryManager album count:" << m_libraryManager->albumCount();
    qDebug() << "LibraryManager track count:" << m_libraryManager->trackCount();
    
    // Since albumByTitle might not work with deferred loading, let's use a different approach
    // Get tracks for the album and create a temporary queue
    qDebug() << "Calling getTracksForAlbumAsVariantList with artist:" << artist << "title:" << title;
    auto trackList = m_libraryManager->getTracksForAlbumAsVariantList(artist, title);
    qDebug() << "Found" << trackList.size() << "tracks for album via getTracksForAlbumAsVariantList";
    
    if (!trackList.isEmpty()) {
        // Clear current queue and set up new one
        clearQueue();
        
        // Set the current album info
        m_currentAlbum = nullptr; // We don't have the actual album object
        
        // Build the queue from track data
        for (const auto& trackData : trackList) {
            auto trackMap = trackData.toMap();
            QString title = trackMap.value("title").toString();
            QString filePath = trackMap.value("filePath").toString();
            
            if (filePath.isEmpty()) {
                qWarning() << "Empty filePath for track:" << title;
                continue;
            }
            
            // Create a new Track object from the data
            Mtoc::Track* track = new Mtoc::Track(this);
            track->setTitle(title);
            track->setArtist(trackMap.value("artist").toString());
            track->setAlbum(trackMap.value("album").toString());
            track->setAlbumArtist(trackMap.value("albumArtist").toString());
            track->setTrackNumber(trackMap.value("trackNumber").toInt());
            track->setDuration(trackMap.value("duration").toInt());
            track->setFileUrl(QUrl::fromLocalFile(filePath));
            
            m_playbackQueue.append(track);
        }
        
        qDebug() << "Built queue with" << m_playbackQueue.size() << "tracks";
        
        if (!m_playbackQueue.isEmpty() && startIndex < m_playbackQueue.size()) {
            m_currentQueueIndex = startIndex;
            emit playbackQueueChanged();
            playTrack(m_playbackQueue[startIndex]);
        }
    } else {
        qWarning() << "No tracks found for album:" << artist << "-" << title;
    }
}

void MediaPlayer::playTrackFromData(const QVariant& trackData)
{
    auto trackMap = trackData.toMap();
    QString title = trackMap.value("title").toString();
    QString filePath = trackMap.value("filePath").toString();
    
    qDebug() << "MediaPlayer::playTrackFromData called with track:" << title << "path:" << filePath;
    
    if (filePath.isEmpty()) {
        qWarning() << "Empty filePath for track:" << title;
        return;
    }
    
    // Clear any existing queue
    clearQueue();
    
    // Create a new Track object from the data
    Mtoc::Track* track = new Mtoc::Track(this);
    track->setTitle(title);
    track->setArtist(trackMap.value("artist").toString());
    track->setAlbum(trackMap.value("album").toString());
    track->setAlbumArtist(trackMap.value("albumArtist").toString());
    track->setTrackNumber(trackMap.value("trackNumber").toInt());
    track->setDuration(trackMap.value("duration").toInt());
    track->setFileUrl(QUrl::fromLocalFile(filePath));
    
    // Add to queue so it gets cleaned up properly
    m_playbackQueue.append(track);
    m_currentQueueIndex = 0;
    
    // Play the single track
    playTrack(track);
    
    emit playbackQueueChanged();
}

void MediaPlayer::updateCurrentTrack(Mtoc::Track* track)
{
    if (m_currentTrack != track) {
        m_currentTrack = track;
        emit currentTrackChanged(track);
        
        // If we're not playing from an album queue, clear the current album
        if (m_playbackQueue.isEmpty() || !m_playbackQueue.contains(track)) {
            if (m_currentAlbum) {
                m_currentAlbum = nullptr;
                emit currentAlbumChanged(nullptr);
            }
        }
    }
}

void MediaPlayer::handleTrackFinished()
{
    QFile debugFile(getDebugLogPath());
    if (debugFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&debugFile);
        stream << QDateTime::currentDateTime().toString() 
               << " - Track finished, checking for next track" << Qt::endl;
    }
    
    if (hasNext()) {
        next();
    } else {
        m_state = StoppedState;
        emit stateChanged(m_state);
    }
}

void MediaPlayer::onEngineStateChanged(AudioEngine::State state)
{
    State newState = StoppedState;
    
    switch (state) {
    case AudioEngine::State::Playing:
        newState = PlayingState;
        break;
    case AudioEngine::State::Paused:
        newState = PausedState;
        break;
    default:
        newState = StoppedState;
        break;
    }
    
    if (m_state != newState) {
        m_state = newState;
        emit stateChanged(m_state);
    }
}