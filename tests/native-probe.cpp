// SPDX-License-Identifier: GPL-3.0-or-later
#include "secureclient.h"
#include <QCoreApplication>
#include <QCommandLineParser>
#include <QTimer>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>
#include <unistd.h>
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);QCommandLineParser parser;
    for(const auto &name:{"source","address","interface","auth","credential","ca","switch-address","switch-credential","switch-auth","switch-after-ms","cancel-after-ms"})
        parser.addOption(QCommandLineOption(name,name,"value"));
    parser.addOption({"wrong-scope","Use an invalid credential scope"});parser.addOption({"keep-old-scope-on-switch","Preserve prior endpoint credential scope"});parser.addOption({"switch-on-success","Change settings after first success"});parser.process(app);
    SecureClient::setTestCertificate(parser.value("ca"));SecureClient client;QElapsedTimer clock;clock.start();int successes=0,failures=0;
    const auto source=parser.value("source").isEmpty()?QString("nightscout"):parser.value("source");
    const auto interface=parser.value("interface").isEmpty()?QString("wg0"):parser.value("interface");
    const auto auth=parser.value("auth").isEmpty()?QString("token"):parser.value("auth");
    bool switching=false;
    auto fetch=[&](bool second){
        const auto address=parser.value(second?"switch-address":"address");
        const auto mode=second&&!parser.value("switch-auth").isEmpty()?parser.value("switch-auth"):auth;
        const auto credential=parser.value(second?"switch-credential":"credential");
        auto scope=parser.isSet("wrong-scope")?QString("wrong"):client.scopeFor(source,address,interface,mode);
        if(second&&parser.isSet("keep-old-scope-on-switch"))scope=client.scopeFor(source,parser.value("address"),interface,auth);
        client.fetch(source,address,interface,mode,credential,scope);
    };
    auto output=[&](bool ok,const QString &error,const QString &api,int count){
        QJsonObject result{{"ok",ok},{"error",error},{"api",api},{"entries",count},{"success_events",successes},{"failure_events",failures},{"elapsed_ms",double(clock.elapsed())},{"privileged",geteuid()==0}};
        std::cout<<QJsonDocument(result).toJson(QJsonDocument::Compact).constData()<<std::endl;app.exit(ok?0:1);
    };
    QObject::connect(&client,&SecureClient::succeeded,&app,[&](const QVariantList &rows,const QString &api){
        ++successes;
        if(parser.isSet("switch-on-success")&&!switching){switching=true;QTimer::singleShot(0,&app,[&]{fetch(true);});return;}
        output(true,{},api,rows.size());
    });
    QObject::connect(&client,&SecureClient::failed,&app,[&](const QString &error){++failures;output(false,error,{},0);});
    QTimer::singleShot(15000,&app,[&]{output(false,"Testiajurin aikaraja.",{},0);});
    QTimer::singleShot(0,&app,[&]{fetch(false);});
    if(parser.isSet("switch-after-ms"))QTimer::singleShot(parser.value("switch-after-ms").toInt(),&app,[&]{switching=true;fetch(true);});
    if(parser.isSet("cancel-after-ms"))QTimer::singleShot(parser.value("cancel-after-ms").toInt(),&app,[&]{
        client.cancel();QTimer::singleShot(250,&app,[&]{output(false,"Testissä peruttu.",{},0);});
    });
    return app.exec();
}
