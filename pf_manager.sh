#!/bin/sh
# FreeBSD PF firewall manager.
# Manage TCP/UDP allowed ports and a persistent PF blacklist.

set -u

STATE_FILE="/etc/pf_ports.list"
BLACKLIST_FILE="/etc/pf_blacklist.txt"
PF_CONF="/etc/pf.conf"
PF_CONF_TMP="/etc/pf.conf.tmp.$$"
CRON_PATTERN='pfctl -t blacklist -T expire 86400'
CRON_LINE='0 3 * * * /sbin/pfctl -t blacklist -T expire 86400 >/dev/null 2>&1 && /sbin/pfctl -t blacklist -T show > /etc/pf_blacklist.txt'
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"

if [ "$(id -u)" != "0" ]; then
    echo "错误：必须使用 root 权限运行。"
    exit 1
fi

cleanup() {
    rm -f "$PF_CONF_TMP"
}
trap cleanup EXIT INT TERM

is_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_ip_or_cidr() {
    case "$1" in
        ''|*[!0-9./:a-fA-F]*) return 1 ;;
    esac
    return 0
}

confirm() {
    printf "%s [y/N]: " "$1"
    read ans
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

cron_expire_installed() {
    crontab -l 2>/dev/null | grep -q "$CRON_PATTERN"
}

get_active_ssh_ports() {
    sockstat -46 -l -P tcp 2>/dev/null \
        | awk '$1 ~ /sshd/ { split($6, a, ":"); print a[length(a)] }' \
        | awk 'NF && $0 ~ /^[0-9]+$/' \
        | sort -n -u
}

ensure_base_files() {
    [ -f "$STATE_FILE" ] || : > "$STATE_FILE"
    [ -f "$BLACKLIST_FILE" ] || : > "$BLACKLIST_FILE"
    chmod 600 "$STATE_FILE" "$BLACKLIST_FILE"
}

normalize_state_file() {
    tmp="${STATE_FILE}.tmp.$$"
    awk '
        $1 ~ /^(tcp|udp)$/ && $2 ~ /^[0-9]+$/ && $2 >= 1 && $2 <= 65535 {
            print $1, $2
        }
    ' "$STATE_FILE" | sort -u > "$tmp"
    mv "$tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

init_env() {
    if ! grep -q '^pf_enable="YES"' /etc/rc.conf 2>/dev/null; then
        sysrc pf_enable="YES" >/dev/null
    fi

    ensure_base_files

    if [ ! -s "$STATE_FILE" ]; then
        init_zero
    else
        normalize_state_file
        apply_rules
    fi

    service pf onestatus >/dev/null 2>&1 || service pf start >/dev/null 2>&1 || {
        kldload pf >/dev/null 2>&1 || true
        service pf start >/dev/null 2>&1
    }
}

init_zero() {
    : > "$STATE_FILE"

    active_ports="$(get_active_ssh_ports)"
    if [ -z "$active_ports" ]; then
        active_ports="22"
    fi

    for port in $active_ports; do
        echo "tcp $port" >> "$STATE_FILE"
    done

    normalize_state_file
    apply_rules

    echo "已重置端口列表。当前保留 SSH TCP 端口：$active_ports"
}

write_rules() {
    cat > "$PF_CONF_TMP" <<EOF
set skip on lo0
set block-policy drop

table <blacklist> persist file "$BLACKLIST_FILE"

scrub in all fragment reassemble

block in quick from <blacklist> to any
block in all

pass out all keep state
pass in quick inet proto icmp all icmp-type echoreq keep state
EOF

    while read -r proto port; do
        [ -n "$proto" ] || continue
        [ -n "$port" ] || continue

        case "$proto" in
            tcp)
                echo "pass in quick inet proto tcp from any to any port $port flags S/SA keep state (max-src-conn 80, max-src-conn-rate 30/10, overload <blacklist> flush global)" >> "$PF_CONF_TMP"
                ;;
            udp)
                echo "pass in quick inet proto udp from any to any port $port keep state (max-src-states 80)" >> "$PF_CONF_TMP"
                ;;
        esac
    done < "$STATE_FILE"
}

apply_rules() {
    normalize_state_file
    write_rules

    if pfctl -nf "$PF_CONF_TMP"; then
        cp "$PF_CONF_TMP" "$PF_CONF"
        pfctl -f "$PF_CONF"
        echo "规则已通过语法检查并生效。"
    else
        echo "规则语法检查失败，未覆盖当前 $PF_CONF。"
        return 1
    fi
}

view_rules() {
    echo "--- 当前 PF 规则 ---"
    pfctl -sr
}

view_ports() {
    echo "--- 当前开放端口 ---"
    if [ -s "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "(空)"
    fi
}

open_port() {
    printf "请输入要开放的端口号 (1-65535): "
    read port

    if ! is_port "$port"; then
        echo "错误：端口号无效。"
        return 1
    fi

    echo "请选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP 和 UDP"
    printf "输入选项 [1-3]: "
    read proto_opt

    case "$proto_opt" in
        1) echo "tcp $port" >> "$STATE_FILE" ;;
        2) echo "udp $port" >> "$STATE_FILE" ;;
        3)
            echo "tcp $port" >> "$STATE_FILE"
            echo "udp $port" >> "$STATE_FILE"
            ;;
        *)
            echo "错误：无效选项。"
            return 1
            ;;
    esac

    apply_rules
}

