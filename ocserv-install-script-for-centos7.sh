#!/bin/bash
####################################################
#                                                  #
# This is a ocserv installation for CentOS 7       #
# Version: 1.2.5 20151009                          #
# Author: Travis Lee                               #
# Website: https://www.stunnel.info                #
#                                                  #
####################################################

#  Version: 1.2.5 20151009
#  *源码下载改回作者的官方网站
#  *更新ocserv的版本为0.10.9

#  Version: 1.2.4 20150929
#  *源码下载改为从 github 下载，作者网站似乎挂了
#  *更新ocserv的版本为0.10.7
#  *更新libtasn1的版本为4.7

#  Version: 1.2.3 20150508
#  *更新libtasn1的版本为4.5
#  *更新ocserv的版本为0.10.4

#  Version: 1.2.2 20150402
#  *兼容CentOS 7.1，编译libtasn1-4.4替换系统的3.8版
#  *修正 修改src/vpn.h路由条数 的命令

#  +增加firewalld和iptables检测功能，使用systemctl is-active判断哪个防火墙在运行，请确保有一个防火墙自启动并加载默认配置
#  *把几个功能用function分隔，如果脚本运行遇到问题，可以注释已经完成的部分，修正后继续


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

basepath=$(dirname $0)
cd ${basepath}

function ConfigEnvironmentVariable {
    #ocserv版本
    ocserv_version="0.10.9"
    version=${1-${ocserv_version}}
    libtasn1_version=4.7
    #变量设置
    #单IP最大连接数，默认是2
    maxsameclients=10
    #最大连接数，默认是16
    maxclients=1024
    #服务器的证书和key文件，放在本脚本的同目录下，key文件的权限应该是600或者400
    servercert=${2-server-cert.pem}
    serverkey=${3-server-key.pem}
    #配置目录，你可更改为 /etc/ocserv 之类的
    confdir="/usr/local/etc/ocserv"

    #安装系统组件
    yum install -y -q net-tools bind-utils
    #获取网卡接口名称
    ethlist=$(ifconfig | grep ": flags" | cut -d ":" -f1)
    eth=$(printf "${ethlist}\n" | head -n 1)
    if [[ $(printf "${ethlist}\n" | wc -l) -gt 2 ]]; then
        echo ======================================
        echo "Network Interface list:"
        printf "\e[33m${ethlist}\e[0m\n"
        echo ======================================
        echo "Which network interface you want to listen for ocserv?"
        printf "Default network interface is \e[33m${eth}\e[0m, let it blank to use default network interface: "
        read ethtmp
        if [[ -n "${ethtmp}" ]]; then
            eth=${ethtmp}
        fi
    fi

    #端口，默认是10443
    port=10443
    echo "Please input the port ocserv listen to."
    printf "Default port is \e[33m${port}\e[0m, let it blank to use default port: "
    read porttmp
    if [[ -n "${porttmp}" ]]; then
        port=${porttmp}
    fi

    #用户名，默认是user
    username=user
    echo "Please input ocserv user name:"
    printf "Default user name is \e[33m${username}\e[0m, let it blank to use default user name: "
    read usernametmp
    if [[ -n "${usernametmp}" ]]; then
        username=${usernametmp}
    fi

    #随机密码
    randstr() {
        index=0
        str=""
        for i in {a..z}; do arr[index]=$i; index=$(expr ${index} + 1); done
        for i in {A..Z}; do arr[index]=$i; index=$(expr ${index} + 1); done
        for i in {0..9}; do arr[index]=$i; index=$(expr ${index} + 1); done
        for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
        echo ${str}
    }
    password=$(randstr)
    printf "Please input \e[33m${username}\e[0m's password:\n"
    printf "Default password is \e[33m${password}\e[0m, let it blank to use default password: "
    read passwordtmp
    if [[ -n "${passwordtmp}" ]]; then
        password=${passwordtmp}
    fi
}

