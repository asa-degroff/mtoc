#ifndef SYSTEMINFO_H
#define SYSTEMINFO_H

#include <QObject>
#include <QString>

class SystemInfo : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString appName READ appName CONSTANT)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    QString appName() const;
    QString appVersion() const;

private:
    QString m_appName;
    QString m_appVersion;
};

#endif // SYSTEMINFO_H
