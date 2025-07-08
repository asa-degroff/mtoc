#ifndef MEDIAPLAYER_H
#define MEDIAPLAYER_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QTimer>
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
    Q_PROPERTY(bool restoringState READ isRestoringState NOTIFY restoringStateChanged)
    Q_PROPERTY(qint64 savedPosition READ savedPosition NOTIFY savedPositionChanged)
    Q_PROPERTY(bool isReady READ isReady NOTIFY readyChanged)

public:
    enum State {
        StoppedState,
        PlayingState,
        PausedState
    };
    Q_ENUM(State)

    explicit MediaPlayer(QObject *parent = nullptr);
    ~MediaPlayer();
    
    void setLibraryManager(Mtoc::LibraryManager* manager);

    State state() const;
    qint64 position() const;
    qint64 duration() const;
    float volume() const;
    Mtoc::Track* currentTrack() const { return m_currentTrack; }
    Mtoc::Album* currentAlbum() const { return m_currentAlbum; }
    bool hasNext() const;
    bool hasPrevious() const;
    bool isRestoringState() const { return m_restoringState; }
    qint64 savedPosition() const { return m_savedPosition; }
    bool isReady() const { return m_isReady; }

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
    
    // State persistence
    void saveState();
    void restoreState();

signals:
    void stateChanged(MediaPlayer::State state);
    void positionChanged(qint64 position);
    void durationChanged(qint64 duration);
    void volumeChanged(float volume);
    void currentTrackChanged(Mtoc::Track* track);
    void currentAlbumChanged(Mtoc::Album* album);
    void playbackQueueChanged();
    void error(const QString &message);
    void restoringStateChanged(bool restoring);
    void savedPositionChanged(qint64 position);
    void readyChanged(bool ready);

private slots:
    void periodicStateSave();
    void onTrackLoadedForRestore();
    void onTrackLoadTimeout();

private:
    void setupConnections();
    void updateCurrentTrack(Mtoc::Track* track);
    void playNextInQueue();
    void handleTrackFinished();
    void onEngineStateChanged(AudioEngine::State state);
    static QString getDebugLogPath();
    void loadTrack(Mtoc::Track* track, bool autoPlay = true);
    void restoreAlbumByName(const QString& artist, const QString& title, int trackIndex, qint64 position);
    void restoreTrackFromData(const QString& filePath, qint64 position, qint64 duration);
    void clearRestorationState();
    void clearSavedPosition();
    void checkPositionSync();
    void setReady(bool ready);
    
    std::unique_ptr<AudioEngine> m_audioEngine;
    Mtoc::Track* m_currentTrack = nullptr;
    Mtoc::Album* m_currentAlbum = nullptr;
    QList<Mtoc::Track*> m_playbackQueue;
    int m_currentQueueIndex = -1;
    State m_state = StoppedState;
    Mtoc::LibraryManager* m_libraryManager = nullptr;
    QTimer* m_saveStateTimer = nullptr;
    QTimer* m_loadTimeoutTimer = nullptr;
    bool m_restoringState = false;
    qint64 m_savedPosition = 0;
    qint64 m_targetRestorePosition = 0;
    bool m_isReady = false;
    QMetaObject::Connection m_restoreConnection;
};

#endif // MEDIAPLAYER_H