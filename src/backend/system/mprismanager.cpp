#include "mprismanager.h"
#include "../playback/mediaplayer.h"
#include "../library/track.h"
#include "../library/librarymanager.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusInterface>
#include <QApplication>
#include <QDebug>
#include <QFileInfo>
#include <QUrl>
#include <QPixmap>
#include <QStandardPaths>
#include <QDir>
#include <QTemporaryDir>
#include <QDateTime>
#include <QWidget>

// MediaPlayer2Adaptor implementation
MediaPlayer2Adaptor::MediaPlayer2Adaptor(QObject *parent)
    : QDBusAbstractAdaptor(parent)
{
}

QStringList MediaPlayer2Adaptor::supportedMimeTypes() const
{
    return QStringList() << "audio/mpeg" << "audio/ogg" << "audio/flac" 
                        << "audio/mp4" << "audio/x-wav" << "audio/x-ms-wma";
}

void MediaPlayer2Adaptor::Quit()
{
    emit quitRequested();
}

void MediaPlayer2Adaptor::Raise()
{
    emit raiseRequested();
}

// MediaPlayer2PlayerAdaptor implementation
MediaPlayer2PlayerAdaptor::MediaPlayer2PlayerAdaptor(MediaPlayer *parent)
    : QDBusAbstractAdaptor(parent), m_mediaPlayer(parent), m_mprisManager(nullptr)
{
}

void MediaPlayer2PlayerAdaptor::setMprisManager(MprisManager *manager)
{
    m_mprisManager = manager;
}

QString MediaPlayer2PlayerAdaptor::playbackStatus() const
{
    if (!m_mediaPlayer) return "Stopped";
    
    switch (m_mediaPlayer->state()) {
    case MediaPlayer::PlayingState:
        return "Playing";
    case MediaPlayer::PausedState:
        return "Paused";
    case MediaPlayer::StoppedState:
    default:
        return "Stopped";
    }
}

QVariantMap MediaPlayer2PlayerAdaptor::metadata() const
{
    QVariantMap metadata;
    if (!m_mediaPlayer || !m_mediaPlayer->currentTrack()) {
        return metadata;
    }

    Mtoc::Track *track = m_mediaPlayer->currentTrack();
    
    // Required MPRIS metadata fields
    metadata["mpris:trackid"] = QDBusObjectPath("/org/mtoc/track/" + QString::number(reinterpret_cast<quintptr>(track)));
    
    if (!track->title().isEmpty()) {
        metadata["xesam:title"] = track->title();
    }
    
    if (!track->artist().isEmpty()) {
        metadata["xesam:artist"] = QStringList() << track->artist();
    }
    
    if (!track->albumArtist().isEmpty()) {
        metadata["xesam:albumArtist"] = QStringList() << track->albumArtist();
    }
    
    if (!track->album().isEmpty()) {
        metadata["xesam:album"] = track->album();
    }
    
    if (!track->genre().isEmpty()) {
        metadata["xesam:genre"] = QStringList() << track->genre();
    }
    
    if (track->trackNumber() > 0) {
        metadata["xesam:trackNumber"] = track->trackNumber();
    }
    
    if (track->discNumber() > 0) {
        metadata["xesam:discNumber"] = track->discNumber();
    }
    
    if (track->year() > 0) {
        metadata["xesam:contentCreated"] = QString::number(track->year());
    }
    
    if (track->duration() > 0) {
        metadata["mpris:length"] = track->duration() * 1000000; // Convert to microseconds
    }
    
    // File URL
    if (!track->filePath().isEmpty()) {
        metadata["xesam:url"] = QUrl::fromLocalFile(track->filePath()).toString();
    }
    
    // Album art URL
    if (m_mprisManager) {
        QString albumArtUrl = m_mprisManager->exportAlbumArt(track);
        if (!albumArtUrl.isEmpty()) {
            metadata["mpris:artUrl"] = albumArtUrl;
        }
    }

    return metadata;
}

double MediaPlayer2PlayerAdaptor::volume() const
{
    return m_mediaPlayer ? m_mediaPlayer->volume() : 1.0;
}

