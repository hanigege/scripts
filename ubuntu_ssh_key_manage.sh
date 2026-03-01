#!/bin/bash

# 颜色定义
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_hong='\033[31m'
gl_bai='\033[0m'
gl_hui='\e[37m'

# 检查 root 权限
root_use() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${gl_huang}提示: ${gl_bai}该功能需要 root 用户才能运行！"
        exit 1
    fi
}

# 获取 IP 地址 (仅用于生成提示信息)
ip_address() {
    ipv4_address=$(curl -s https://ipinfo.io/ip)
}

# 重启 SSH 服务
restart_ssh() {
    if command -v systemctl &>/dev/null; then
        systemctl restart sshd || systemctl restart ssh
    else
        service sshd restart || service ssh restart
    fi
}

# 开启密钥登录模式并关闭密码登录
sshkey_on() {
    local sshd_config="/etc/ssh/sshd_config"
    sed -i -e 's/^\s*#\?\s*PermitRootLogin .*/PermitRootLogin prohibit-password/' \
           -e 's/^\s*#\?\s*PasswordAuthentication .*/PasswordAuthentication no/' \
           -e 's/^\s*#\?\s*PubkeyAuthentication .*/PubkeyAuthentication yes/' \
           -e 's/^\s*#\?\s*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' "$sshd_config"
    rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*
    restart_ssh
    echo -e "${gl_lv}用户密钥登录模式已开启，已关闭密码登录模式，重连将会生效${gl_bai}"
}

# 生成新密钥对
add_sshkey() {
    chmod 700 "${HOME}"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys"

    # 使用 ED25519 算法生成密钥
    ssh-keygen -t ed25519 -C "admin@vps" -f "${HOME}/.ssh/sshkey" -N ""

    cat "${HOME}/.ssh/sshkey.pub" >> "${HOME}/.ssh/authorized_keys"
    chmod 600 "${HOME}/.ssh/authorized_keys"

    ip_address
    echo -e "私钥信息已生成，务必复制保存，可保存成 ${gl_huang}${ipv4_address}_ssh.key${gl_bai} 文件"
    echo "--------------------------------"
    cat "${HOME}/.ssh/sshkey"
    echo "--------------------------------"
    sshkey_on
}

# 导入已有公钥
import_sshkey() {
    read -e -p "请输入您的SSH公钥内容: " public_key
    if [[ ! "$public_key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        echo -e "${gl_hong}错误：无效的 SSH 公钥格式。${gl_bai}"
        return 1
    fi
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    echo "$public_key" >> "${HOME}/.ssh/authorized_keys"
    chmod 600 "${HOME}/.ssh/authorized_keys"
    sshkey_on
}

# 主菜单
sshkey_panel() {
    root_use
    while true; do
        clear
        local REAL_STATUS=$(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        IS_KEY_ENABLED="${gl_hui}未启用${gl_bai}"
        [[ "$REAL_STATUS" == "yes" ]] && IS_KEY_ENABLED="${gl_lv}已启用${gl_bai}"
        
        echo -e "用户密钥登录模式管理 ${IS_KEY_ENABLED}"
        echo "------------------------------------------------"
        echo "1. 生成新密钥对 (ED25519)"
        echo "2. 手动输入已有公钥"
        echo "3. 从 GitHub 导入公钥"
        echo "4. 编辑公钥文件 (authorized_keys)"
        echo "5. 查看本机密钥信息"
        echo "0. 退出"
        echo "------------------------------------------------"
        read -e -p "请输入你的选择: " choice
        case $choice in
            1) add_sshkey ;;
            2) import_sshkey ;;
            3) 
                read -e -p "请输入 GitHub 用户名: " username
                curl -fsSL "https://github.com/${username}.keys" >> "${HOME}/.ssh/authorized_keys"
                sshkey_on ;;
            4) nano "${HOME}/.ssh/authorized_keys" ;;
            5)
                echo "--- 公钥 (authorized_keys) ---"
                cat "${HOME}/.ssh/authorized_keys"
                echo "--- 本机生成的私钥 (如有) ---"
                [ -f "${HOME}/.ssh/sshkey" ] && cat "${HOME}/.ssh/sshkey" || echo "未找到私钥文件"
                read -p "按回车继续..." ;;
            0) exit 0 ;;
            *) echo "无效选择"; sleep 1 ;;
        esac
    done
}

sshkey_panel

