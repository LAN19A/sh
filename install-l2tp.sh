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

echo "开始安装必要软件..."
apt update -y
apt install -y strongswan xl2tpd ppp iptables iptables-persistent curl

# 切换 iptables legacy（Debian 11 必须）
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

# 自动获取公网 IP
PUBLIC_IP=$(curl -s 4.ipw.cn)
echo "检测到公网 IP: $PUBLIC_IP"

cat > /etc/ipsec.conf <<EOF
config setup
    uniqueids=no

conn L2TP-PSK
    keyexchange=ikev1
    authby=psk
    type=transport
    left=$PUBLIC_IP
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    ike=aes128-sha1-modp1024
    esp=aes128-sha1
    auto=add
EOF

cat > /etc/ipsec.secrets <<EOF
%any %any : PSK "Network1888"
EOF

echo "配置 xl2tpd..."

cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

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

echo "配置单用户账号..."

cat > /etc/ppp/chap-secrets <<EOF
user    l2tpd    Network1888    *
EOF

# 自动检测公网网卡
WAN_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
echo "检测到公网网卡: $WAN_IF"

echo "配置防火墙..."

iptables -F
iptables -t nat -F

# NAT
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $WAN_IF -j MASQUERADE

# FORWARD
iptables -A FORWARD -s 10.10.10.0/24 -o $WAN_IF -j ACCEPT
iptables -A FORWARD -d 10.10.10.0/24 -m state --state RELATED,ESTABLISHED -j ACCEPT

# 允许 IPsec
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT

# 只允许 IPsec 保护的 1701
iptables -A INPUT -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
iptables -A INPUT -p udp --dport 1701 -j DROP

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
echo "共享密钥: Network1888"
echo "账号: user"
echo "密码: Network1888"
echo "========================================"
