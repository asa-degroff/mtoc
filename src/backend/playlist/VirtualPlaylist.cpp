#include "VirtualPlaylist.h"
#include "../database/databasemanager.h"
#include <QDebug>
#include <QtConcurrent>
#include <algorithm>
#include <random>
#include <QThread>
#include <QSqlDatabase>

namespace Mtoc {

VirtualPlaylist::VirtualPlaylist(DatabaseManager* dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
}

VirtualPlaylist::~VirtualPlaylist()
{
    if (m_loadFuture.isRunning()) {
        m_loadFuture.cancel();
        m_loadFuture.waitForFinished();
    }
    
    // Clean up all allocated tracks
    clear();
}

void VirtualPlaylist::loadAllTracks()
{
    if (m_isLoading) {
        qDebug() << "[VirtualPlaylist] Already loading, skipping request";
        return;
    }
    
    m_isLoading = true;
    emit loadingStarted();
    
    // Get total count first
    m_totalTrackCount = m_dbManager->getTrackCount();
    
    if (m_totalTrackCount == 0) {
        m_isLoading = false;
        emit loadingFinished();
        return;
    }
    
    // Pre-allocate vector with nullptrs
    {
        QMutexLocker locker(&m_trackMutex);
        // Delete existing tracks
        for (auto* track : m_tracks) {
            delete track;
        }
        m_tracks.clear();
        m_tracks.resize(m_totalTrackCount, nullptr);
        m_loadedRanges.clear();
        m_totalDuration = 0;
    }
    
    // Start loading the first chunk immediately
    loadRange(0, m_bufferSize);
}

void VirtualPlaylist::clear()
{
    if (m_loadFuture.isRunning()) {
        m_loadFuture.cancel();
        m_loadFuture.waitForFinished();
    }
    
    QMutexLocker locker(&m_trackMutex);
    // Delete all allocated tracks
    for (auto* track : m_tracks) {
        delete track;
    }
    m_tracks.clear();
    m_loadedRanges.clear();
    m_totalTrackCount = 0;
    m_totalDuration = 0;
    m_isLoading = false;
    
    QMutexLocker shuffleLocker(&m_shuffleMutex);
    m_shuffleOrder.clear();
}

VirtualTrackData VirtualPlaylist::getTrack(int index) const
{
    if (index < 0 || index >= m_totalTrackCount) {
        qWarning() << "[VirtualPlaylist::getTrack] Invalid index:" << index << "total tracks:" << m_totalTrackCount;
        return VirtualTrackData();
    }
    
    // Ensure track is loaded first (before locking)
    const_cast<VirtualPlaylist*>(this)->ensureLoaded(index);
    
    QMutexLocker locker(&m_trackMutex);
    
    if (index < m_tracks.size() && m_tracks[index]) {
        VirtualTrackData trackData = *m_tracks[index];
        if (!trackData.isValid()) {
            qWarning() << "[VirtualPlaylist::getTrack] Track data at index" << index << "is invalid";
        }
        return trackData;
    }
    
    // Still not loaded - return empty data, will be loaded on demand
    return VirtualTrackData();
}

QVariantMap VirtualPlaylist::getTrackVariant(int index) const
{
    VirtualTrackData track = getTrack(index);
    return track.isValid() ? track.toVariantMap() : QVariantMap();
}

QVector<VirtualTrackData> VirtualPlaylist::getTracks(int startIndex, int count) const
{
    QVector<VirtualTrackData> result;
    
    if (startIndex < 0 || startIndex >= m_totalTrackCount || count <= 0) {
        return result;
    }
    
    int endIndex = qMin(startIndex + count, m_totalTrackCount);
    result.reserve(endIndex - startIndex);
    
    QMutexLocker locker(&m_trackMutex);
    
    for (int i = startIndex; i < endIndex; ++i) {
        if (i < m_tracks.size() && m_tracks[i]) {
            result.append(*m_tracks[i]);
        } else {
            // Return partial results and trigger loading
            const_cast<VirtualPlaylist*>(this)->ensureLoaded(i);
            break;
        }
    }
    
    return result;
}

int VirtualPlaylist::trackCount() const
{
    return m_totalTrackCount;
}

int VirtualPlaylist::loadedTrackCount() const
{
    QMutexLocker locker(&m_trackMutex);
    int count = 0;
    for (const auto& range : m_loadedRanges) {
        count += (range.end - range.start + 1);
    }
    return count;
}

bool VirtualPlaylist::isFullyLoaded() const
{
    return loadedTrackCount() == m_totalTrackCount;
}

bool VirtualPlaylist::isLoading() const
{
    return m_isLoading;
}

int VirtualPlaylist::totalDuration() const
{
    return m_totalDuration;
}

void VirtualPlaylist::preloadRange(int centerIndex, int radius)
{
    if (centerIndex < 0 || centerIndex >= m_totalTrackCount) {
        return;
    }
    
    if (radius < 0) {
        radius = m_preloadRadius;
    }
    
    int startIndex = qMax(0, centerIndex - radius);
    int endIndex = qMin(m_totalTrackCount - 1, centerIndex + radius);
    int count = endIndex - startIndex + 1;
    
    // Check if range is already loaded
    bool needsLoading = false;
    {
        QMutexLocker locker(&m_trackMutex);
        for (int i = startIndex; i <= endIndex; ++i) {
            if (!isInLoadedRange(i)) {
                needsLoading = true;
                break;
            }
        }
    }
    
    if (needsLoading) {
        loadRange(startIndex, count);
    }
}

void VirtualPlaylist::ensureLoaded(int index)
{
    if (index < 0 || index >= m_totalTrackCount) {
        return;
    }
    
    {
        QMutexLocker locker(&m_trackMutex);
        if (isInLoadedRange(index)) {
            return;
        }
    }
    
    // Load a chunk centered around the requested index
    int startIndex = qMax(0, index - m_bufferSize / 2);
    int endIndex = qMin(m_totalTrackCount - 1, startIndex + m_bufferSize - 1);
    loadRange(startIndex, endIndex - startIndex + 1);
}

bool VirtualPlaylist::isTrackLoaded(int index) const
{
    if (index < 0 || index >= m_totalTrackCount) {
        return false;
    }
    
    QMutexLocker locker(&m_trackMutex);
    return isInLoadedRange(index);
}

void VirtualPlaylist::generateShuffleOrder(int currentIndex)
{
    QMutexLocker locker(&m_shuffleMutex);
    
    m_shuffleOrder.clear();
    m_shuffleOrder.reserve(m_totalTrackCount);
    
    // Create sequential indices
    for (int i = 0; i < m_totalTrackCount; ++i) {
        m_shuffleOrder.append(i);
    }
    
    // Shuffle using random device
    std::random_device rd;
    std::mt19937 gen(rd());
    
    if (currentIndex >= 0 && currentIndex < m_totalTrackCount) {
        // Keep current track at the beginning
        auto it = std::find(m_shuffleOrder.begin(), m_shuffleOrder.end(), currentIndex);
        if (it != m_shuffleOrder.end()) {
            std::iter_swap(m_shuffleOrder.begin(), it);
        }
        // Shuffle the rest
        std::shuffle(m_shuffleOrder.begin() + 1, m_shuffleOrder.end(), gen);
    } else {
        // Shuffle everything
        std::shuffle(m_shuffleOrder.begin(), m_shuffleOrder.end(), gen);
    }
}

int VirtualPlaylist::getShuffledIndex(int linearIndex) const
{
    QMutexLocker locker(&m_shuffleMutex);
    
    if (m_shuffleOrder.isEmpty() || linearIndex < 0 || linearIndex >= m_shuffleOrder.size()) {
        return linearIndex;
    }
    
    return m_shuffleOrder[linearIndex];
}

int VirtualPlaylist::getLinearIndex(int shuffledIndex) const
{
    QMutexLocker locker(&m_shuffleMutex);
    
    if (m_shuffleOrder.isEmpty()) {
        qWarning() << "[VirtualPlaylist::getLinearIndex] Shuffle order is empty";
        return -1;
    }
    
    int index = m_shuffleOrder.indexOf(shuffledIndex);
    if (index < 0) {
        qWarning() << "[VirtualPlaylist::getLinearIndex] Track index" << shuffledIndex 
                   << "not found in shuffle order";
    }
    return index;
}

QVector<int> VirtualPlaylist::getNextShuffleIndices(int currentShuffledIndex, int count) const
{
    QMutexLocker locker(&m_shuffleMutex);
    
    QVector<int> indices;
    if (m_shuffleOrder.isEmpty() || count <= 0) {
        return indices;
    }
    
    // Prevent infinite recursion by not calling getLinearIndex from within a mutex lock
    int linearIndex = -1;
    {
        // Find the position without calling getLinearIndex (which also locks the mutex)
        linearIndex = m_shuffleOrder.indexOf(currentShuffledIndex);
    }
    
    if (linearIndex < 0) {
        return indices;
    }
    
    indices.reserve(count);
    for (int i = 1; i <= count && linearIndex + i < m_shuffleOrder.size(); ++i) {
        indices.append(m_shuffleOrder[linearIndex + i]);
    }
    
    return indices;
}

int VirtualPlaylist::getPreviousShuffleIndex(int currentShuffledIndex) const
{
    QMutexLocker locker(&m_shuffleMutex);
    
    if (m_shuffleOrder.isEmpty()) {
        return -1;
    }
    
    // Find current position in shuffle order
    int linearIndex = m_shuffleOrder.indexOf(currentShuffledIndex);
    if (linearIndex < 0) {
        return -1;
    }
    
    // Get previous position
    int prevLinearIndex = linearIndex - 1;
    if (prevLinearIndex < 0) {
        // At beginning of shuffle order
        return -1;
    }
    
    return m_shuffleOrder[prevLinearIndex];
}

void VirtualPlaylist::loadRange(int startIndex, int count)
{
    if (m_loadFuture.isRunning()) {
        // Cancel previous load if still running
        m_loadFuture.cancel();
        m_loadFuture.waitForFinished();
    }
    
    // Load tracks in background
    m_loadFuture = QtConcurrent::run([this, startIndex, count]() {
        // Store thread ID for cleanup
        QString connectionName = QString("MtocThread_%1").arg(quintptr(QThread::currentThreadId()));
        
        QVariantList tracks = m_dbManager->getAllTracks(count, startIndex);
        
        // Clean up thread connection
        if (QSqlDatabase::contains(connectionName)) {
            QSqlDatabase::removeDatabase(connectionName);
        }
        
        if (tracks.isEmpty()) {
            qWarning() << "[VirtualPlaylist] Failed to load tracks at range" << startIndex << "count" << count;
            return;
        }
        
        {
            QMutexLocker locker(&m_trackMutex);
            
            int index = startIndex;
            for (const QVariant& trackVariant : tracks) {
                if (index >= m_tracks.size()) {
                    break;
                }
                
                QVariantMap trackMap = trackVariant.toMap();
                auto* trackData = new VirtualTrackData(VirtualTrackData::fromVariantMap(trackMap));
                
                // Delete existing track if any
                delete m_tracks[index];
                m_tracks[index] = trackData;
                m_totalDuration += trackData->duration;
                
                ++index;
            }
            
            updateLoadedRanges(startIndex, startIndex + tracks.size() - 1);
        }
        
        emit rangeLoaded(startIndex, startIndex + tracks.size() - 1);
        emit loadingProgress(loadedTrackCount(), m_totalTrackCount);
        
        if (isFullyLoaded()) {
            m_isLoading = false;
            emit loadingFinished();
        }
    });
}

void VirtualPlaylist::updateLoadedRanges(int startIndex, int endIndex)
{
    // This method assumes m_trackMutex is already locked
    
    // Try to merge with existing ranges
    bool merged = false;
    
    for (auto& range : m_loadedRanges) {
        // Check if new range overlaps or is adjacent
        if ((startIndex >= range.start - 1 && startIndex <= range.end + 1) ||
            (endIndex >= range.start - 1 && endIndex <= range.end + 1) ||
            (startIndex <= range.start && endIndex >= range.end)) {
            // Merge ranges
            range.start = qMin(range.start, startIndex);
            range.end = qMax(range.end, endIndex);
            merged = true;
            break;
        }
    }
    
    if (!merged) {
        // Add new range
        m_loadedRanges.append({startIndex, endIndex});
    }
    
    // Merge any overlapping ranges
    std::sort(m_loadedRanges.begin(), m_loadedRanges.end(),
              [](const LoadedRange& a, const LoadedRange& b) {
                  return a.start < b.start;
              });
    
    QVector<LoadedRange> mergedRanges;
    for (const auto& range : m_loadedRanges) {
        if (mergedRanges.isEmpty() || mergedRanges.last().end + 1 < range.start) {
            mergedRanges.append(range);
        } else {
            mergedRanges.last().end = qMax(mergedRanges.last().end, range.end);
        }
    }
    
    m_loadedRanges = mergedRanges;
}

bool VirtualPlaylist::isInLoadedRange(int index) const
{
    // This method assumes m_trackMutex is already locked
    
    for (const auto& range : m_loadedRanges) {
        if (index >= range.start && index <= range.end) {
            return true;
        }
    }
    return false;
}

} // namespace Mtoc