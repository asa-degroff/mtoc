#include "mprismanager.h"
#include "../playback/mediaplayer.h"
#include "../library/track.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusInterface>
#include <QApplication>
#include <QDebug>
#include <QFileInfo>
#include <QUrl>

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
    : QDBusAbstractAdaptor(parent), m_mediaPlayer(parent)
{
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
    return m_mediaPlayer ? m_mediaPlayer->hasPrevious() : false;
}

void MediaPlayer2PlayerAdaptor::Next()
{
    if (m_mediaPlayer) {
        m_mediaPlayer->next();
    }
}

void MediaPlayer2PlayerAdaptor::Previous()
{
    if (m_mediaPlayer) {
        m_mediaPlayer->previous();
    }
}

void MediaPlayer2PlayerAdaptor::Pause()
{
    if (m_mediaPlayer) {
        m_mediaPlayer->pause();
    }
}

void MediaPlayer2PlayerAdaptor::PlayPause()
{
    if (m_mediaPlayer) {
        m_mediaPlayer->togglePlayPause();
    }
}

void MediaPlayer2PlayerAdaptor::Stop()
{
    if (m_mediaPlayer) {
        m_mediaPlayer->stop();
    }
}

void MediaPlayer2PlayerAdaptor::Play()
{
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

    // Create adaptors
    m_mprisAdaptor = new MediaPlayer2Adaptor(this);
    m_playerAdaptor = new MediaPlayer2PlayerAdaptor(m_mediaPlayer);

    // Register object path
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
            changedProperties["CanGoPrevious"] = m_mediaPlayer->hasPrevious();
            emitPropertiesChanged("org.mpris.MediaPlayer2.Player", changedProperties);
        });

        // Connect adaptor signals to application actions
        connect(m_mprisAdaptor, &MediaPlayer2Adaptor::quitRequested, 
                qApp, &QApplication::quit);
        connect(m_mprisAdaptor, &MediaPlayer2Adaptor::raiseRequested, 
                this, [this]() {
            // Try to raise the main window (implementation depends on your window management)
            qDebug() << "MPRIS: Raise requested";
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