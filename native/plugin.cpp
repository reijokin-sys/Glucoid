// SPDX-License-Identifier: GPL-3.0-or-later
#include "secureclient.h"
#include <QQmlExtensionPlugin>
#include <qqml.h>
class GlucoidNetworkPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<SecureClient>(uri,1,0,"SecureClient"); qmlProtectModule(uri,1); }
};
#include "plugin.moc"
