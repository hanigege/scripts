#!/bin/ash
# Alpine Linux iptables firewall manager.
# Interactive IPv4/IPv6 port, blocklist, persistence, and hardening helper.

set -u

GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"

HAS_IPV6=false
CMDS="iptables"

if [ "$(id -u)" != "0" ]; then
    printf "%s错误：必须使用 root 权限运行。%s\n" "$RED" "$RESET"
    exit 1
fi

pause() {
    printf "按回车继续..."
    read dummy
}

confirm() {
    printf "%s [y/N]: " "$1"
    read ans
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

is_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

has_global_ipv6() {
    ip -6 addr 2>/dev/null | grep -q 'scope global'
}

init_env() {
    if ! command -v iptables >/dev/null 2>&1 || ! command -v iptables-save >/dev/null 2>&1; then
        printf "%s正在安装 iptables 相关组件...%s\n" "$YELLOW" "$RESET"
        apk add --no-cache iptables >/dev/null
    fi

    if command -v ip6tables >/dev/null 2>&1 && has_global_ipv6; then
        HAS_IPV6=true
        CMDS="iptables ip6tables"
    fi

    rc-update add iptables default >/dev/null 2>&1 || true
    if [ "$HAS_IPV6" = true ]; then
        rc-update add ip6tables default >/dev/null 2>&1 || true
    fi
}

save_rules() {
    printf "%s正在持久化规则...%s\n" "$YELLOW" "$RESET"
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules-save
    if [ "$HAS_IPV6" = true ]; then
        ip6tables-save > /etc/iptables/rules6-save
    fi
    rc-service iptables save >/dev/null 2>&1 || true
    if [ "$HAS_IPV6" = true ]; then
        rc-service ip6tables save >/dev/null 2>&1 || true
    fi
    printf "%s规则已保存。%s\n" "$GREEN" "$RESET"
}

get_ssh_ports() {
    if command -v ss >/dev/null 2>&1; then
        ss -H -ltnp 2>/dev/null \
            | awk '/sshd/ { split($4, a, ":"); print a[length(a)] }' \
            | awk 'NF && $0 ~ /^[0-9]+$/'
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null \
            | awk '/sshd/ { split($4, a, ":"); print a[length(a)] }' \
            | awk 'NF && $0 ~ /^[0-9]+$/'
    fi
}

get_ssh_ports_fallback() {
    ports=""
    if [ -f /etc/ssh/sshd_config ]; then
        ports="$(awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ { print $2 }' /etc/ssh/sshd_config | sort -n -u)"
    fi
    if [ -z "$ports" ]; then
        ports="$(get_ssh_ports | sort -n -u)"
    fi
    [ -n "$ports" ] || ports="22"
    echo "$ports"
}

view_rules() {
    for cmd in $CMDS; do
        printf "\n%s=== %s INPUT 规则 ===%s\n" "$GREEN" "$cmd" "$RESET"
        $cmd -L INPUT -n -v --line-numbers
        printf "%s--- FORWARD 规则 ---%s\n" "$YELLOW" "$RESET"
        $cmd -L FORWARD -n -v --line-numbers
        printf "%s--- mangle/FORWARD MSS 规则 ---%s\n" "$YELLOW" "$RESET"
        $cmd -t mangle -L FORWARD -n -v --line-numbers
    done
    pause
}

allow_port() {
    printf "请输入要放行的端口号 (1-65535): "
    read port
    if ! is_port "$port"; then
        printf "%s错误：端口号无效。%s\n" "$RED" "$RESET"
        return 1
    fi

    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP 和 UDP"
    printf "请选择协议 [1-3]: "
    read proto_choice

    case "$proto_choice" in
        1) protos="tcp" ;;
        2) protos="udp" ;;
        3) protos="tcp udp" ;;
        *)
            printf "%s错误：无效选项。%s\n" "$RED" "$RESET"
            return 1
            ;;
    esac

    for cmd in $CMDS; do
        for proto in $protos; do
            $cmd -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
                $cmd -I INPUT 4 -p "$proto" --dport "$port" -j ACCEPT
        done
    done
    save_rules
}

block_ip() {
    printf "请输入要屏蔽的 IP 或 CIDR: "
    read target
    [ -n "$target" ] || return 1

    case "$target" in
        *:*)
            if [ "$HAS_IPV6" != true ]; then
                printf "%s系统未检测到全局 IPv6，未添加 IPv6 规则。%s\n" "$RED" "$RESET"
                return 1
            fi
            ip6tables -C INPUT -s "$target" -j DROP 2>/dev/null || ip6tables -I INPUT 1 -s "$target" -j DROP
            ;;
        *)
            iptables -C INPUT -s "$target" -j DROP 2>/dev/null || iptables -I INPUT 1 -s "$target" -j DROP
            ;;
    esac
    save_rules
}

delete_rule() {
    echo "1. IPv4 (iptables)"
    [ "$HAS_IPV6" = true ] && echo "2. IPv6 (ip6tables)"
    printf "选择协议: "
    read choice

    cmd="iptables"
    if [ "$choice" = "2" ]; then
        if [ "$HAS_IPV6" = true ]; then
            cmd="ip6tables"
        else
            printf "%s系统未启用 IPv6。%s\n" "$RED" "$RESET"
            return 1
        fi
    fi

    $cmd -L INPUT -n --line-numbers
    printf "输入要删除的 INPUT 规则编号: "
    read num
    case "$num" in
        ''|*[!0-9]*)
            printf "%s错误：编号无效。%s\n" "$RED" "$RESET"
            return 1
            ;;
    esac

    $cmd -D INPUT "$num" && save_rules
}

