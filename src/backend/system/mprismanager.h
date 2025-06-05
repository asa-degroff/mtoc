#ifndef MPRISMANAGER_H
#define MPRISMANAGER_H

#include <QObject>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QVariantMap>
#include <QString>
#include <QStringList>

class MediaPlayer;

namespace Mtoc {
class Track;
}

// MPRIS MediaPlayer2 interface
class MediaPlayer2Adaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ canQuit)
    Q_PROPERTY(bool CanRaise READ canRaise)
    Q_PROPERTY(bool HasTrackList READ hasTrackList)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QStringList SupportedUriSchemes READ supportedUriSchemes)
    Q_PROPERTY(QStringList SupportedMimeTypes READ supportedMimeTypes)

public:
    explicit MediaPlayer2Adaptor(QObject *parent);

    bool canQuit() const { return true; }
    bool canRaise() const { return true; }
    bool hasTrackList() const { return false; }
    QString identity() const { return "mtoc"; }
    QStringList supportedUriSchemes() const { return QStringList() << "file"; }
    QStringList supportedMimeTypes() const;

public slots:
    void Quit();
    void Raise();

signals:
    void quitRequested();
    void raiseRequested();
};

// MPRIS MediaPlayer2.Player interface
class MediaPlayer2PlayerAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qint64 Position READ position)
    Q_PROPERTY(double MinimumRate READ minimumRate)
    Q_PROPERTY(double MaximumRate READ maximumRate)
    Q_PROPERTY(bool CanGoNext READ canGoNext)
    Q_PROPERTY(bool CanGoPrevious READ canGoPrevious)
    Q_PROPERTY(bool CanPlay READ canPlay)
    Q_PROPERTY(bool CanPause READ canPause)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ canControl)

public:
    explicit MediaPlayer2PlayerAdaptor(MediaPlayer *parent);

    QString playbackStatus() const;
    double rate() const { return 1.0; }
    void setRate(double rate) { Q_UNUSED(rate) } // Not implemented
    QVariantMap metadata() const;
    double volume() const;
    void setVolume(double volume);
    qint64 position() const;
    double minimumRate() const { return 1.0; }
    double maximumRate() const { return 1.0; }
    bool canGoNext() const;
    bool canGoPrevious() const;
    bool canPlay() const { return true; }
    bool canPause() const { return true; }
    bool canSeek() const { return true; }
    bool canControl() const { return true; }

public slots:
    void Next();
    void Previous();
    void Pause();
    void PlayPause();
    void Stop();
    void Play();
    void Seek(qint64 offset);
    void SetPosition(const QDBusObjectPath &trackId, qint64 position);

signals:
    void Seeked(qint64 position);

private:
    MediaPlayer *m_mediaPlayer;
};

// Main MPRIS Manager class
class MprisManager : public QObject
{
    Q_OBJECT

public:
    explicit MprisManager(MediaPlayer *mediaPlayer, QObject *parent = nullptr);
    ~MprisManager();

    bool initialize();
    void cleanup();

private slots:
    void onStateChanged();
    void onPositionChanged(qint64 position);
    void onVolumeChanged(float volume);
    void onCurrentTrackChanged(Mtoc::Track *track);

private:
    void updateMetadata();
    void emitPropertiesChanged(const QString &interface, const QVariantMap &changedProperties);
    QVariantMap createMetadata(Mtoc::Track *track) const;

    MediaPlayer *m_mediaPlayer;
    MediaPlayer2Adaptor *m_mprisAdaptor;
    MediaPlayer2PlayerAdaptor *m_playerAdaptor;
    QDBusConnection m_dbusConnection;
    QString m_serviceName;
    bool m_initialized;
};

#endif // MPRISMANAGER_H