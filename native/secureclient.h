// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QObject>
#include <QVariantList>
#include <QThread>
#include <QDeadlineTimer>
#include <atomic>
#include <memory>
#include <optional>

struct FetchConfiguration {
    quint64 generation=0;
    QString source,address,interface,auth,credential;
    QDeadlineTimer deadline{10000};
};
class SecureClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    explicit SecureClient(QObject *parent=nullptr);
    ~SecureClient() override;
    bool busy() const { return m_busy; }
    Q_INVOKABLE QString scopeFor(const QString &source,const QString &address,
                                 const QString &interface,const QString &auth) const;
    Q_INVOKABLE void fetch(const QString &source,const QString &address,const QString &interface,
                           const QString &auth,const QString &credential,const QString &credentialScope);
    Q_INVOKABLE void cancel();
#ifdef GLUCOID_TESTING
    static void setTestCertificate(const QString &path);
#endif
signals:
    void succeeded(const QVariantList &entries,const QString &api);
    void failed(const QString &message);
    void busyChanged();
private:
    void startPending();
    void setBusy(bool value);
    quint64 m_generation=0;
    bool m_busy=false;
    QString m_legacyScope;
    QThread *m_thread=nullptr;
    std::shared_ptr<std::atomic_bool> m_cancel;
    std::optional<FetchConfiguration> m_pending;
};
