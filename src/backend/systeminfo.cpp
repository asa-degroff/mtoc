#include "systeminfo.h"

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent),
      m_appName("mtoc"),
      m_appVersion("2.0.1") // Corresponds to project version in CMakeLists.txt
{
}

QString SystemInfo::appName() const
{
    return m_appName;
}

QString SystemInfo::appVersion() const
{
    return m_appVersion;
}
