#!/bin/bash
####################################################
#                                                  #
# This is a ocserv installation for CentOS 7       #
# Version: 1.1.2 20141008                          #
# Author: Travis Lee                               #
# Website: http://www.stunnel.info                 #
#                                                  #
####################################################

#变量设置
#单IP最大连接数，默认是2
maxsameclients=10
#最大连接数，默认是16
maxclients=1024
#ocserv版本
version=0.8.6
#服务器的证书和key文件，放在本脚本的同目录下，key文件的权限应该是600或者400
servercert=server-cert.pem
serverkey=server-key.pem
#配置目录，你可更改为 /etc/ocserv 之类的
confdir=/usr/local/etc/ocserv

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

#升级系统，安装系统组件
yum update -y
yum install -y gcc wget pcre-devel tar net-tools \
openssl openssl-devel curl-devel bind-utils
clear

#获取网卡接口名称
ethlist=$(ifconfig | grep ": flags" | cut -d ":" -f1)
eth=$(printf "$ethlist\n" | head -n 1)
if [[ $(printf "$ethlist\n" | wc -l) -gt 2 ]]; then
    echo ======================================
    echo "Network Interface list:"
    printf "\e[33m$ethlist\e[0m\n"
    echo ======================================
    echo "Which network interface you want to listen for ocserv?"
    printf "Default network interface is \e[33m$eth\e[0m, let it blank to use default network interface: "
    read ethtmp
    if [[ -n "$ethtmp" ]]; then
        eth=$ethtmp
    fi
fi

#端口，默认是10443
port=10443
echo "Please input the port ocserv listen to."
printf "Default port is \e[33m$port\e[0m, let it blank to use default port: "
read porttmp
if [[ -n "$porttmp" ]]; then
    port=$porttmp
fi

#用户名，默认是user
username=user
echo "Please input ocserv user name:"
printf "Default user name is \e[33m$username\e[0m, let it blank to use default user name: "
read usernametmp
if [[ -n "$usernametmp" ]]; then
    username=$usernametmp
fi

#随机密码
randstr() {
    index=0
    str=""
    for i in {a..z}; do arr[index]=$i; index=$(expr ${index} + 1); done
    for i in {A..Z}; do arr[index]=$i; index=$(expr ${index} + 1); done
    for i in {0..9}; do arr[index]=$i; index=$(expr ${index} + 1); done
    for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
    echo $str
}
password=$(randstr)
printf "Please input \e[33m$username\e[0m's password:\n"
printf "Default password is \e[33m$password\e[0m, let it blank to use default password: "
read passwordtmp
if [[ -n "$passwordtmp" ]]; then
    password=$passwordtmp
fi

#打印配置参数
clear
ipv4=$(ip -4 -f inet addr | grep "inet " | grep -v "lo:" | grep -v "127.0.0.1" | grep -o -P "\d+\.\d+\.\d+\.\d+\/\d+" | grep -o -P "\d+\.\d+\.\d+\.\d+")
ipv6=$(ip -6 addr | grep "inet6" | grep -v "::1/128" | grep -o -P "([a-z\d]+:[a-z\d:]+\/\d+)" | grep -o -P "([a-z\d]+:[a-z\d:]+)")
echo -e "IPv4:\t\t\e[34m$(echo $ipv4)\e[0m"
echo -e "IPv6:\t\t\e[34m$(echo $ipv6)\e[0m"
echo -e "Port:\t\t\e[34m$port\e[0m"
echo -e "username:\t\e[34m$username\e[0m"
echo -e "password:\t\e[34m$password\e[0m"
echo
echo "Press any key to start install ocserv."

get_char() {
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}
char=$(get_char)
clear

#安装ocserv依赖组件
yum install -y gnutls gnutls-utils gnutls-devel readline readline-devel \
libnl-devel libtalloc libtalloc-devel libnl3-devel \
unbound pam pam-devel libtalloc-devel xz libseccomp-devel \
tcp_wrappers-devel autogen autogen-libopts-devel

#关闭selinux，增加libgnutls环境变量
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0
export LIBGNUTLS_CFLAGS="-I/usr/include/" LIBGNUTLS_LIBS="-L/usr/lib/ -lgnutls"

#下载ocserv并编译安装
wget -t 0 -T 60 "ftp://ftp.infradead.org/pub/ocserv/ocserv-$version.tar.xz"
tar Jxf ocserv-$version.tar.xz
cd ocserv-$version
sed -i 's/define MAX_CONFIG_ENTRIES 64/define MAX_CONFIG_ENTRIES 400/g' src/vpn.h
./configure
make
make install

#复制配置文件样本
mkdir -p "$confdir"
cp "doc/sample.config" "$confdir/ocserv.conf"
cp "doc/systemd/standalone/ocserv.service" "/usr/lib/systemd/system/ocserv.service"

