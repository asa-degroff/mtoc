#include "settingsmanager.h"
#include <QDebug>

SettingsManager* SettingsManager::s_instance = nullptr;

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings("mtoc", "mtoc")
{
    loadSettings();
}

SettingsManager::~SettingsManager()
{
    saveSettings();
}

SettingsManager* SettingsManager::instance()
{
    if (!s_instance) {
        s_instance = new SettingsManager();
    }
    return s_instance;
}

void SettingsManager::setQueueActionDefault(QueueAction action)
{
    if (m_queueActionDefault != action) {
        m_queueActionDefault = action;
        emit queueActionDefaultChanged(action);
        saveSettings();
    }
}

void SettingsManager::setShowTrackInfoByDefault(bool show)
{
    if (m_showTrackInfoByDefault != show) {
        m_showTrackInfoByDefault = show;
        emit showTrackInfoByDefaultChanged(show);
        saveSettings();
    }
}

void SettingsManager::setRestorePlaybackPosition(bool restore)
{
    if (m_restorePlaybackPosition != restore) {
        m_restorePlaybackPosition = restore;
        emit restorePlaybackPositionChanged(restore);
        saveSettings();
    }
}

void SettingsManager::loadSettings()
{
    m_settings.beginGroup("QueueBehavior");
    m_queueActionDefault = static_cast<QueueAction>(m_settings.value("defaultAction", Ask).toInt());
    m_settings.endGroup();
    
    m_settings.beginGroup("Display");
    m_showTrackInfoByDefault = m_settings.value("showTrackInfoByDefault", false).toBool();
    m_settings.endGroup();
    
    m_settings.beginGroup("Playback");
    m_restorePlaybackPosition = m_settings.value("restorePosition", true).toBool();
    m_settings.endGroup();
    
    qDebug() << "SettingsManager: Loaded settings - Queue action:" << m_queueActionDefault 
             << "Show track info:" << m_showTrackInfoByDefault 
             << "Restore position:" << m_restorePlaybackPosition;
}

void SettingsManager::saveSettings()
{
    m_settings.beginGroup("QueueBehavior");
    m_settings.setValue("defaultAction", static_cast<int>(m_queueActionDefault));
    m_settings.endGroup();
    
    m_settings.beginGroup("Display");
    m_settings.setValue("showTrackInfoByDefault", m_showTrackInfoByDefault);
    m_settings.endGroup();
    
    m_settings.beginGroup("Playback");
    m_settings.setValue("restorePosition", m_restorePlaybackPosition);
    m_settings.endGroup();
    
    m_settings.sync();
    qDebug() << "SettingsManager: Settings saved";
}