void MediaPlayer2PlayerAdaptor::setVolume(double volume)
{
    if (m_mediaPlayer) {
        m_mediaPlayer->setVolume(static_cast<float>(volume));
    }
}

qint64 MediaPlayer2PlayerAdaptor::position() const
{
    return m_mediaPlayer ? m_mediaPlayer->position() * 1000 : 0; // Convert to microseconds
}

bool MediaPlayer2PlayerAdaptor::canGoNext() const
{
    return m_mediaPlayer ? m_mediaPlayer->hasNext() : false;
}

bool MediaPlayer2PlayerAdaptor::canGoPrevious() const
{
    // Return true if we can go to previous track OR if we're playing/paused
    // (so Previous can restart the current track)
    if (!m_mediaPlayer) {
        return false;
    }
    
    MediaPlayer::State state = m_mediaPlayer->state();
    return m_mediaPlayer->hasPrevious() || 
           state == MediaPlayer::PlayingState || 
           state == MediaPlayer::PausedState;
}

void MediaPlayer2PlayerAdaptor::Next()
{
    qDebug() << "MPRIS: Next() called via D-Bus";
    if (m_mediaPlayer) {
        m_mediaPlayer->next();
    }
}

void MediaPlayer2PlayerAdaptor::Previous()
{
    qDebug() << "MPRIS: Previous() called via D-Bus";
    if (m_mediaPlayer) {
        m_mediaPlayer->previous();
    }
}

void MediaPlayer2PlayerAdaptor::Pause()
{
    qDebug() << "MPRIS: Pause() called via D-Bus";
    if (m_mediaPlayer) {
        m_mediaPlayer->pause();
    }
}

void MediaPlayer2PlayerAdaptor::PlayPause()
{
    qDebug() << "MPRIS: PlayPause() called via D-Bus";
    if (m_mediaPlayer) {
        m_mediaPlayer->togglePlayPause();
    }
}

void MediaPlayer2PlayerAdaptor::Stop()
{
    qDebug() << "MPRIS: Stop() called via D-Bus";
    if (m_mediaPlayer) {
        m_mediaPlayer->stop();
    }
}

void MediaPlayer2PlayerAdaptor::Play()
{
    qDebug() << "MPRIS: Play() called via D-Bus";
    if (m_mediaPlayer) {
        m_mediaPlayer->play();
    }
}

void MediaPlayer2PlayerAdaptor::Seek(qint64 offset)
{
    if (m_mediaPlayer) {
        qint64 newPosition = m_mediaPlayer->position() + (offset / 1000); // Convert from microseconds
        m_mediaPlayer->seek(qMax(0LL, newPosition));
    }
}

void MediaPlayer2PlayerAdaptor::SetPosition(const QDBusObjectPath &trackId, qint64 position)
{
    Q_UNUSED(trackId)
    if (m_mediaPlayer) {
        m_mediaPlayer->seek(position / 1000); // Convert from microseconds
    }
}

// MprisManager implementation
MprisManager::MprisManager(MediaPlayer *mediaPlayer, QObject *parent)
    : QObject(parent)
    , m_mediaPlayer(mediaPlayer)
    , m_libraryManager(nullptr)
    , m_mprisAdaptor(nullptr)
    , m_playerAdaptor(nullptr)
    , m_dbusConnection(QDBusConnection::sessionBus())
    , m_serviceName("org.mpris.MediaPlayer2.mtoc")
    , m_initialized(false)
{
}

MprisManager::~MprisManager()
{
    cleanup();
}

void MprisManager::setLibraryManager(Mtoc::LibraryManager *libraryManager)
{
    m_libraryManager = libraryManager;
}

