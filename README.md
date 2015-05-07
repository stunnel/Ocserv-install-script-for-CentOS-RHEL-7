Ocserv install script for CentOS&RHEL 7
=======================================
这是 ocserv 在 CentOS 7 和 RHEL 7 的一键安装脚本，可以在最小化安装环境的 CentOS 7 和 RHEL 7 下一键部署 ocserv。<br />
已知部分 64M 内存的 VPS 一次 yum 太多软件包会报错，可以修改脚本分多次安装。<br />
支持自动判断 firewalld 和 iptables。<br />

* 支持自动判断防火墙，请确保 Firewalld 或者 iptables 其中一个是 active 状态；<br />
* 默认采用用户名密码验证，本安装脚本编译的 ocserv 也支持 pam 验证，只需要修改配置文件即可；<br />
* 默认配置文件在 /usr/local/etc/ocserv/ 目录，可自行更改脚本里的参数；<br />
* 安装时会提示你输入端口、用户名、密码等信息，也可直接回车采用默认值，密码是随机生成的；<br />
* 安装脚本会关闭 SELINUX；<br />
* 自带路由表，只有路由表里的 IP 才会走 VPN，如果你有需要添加的路由表可自行添加，最多支持 200 条；<br />
* 如果你有证书机构颁发的证书，可以把证书放到脚本的同目录下，确保文件名和脚本里的匹配，安装脚本会使用你的证书，客户端连接时不会提示证书错误；<br />
* 配置文件修改为每个账号允许 10 个连接，全局 1024 个连接，可修改脚本前面的变量。1024 个连接大约需要 2048 个 IP，所以虚拟接口的 IP 配置了 8 个 C 段。<br />

安装脚本分为以下几大块，如果中间有错误，可以注释掉部分然后重新执行脚本，ConfigEnvironmentVariable 为必须，后面的脚本会使用这里的变量<br />

* ConfigEnvironmentVariable // 配置环境变量<br />
* PrintEnvironmentVariable // 打印环境变量<br />
* CompileOcserv $@ // 下载并编译 ocserv<br />
* ConfigOcserv // 配置 ocserv，包括修改 ocserv.conf，配置 ocserv.service<br />
* ConfigFirewall // 配置防火墙，会自动判断防火墙为 iptables 或 firewalld<br />
* ConfigSystem  // 配置系统<br />
* PrintResult // 打印最后的安装结果和 VPN 账号等<br />
