#!/bin/bash

version=${1-0.8.9}
filename=ocserv-$version.tar.xz
dirname=ocserv-$version
url="ftp://ftp.infradead.org/pub/ocserv/$filename"
export LIBGNUTLS_CFLAGS="-I/usr/include/" LIBGNUTLS_LIBS="-L/usr/lib/ -lgnutls"

#检测是否是root用户
if [[ $(id -u) != "0" ]]; then
    printf "\e[42m\e[31mError: You must be root to run this install script.\e[0m\n"
    exit 1
fi

#检测是否是CentOS 7或者RHEL 7
if [[ $(grep "release 7." /etc/redhat-release 2>/dev/null | wc -l) -eq 0 ]]; then
    printf "\e[42m\e[31mError: Your OS is NOT CentOS 7 or RHEL 7.\e[0m\n"
    printf "\e[42m\e[31mThis install script is ONLY for CentOS 7 and RHEL 7.\e[0m\n"
    exit 1
fi

#下载ocserv并编译安装
if [ ! -f "$filename" ]; then
    wget -t 0 -T 60 "$url"
fi
tar axf $filename
cd $dirname

sed -i 's/define MAX_CONFIG_ENTRIES 64/define MAX_CONFIG_ENTRIES 400/g' src/vpn.h
./configure
make
make install

exit 0
