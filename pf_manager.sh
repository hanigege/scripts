#!/bin/sh
# FreeBSD 15 PF 交互式防火墙管理脚本 - 自动拉黑防御终极版
# 核心功能: 动态端口管理、TCP/UDP状态追踪分离、防爆破自动拉黑、黑名单持久化

STATE_FILE="/etc/pf_ports.list"
BLACKLIST_FILE="/etc/pf_blacklist.txt"
PF_CONF="/etc/pf.conf"

if [ "$(id -u)" != "0" ]; then
    echo "错误：必须使用 root 权限运行。"
    exit 1
fi

get_active_ssh_ports() {
    ports=$(sockstat -46 -l -P tcp | grep -E '\bsshd\b' | awk '{print $6}' | awk -F':' '{print $NF}' | sort -u)
    if [ -z "$ports" ]; then echo "22"; else echo "$ports"; fi
}

init_env() {
    if ! grep -q "^pf_enable=\"YES\"" /etc/rc.conf; then
        sysrc pf_enable="YES" >/dev/null
        service pf start >/dev/null 2>&1
    fi
    [ ! -f "$STATE_FILE" ] && init_zero
    [ ! -f "$BLACKLIST_FILE" ] && touch "$BLACKLIST_FILE"
}

init_zero() {
    > "$STATE_FILE"
    active_ports=$(get_active_ssh_ports)
    for port in $active_ports; do
        echo "tcp $port" >> "$STATE_FILE"
    done
    apply_rules >/dev/null 2>&1
    echo "✅ 已清空所有自定义端口规则。"
    echo "🔒 自动检测并放行当前活动 SSH 端口: [ $active_ports ]"
}

apply_rules() {
    cat <<EOF > "$PF_CONF"
# 宏定义与全局选项
set skip on lo0
set block-policy drop

# 黑名单表定义 (持久化)
table <blacklist> persist file "$BLACKLIST_FILE"

# 流量清理
scrub in all fragment reassemble

# --- 核心拦截区 ---
# 匹配黑名单立刻丢弃，不予回应
block in quick from <blacklist> to any

# --- 基础过滤规则 ---
block in all
pass out all keep state
pass in quick inet proto icmp all icmp-type echoreq keep state
EOF

    if grep -q "^ALL PORTS OPEN$" "$STATE_FILE"; then
        echo "pass in quick all keep state" >> "$PF_CONF"
    else
        while read -r proto port; do
            [ -z "$proto" ] || [ -z "$port" ] && continue
            
            # 核心机制：区分 TCP 和 UDP 的状态追踪参数与防爆破
            if [ "$proto" = "tcp" ]; then
                echo "pass in quick inet proto tcp from any to any port $port keep state (max-src-conn 100, max-src-conn-rate 50/5, overload <blacklist> flush global)" >> "$PF_CONF"
            elif [ "$proto" = "udp" ]; then
                echo "pass in quick inet proto udp from any to any port $port keep state (max-src-states 100, max-src-conn-rate 50/5, overload <blacklist> flush global)" >> "$PF_CONF"
            fi
        done < "$STATE_FILE"
    fi

    pfctl -nf "$PF_CONF" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        pfctl -f "$PF_CONF" >/dev/null 2>&1
        echo "✅ 规则已成功更新并生效！"
    else
        echo "❌ 规则语法错误，未应用更改！"
    fi
}

view_rules() {
    echo "--- 当前系统生效的 PF 规则 (pfctl -sr) ---"
    pfctl -sr
    echo "------------------------------------------"
}