bool MprisManager::initialize()
{
    if (m_initialized) {
        return true;
    }

    if (!m_dbusConnection.isConnected()) {
        qWarning() << "MPRIS: Could not connect to D-Bus session bus";
        return false;
    }

    // Register service name
    if (!m_dbusConnection.registerService(m_serviceName)) {
        qWarning() << "MPRIS: Could not register service name" << m_serviceName;
        return false;
    }

    // Create adaptors - both need to be on the same parent object
    m_mprisAdaptor = new MediaPlayer2Adaptor(this);
    m_playerAdaptor = new MediaPlayer2PlayerAdaptor(m_mediaPlayer);
    
    // IMPORTANT: Set the parent of the player adaptor to be the same as the main adaptor
    // This ensures both interfaces are exposed on the same D-Bus object
    m_playerAdaptor->setParent(this);
    
    // Set the MPRIS manager reference for album art access
    m_playerAdaptor->setMprisManager(this);

    // Register object path with both adaptors
    if (!m_dbusConnection.registerObject("/org/mpris/MediaPlayer2", this)) {
        qWarning() << "MPRIS: Could not register object path";
        cleanup();
        return false;
    }

    // Connect MediaPlayer signals to update MPRIS properties
    if (m_mediaPlayer) {
        connect(m_mediaPlayer, &MediaPlayer::stateChanged, this, &MprisManager::onStateChanged);
        connect(m_mediaPlayer, &MediaPlayer::positionChanged, this, &MprisManager::onPositionChanged);
        connect(m_mediaPlayer, &MediaPlayer::volumeChanged, this, &MprisManager::onVolumeChanged);
        connect(m_mediaPlayer, &MediaPlayer::currentTrackChanged, this, &MprisManager::onCurrentTrackChanged);
        connect(m_mediaPlayer, &MediaPlayer::playbackQueueChanged, this, [this]() {
            // Update CanGoNext and CanGoPrevious properties
            QVariantMap changedProperties;
            changedProperties["CanGoNext"] = m_mediaPlayer->hasNext();
            changedProperties["CanGoPrevious"] = m_playerAdaptor->canGoPrevious();
            emitPropertiesChanged("org.mpris.MediaPlayer2.Player", changedProperties);
        });

        // Connect adaptor signals to application actions
        connect(m_mprisAdaptor, &MediaPlayer2Adaptor::quitRequested, 
                qApp, &QApplication::quit);
        connect(m_mprisAdaptor, &MediaPlayer2Adaptor::raiseRequested, 
                this, [this]() {
            qDebug() << "MPRIS: Raise requested";
            // Find and raise the main window
            for (QWidget *widget : qApp->topLevelWidgets()) {
                if (widget->isWindow() && !widget->isHidden()) {
                    widget->raise();
                    widget->activateWindow();
                    widget->show();
                    break;
                }
            }
        });
    }

    m_initialized = true;
    qDebug() << "MPRIS: Successfully initialized with service name" << m_serviceName;
    
    return true;
}

void MprisManager::cleanup()
{
    if (m_initialized) {
        m_dbusConnection.unregisterObject("/org/mpris/MediaPlayer2");
        m_dbusConnection.unregisterService(m_serviceName);
        m_initialized = false;
    }

    if (m_mprisAdaptor) {
        delete m_mprisAdaptor;
        m_mprisAdaptor = nullptr;
    }

    if (m_playerAdaptor) {
        delete m_playerAdaptor;
        m_playerAdaptor = nullptr;
    }
}

void MprisManager::onStateChanged()
{
    QVariantMap changedProperties;
    changedProperties["PlaybackStatus"] = m_playerAdaptor->playbackStatus();
    changedProperties["CanGoPrevious"] = m_playerAdaptor->canGoPrevious();
    emitPropertiesChanged("org.mpris.MediaPlayer2.Player", changedProperties);
}

void MprisManager::onPositionChanged(qint64 position)
{
    Q_UNUSED(position)
    // Position changes are too frequent to emit property changes for each one
    // MPRIS clients typically poll the Position property instead
    
    // However, we can emit Seeked signal when position changes significantly
    static qint64 lastEmittedPosition = 0;
    qint64 currentPos = position * 1000; // Convert to microseconds
    
    if (qAbs(currentPos - lastEmittedPosition) > 1000000) { // > 1 second difference
        emit m_playerAdaptor->Seeked(currentPos);
        lastEmittedPosition = currentPos;
    }
}

