#include "systeminfo.h"
#include <QCoreApplication>
#include <QStringList>

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent),
      m_appName("mtoc"),
      m_appVersion("2.6") // Corresponds to project version in CMakeLists.txt
{
    // Check for --show-changelog command line flag
    QStringList args = QCoreApplication::arguments();
    m_forceShowChangelog = args.contains("--show-changelog") || args.contains("--changelog");
}

QString SystemInfo::appName() const
{
    return m_appName;
}

QString SystemInfo::appVersion() const
{
    return m_appVersion;
}

bool SystemInfo::forceShowChangelog() const
{
    return m_forceShowChangelog;
}