#检测是否有证书和key文件
cd ..
if [[ ! -f "$servercert" ]] || [[ ! -f "$serverkey" ]]; then
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
    certtool --generate-privkey --outfile $serverkey

    cat << _EOF_ >server.tmpl
cn = "stunnel.info VPN"
o = "stunnel"
serial = 2
expiration_days = 3650
signing_key
encryption_key #only if the generated key is an RSA one
tls_www_server
_EOF_

    certtool --generate-certificate --load-privkey $serverkey \
    --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem \
    --template server.tmpl --outfile $servercert
fi

#把证书复制到ocserv的配置目录
cp "$servercert" "$confdir" && cp "$serverkey" "$confdir"

#编辑配置文件
(echo "$password"; sleep 1; echo "$password") | ocpasswd -c "$confdir/ocpasswd" $username

sed -i "s#./sample.passwd#$confdir/ocpasswd#g" "$confdir/ocserv.conf"
sed -i "s#server-cert = ../tests/server-cert.pem#server-cert = $confdir/$servercert#g" "$confdir/ocserv.conf"
sed -i "s#server-key = ../tests/server-key.pem#server-key = $confdir/$serverkey#g" "$confdir/ocserv.conf"
sed -i "s/max-same-clients = 2/max-same-clients = $maxsameclients/g" "$confdir/ocserv.conf"
sed -i "s/max-clients = 16/max-clients = $maxclients/g" "$confdir/ocserv.conf"
sed -i "s/tcp-port = 443/tcp-port = $port/g" "$confdir/ocserv.conf"
sed -i "s/udp-port = 443/udp-port = $port/g" "$confdir/ocserv.conf"
sed -i "s/default-domain = example.com/#default-domain = example.com/g" "$confdir/ocserv.conf"
sed -i "s/ipv4-network = 192.168.1.0/ipv4-network = 192.168.8.0/g" "$confdir/ocserv.conf"
sed -i "s/ipv4-netmask = 255.255.255.0/ipv4-netmask = 255.255.251.0/g" "$confdir/ocserv.conf"
sed -i "s/dns = 192.168.1.2/dns = 8.8.8.8\ndns = 8.8.4.4/g" "$confdir/ocserv.conf"
sed -i "s/run-as-group = daemon/run-as-group = nobody/g" "$confdir/ocserv.conf"
sed -i "s/cookie-timeout = 300/cookie-timeout = 86400/g" "$confdir/ocserv.conf"
sed -i 's$route = 192.168.1.0/255.255.255.0$#route = 192.168.1.0/255.255.255.0$g' "$confdir/ocserv.conf"
sed -i 's$route = 192.168.5.0/255.255.255.0$#route = 192.168.5.0/255.255.255.0$g' "$confdir/ocserv.conf"

cat << _EOF_ >>$confdir/ocserv.conf
route = 3.0.0.0/255.0.0.0
route = 4.0.0.0/255.0.0.0
route = 8.0.0.0/252.0.0.0
route = 16.0.0.0/248.0.0.0
route = 23.0.0.0/255.0.0.0
route = 31.0.0.0/255.0.0.0
route = 46.0.0.0/255.0.0.0
route = 50.0.0.0/255.0.0.0
route = 54.0.0.0/255.0.0.0
#route = 61.0.0.0/255.0.0.0
#route = 63.0.0.0/255.0.0.0
route = 64.0.0.0/255.0.0.0
route = 67.0.0.0/255.0.0.0
route = 68.0.0.0/254.0.0.0
route = 70.0.0.0/255.0.0.0
route = 72.0.0.0/248.0.0.0
route = 92.0.0.0/255.0.0.0
route = 93.0.0.0/255.0.0.0
route = 96.0.0.0/255.0.0.0
route = 97.0.0.0/255.0.0.0
#route = 101.0.0.0/255.0.0.0
route = 103.0.0.0/255.0.0.0
route = 104.0.0.0/252.0.0.0
route = 108.0.0.0/254.0.0.0
route = 111.0.0.0/255.0.0.0
#route = 117.0.0.0/255.0.0.0
#route = 125.0.0.0/255.0.0.0
route = 128.0.0.0/255.0.0.0
route = 141.0.0.0/255.0.0.0
route = 153.0.0.0/255.0.0.0
route = 160.0.0.0/255.0.0.0
route = 166.0.0.0/255.0.0.0
#route = 168.0.0.0/255.0.0.0
route = 173.0.0.0/255.0.0.0
route = 174.0.0.0/255.0.0.0
route = 176.0.0.0/255.0.0.0
route = 178.0.0.0/255.0.0.0
route = 184.0.0.0/255.0.0.0
route = 190.0.0.0/255.0.0.0
route = 192.0.0.0/255.0.0.0
route = 194.0.0.0/255.0.0.0
route = 198.0.0.0/254.0.0.0
route = 203.0.0.0/255.0.0.0
route = 204.0.0.0/254.0.0.0
route = 206.0.0.0/255.0.0.0
route = 208.0.0.0/254.0.0.0
#route = 210.128.0.0/255.192.0.0
route = 216.0.0.0/255.0.0.0
#route = 220.128.0.0/255.128.0.0
#日本百度
route = 119.63.0.0/255.255.0.0
#Twitter
route = 210.163.0.0/255.255.0.0
route = 199.16.0.0/255.255.0.0
route = 199.59.0.0/255.255.0.0
_EOF_

