#!/bin/bash

# 如果集合不存在就创建
ipset list mail_allow >/dev/null 2>&1 || ipset create mail_allow hash:ip

# 清空已有内容
ipset flush mail_allow

for d in gmail.com qq.com 163.com yahoo.com sina.com 126.com outlook.com yeah.net foxmail.com
do
    # 获取 MX 主机名
    dig +short MX $d | awk '{print $2}' | sed 's/\.$//' | while read mx
    do
        # 解析 MX 主机名的 IP
        dig +short $mx | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | while read ip
        do
            ipset add mail_allow $ip -exist
        done
    done
done
