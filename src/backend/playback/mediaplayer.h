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
class VirtualPlaylistModel;
class VirtualPlaylist;
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
    Q_PROPERTY(QVariantList queue READ queue NOTIFY playbackQueueChanged)
    Q_PROPERTY(int queueLength READ queueLength NOTIFY playbackQueueChanged)
    Q_PROPERTY(int currentQueueIndex READ currentQueueIndex NOTIFY playbackQueueChanged)
    Q_PROPERTY(int totalQueueDuration READ totalQueueDuration NOTIFY playbackQueueChanged)
    Q_PROPERTY(bool isQueueModified READ isQueueModified NOTIFY queueModifiedChanged)
    Q_PROPERTY(bool canUndoClear READ canUndoClear NOTIFY canUndoClearChanged)
    Q_PROPERTY(bool repeatEnabled READ repeatEnabled WRITE setRepeatEnabled NOTIFY repeatEnabledChanged)
    Q_PROPERTY(bool shuffleEnabled READ shuffleEnabled WRITE setShuffleEnabled NOTIFY shuffleEnabledChanged)

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
    void setSettingsManager(class SettingsManager* settingsManager);

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
    QVariantList queue() const;
    int queueLength() const;
    int currentQueueIndex() const;
    int totalQueueDuration() const;
    bool isQueueModified() const { return m_isQueueModified; }
    bool canUndoClear() const { return !m_undoQueue.isEmpty(); }
    bool repeatEnabled() const { return m_repeatEnabled; }
    bool shuffleEnabled() const { return m_shuffleEnabled; }

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
    Q_INVOKABLE void playTrackNext(const QVariant& trackData);
    Q_INVOKABLE void playTrackLast(const QVariant& trackData);
    Q_INVOKABLE void playAlbumNext(const QString& artist, const QString& title);
    Q_INVOKABLE void playAlbumLast(const QString& artist, const QString& title);
    Q_INVOKABLE void playPlaylistNext(const QString& playlistName);
    Q_INVOKABLE void playPlaylistLast(const QString& playlistName);
    Q_INVOKABLE void removeTrackAt(int index);
    Q_INVOKABLE void removeTracks(const QList<int>& indices);
    Q_INVOKABLE void playTrackAt(int index);
    Q_INVOKABLE void moveTrack(int fromIndex, int toIndex);
    Q_INVOKABLE void updateShuffleOrder();
    void clearQueue();
    Q_INVOKABLE void clearQueueForUndo();
    Q_INVOKABLE void undoClearQueue();
    
    // Virtual playlist support
    Q_INVOKABLE void loadVirtualPlaylist(Mtoc::VirtualPlaylistModel* model);
    Q_INVOKABLE void playVirtualPlaylist(); // Start playing respecting shuffle mode
    Q_INVOKABLE void loadVirtualPlaylistNext(Mtoc::VirtualPlaylistModel* model);
    Q_INVOKABLE void loadVirtualPlaylistLast(Mtoc::VirtualPlaylistModel* model);
    void clearVirtualPlaylist();
    
    void setRepeatEnabled(bool enabled);
    void setShuffleEnabled(bool enabled);
    
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
    void queueModifiedChanged(bool modified);
    void canUndoClearChanged(bool canUndo);
    void repeatEnabledChanged(bool enabled);
    void shuffleEnabledChanged(bool enabled);

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
    void setQueueModified(bool modified);
    void clearUndoQueue();
    
    std::unique_ptr<AudioEngine> m_audioEngine;
    Mtoc::Track* m_currentTrack = nullptr;
    Mtoc::Album* m_currentAlbum = nullptr;
    QList<Mtoc::Track*> m_playbackQueue;
    int m_currentQueueIndex = -1;
    State m_state = StoppedState;
    Mtoc::LibraryManager* m_libraryManager = nullptr;
    SettingsManager* m_settingsManager = nullptr;
    QTimer* m_saveStateTimer = nullptr;
    QTimer* m_loadTimeoutTimer = nullptr;
    bool m_restoringState = false;
    qint64 m_savedPosition = 0;
    qint64 m_targetRestorePosition = 0;
    bool m_isReady = false;
    QMetaObject::Connection m_restoreConnection;
    bool m_isQueueModified = false;
    
    // Undo functionality
    QList<Mtoc::Track*> m_undoQueue;
    int m_undoQueueIndex = -1;
    Mtoc::Track* m_undoCurrentTrack = nullptr;
    bool m_undoQueueModified = false;
    
    // Repeat and shuffle
    bool m_repeatEnabled = false;
    bool m_shuffleEnabled = false;
    QList<int> m_shuffleOrder;  // Randomized indices
    int m_shuffleIndex = -1;     // Current position in shuffle order
    
    void generateShuffleOrder();
    void generateShuffleOrder(bool putCurrentTrackFirst);
    int getNextShuffleIndex() const;
    int getPreviousShuffleIndex() const;
    
    // Virtual playlist support
    Mtoc::VirtualPlaylist* m_virtualPlaylist = nullptr;
    bool m_isVirtualPlaylist = false;
    int m_virtualCurrentIndex = -1;
    int m_virtualShuffleIndex = -1;  // Current position in virtual playlist shuffle order
    QList<Mtoc::Track*> m_virtualBufferTracks;  // Pre-loaded tracks for smooth playback
    bool m_waitingForVirtualTrack = false;  // Track if we're waiting for a track to load
    QMetaObject::Connection m_virtualTrackLoadConnection;  // Connection for virtual track loading
    void preloadVirtualTracks(int centerIndex);
    Mtoc::Track* getOrCreateTrackFromVirtual(int index);
};

#endif // MEDIAPLAYER_H