function PrintEnvironmentVariable {
    #打印配置参数
    clear
    ipv4=$(ip -4 -f inet addr | grep "inet " | grep -v "lo:" | grep -v "127.0.0.1" | grep -o -P "\d+\.\d+\.\d+\.\d+\/\d+" | grep -o -P "\d+\.\d+\.\d+\.\d+")
    ipv6=$(ip -6 addr | grep "inet6" | grep -v "::1/128" | grep -o -P "([a-z\d]+:[a-z\d:]+\/\d+)" | grep -o -P "([a-z\d]+:[a-z\d:]+)")
    echo -e "IPv4:\t\t\e[34m$(echo ${ipv4})\e[0m"
    echo -e "IPv6:\t\t\e[34m$(echo ${ipv6})\e[0m"
    echo -e "Port:\t\t\e[34m${port}\e[0m"
    echo -e "Username:\t\e[34m${username}\e[0m"
    echo -e "Password:\t\e[34m${password}\e[0m"
    echo
    echo "Press any key to start install ocserv."

    get_char() {
        SAVEDSTTY=$(stty -g)
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty ${SAVEDSTTY}
    }
    char=$(get_char)
    clear
}

function CompileOcserv {
    #升级系统
    #yum update -y -q
    yum install -y -q epel-release
    #安装ocserv依赖组件
    yum install -y gnutls gnutls-utils gnutls-devel readline readline-devel \
    libnl-devel libtalloc libtalloc-devel libnl3-devel wget \
    pam pam-devel libtalloc-devel xz libseccomp-devel \
    tcp_wrappers-devel autogen autogen-libopts-devel tar \
    gcc pcre-devel openssl openssl-devel curl-devel \
    freeradius-client-devel freeradius-client lz4-devel lz4 \
    http-parser-devel http-parser protobuf-c-devel protobuf-c \
    pcllib-devel pcllib cyrus-sasl-gssapi dbus-devel policycoreutils gperf

:<<_EOF_
    wget -t 0 -T 60 "http://ftp.gnu.org/gnu/libtasn1/libtasn1-${libtasn1_version}.tar.gz"
    tar axf libtasn1-${libtasn1_version}.tar.gz
    cd libtasn1-${libtasn1_version}
    ./configure --prefix=/usr --libdir=/usr/lib64 --includedir=/usr/include
    make && make install
    cd ..
_EOF_

    #增加libgnutls环境变量
     ##export LIBGNUTLS_CFLAGS="-I/usr/include/" LIBGNUTLS_LIBS="-L/usr/lib/ -lgnutls"

    #下载ocserv并编译安装
    wget -t 0 -T 60 "ftp://ftp.infradead.org/pub/ocserv/ocserv-${version}.tar.xz"
    #wget -t 0 -T 60 "https://github.com/mtmiller/ocserv/archive/ocserv_${version}.tar.gz" -O "ocserv-${version}.tar.gz"
    tar axf ocserv-${version}.tar.xz
    cd ocserv-${version}
    sed -i 's/#define MAX_CONFIG_ENTRIES.*/#define MAX_CONFIG_ENTRIES 200/g' src/vpn.h
    ./configure && make && make install

    #复制配置文件样本
    mkdir -p "${confdir}"
    cp "doc/sample.config" "${confdir}/ocserv.conf"
    cp "doc/systemd/standalone/ocserv.service" "/usr/lib/systemd/system/ocserv.service"
    cd ${basepath}
}

