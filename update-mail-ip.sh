#!/bin/bash
# /root/update_mail_allow.sh
# 每30分钟更新 SMTP 可访问的邮箱 IP，不影响原有 iptables 规则

IPSET_NAME="mail_allow"

# 如果集合不存在就创建
ipset list $IPSET_NAME >/dev/null 2>&1 || ipset create $IPSET_NAME hash:ip

# 清空已有内容
ipset flush $IPSET_NAME

# 邮箱域列表
DOMAINS=(gmail.com qq.com 163.com yahoo.com sina.com 126.com outlook.com yeah.net foxmail.com)

for d in "${DOMAINS[@]}"
do
    # 获取 MX 主机名
    dig +short MX $d | awk '{print $2}' | sed 's/\.$//' | while read mx
    do
        # 解析 MX 主机名的 IP
        dig +short $mx | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | while read ip
        do
            ipset add $IPSET_NAME $ip -exist
        done
    done
done

# 检查 iptables 是否已经有规则允许集合 IP 发 25
RULE_EXISTS=$(iptables -C OUTPUT -p tcp --dport 25 -m set --match-set $IPSET_NAME dst -j ACCEPT 2>/dev/null)
if [ $? -ne 0 ]; then
    # 规则不存在就添加
    iptables -I OUTPUT -p tcp --dport 25 -m set --match-set $IPSET_NAME dst -j ACCEPT
fi

# 检查是否已经有 DROP 规则阻止非集合 IP
DROP_EXISTS=$(iptables -C OUTPUT -p tcp --dport 25 -j DROP 2>/dev/null)
if [ $? -ne 0 ]; then
    iptables -A OUTPUT -p tcp --dport 25 -j DROP
fi