allow_known_forwarding() {
    cmd="$1"

    if $cmd -L ts-forward >/dev/null 2>&1; then
        $cmd -D FORWARD -j ts-forward 2>/dev/null || true
        $cmd -I FORWARD 1 -j ts-forward
    fi

    if command -v docker >/dev/null 2>&1 || command -v dockerd >/dev/null 2>&1; then
        $cmd -A FORWARD -i docker+ -j ACCEPT 2>/dev/null || true
        $cmd -A FORWARD -o docker+ -j ACCEPT 2>/dev/null || true
    fi

    if command -v tailscaled >/dev/null 2>&1; then
        $cmd -A FORWARD -i tailscale+ -j ACCEPT 2>/dev/null || true
        $cmd -A FORWARD -o tailscale+ -j ACCEPT 2>/dev/null || true
    fi

    if command -v wg >/dev/null 2>&1 || lsmod 2>/dev/null | grep -q wireguard; then
        $cmd -A FORWARD -i wg+ -j ACCEPT 2>/dev/null || true
        $cmd -A FORWARD -o wg+ -j ACCEPT 2>/dev/null || true
    fi

    if command -v openvpn >/dev/null 2>&1 || [ -c /dev/net/tun ]; then
        $cmd -A FORWARD -i tun+ -j ACCEPT 2>/dev/null || true
        $cmd -A FORWARD -o tun+ -j ACCEPT 2>/dev/null || true
    fi

    if command -v pppd >/dev/null 2>&1; then
        $cmd -A FORWARD -i ppp+ -j ACCEPT 2>/dev/null || true
        $cmd -A FORWARD -o ppp+ -j ACCEPT 2>/dev/null || true
    fi
}

harden_firewall() {
    ssh_ports="$(get_ssh_ports_fallback)"
    printf "%s即将执行防火墙加固，仅保留当前 SSH TCP 端口：%s%s\n" "$YELLOW" "$ssh_ports" "$RESET"
    if ! confirm "确认继续吗？"; then
        echo "已取消。"
        return 0
    fi

    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    if [ "$HAS_IPV6" = true ]; then
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true
    fi

    for cmd in $CMDS; do
        $cmd -P INPUT ACCEPT
        $cmd -P FORWARD ACCEPT
        $cmd -F INPUT
        $cmd -F FORWARD
        $cmd -t mangle -F FORWARD 2>/dev/null || true

        $cmd -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
        $cmd -A INPUT -i lo -j ACCEPT

        if $cmd -L ts-input >/dev/null 2>&1; then
            $cmd -D INPUT -j ts-input 2>/dev/null || true
            $cmd -A INPUT -j ts-input
        fi

        for port in $ssh_ports; do
            $cmd -A INPUT -p tcp --dport "$port" -j ACCEPT
        done

        if [ "$cmd" = "iptables" ]; then
            $cmd -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 5 -j ACCEPT
            $cmd -A INPUT -p icmp --icmp-type 3 -j ACCEPT
            $cmd -A INPUT -p icmp --icmp-type 11 -j ACCEPT
            $cmd -A INPUT -p icmp -j DROP
        else
            for type in 2 133 134 135 136 137; do
                $cmd -A INPUT -p ipv6-icmp --icmpv6-type "$type" -j ACCEPT
            done
            $cmd -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 1/s --limit-burst 5 -j ACCEPT
            $cmd -A INPUT -p ipv6-icmp -j DROP
        fi

        allow_known_forwarding "$cmd"
        $cmd -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
        $cmd -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true

        $cmd -P INPUT DROP
        $cmd -P FORWARD DROP
    done

    save_rules
    printf "%s防火墙加固完成。%s\n" "$GREEN" "$RESET"
    sleep 2
}

open_all_ports() {
    if ! confirm "确认重置为全开放模式吗？"; then
        echo "已取消。"
        return 0
    fi

    for cmd in iptables ip6tables; do
        command -v "$cmd" >/dev/null 2>&1 || continue
        $cmd -P INPUT ACCEPT
        $cmd -P FORWARD ACCEPT
        $cmd -P OUTPUT ACCEPT
        $cmd -F
        $cmd -X 2>/dev/null || true
        $cmd -t mangle -F FORWARD 2>/dev/null || true
    done

    save_rules
    printf "%s防火墙已重置为全开放模式。%s\n" "$GREEN" "$RESET"
    sleep 2
}

init_env

while :; do
    clear
    echo "==========================================="
    echo " Alpine iptables 防火墙管理"
    if [ "$HAS_IPV6" = true ]; then
        printf " IPv6 状态：%s已启用%s\n" "$GREEN" "$RESET"
    else
        printf " IPv6 状态：%s未启用%s\n" "$YELLOW" "$RESET"
    fi
    echo "==========================================="
    echo "1. 查看规则"
    echo "2. 放行端口"
    echo "3. 屏蔽 IP/CIDR"
    echo "4. 删除 INPUT 规则"
    echo "5. 执行防火墙加固，仅保留 SSH 和常见转发环境"
    echo "6. 紧急恢复全开放"
    echo "7. 手动持久化保存"
    echo "0. 退出"
    echo "-------------------------------------------"
    printf "请选择: "
    read choice

    case "$choice" in
        1) view_rules ;;
        2) allow_port ;;
        3) block_ip ;;
        4) delete_rule ;;
        5) harden_firewall ;;
        6) open_all_ports ;;
        7) save_rules; sleep 2 ;;
        0) exit 0 ;;
        *) echo "无效选项。"; sleep 1 ;;
    esac
done