function ConfigOcserv {
    #检测是否有证书和key文件
    if [[ ! -f "${servercert}" ]] || [[ ! -f "${serverkey}" ]]; then
        #创建ca证书和服务器证书（参考http://www.infradead.org/ocserv/manual.html#heading5）
        certtool --generate-privkey --outfile ca-key.pem

        cat << _EOF_ >ca.tmpl
cn = "stunnel.info VPN"
organization = "stunnel.info"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
crl_signing_key
_EOF_

        certtool --generate-self-signed --load-privkey ca-key.pem \
        --template ca.tmpl --outfile ca-cert.pem
        certtool --generate-privkey --outfile ${serverkey}

        cat << _EOF_ >server.tmpl
cn = "stunnel.info VPN"
o = "stunnel"
serial = 2
expiration_days = 3650
signing_key
encryption_key #only if the generated key is an RSA one
tls_www_server
_EOF_

        certtool --generate-certificate --load-privkey ${serverkey} \
        --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem \
        --template server.tmpl --outfile ${servercert}
    fi

    #把证书复制到ocserv的配置目录
    cp "${servercert}" "${confdir}" && cp "${serverkey}" "${confdir}"

    #编辑配置文件
    (echo "${password}"; sleep 1; echo "${password}") | ocpasswd -c "${confdir}/ocpasswd" ${username}

    sed -i "s#./sample.passwd#${confdir}/ocpasswd#g" "${confdir}/ocserv.conf"
    sed -i "s#server-cert = ../tests/server-cert.pem#server-cert = ${confdir}/${servercert}#g" "${confdir}/ocserv.conf"
    sed -i "s#server-key = ../tests/server-key.pem#server-key = ${confdir}/${serverkey}#g" "${confdir}/ocserv.conf"
    sed -i "s/max-same-clients = 2/max-same-clients = ${maxsameclients}/g" "${confdir}/ocserv.conf"
    sed -i "s/max-clients = 16/max-clients = ${maxclients}/g" "${confdir}/ocserv.conf"
    sed -i "s/tcp-port = 443/tcp-port = ${port}/g" "${confdir}/ocserv.conf"
    sed -i "s/udp-port = 443/udp-port = ${port}/g" "${confdir}/ocserv.conf"
    sed -i "s/default-domain = example.com/#default-domain = example.com/g" "${confdir}/ocserv.conf"
    sed -i "s/ipv4-network = 192.168.1.0/ipv4-network = 192.168.8.0/g" "${confdir}/ocserv.conf"
    sed -i "s/ipv4-netmask = 255.255.255.0/ipv4-netmask = 255.255.248.0/g" "${confdir}/ocserv.conf"
    sed -i "s/dns = 192.168.1.2/dns = 8.8.8.8\ndns = 8.8.4.4/g" "${confdir}/ocserv.conf"
    sed -i "s/run-as-group = daemon/run-as-group = nobody/g" "${confdir}/ocserv.conf"
    sed -i "s/cookie-timeout = 300/cookie-timeout = 86400/g" "${confdir}/ocserv.conf"
    sed -i 's$route = 192.168.1.0/255.255.255.0$#route = 192.168.1.0/255.255.255.0$g' "${confdir}/ocserv.conf"
    sed -i 's$route = 192.168.5.0/255.255.255.0$#route = 192.168.5.0/255.255.255.0$g' "${confdir}/ocserv.conf"

    cat << _EOF_ >>${confdir}/ocserv.conf
# Apple
route = 17.0.0.0/255.0.0.0
route = 192.12.74.0/255.255.255.0
route = 192.42.249.0/255.255.255.0
#route = 204.79.190.0/255.255.255.0
#route = 63.92.224.0/255.255.224.0
# Dropbox
route = 108.160.160.0/255.255.240.0
route = 199.47.216.0/255.255.252.0
#route = 205.189.0.0/255.255.255.0
# Github
route = 192.30.252.0/255.255.252.0
# Google
route = 8.15.202.0/255.255.255.0
route = 8.34.208.0/255.255.240.0
route = 8.35.192.0/255.255.240.0
route = 8.6.48.0/255.255.248.0
route = 8.8.4.0/255.255.255.0
route = 8.8.8.0/255.255.255.0
route = 66.102.0.0/255.255.240.0
route = 66.249.64.0/255.255.224.0
route = 70.32.128.0/255.255.224.0
route = 72.14.192.0/255.255.192.0
route = 74.125.0.0/255.255.0.0
route = 104.128.0.0/255.192.0.0
route = 104.196.0.0/255.252.0.0
route = 107.167.160.0/255.255.224.0
route = 107.178.192.0/255.255.192.0
route = 108.170.192.0/255.255.192.0
route = 108.177.0.0/255.255.128.0
route = 108.59.80.0/255.255.240.0
route = 130.211.0.0/255.255.0.0
route = 142.250.0.0/255.254.0.0
route = 146.148.0.0/255.255.128.0
route = 162.216.148.0/255.255.252.0
route = 162.222.176.0/255.255.248.0
route = 172.217.0.0/255.255.0.0
route = 172.253.0.0/255.255.0.0
route = 173.194.0.0/255.255.0.0
route = 173.255.112.0/255.255.240.0
route = 192.158.28.0/255.255.252.0
route = 192.178.0.0/255.254.0.0
route = 216.239.32.0/255.255.224.0
route = 216.58.192.0/255.255.224.0
#route = 23.236.48.0/255.255.240.0
#route = 23.251.128.0/255.255.224.0
#route = 64.233.160.0/255.255.224.0
#route = 64.9.224.0/255.255.224.0
route = 199.192.112.0/255.255.252.0
route = 199.223.232.0/255.255.248.0
#route = 207.223.160.0/255.255.240.0
#route = 209.85.128.0/255.255.128.0
# Twitter
route = 8.25.192.0/255.255.252.0
route = 8.25.196.0/255.255.254.0
route = 192.133.76.0/255.255.252.0
route = 210.163.0.0/255.255.0.0
route = 199.16.156.0/255.255.252.0
route = 199.59.148.0/255.255.252.0
route = 199.96.56.0/255.255.248.0
# TW
route = 202.39.0.0/255.255.0.0
route = 220.130.0.0/255.255.0.0
# Amazon
route = 8.18.144.0/255.255.254.0
route = 46.137.0.0/255.255.0.0
route = 46.51.128.0/255.255.128.0
route = 50.112.0.0/255.255.0.0
route = 50.16.0.0/255.252.0.0
route = 54.0.0.0/255.0.0.0
#route = 54.160.0.0/255.224.0.0
#route = 54.192.0.0/255.192.0.0
route = 67.202.0.0/255.255.192.0
route = 72.21.192.0/255.255.224.0
route = 72.44.32.0/255.255.224.0
route = 75.101.128.0/255.255.128.0
route = 79.125.0.0/255.255.128.0
route = 87.238.80.0/255.255.248.0
#route = 96.127.0.0/255.255.128.0
route = 103.246.148.0/255.255.252.0
#instagram
route = 107.20.0.0/255.252.0.0
route = 122.248.192.0/255.255.192.0
route = 174.129.0.0/255.255.0.0
route = 176.32.64.0/255.255.224.0
route = 176.34.0.0/255.255.0.0
route = 178.236.0.0/255.255.240.0
route = 184.169.128.0/255.255.128.0
route = 184.72.0.0/255.254.0.0
route = 185.48.120.0/255.255.252.0
route = 203.83.220.0/255.255.252.0
route = 216.137.32.0/255.255.224.0
route = 216.182.224.0/255.255.240.0
route = 27.0.0.0/255.255.252.0
#route = 23.20.0.0/255.252.0.0
route = 199.127.232.0/255.255.252.0
route = 199.255.192.0/255.255.252.0
#route = 204.236.128.0/255.255.128.0
#route = 204.246.128.0/255.255.128.0
#route = 205.251.192.0/255.255.192.0
#route = 207.171.160.0/255.255.224.0
# bgp.he.net
#route = 72.52.94.234/255.255.255.255
# t66y
route = 184.154.128.0/255.255.255.0
# Wordpress
route = 66.155.8.0/255.255.248.0
#route = 76.74.248.0/255.255.248.0
route = 192.0.64.0/255.255.192.0
route = 198.181.116.0/255.255.252.0
route = 199.47.91.0/255.255.255.0
# Wikimedia
route = 91.198.174.0/255.255.255.0
route = 185.15.56.0/255.255.252.0
route = 198.35.26.0/255.255.254.0
route = 198.73.209.0/255.255.255.0
#route = 208.80.152.0/255.255.252.0
## Adobe
#route = 130.248.0.0/255.255.0.0
#route = 153.32.0.0/255.255.0.0
#route = 185.34.188.0/255.255.252.0
#route = 192.147.117.0/255.255.255.0
#route = 192.150.0.0/255.255.240.0
#route = 192.150.16.0/255.255.248.0
#route = 192.243.224.0/255.255.240.0
#route = 192.243.248.0/255.255.248.0
#route = 193.104.215.0/255.255.255.0
#route = 195.35.86.0/255.255.255.0
#route = 208.77.136.0/255.255.252.0
#route = 216.104.208.0/255.255.248.0
#route = 216.104.216.0/255.255.252.0
#route = 216.104.220.0/255.255.254.0
#route = 63.140.32.0/255.255.224.0
#route = 66.117.16.0/255.255.240.0
#route = 66.235.0.0/255.255.0.0
# Akamai
route = 23.0.0.0/255.128.0.0
route = 23.192.0.0/255.192.0.0
route = 60.254.128.0/255.255.192.0
route = 63.0.0.0/255.0.0.0
route = 64.0.0.0/254.0.0.0
route = 66.171.0.0/255.255.0.0
route = 66.198.8.0/255.255.255.0
route = 67.131.232.0/255.255.255.0
route = 69.192.0.0/255.255.0.0
route = 69.22.154.0/255.255.254.0
route = 69.31.0.0/255.255.0.0
route = 70.39.163.0/255.255.255.0
route = 70.39.178.0/255.255.254.0
route = 72.246.0.0/255.254.0.0
#route = 96.16.0.0/255.254.0.0
#route = 96.6.0.0/255.254.0.0
#route = 98.124.141.0/255.255.255.0
route = 104.64.0.0/255.192.0.0
route = 172.224.0.0/255.240.0.0
route = 184.24.0.0/255.248.0.0
route = 184.50.0.0/255.254.0.0
route = 184.84.0.0/255.252.0.0
route = 216.151.176.0/255.255.255.0
route = 216.151.187.0/255.255.255.0
route = 216.206.30.0/255.255.255.0
route = 216.246.122.0/255.255.255.0
route = 216.246.75.0/255.255.255.0
route = 216.246.87.0/255.255.255.0
route = 216.246.93.0/255.255.255.0
route = 173.222.0.0/255.254.0.0
route = 173.245.0.0/255.255.0.0
route = 198.144.0.0/255.255.0.0
route = 198.47.108.0/255.255.255.0
#route = 204.10.28.0/255.255.252.0
#route = 204.8.48.0/255.255.252.0
#route = 204.93.0.0/255.255.0.0
#route = 204.95.24.0/255.255.254.0
#route = 205.161.113.0/255.255.255.0
#route = 205.185.204.0/255.255.254.0
#route = 205.234.218.0/255.255.255.0
#route = 205.234.225.0/255.255.255.0
#route = 205.246.30.0/255.255.255.0
#route = 208.34.250.0/255.255.255.0
#route = 209.107.0.0/255.255.0.0
#route = 209.136.40.0/255.255.255.0
#route = 209.170.0.0/255.255.0.0
#route = 209.234.250.0/255.255.255.0
#route = 209.234.252.0/255.255.255.0
#route = 209.95.152.0/255.255.255.0
# Cloudflare
route = 104.16.0.0/255.240.0.0
route = 108.162.192.0/255.255.192.0
route = 162.158.0.0/255.254.0.0
#route = 173.245.48.0/255.255.240.0
route = 198.41.128.0/255.255.128.0
route = 199.27.128.0/255.255.248.0
#route = 204.93.177.0/255.255.255.0
# E-hentai
route = 37.48.64.0/255.255.192.0
route = 85.17.0.0/255.255.0.0
route = 95.211.0.0/255.255.0.0
# Facebook
route = 31.13.24.0/255.255.248.0
route = 31.13.64.0/255.255.192.0
route = 66.220.144.0/255.255.240.0
route = 69.171.224.0/255.255.224.0
route = 69.63.176.0/255.255.240.0
route = 74.119.76.0/255.255.252.0
#route = 173.252.64.0/255.255.192.0
route = 199.201.64.0/255.255.252.0
#route = 204.15.20.0/255.255.252.0
# Fastly
#route = 23.235.32.0/255.255.240.0
#route = 104.156.80.0/255.255.240.0
route = 199.27.72.0/255.255.248.0
# Fc2
route = 199.116.176.0/255.255.252.0
#route = 208.71.104.0/255.255.252.0
# Mediafire
route = 199.91.152.0/255.255.248.0
#route = 205.196.120.0/255.255.252.0
# Ntt
route = 66.116.105.0/255.255.255.0
route = 128.121.0.0/255.255.0.0
route = 128.240.0.0/255.254.0.0
route = 128.242.0.0/255.255.0.0
route = 129.250.0.0/255.255.0.0
route = 130.94.0.0/255.255.0.0
route = 131.103.0.0/255.255.0.0
route = 140.174.0.0/255.255.0.0
route = 157.238.0.0/255.255.0.0
route = 161.58.0.0/255.255.0.0
route = 165.254.0.0/255.255.0.0
route = 168.143.0.0/255.255.0.0
route = 192.102.248.0/255.255.255.0
route = 192.147.160.0/255.255.248.0
route = 192.147.176.0/255.255.252.0
route = 192.204.0.0/255.255.0.0
route = 192.217.0.0/255.255.0.0
route = 192.220.0.0/255.255.0.0
route = 192.35.171.0/255.255.255.0
route = 192.67.14.0/255.255.255.0
route = 192.67.236.0/255.255.252.0
route = 192.80.12.0/255.255.252.0
#route = 198.0.0.0/255.0.0.0
#route = 199.0.0.0/255.0.0.0
route = 204.0.0.0/252.0.0.0
route = 208.0.0.0/254.0.0.0
route = 216.115.90.0/255.255.254.0
route = 216.167.0.0/255.255.128.0
route = 216.42.0.0/255.255.0.0
route = 216.44.0.0/255.255.0.0
# Timewarner
#route = 76.85.128.0/255.255.128.0
#route = 76.85.16.0/255.255.240.0
#route = 76.85.4.0/255.255.252.0
#route = 76.85.48.0/255.255.248.0
#route = 76.85.64.0/255.255.224.0
#route = 76.85.96.0/255.255.252.0
#route = 76.86.0.0/255.254.0.0
#route = 76.88.0.0/255.248.0.0
route = 76.0.0.0/255.0.0.0
route = 96.0.0.0/255.0.0.0
route = 97.0.0.0/255.0.0.0
route = 98.0.0.0/255.0.0.0
#route = 96.10.0.0/255.254.0.0
#route = 96.28.0.0/255.254.0.0
#route = 97.104.0.0/255.254.0.0
#route = 97.106.0.0/255.255.128.0
#route = 97.106.128.0/255.255.192.0
#route = 97.76.0.0/255.254.0.0
#route = 97.78.0.0/255.255.128.0
#route = 97.78.128.0/255.255.224.0
#route = 97.79.0.0/255.255.0.0
#route = 97.96.0.0/255.248.0.0
#route = 98.0.0.0/255.240.0.0
#route = 98.100.0.0/255.252.0.0
#route = 98.120.0.0/255.252.0.0
#route = 98.144.0.0/255.248.0.0
#route = 98.152.0.0/255.252.0.0
#route = 98.156.0.0/255.254.0.0
#route = 98.24.0.0/255.248.0.0
# 6park
route = 159.106.121.0/255.255.255.0
route = 198.11.0.0/255.255.0.0
route = 173.192.0.0/255.255.0.0
route = 50.22.0.0/255.255.0.0
# kakao.com
route = 110.76.141.0/255.255.255.0
# shadownsocks
route = 103.245.0.0/255.255.0.0
# softether.org
route = 27.121.46.0/255.255.255.0
# haproxy.org
route = 195.154.117.0/255.255.255.0
# openvpn.net
route = 189.163.17.5/255.255.255.255
# menuetos.net
route = 213.188.129.144/255.255.255.255
# gamer.com.tw
route = 60.199.217.0/255.255.255.0
_EOF_

    #修改ocserv服务
    #sed -i "s#^ExecStart=#ExecStartPre=/usr/bin/firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -s 192.168.8.0/21 -j ACCEPT\nExecStartPre=/usr/bin/firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 192.168.8.0/21 -o ${eth} -j MASQUERADE\nExecStart=#g" "/usr/lib/systemd/system/ocserv.service"
    sed -i "s#/usr/sbin/ocserv#/usr/local/sbin/ocserv#g" "/usr/lib/systemd/system/ocserv.service"
    sed -i "s#/etc/ocserv/ocserv.conf#$confdir/ocserv.conf#g" "/usr/lib/systemd/system/ocserv.service"
}

