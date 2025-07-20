#ifndef VIRTUALPLAYLIST_H
#define VIRTUALPLAYLIST_H

#include <QObject>
#include <QVector>
#include <QMutex>
#include <QFuture>
#include <QPromise>
#include <memory>
#include "VirtualTrackData.h"

namespace Mtoc {

class DatabaseManager;

class VirtualPlaylist : public QObject
{
    Q_OBJECT
    
public:
    explicit VirtualPlaylist(DatabaseManager* dbManager, QObject *parent = nullptr);
    ~VirtualPlaylist();
    
    // Configuration
    void setBufferSize(int size) { m_bufferSize = size; }
    int bufferSize() const { return m_bufferSize; }
    
    // Playlist operations
    void loadAllTracks();
    void clear();
    
    // Track access
    VirtualTrackData getTrack(int index) const;
    QVariantMap getTrackVariant(int index) const;
    QVector<VirtualTrackData> getTracks(int startIndex, int count) const;
    
    // Playlist info
    int trackCount() const;
    int loadedTrackCount() const;
    bool isFullyLoaded() const;
    bool isLoading() const;
    int totalDuration() const; // in seconds
    
    // Buffer management
    void preloadRange(int centerIndex, int radius = -1);
    void ensureLoaded(int index);
    bool isTrackLoaded(int index) const;
    
    // Shuffle support
    void generateShuffleOrder(int currentIndex = -1);
    int getShuffledIndex(int linearIndex) const;
    int getLinearIndex(int shuffledIndex) const;
    QVector<int> getNextShuffleIndices(int currentShuffledIndex, int count) const;
    int getPreviousShuffleIndex(int currentShuffledIndex) const;
    
signals:
    void loadingStarted();
    void loadingProgress(int loaded, int total);
    void loadingFinished();
    void trackLoaded(int index);
    void rangeLoaded(int startIndex, int endIndex);
    void error(const QString& message);
    
    
private:
    void loadRange(int startIndex, int count);
    void updateLoadedRanges(int startIndex, int endIndex);
    bool isInLoadedRange(int index) const;
    
    DatabaseManager* m_dbManager;
    
    // Track storage
    mutable QMutex m_trackMutex;
    QVector<VirtualTrackData*> m_tracks;  // Using raw pointers, managed manually
    int m_totalTrackCount = 0;
    int m_totalDuration = 0;
    
    // Loading state
    std::atomic<bool> m_isLoading{false};
    QFuture<void> m_loadFuture;
    
    // Buffer configuration
    int m_bufferSize = 50;  // Number of tracks to load at once
    int m_preloadRadius = 10; // Number of tracks to preload around current
    
    // Loaded ranges tracking
    struct LoadedRange {
        int start;
        int end;
    };
    QVector<LoadedRange> m_loadedRanges;
    
    // Shuffle support
    QVector<int> m_shuffleOrder;
    mutable QMutex m_shuffleMutex;
};

} // namespace Mtoc

#endif // VIRTUALPLAYLIST_H