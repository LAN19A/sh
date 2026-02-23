#!/bin/bash

clear
echo "========================================"
echo "      L2TP/IPsec Single User Installer"
echo "        Debian 11 Compatible"
echo "========================================"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 运行"
    exit 1
fi

# 默认端口
L2TP_PORT=1701

# 解析参数
while getopts "P:" opt; do
  case $opt in
    P)
      L2TP_PORT=$OPTARG
      ;;
    *)
      echo "用法: $0 [-P 端口]"
      exit 1
      ;;
  esac
done

echo "使用 L2TP 端口: $L2TP_PORT"

echo "开始安装必要软件..."
apt update -y
apt install -y strongswan xl2tpd ppp iptables iptables-persistent curl

update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

echo "开启 IP 转发..."
cat > /etc/sysctl.d/99-l2tp.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF
sysctl --system

echo "配置 IPsec..."

PUBLIC_IP=$(curl -s 4.ipw.cn)
echo "检测到公网 IP: $PUBLIC_IP"

cat > /etc/ipsec.conf <<EOF
config setup
    uniqueids=no
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2"

conn L2TP-PSK
    keyexchange=ikev1
    authby=psk
    type=transport
    left=$PUBLIC_IP
    leftprotoport=17/$L2TP_PORT
    right=%any
    rightprotoport=17/%any
    dpddelay=30
    dpdtimeout=150
    ike=aes256-sha2_256-modp2048,aes128-sha2_256-modp2048,aes128-sha1-modp1024
    esp=aes256-sha2_256,aes128-sha2_256,aes128-sha1
    auto=add
    rekey=no
    keylife=24h
    ikelifetime=24h
EOF

cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "TTNE888"
EOF

echo "配置 xl2tpd..."

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = $L2TP_PORT

[lns default]
ip range = 10.10.10.10-10.10.10.100
local ip = 10.10.10.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat > /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 1.1.1.1
asyncmap 0
auth
idle 1800
mtu 1400
mru 1400
connect-delay 5000
EOF

cat > /etc/ppp/chap-secrets <<EOF
user    l2tpd    Network1888    *
EOF

WAN_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
echo "检测到公网网卡: $WAN_IF"

echo "配置防火墙..."

iptables -F
iptables -t nat -F

iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $WAN_IF -j MASQUERADE

iptables -A FORWARD -s 10.10.10.0/24 -o $WAN_IF -j ACCEPT
iptables -A FORWARD -d 10.10.10.0/24 -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT

iptables -A INPUT -p udp --dport $L2TP_PORT -m policy --dir in --pol ipsec -j ACCEPT
iptables -A INPUT -p udp --dport $L2TP_PORT -j DROP

netfilter-persistent save

echo "启动服务..."

systemctl restart strongswan-starter
systemctl restart xl2tpd
systemctl enable strongswan-starter
systemctl enable xl2tpd

echo ""
echo "========================================"
echo "安装完成！"
echo "服务器IP: $(curl -s ifconfig.me)"
echo "L2TP端口: $L2TP_PORT"
echo "共享密钥: TTNE888"
echo "账号: user"
echo "密码: Network1888"
echo "分配网段: 10.10.10.10-10.10.10.100"
echo "========================================"
