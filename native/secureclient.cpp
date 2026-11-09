// SPDX-License-Identifier: GPL-3.0-or-later
#include "secureclient.h"
#include "wireguard.h"
#include <QUrl>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <curl/curl.h>
#include <mutex>
#include <algorithm>
#include <limits>
#include <cmath>

namespace {
constexpr qsizetype bodyLimit=1024*1024,headerLimit=16384;
#ifdef GLUCOID_TESTING
QString testCertificate;
#endif
struct Result {QVariantList entries;QString api,error;};
struct Transfer {
    QByteArray body;
    qsizetype headerBytes=0;
    bool oversized=false,bindingFailed=false;
    QString interface;
    std::shared_ptr<std::atomic_bool> cancelled;
};
QString normalize(FetchConfiguration &c) {
    QUrl url(c.address.trimmed());
    if(!url.isValid()||url.host().isEmpty()||!url.userInfo().isEmpty()||url.hasQuery()||url.hasFragment())
        return QStringLiteral("Anna palvelimen osoite ilman tunnusta tai kyselyparametreja.");
    if(c.source=="legacy")c.source=url.scheme()=="https"?"nightscout":"juggluco";
    if(c.source!="nightscout"&&c.source!="juggluco")return QStringLiteral("Valitse tietolähde.");
    if(c.source=="nightscout") {
        if(url.scheme()!="https")return QStringLiteral("Erillinen Nightscout edellyttää HTTPS-yhteyttä.");
        c.interface.clear();
    } else {
        QHostAddress ip;
        static const QRegularExpression name("^[A-Za-z0-9_.-]{1,15}$");
        if((url.scheme()!="http"&&url.scheme()!="https")||!ip.setAddress(url.host())||!ip.scopeId().isEmpty())
            return QStringLiteral("Juggluco tarvitsee numeerisen WireGuard-tunneliosoitteen.");
        c.interface=c.interface.trimmed();
        if(!name.match(c.interface).hasMatch())return QStringLiteral("Anna WireGuard-liittymä, esimerkiksi wg0.");
    }
    if(c.auth!="token"&&c.auth!="apisecret"&&c.auth!="none")return QStringLiteral("Tuntematon tunnistautumistapa.");
    if((url.scheme()=="https"&&url.port()==443)||(url.scheme()=="http"&&url.port()==80))url.setPort(-1);
    auto path=url.path();while(path.endsWith('/'))path.chop(1);url.setPath(path+'/');
    c.address=url.toString(QUrl::FullyEncoded);return {};
}
QString scope(const FetchConfiguration &c) {
    const auto encoded=QJsonDocument(QJsonArray{c.source,c.address,c.interface,c.auth}).toJson(QJsonDocument::Compact);
    return QString::fromLatin1(QCryptographicHash::hash(encoded,QCryptographicHash::Sha256).toHex());
}
size_t writeBody(char *data,size_t size,size_t count,void *context) {
    auto &t=*static_cast<Transfer*>(context);
    if(count>size_t(bodyLimit)||size>size_t(bodyLimit)|| (size && count>size_t(bodyLimit)/size)) {t.oversized=true;return 0;}
    const auto n=qsizetype(size*count);
    if(t.cancelled->load()||n>bodyLimit-t.body.size()) {t.oversized=true;return 0;}
    t.body.append(data,n);return size_t(n);
}
size_t readHeader(char*,size_t size,size_t count,void *context) {
    auto &t=*static_cast<Transfer*>(context);
    if(count>size_t(headerLimit)||size>size_t(headerLimit)||(size&&count>size_t(headerLimit)/size)) {t.oversized=true;return 0;}
    const auto n=qsizetype(size*count);
    if(n>headerLimit-t.headerBytes){t.oversized=true;return 0;}
    t.headerBytes+=n;return size_t(n);
}
int bindSocket(void *context,curl_socket_t socket,curlsocktype purpose) {
    auto &t=*static_cast<Transfer*>(context);
    if(purpose!=CURLSOCKTYPE_IPCXN||!bindWireguard(int(socket),t.interface)) {t.bindingFailed=true;return CURL_SOCKOPT_ERROR;}
    return CURL_SOCKOPT_OK;
}
struct Http {long status=0;QByteArray body;QString error;};
Http request(const FetchConfiguration &c,const QString &relative,const QByteArray &header,
             const std::shared_ptr<std::atomic_bool> &cancelled) {
    Http out;Transfer t;t.cancelled=cancelled;t.interface=c.interface;
    if(cancelled->load()) {out.error="Haku peruttu.";return out;}
    if(c.deadline.hasExpired()) {out.error="Yhteys aikakatkaistiin.";return out;}
    if(c.source=="juggluco"&&!activeWireguard(c.interface)) {out.error="Vaadittu WireGuard-yhteys ei ole käytettävissä.";return out;}
    CURL *handle=curl_easy_init();CURLM *multi=curl_multi_init();
    if(!handle||!multi){if(handle)curl_easy_cleanup(handle);if(multi)curl_multi_cleanup(multi);out.error="Verkkoyhteyden alustaminen epäonnistui.";return out;}
    auto encoded=QUrl(c.address).resolved(QUrl(relative,QUrl::StrictMode)).toEncoded();
    curl_slist *headers=nullptr;headers=curl_slist_append(headers,"Accept: application/json");
    if(!header.isEmpty())headers=curl_slist_append(headers,header.constData());
    // This library handles all HTTP framing, decoding and certificate checks.
    curl_easy_setopt(handle,CURLOPT_URL,encoded.constData());
    curl_easy_setopt(handle,CURLOPT_HTTPHEADER,headers);
    curl_easy_setopt(handle,CURLOPT_PROTOCOLS_STR,"http,https");
    curl_easy_setopt(handle,CURLOPT_FOLLOWLOCATION,0L);
    curl_easy_setopt(handle,CURLOPT_PROXY,"");
    curl_easy_setopt(handle,CURLOPT_NETRC,long(CURL_NETRC_IGNORED));
    curl_easy_setopt(handle,CURLOPT_SSL_VERIFYPEER,1L);
    curl_easy_setopt(handle,CURLOPT_SSL_VERIFYHOST,2L);
    curl_easy_setopt(handle,CURLOPT_NOSIGNAL,1L);
    curl_easy_setopt(handle,CURLOPT_TIMEOUT_MS,long(std::max<qint64>(1,c.deadline.remainingTime())));
    curl_easy_setopt(handle,CURLOPT_CONNECTTIMEOUT_MS,5000L);
    curl_easy_setopt(handle,CURLOPT_MAXFILESIZE_LARGE,curl_off_t(bodyLimit));
    curl_easy_setopt(handle,CURLOPT_ACCEPT_ENCODING,"");
    curl_easy_setopt(handle,CURLOPT_WRITEFUNCTION,writeBody);curl_easy_setopt(handle,CURLOPT_WRITEDATA,&t);
    curl_easy_setopt(handle,CURLOPT_HEADERFUNCTION,readHeader);curl_easy_setopt(handle,CURLOPT_HEADERDATA,&t);
#ifdef GLUCOID_TESTING
    const auto ca=testCertificate.toUtf8();if(!ca.isEmpty())curl_easy_setopt(handle,CURLOPT_CAINFO,ca.constData());
#endif
    if(c.source=="juggluco") {
        curl_easy_setopt(handle,CURLOPT_SOCKOPTFUNCTION,bindSocket);curl_easy_setopt(handle,CURLOPT_SOCKOPTDATA,&t);
    }
    CURLcode code=CURLE_FAILED_INIT;int running=0;
    auto multiCode=curl_multi_add_handle(multi,handle);
    if(multiCode==CURLM_OK) {
        do {
            multiCode=curl_multi_perform(multi,&running);
            if(multiCode!=CURLM_OK||!running||cancelled->load()||c.deadline.hasExpired())break;
            int count=0;multiCode=curl_multi_poll(multi,nullptr,0,100,&count);
        } while(multiCode==CURLM_OK);
        int left=0;while(auto *message=curl_multi_info_read(multi,&left))if(message->msg==CURLMSG_DONE)code=message->data.result;
    }
    curl_easy_getinfo(handle,CURLINFO_RESPONSE_CODE,&out.status);
    curl_multi_remove_handle(multi,handle);curl_multi_cleanup(multi);curl_easy_cleanup(handle);curl_slist_free_all(headers);
    if(cancelled->load())out.error="Haku peruttu.";
    else if(c.deadline.hasExpired()||code==CURLE_OPERATION_TIMEDOUT)out.error="Yhteys aikakatkaistiin.";
    else if(t.bindingFailed)out.error="WireGuard-sidonta epäonnistui. Pyyntöä ei lähetetty.";
    else if(t.oversized||code==CURLE_FILESIZE_EXCEEDED)out.error="Palvelimen vastaus ylittää sallitun koon.";
    else if(code!=CURLE_OK||multiCode!=CURLM_OK)out.error="Yhteys epäonnistui. Tarkista yhteys ja HTTPS-varmenne.";
    else if(out.status>=300&&out.status<400)out.error="Palvelin ohjaa toiseen osoitteeseen. Anna lopullinen palvelinosoite.";
    else out.body=std::move(t.body);
    return out;
}
Result fetchResult(const FetchConfiguration &c,const std::shared_ptr<std::atomic_bool>&cancelled) {
    Result result;QByteArray jwt;bool tokenQuery=false;
    const auto secret=c.credential.toUtf8();
    if(c.auth=="token") {
        const auto auth=request(c,"api/v2/authorization/request/"+QString::fromLatin1(QUrl::toPercentEncoding(c.credential)),{},cancelled);
        if(!auth.error.isEmpty()){result.error=auth.error;return result;}
        if(auth.status==404||auth.status==405)tokenQuery=true;
        else if(auth.status==200) {
            QJsonParseError parse;const auto document=QJsonDocument::fromJson(auth.body,&parse);
            jwt=document.object()["token"].toString().toUtf8();
            if(parse.error!=QJsonParseError::NoError||jwt.isEmpty()||jwt.size()>8192||jwt.contains('\r')||jwt.contains('\n')){result.error="Palvelin ei palauttanut kelvollista lukuoikeutta.";return result;}
        } else {result.error="Palvelin hylkäsi lukutunnuksen.";return result;}
    }
    const QStringList apis=!jwt.isEmpty()?QStringList{"v3","v2","v1"}:QStringList{"v1","v2","v3"};
    for(const auto &api:apis) {
        if(c.auth=="apisecret"&&api=="v3")continue;
        if(tokenQuery&&api=="v3")continue;
        QString path=api=="v3"?"api/v3/entries?sort$desc=date&limit=20&fields=sgv,direction,date&type$eq=sgv"
                   :api=="v2"?"api/v2/entries/sgv?count=20":"api/v1/entries.json?count=20";
        QByteArray header;
        if(c.auth=="apisecret")header="api-secret: "+QCryptographicHash::hash(secret,QCryptographicHash::Sha1).toHex();
        else if(c.auth=="token") {
            if(!jwt.isEmpty()&&api!="v1")header="Authorization: Bearer "+jwt;
            else path+="&token="+QString::fromLatin1(QUrl::toPercentEncoding(c.credential));
        }
        const auto reply=request(c,path,header,cancelled);
        if(!reply.error.isEmpty()){result.error=reply.error;return result;}
        if(reply.status==404||reply.status==405)continue;
        if(reply.status!=200){result.error="Palvelin hylkäsi haun tai lukuoikeus puuttuu.";return result;}
        QJsonParseError error;const auto document=QJsonDocument::fromJson(reply.body,&error);
        const auto value=api=="v3"?document.object().value("result"):QJsonValue(document.array());
        if(error.error!=QJsonParseError::NoError||!value.isArray()||value.toArray().isEmpty()||value.toArray().size()>4096
            ||(api!="v3"&&!document.isArray())) {result.error="Palvelin palautti virheellisen tai tyhjän mittausvastauksen.";return result;}
        if(api=="v3"&&document.object().contains("status")&&document.object()["status"].toInt()!=200) {
            result.error="Palvelin palautti virhetilan mittausvastauksessa.";return result;
        }
        for(const auto &entry:value.toArray()) {
            if(!entry.isObject()){result.error="Mittausvastauksessa on virheellinen rivi.";return result;}
            const auto object=entry.toObject();bool valueOk=false,timeOk=false;
            const double number=object["sgv"].toVariant().toDouble(&valueOk);
            const auto stamp=object.contains("date")?object["date"]:object["mills"];
            const double time=stamp.toVariant().toDouble(&timeOk);
            if(!valueOk||!timeOk||!std::isfinite(number)||!std::isfinite(time)||time<=0) {
                result.error="Mittausvastauksessa on virheellinen arvo tai aikaleima.";return result;
            }
            if(number>0)result.entries.append(object.toVariantMap());
        }
        if(result.entries.isEmpty()){result.error="Palvelin ei palauttanut mittauksia.";return result;}
        result.api=api;return result;
    }
    result.error="Palvelimen tuettua lukurajapintaa ei löytynyt.";return result;
}
}
SecureClient::SecureClient(QObject *parent):QObject(parent) {
    static std::once_flag initialized;std::call_once(initialized,[]{curl_global_init(CURL_GLOBAL_DEFAULT);});
}
SecureClient::~SecureClient() {
    if(m_cancel)m_cancel->store(true);
    if(m_thread){m_thread->wait();delete m_thread;m_thread=nullptr;}
}
void SecureClient::setBusy(bool value){if(value!=m_busy){m_busy=value;emit busyChanged();}}
QString SecureClient::scopeFor(const QString &source,const QString &address,const QString &interface,const QString &auth)const {
    FetchConfiguration c;c.source=source;c.address=address;c.interface=interface;c.auth=auth;
    return normalize(c).isEmpty()?scope(c):QString();
}
void SecureClient::cancel(){++m_generation;m_pending.reset();if(m_cancel)m_cancel->store(true);setBusy(false);}
void SecureClient::fetch(const QString &source,const QString &address,const QString &interface,const QString &auth,
                         const QString &credential,const QString &credentialScope) {
    cancel();FetchConfiguration c;c.generation=m_generation;c.source=source;c.address=address;c.interface=interface;c.auth=auth;
    auto error=normalize(c);
    if(error.isEmpty()&&c.auth!="none") {
        if(credential.isEmpty()||credential.size()>8192)error="Anna tämän yhteyden lukutunnus.";
        else {
            const auto expected=scope(c);
            if(m_legacyScope.isEmpty()&&credentialScope.isEmpty())m_legacyScope=expected;
            if(credentialScope!=expected&&!(credentialScope.isEmpty()&&m_legacyScope==expected))
                error="Yhteys muuttui. Tallenna tunnus uudelle yhteydelle.";
        }
        c.credential=credential;
    }
    if(!error.isEmpty()){emit failed(error);return;}
    m_pending=std::move(c);setBusy(true);if(!m_thread)startPending();
}
void SecureClient::startPending() {
    if(!m_pending){setBusy(false);return;}
    auto c=std::move(*m_pending);m_pending.reset();m_cancel=std::make_shared<std::atomic_bool>(false);
    auto cancelled=m_cancel;auto result=std::make_shared<Result>();
    m_thread=QThread::create([c,cancelled,result]{*result=fetchResult(c,cancelled);});
    connect(m_thread,&QThread::finished,this,[this,id=c.generation,cancelled,result]{
        auto *thread=m_thread;m_thread=nullptr;thread->deleteLater();
        if(id==m_generation&&!cancelled->load()) {
            setBusy(false);
            if(id==m_generation&&!cancelled->load()) {
                if(result->error.isEmpty())emit succeeded(result->entries,result->api);else emit failed(result->error);
            }
        }
        if(m_pending&&!m_thread)startPending();
    });
    m_thread->start();
}
#ifdef GLUCOID_TESTING
void SecureClient::setTestCertificate(const QString &path){testCertificate=path;}
#endif