function ConfigFirewall {

firewalldisactive=$(systemctl is-active firewalld.service)
iptablesisactive=$(systemctl is-active iptables.service)

if [[ ${firewalldisactive} = 'active' ]]; then
    #添加防火墙允许列表
    echo "Adding firewall ports."
    firewall-cmd --permanent --add-port=${port}/tcp
    firewall-cmd --permanent --add-port=${port}/udp
    echo "Allow firewall to forward."
    firewall-cmd --permanent --add-masquerade
    echo "Reload firewall configure."
    firewall-cmd --reload
elif [[ ${iptablesisactive} = 'active' ]]; then
    iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
    iptables -I INPUT -p udp --dport ${port} -j ACCEPT
    iptables -A FORWARD -s 192.168.8.0/21 -j ACCEPT
    iptables -t nat -A POSTROUTING -s 192.168.8.0/21 -o ${eth} -j MASQUERADE
    service iptables save
else
    printf "\e[33mWARNING!!! Either firewalld or iptables is NOT Running! \e[0m\n"
fi
}

function ConfigSystem {
    #关闭selinux
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
    #修改系统
    echo "Enable IP forward."
    sysctl -w net.ipv4.ip_forward=1
    echo net.ipv4.ip_forward = 1 >> "/etc/sysctl.conf"
    systemctl daemon-reload
    echo "Enable ocserv service to start during bootup."
    systemctl enable ocserv.service
    #开启ocserv服务
    systemctl start ocserv.service
    echo
}

