#ifndef AUDIOENGINE_H
#define AUDIOENGINE_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <gst/gst.h>
#include <memory>

class AudioEngine : public QObject
{
    Q_OBJECT

public:
    enum class State {
        Null,
        Ready,
        Playing,
        Paused,
        Stopped
    };
    Q_ENUM(State)

    explicit AudioEngine(QObject *parent = nullptr);
    ~AudioEngine();

    void loadTrack(const QString &filePath);
    void play();
    void pause();
    void stop();
    void seek(qint64 position);
    
    qint64 position() const;
    qint64 duration() const;
    float volume() const;
    void setVolume(float volume);
    
    State state() const { return m_state; }
    QString currentTrack() const { return m_currentTrack; }
    
    // Replay gain control
    void setReplayGainEnabled(bool enabled);
    void setReplayGainMode(bool albumMode);
    void setReplayGainPreAmp(double preAmp);
    void setReplayGainFallbackGain(double fallbackGain);

signals:
    void stateChanged(AudioEngine::State state);
    void positionChanged(qint64 position);
    void durationChanged(qint64 duration);
    void trackFinished();
    void error(const QString &message);
    void aboutToFinish();

private:
    void initializePipeline();
    void cleanupPipeline();
    void setState(State state);
    void updatePosition();
    
    static gboolean busCallback(GstBus *bus, GstMessage *message, gpointer data);
    static void aboutToFinishCallback(GstElement *playbin, gpointer data);
    
    GstElement *m_pipeline = nullptr;
    GstElement *m_playbin = nullptr;
    GstElement *m_rgvolume = nullptr;
    GstElement *m_audioFilterBin = nullptr;
    GstBus *m_bus = nullptr;
    guint m_busWatchId = 0;
    
    State m_state = State::Null;
    QString m_currentTrack;
    float m_volume = 1.0f;
    
    QTimer *m_positionTimer = nullptr;
    
    // Seek tracking
    bool m_seekPending = false;
    qint64 m_seekTarget = 0;
    
    static bool s_gstInitialized;
};

#endif // AUDIOENGINE_H