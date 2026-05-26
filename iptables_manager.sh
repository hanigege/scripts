#!/bin/bash

# ==========================================================

# 脚本名称：高级防火墙管理工具 (Debian/Ubuntu 专属自适应版 V4.1)

# 核心升级：基于软件和内核模块的深度智能检测，消除冗余规则

# ==========================================================



gl_lv='\033[32m'

gl_huang='\033[33m'

gl_hong='\033[31m'

gl_bai='\033[0m'



root_use() {

    [ "$EUID" -ne 0 ] && echo -e "${gl_huang}提示: ${gl_bai}需 root 权限运行！" && exit 1

}



check_deps() {

    if ! dpkg -l | grep -qw iptables-persistent; then

        echo -e "${gl_huang}检测到未安装持久化组件，正在自动安装...${gl_bai}"

        apt-get update

        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables iptables-persistent netfilter-persistent

        echo -e "${gl_lv}依赖安装完成！${gl_bai}"

        sleep 1

    fi

}



root_use

check_deps



if command -v ip6tables >/dev/null 2>&1 && ip addr 2>/dev/null | grep -q "inet6 .* global"; then

    CMDS="iptables ip6tables"

    HAS_IPV6=true

else

    CMDS="iptables"

    HAS_IPV6=false

fi



save_rules() {

    echo -e "${gl_huang}正在持久化规则...${gl_bai}"

    mkdir -p /etc/iptables

    netfilter-persistent save >/dev/null 2>&1 || {

        iptables-save > /etc/iptables/rules.v4

        [ "$HAS_IPV6" == true ] && ip6tables-save > /etc/iptables/rules.v6

    }

    echo -e "${gl_lv}规则保存成功。${gl_bai}"

}



get_ssh_port() {

    local port=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n 1)

    [ -z "$port" ] && port=22

    echo "$port"

}



view_rules() {

    for cmd in $CMDS; do

        echo -e "\n${gl_lv}=== $cmd filter 表状态 ===${gl_bai}"

        $cmd -L INPUT -n -v --line-numbers

        echo -e "${gl_huang}--- FORWARD 转发状态 ---${gl_bai}"

        $cmd -L FORWARD -n -v --line-numbers

        echo -e "${gl_huang}--- MSS 钳制状态 (mangle 表) ---${gl_bai}"

        $cmd -t mangle -L FORWARD -n -v --line-numbers

    done

    read -p "按回车继续..."

}



allow_port_flexible() {

    read -e -p "请输入要放行的端口号: " port

    [ -z "$port" ] && return

    echo -e "1. TCP  2. UDP  3. 同时放行"

    read -p "选择 (1-3): " p_choice

    for cmd in $CMDS; do

        case $p_choice in

            1) $cmd -I INPUT 4 -p tcp --dport "$port" -j ACCEPT ;;

            2) $cmd -I INPUT 4 -p udp --dport "$port" -j ACCEPT ;;

            3) 

               $cmd -I INPUT 4 -p tcp --dport "$port" -j ACCEPT

               $cmd -I INPUT 4 -p udp --dport "$port" -j ACCEPT 

               ;;

        esac

    done

    save_rules

}



block_ip() {

    read -e -p "输入要屏蔽的 IP: " tip

    [ -z "$tip" ] && return

    if [[ "$tip" == *":"* ]]; then

        if [ "$HAS_IPV6" == true ]; then

            ip6tables -I INPUT 1 -s "$tip" -j DROP

        else

            echo -e "${gl_hong}系统未开启 IPv6，无法添加该规则。${gl_bai}"

            sleep 2

            return

        fi

    else

        iptables -I INPUT 1 -s "$tip" -j DROP

    fi

    save_rules

}



delete_rule() {

    echo -e "1. IPv4 (iptables)"

    [ "$HAS_IPV6" == true ] && echo "2. IPv6 (ip6tables)"

    read -p "选择协议: " p_choice

    local cmd="iptables"

    if [ "$p_choice" == "2" ] && [ "$HAS_IPV6" == true ]; then

        cmd="ip6tables"

    elif [ "$p_choice" == "2" ]; then

        echo -e "${gl_hong}系统不支持 IPv6。${gl_bai}"

        sleep 2

        return

    fi

    $cmd -L INPUT -n --line-numbers

    read -p "输入要删除的 filter/INPUT 规则编号: " num

    [ -n "$num" ] && $cmd -D INPUT "$num" && save_rules

}