delete_port() {
    printf "请输入要关闭的端口号: "
    read port

    if ! is_port "$port"; then
        echo "错误：端口号无效。"
        return 1
    fi

    tmp="${STATE_FILE}.tmp.$$"
    awk -v port="$port" '$2 != port { print }' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"

    apply_rules
}

view_blacklist() {
    echo "--- 当前黑名单 ---"
    pfctl -t blacklist -T show > "$BLACKLIST_FILE" 2>/dev/null || true

    if [ -s "$BLACKLIST_FILE" ]; then
        cat "$BLACKLIST_FILE"
    else
        echo "(空)"
    fi
}

ban_ip() {
    printf "请输入要封禁的 IP 或 CIDR: "
    read ip

    if ! is_ip_or_cidr "$ip"; then
        echo "错误：IP 或 CIDR 格式无效。"
        return 1
    fi

    pfctl -t blacklist -T add "$ip" >/dev/null
    pfctl -k "$ip" >/dev/null 2>&1 || true
    pfctl -t blacklist -T show > "$BLACKLIST_FILE"
    echo "已封禁并同步保存：$ip"
}

unban_ip() {
    printf "请输入要解封的 IP 或 CIDR: "
    read ip

    if ! is_ip_or_cidr "$ip"; then
        echo "错误：IP 或 CIDR 格式无效。"
        return 1
    fi

    pfctl -t blacklist -T delete "$ip" >/dev/null 2>&1 || true
    pfctl -t blacklist -T show > "$BLACKLIST_FILE"
    echo "已解封并同步保存：$ip"
}

expire_blacklist() {
    printf "请输入释放时间，单位秒，默认 86400: "
    read seconds
    [ -n "$seconds" ] || seconds="86400"

    case "$seconds" in
        ''|*[!0-9]*)
            echo "错误：时间必须是数字。"
            return 1
            ;;
    esac

    pfctl -t blacklist -T expire "$seconds" >/dev/null
    pfctl -t blacklist -T show > "$BLACKLIST_FILE"
    echo "已释放 $seconds 秒内未活动的黑名单地址，并同步保存。"
}

install_cron_expire() {
    tmp="/tmp/pf-cron.$$"
    crontab -l 2>/dev/null | grep -v "$CRON_PATTERN" > "$tmp"
    echo "$CRON_LINE" >> "$tmp"
    if crontab "$tmp"; then
        rm -f "$tmp"
        echo "已安装每日 03:00 自动释放 24 小时未活动黑名单的定时任务。"
        echo "当前写入的任务是："
        echo "$CRON_LINE"
        echo "你可以运行下面的命令复查："
        echo "crontab -l | grep 'pfctl -t blacklist'"
    else
        rm -f "$tmp"
        echo "安装 crontab 失败，请手动执行 crontab -e 检查。"
        return 1
    fi
}

remove_cron_expire() {
    if ! cron_expire_installed; then
        echo "每日自动释放黑名单任务当前未安装。"
        return 0
    fi

    if ! confirm "确认移除每日自动释放黑名单任务吗？"; then
        echo "已取消。"
        return 0
    fi

    tmp="/tmp/pf-cron.$$"
    crontab -l 2>/dev/null | grep -v "$CRON_PATTERN" > "$tmp"
    if crontab "$tmp"; then
        rm -f "$tmp"
        echo "已移除每日自动释放黑名单任务。"
        echo "你可以运行下面的命令复查，正常情况下不会再输出任务："
        echo "crontab -l | grep 'pfctl -t blacklist'"
    else
        rm -f "$tmp"
        echo "移除 crontab 任务失败，请手动执行 crontab -e 检查。"
        return 1
    fi
}

init_env

while :; do
    echo ""
    echo "=== PF 防火墙管理菜单 ==="
    echo "1. 查看当前生效规则"
    echo "2. 查看已开放端口"
    echo "3. 开放新端口"
    echo "4. 删除端口"
    echo "5. 重置端口列表，仅保留当前 SSH 端口"
    echo "6. 查看黑名单"
    echo "7. 手动封禁 IP"
    echo "8. 解封 IP"
    echo "9. 释放过期黑名单"
    if cron_expire_installed; then
        printf "10. 安装每日自动释放黑名单任务 %s[已安装]%s\n" "$RED" "$RESET"
    else
        echo "10. 安装每日自动释放黑名单任务"
    fi
    echo "11. 移除每日自动释放黑名单任务"
    echo "0. 退出"
    printf "请选择操作 [0-11]: "
    read choice

    case "$choice" in
        1) view_rules ;;
        2) view_ports ;;
        3) open_port ;;
        4) delete_port ;;
        5)
            if confirm "确认重置端口列表并仅保留当前 SSH 端口吗？"; then
                init_zero
            fi
            ;;
        6) view_blacklist ;;
        7) ban_ip ;;
        8) unban_ip ;;
        9) expire_blacklist ;;
        10) install_cron_expire ;;
        11) remove_cron_expire ;;
        0) exit 0 ;;
        *) echo "无效选项。" ;;
    esac
done
