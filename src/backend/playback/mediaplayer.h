#ifndef MEDIAPLAYER_H
#define MEDIAPLAYER_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <memory>
#include "audioengine.h"

namespace Mtoc {
class Track;
class Album;
class LibraryManager;
}

class MediaPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(Mtoc::Track* currentTrack READ currentTrack NOTIFY currentTrackChanged)
    Q_PROPERTY(Mtoc::Album* currentAlbum READ currentAlbum NOTIFY currentAlbumChanged)
    Q_PROPERTY(bool hasNext READ hasNext NOTIFY playbackQueueChanged)
    Q_PROPERTY(bool hasPrevious READ hasPrevious NOTIFY playbackQueueChanged)

public:
    enum State {
        StoppedState,
        PlayingState,
        PausedState
    };
    Q_ENUM(State)

    explicit MediaPlayer(QObject *parent = nullptr);
    ~MediaPlayer();
    
    void setLibraryManager(Mtoc::LibraryManager* manager) { m_libraryManager = manager; }

    State state() const;
    qint64 position() const;
    qint64 duration() const;
    float volume() const;
    Mtoc::Track* currentTrack() const { return m_currentTrack; }
    Mtoc::Album* currentAlbum() const { return m_currentAlbum; }
    bool hasNext() const;
    bool hasPrevious() const;

public slots:
    void play();
    void pause();
    void stop();
    void togglePlayPause();
    void next();
    void previous();
    void seek(qint64 position);
    void setVolume(float volume);
    
    void playTrack(Mtoc::Track* track);
    void playAlbum(Mtoc::Album* album, int startIndex = 0);
    Q_INVOKABLE void playAlbumByName(const QString& artist, const QString& title, int startIndex = 0);
    Q_INVOKABLE void playTrackFromData(const QVariant& trackData);
    void clearQueue();

signals:
    void stateChanged(MediaPlayer::State state);
    void positionChanged(qint64 position);
    void durationChanged(qint64 duration);
    void volumeChanged(float volume);
    void currentTrackChanged(Mtoc::Track* track);
    void currentAlbumChanged(Mtoc::Album* album);
    void playbackQueueChanged();
    void error(const QString &message);

private:
    void setupConnections();
    void updateCurrentTrack(Mtoc::Track* track);
    void playNextInQueue();
    void handleTrackFinished();
    void onEngineStateChanged(AudioEngine::State state);
    static QString getDebugLogPath();
    
    std::unique_ptr<AudioEngine> m_audioEngine;
    Mtoc::Track* m_currentTrack = nullptr;
    Mtoc::Album* m_currentAlbum = nullptr;
    QList<Mtoc::Track*> m_playbackQueue;
    int m_currentQueueIndex = -1;
    State m_state = StoppedState;
    Mtoc::LibraryManager* m_libraryManager = nullptr;
};

#endif // MEDIAPLAYER_H