close_all_but_ssh() {

    local ssh_p=$(get_ssh_port)

    echo -e "${gl_huang}开始执行自适应深度加固...${gl_bai}"



    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    [ "$HAS_IPV6" == true ] && sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true



    for cmd in $CMDS; do

        $cmd -P INPUT ACCEPT

        $cmd -P FORWARD ACCEPT



        $cmd -L INPUT --line-numbers | grep -vE "ts-|DOCKER" | awk '/^[0-9]/ {print $1}' | sort -nr | xargs -r -I{} $cmd -D INPUT {} 2>/dev/null

        $cmd -F FORWARD



        $cmd -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

        $cmd -A INPUT -i lo -j ACCEPT

        

        if $cmd -L ts-input >/dev/null 2>&1; then

            $cmd -D INPUT -j ts-input 2>/dev/null || true

            $cmd -I INPUT 3 -j ts-input

        fi

        

        $cmd -A INPUT -p tcp --dport "$ssh_p" -j ACCEPT



        # 规范 ICMP

        if [ "$cmd" == "iptables" ]; then

            $cmd -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 5 -j ACCEPT

            $cmd -A INPUT -p icmp --icmp-type 3 -j ACCEPT

            $cmd -A INPUT -p icmp --icmp-type 11 -j ACCEPT

            $cmd -A INPUT -p icmp -j DROP

        else

            for type in 2 133 134 135 136 137; do

                $cmd -A INPUT -p ipv6-icmp --icmpv6-type $type -j ACCEPT

            done

            $cmd -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 1/s --limit-burst 5 -j ACCEPT

            $cmd -A INPUT -p ipv6-icmp -j DROP

        fi



        if $cmd -L ts-forward >/dev/null 2>&1; then

            $cmd -D FORWARD -j ts-forward 2>/dev/null || true

            $cmd -I FORWARD 1 -j ts-forward

        fi

        

        # 核心优化：智能环境检测 (检测软件安装状态而非网卡状态)

        if command -v docker >/dev/null 2>&1 || command -v dockerd >/dev/null 2>&1; then

            $cmd -A FORWARD -i docker+ -j ACCEPT

            $cmd -A FORWARD -o docker+ -j ACCEPT

        fi

        

        if command -v tailscaled >/dev/null 2>&1; then

            $cmd -A FORWARD -i tailscale+ -j ACCEPT

            $cmd -A FORWARD -o tailscale+ -j ACCEPT

        fi

        

        if command -v wg >/dev/null 2>&1 || lsmod | grep -q wireguard; then

            $cmd -A FORWARD -i wg+ -j ACCEPT

            $cmd -A FORWARD -o wg+ -j ACCEPT

        fi

        

        if command -v openvpn >/dev/null 2>&1 || [ -c /dev/net/tun ]; then

            $cmd -A FORWARD -i tun+ -j ACCEPT

            $cmd -A FORWARD -o tun+ -j ACCEPT

        fi



        if command -v pppd >/dev/null 2>&1; then

            $cmd -A FORWARD -i ppp+ -j ACCEPT

            $cmd -A FORWARD -o ppp+ -j ACCEPT

        fi

        

        $cmd -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT



        $cmd -P INPUT DROP

        $cmd -P FORWARD DROP



        # 双栈 MSS 钳制

        $cmd -t mangle -F FORWARD

        $cmd -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true

    done



    save_rules

    echo -e "${gl_lv}深度加固及 MSS 网络优化完成！冗余规则已清理。${gl_bai}"

    sleep 2

}



open_all_ports() {

    for cmd in iptables ip6tables; do

        command -v $cmd >/dev/null 2>&1 || continue

        $cmd -P INPUT ACCEPT

        $cmd -P FORWARD ACCEPT

        $cmd -P OUTPUT ACCEPT

        $cmd -F

        $cmd -X 2>/dev/null || true

        $cmd -t mangle -F FORWARD 2>/dev/null || true

    done

    save_rules

    echo -e "${gl_lv}防火墙已重置全开模式，MSS 钳制已清除。${gl_bai}"

    sleep 2

}



iptables_panel() {

    while true; do

        clear

        echo -e "${gl_lv}===========================================${gl_bai}"

        echo -e "    高级防火墙管理 (Debian/Ubuntu 自适应版 V4.1)    "

        echo -e "    当前 IPv6 状态: \c"

        if [ "$HAS_IPV6" == true ]; then echo -e "${gl_lv}已启用${gl_bai}"; else echo -e "${gl_huang}未启用${gl_bai}"; fi

        echo -e "${gl_lv}===========================================${gl_bai}"

        echo " 1. 查看规则 (含 MSS 钳制状态)"

        echo " 2. 放行端口"

        echo " 3. 屏蔽地址"

        echo " 4. 删除规则"

        echo -e " 5. ${gl_hong}执行深度加固 (智能检测环境，拒绝冗余规则)${gl_bai}"

        echo -e " 6. ${gl_huang}紧急恢复全开 (重置所有策略)${gl_bai}"

        echo " 7. 手动持久化保存"

        echo " 0. 退出脚本"

        echo "-------------------------------------------"

        read -e -p "请选择: " choice

        case $choice in

            1) view_rules ;;

            2) allow_port_flexible ;;

            3) block_ip ;;

            4) delete_rule ;;

            5) close_all_but_ssh ;;

            6) open_all_ports ;;

            7) save_rules; sleep 2 ;;

            0) exit 0 ;;

            *) echo "无效选择"; sleep 1 ;;

        esac

    done

}



iptables_panel
