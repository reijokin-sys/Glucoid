// SPDX-License-Identifier: GPL-3.0-or-later
// Local widget implementation; same socket policy as Studio 1.4.1.
#include "wireguard.h"
#include <QNetworkInterface>
#include <QRegularExpression>
#ifdef Q_OS_LINUX
#include <sys/socket.h>
#include <unistd.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/if_link.h>
#endif
bool activeWireguard(const QString &name) {
#ifdef Q_OS_LINUX
    static const QRegularExpression valid("^[A-Za-z0-9_.-]{1,15}$");
    if(!valid.match(name).hasMatch())return false;
    const auto interface=QNetworkInterface::interfaceFromName(name);
    if(!interface.isValid()||!interface.flags().testFlag(QNetworkInterface::IsUp))return false;
    const int fd=::socket(AF_NETLINK,SOCK_RAW|SOCK_CLOEXEC,NETLINK_ROUTE);
    if(fd<0)return false;
    struct Close {int fd;~Close(){::close(fd);}} close{fd};
    const timeval timeout{0,250000};
    if(::setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout)))return false;
    struct {nlmsghdr header;ifinfomsg info;} request{};
    request.header.nlmsg_len=NLMSG_LENGTH(sizeof(ifinfomsg));request.header.nlmsg_type=RTM_GETLINK;
    request.header.nlmsg_flags=NLM_F_REQUEST;request.header.nlmsg_seq=1;request.info.ifi_index=interface.index();
    sockaddr_nl kernel{};kernel.nl_family=AF_NETLINK;
    if(::sendto(fd,&request,request.header.nlmsg_len,0,reinterpret_cast<sockaddr*>(&kernel),sizeof(kernel))<0)return false;
    alignas(nlmsghdr) char bytes[16384];int left=int(::recv(fd,bytes,sizeof(bytes),0));
    for(auto *m=reinterpret_cast<nlmsghdr*>(bytes);NLMSG_OK(m,left);m=NLMSG_NEXT(m,left)) {
        if(m->nlmsg_type!=RTM_NEWLINK||m->nlmsg_seq!=1||m->nlmsg_len<NLMSG_LENGTH(sizeof(ifinfomsg)))continue;
        const auto *info=reinterpret_cast<ifinfomsg*>(NLMSG_DATA(m));if(info->ifi_index!=interface.index())continue;
        int length=IFLA_PAYLOAD(m);
        for(auto *a=IFLA_RTA(info);RTA_OK(a,length);a=RTA_NEXT(a,length)) {
            if((a->rta_type&NLA_TYPE_MASK)!=IFLA_LINKINFO)continue;
            int nested=RTA_PAYLOAD(a);
            for(auto *b=reinterpret_cast<rtattr*>(RTA_DATA(a));RTA_OK(b,nested);b=RTA_NEXT(b,nested))
                if((b->rta_type&NLA_TYPE_MASK)==IFLA_INFO_KIND)
                    return QByteArray(static_cast<const char*>(RTA_DATA(b)),RTA_PAYLOAD(b))==QByteArray("wireguard\0",10);
        }
    }
#else
    Q_UNUSED(name);
#endif
    return false;
}
bool bindWireguard(int descriptor,const QString &name) {
#ifdef Q_OS_LINUX
    if(!activeWireguard(name))return false;
    const auto encoded=name.toLatin1();
    if(::setsockopt(descriptor,SOL_SOCKET,SO_BINDTODEVICE,encoded.constData(),socklen_t(encoded.size()+1)))return false;
    char bound[256]{};socklen_t size=sizeof(bound);
    return ::getsockopt(descriptor,SOL_SOCKET,SO_BINDTODEVICE,bound,&size)==0
        &&QByteArray(bound,int(size)).split('\0').value(0)==encoded&&activeWireguard(name);
#else
    Q_UNUSED(descriptor);Q_UNUSED(name);return false;
#endif
}