#修改ocserv服务
sed -i "s#/usr/sbin/ocserv#/usr/local/sbin/ocserv#g" "/usr/lib/systemd/system/ocserv.service"
sed -i "s#/etc/ocserv/ocserv.conf#$confdir/ocserv.conf#g" "/usr/lib/systemd/system/ocserv.service"

#添加防火墙允许列表
cat << _EOF_ >/usr/lib/firewalld/services/ocserv.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>ocserv</short>
  <description>Cisco AnyConnect</description>
  <port protocol="tcp" port="$port"/>
  <port protocol="udp" port="$port"/>
</service>
_EOF_

#修改系统
echo "Enable IP forward."
sysctl -w net.ipv4.ip_forward=1
echo net.ipv4.ip_forward = 1 >> "/etc/sysctl.conf"
sleep 1
systemctl daemon-reload
sleep 1
echo "Enable ocserv service to start during bootup."
systemctl enable ocserv.service
systemctl restart firewalld
echo "Adding firewall ports."
firewall-cmd --permanent --add-service=ocserv
echo "Allows firewall to forward."
firewall-cmd --permanent --add-masquerade
sleep 1
echo "Reload firewall configure."
firewall-cmd --reload
sleep 1
#firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -s 192.168.8.0/21 -j ACCEPT
##firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -s 192.168.8.0/21 -o $eth -j ACCEPT
##iptables -A FORWARD -s 192.168.8.0/21 -j ACCEPT
#firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 192.168.8.0/21 -o $eth -j MASQUERADE
##iptables -t nat -A POSTROUTING -s 192.168.8.0/21 -o $eth -j MASQUERADE

#开启ocserv服务
systemctl daemon-reload
systemctl start ocserv.service
echo

#检测防火墙和ocserv服务是否正常
clear
printf "\e[36mChenking FirewallD status...\e[0m\n"
iptables -L -n | grep --color=auto -E "($port|192.168.8.0)"
line=$(iptables -L -n | grep -E "($port|192.168.8.0)" | wc -l)
if [[ $line -ge 3 ]]
then
    printf "\e[34mFirewallD is OK! \e[0m\n"
else
    printf "\e[33mWARNING!!! FirewallD is Wrong! \e[0m\n"
fi

echo
printf "\e[36mChenking ocserv service status...\e[0m\n"
netstat -anp | grep ":$port" | grep --color=auto -E "($port|ocserv|tcp|udp)"
linetcp=$(netstat -anp | grep ":$port" | grep ocserv | grep tcp | wc -l)
lineudp=$(netstat -anp | grep ":$port" | grep ocserv | grep udp | wc -l)
if [[ $linetcp -ge 1 && $lineudp -ge 1 ]]
then
    printf "\e[34mocserv service is OK! \e[0m\n"
else
    printf "\e[33mWARNING!!! ocserv service is Wrong! \e[0m\n"
fi

#打印VPN参数
#ipv4=$(ip -4 -f inet addr | grep "inet " | grep -v "lo:" | grep -v "127.0.0.1" | grep -o -P "\d+\.\d+\.\d+\.\d+\/\d+" | grep -o -P "\d+\.\d+\.\d+\.\d+")
#ipv6=$(ip -6 addr | grep "inet6" | grep -v "::1/128" | grep -o -P "([a-z\d]+:[a-z\d:]+\/\d+)" | grep -o -P "([a-z\d]+:[a-z\d:]+)")
printf "
if there are \e[33mNO WARNING\e[0m above, then you can connect to
your ocserv VPN Server with the default user/password below:
======================================\n"
echo -e "IPv4:\t\t\e[34m$(echo $ipv4)\e[0m"
echo -e "IPv6:\t\t\e[34m$(echo $ipv6)\e[0m"
echo -e "Port:\t\t\e[34m$port\e[0m"
echo -e "username:\t\e[34m$username\e[0m"
echo -e "password:\t\e[34m$password\e[0m"

exit 0