void MprisManager::onVolumeChanged(float volume)
{
    QVariantMap changedProperties;
    changedProperties["Volume"] = static_cast<double>(volume);
    emitPropertiesChanged("org.mpris.MediaPlayer2.Player", changedProperties);
}

void MprisManager::onCurrentTrackChanged(Mtoc::Track *track)
{
    Q_UNUSED(track)
    updateMetadata();
}

void MprisManager::updateMetadata()
{
    QVariantMap changedProperties;
    changedProperties["Metadata"] = m_playerAdaptor->metadata();
    emitPropertiesChanged("org.mpris.MediaPlayer2.Player", changedProperties);
}

void MprisManager::emitPropertiesChanged(const QString &interface, const QVariantMap &changedProperties)
{
    if (!m_initialized) return;

    QDBusMessage signal = QDBusMessage::createSignal(
        "/org/mpris/MediaPlayer2",
        "org.freedesktop.DBus.Properties",
        "PropertiesChanged"
    );
    
    signal << interface << changedProperties << QStringList();
    m_dbusConnection.send(signal);
}

QVariantMap MprisManager::createMetadata(Mtoc::Track *track) const
{
    return m_playerAdaptor->metadata();
}

QString MprisManager::exportAlbumArt(Mtoc::Track *track) const
{
    if (!track || !m_libraryManager) {
        return QString();
    }
    
    // Get database manager from library manager
    auto databaseManager = m_libraryManager->databaseManager();
    if (!databaseManager) {
        return QString();
    }
    
    // Look up album ID from track info
    int albumId = databaseManager->getAlbumIdByArtistAndTitle(track->albumArtist(), track->album());
    if (albumId <= 0) {
        return QString();
    }
    
    // Check if we have album art for this album
    if (!databaseManager->albumArtExists(albumId)) {
        return QString();
    }
    
    // Create temp directory if it doesn't exist
    if (m_tempDir.isEmpty()) {
        QDir tempDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
        QString mtocTempDir = tempDir.absoluteFilePath("mtoc-albumart");
        if (!tempDir.exists("mtoc-albumart")) {
            tempDir.mkpath("mtoc-albumart");
        }
        m_tempDir = mtocTempDir;
    }
    
    // Create filename for this album's art
    QString filename = QString("album_%1.jpg").arg(albumId);
    QString fullPath = QDir(m_tempDir).absoluteFilePath(filename);
    
    // Check if file already exists and is recent
    QFileInfo fileInfo(fullPath);
    if (fileInfo.exists() && fileInfo.lastModified().secsTo(QDateTime::currentDateTime()) < 3600) {
        // File exists and is less than 1 hour old, use it
        return QUrl::fromLocalFile(fullPath).toString();
    }
    
    // Get album art thumbnail from database
    QByteArray thumbnailData = databaseManager->getAlbumArtThumbnail(albumId);
    if (thumbnailData.isEmpty()) {
        // Try to get full image path
        QString imagePath = databaseManager->getAlbumArtPath(albumId);
        if (!imagePath.isEmpty()) {
            QPixmap pixmap(imagePath);
            if (!pixmap.isNull()) {
                // Scale down for MPRIS (max 300x300 is usually enough)
                if (pixmap.width() > 300 || pixmap.height() > 300) {
                    pixmap = pixmap.scaled(300, 300, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                }
                if (pixmap.save(fullPath, "JPEG", 85)) {
                    qDebug() << "MPRIS: Exported album art to" << fullPath;
                    return QUrl::fromLocalFile(fullPath).toString();
                }
            }
        }
        return QString();
    }
    
    // Save thumbnail data to temp file
    QImage image;
    if (image.loadFromData(thumbnailData)) {
        // Scale up thumbnail if it's too small for good quality
        if (image.width() < 200 || image.height() < 200) {
            image = image.scaled(200, 200, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
        
        if (image.save(fullPath, "JPEG", 85)) {
            qDebug() << "MPRIS: Exported album art thumbnail to" << fullPath;
            return QUrl::fromLocalFile(fullPath).toString();
        }
    }
    
    return QString();
}