open_port() {
    read -p "请输入要开放的端口号 (1-65535): " port
    if ! [ "$port" -eq "$port" ] 2>/dev/null || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "错误：端口号无效。"
        return
    fi
    echo "请选择协议: 1) TCP  2) UDP  3) TCP 和 UDP"
    read -p "输入选项 (1/2/3): " proto_opt
    sed -i '' '/^ALL PORTS OPEN$/d' "$STATE_FILE"
    case $proto_opt in
        1) grep -q "^tcp $port$" "$STATE_FILE" || echo "tcp $port" >> "$STATE_FILE" ;;
        2) grep -q "^udp $port$" "$STATE_FILE" || echo "udp $port" >> "$STATE_FILE" ;;
        3) 
           grep -q "^tcp $port$" "$STATE_FILE" || echo "tcp $port" >> "$STATE_FILE"
           grep -q "^udp $port$" "$STATE_FILE" || echo "udp $port" >> "$STATE_FILE" ;;
        *) echo "错误：无效选项。" ; return ;;
    esac
    apply_rules
}

delete_port() {
    read -p "请输入要关闭的端口号: " port
    if grep -q " $port$" "$STATE_FILE"; then
        sed -i '' "/ $port$/d" "$STATE_FILE"
        apply_rules
    else
        echo "该端口未在管理列表中。"
    fi
}

open_all_ports() {
    echo "⚠️ 警告：这将放行所有入站流量！(但黑名单依旧有效)"
    read -p "确认执行？(y/n): " confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && { echo "ALL PORTS OPEN" > "$STATE_FILE"; apply_rules; }
}

view_blacklist() {
    echo "--- 当前被封禁的 IP 黑名单 ---"
    # 核心修复：查看时强制将内存表落盘，防止漏存自动拉黑的IP
    pfctl -t blacklist -T show > "$BLACKLIST_FILE" 2>/dev/null
    if [ -s "$BLACKLIST_FILE" ]; then
        cat "$BLACKLIST_FILE"
    else
        echo "(空)"
    fi
    echo "------------------------------"
    echo "提示：触发高频扫描规则的 IP 会自动添加到此处，且已同步保存至硬盘。"
}

ban_ip() {
    read -p "请输入要封禁的 IP 地址: " ip
    if [ -z "$ip" ]; then echo "错误：IP 不能为空。"; return; fi
    
    pfctl -t blacklist -T add "$ip" >/dev/null 2>&1
    pfctl -k "$ip" >/dev/null 2>&1
    
    # 将内存表最新状态同步覆盖到持久化文件
    pfctl -t blacklist -T show > "$BLACKLIST_FILE" 2>/dev/null
    echo "✅ 已手动封禁 IP: $ip，并强制切断其当前所有连接。"
}

unban_ip() {
    read -p "请输入要解封的 IP 地址: " ip
    pfctl -t blacklist -T delete "$ip" >/dev/null 2>&1
    
    # 将内存表最新状态同步覆盖到持久化文件
    pfctl -t blacklist -T show > "$BLACKLIST_FILE" 2>/dev/null
    echo "✅ 已解封 IP: $ip (文件内记录已同步清理)"
}

init_env

while true; do
    echo ""
    echo "=== PF 防火墙管理菜单 ==="
    echo "1. 查看当前底层生效规则"
    echo "2. 查看已开放端口列表"
    echo "3. 开放新端口 (支持 TCP/UDP)"
    echo "4. 删除/关闭端口"
    echo "5. 关闭所有端口并从零开始 (保留当前活动 SSH 端口)"
    echo "6. 开放所有端口 (高危)"
    echo "-------------------------"
    echo "7. 查看被封禁的 IP 黑名单"
    echo "8. 手动添加 IP 到黑名单"
    echo "9. 从黑名单解封 IP"
    echo "0. 退出"
    read -p "请选择操作 [0-9]: " choice

    case $choice in
        1) view_rules ;;
        2) echo "--- 当前管理的端口 ---"; cat "$STATE_FILE" ;;
        3) open_port ;;
        4) delete_port ;;
        5) 
           echo "⚠️ 警告：这将清除所有记录，并重新抓取当前 SSH 端口作为唯一放行规则！"
           read -p "确认执行？(y/n): " confirm
           [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && init_zero ;;
        6) open_all_ports ;;
        7) view_blacklist ;;
        8) ban_ip ;;
        9) unban_ip ;;
        0) exit 0 ;;
        *) echo "无效选项。" ;;
    esac
done