function PrintResult {
    #检测防火墙和ocserv服务是否正常
    clear
    printf "\e[36mChenking Firewall status...\e[0m\n"
    iptables -L -n | grep --color=auto -E "(${port}|192.168.8.0)"
    line=$(iptables -L -n | grep -c -E "(${port}|192.168.8.0)")
    if [[ ${line} -ge 2 ]]
    then
        printf "\e[34mFirewall is Fine! \e[0m\n"
    else
        printf "\e[33mWARNING!!! Firewall is Something Wrong! \e[0m\n"
    fi

    echo
    printf "\e[36mChenking ocserv service status...\e[0m\n"
    netstat -anp | grep ":${port}" | grep --color=auto -E "(${port}|ocserv|tcp|udp)"
    linetcp=$(netstat -anp | grep ":${port}" | grep ocserv | grep tcp | wc -l)
    lineudp=$(netstat -anp | grep ":${port}" | grep ocserv | grep udp | wc -l)
    if [[ ${linetcp} -ge 1 && ${lineudp} -ge 1 ]]
    then
        printf "\e[34mocserv service is Fine! \e[0m\n"
    else
        printf "\e[33mWARNING!!! ocserv service is NOT Running! \e[0m\n"
    fi

    #打印VPN参数
    printf "
    if there are \e[33mNO WARNING\e[0m above, then you can connect to
    your ocserv VPN Server with the default user/password below:
    ======================================\n"
    echo -e "IPv4:\t\t\e[34m$(echo ${ipv4})\e[0m"
    echo -e "IPv6:\t\t\e[34m$(echo ${ipv6})\e[0m"
    echo -e "Port:\t\t\e[34m${port}\e[0m"
    echo -e "Username:\t\e[34m${username}\e[0m"
    echo -e "Password:\t\e[34m${password}\e[0m"
}

ConfigEnvironmentVariable
PrintEnvironmentVariable
CompileOcserv $@
ConfigOcserv
ConfigFirewall
ConfigSystem
PrintResult
exit 0
