#!/bin/bash

ocserv_version=0.10.4
version=${1-${ocserv_version}}
libtasn1_version=4.5
filename="ocserv-${version}.tar.xz"
dirname="ocserv-${version}"
url="ftp://ftp.infradead.org/pub/ocserv/${filename}"
##export LIBGNUTLS_CFLAGS="-I/usr/include/" LIBGNUTLS_LIBS="-L/usr/lib/ -lgnutls"

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

function updatelibtasn1 {
    wget -t 0 -T 60 "http://ftp.gnu.org/gnu/libtasn1/libtasn1-${libtasn1_version}.tar.gz"
    tar axf libtasn1-${libtasn1_version}.tar.gz
    cd libtasn1-${libtasn1_version}
    ./configure --prefix=/usr --libdir=/usr/lib64 --includedir=/usr/include
    make && make install
    cd ..
}

case $1 in
   updatelibtasn1)
        updatelibtasn1
        ;;
esac

#下载ocserv并编译安装
if [ ! -f "${filename}" ]; then
    wget -t 0 -T 60 "${url}"
fi
rm -rf "${dirname}"
tar axf "${filename}"
cd "${dirname}"

sed -i 's/#define MAX_CONFIG_ENTRIES.*/#define MAX_CONFIG_ENTRIES 200/g' src/vpn.h
./configure
make && make install

exit 0
