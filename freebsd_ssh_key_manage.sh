#!/bin/sh

# 颜色定义
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_hong='\033[31m'
gl_bai='\033[0m'

# 检查 root 权限
root_use() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "该功能需要 root 用户才能运行！"
        exit 1
    fi
}

# 重启 SSH 服务
restart_ssh() {
    service sshd restart
}

# 核心修改函数：暴力去重
# 逻辑：先删除整个文件中所有包含该关键字的行，然后在末尾追加唯一正确的配置
modify_sshd() {
    _param=$1
    _value=$2
    _conf="/etc/ssh/sshd_config"
    
    # 暴力删除所有匹配项（包含空格、Tab、注释），确保无残留
    sed -i '' "/$_param/d" "$_conf"
    
    # 在文件末尾追加唯一的正确配置
    echo "$_param $_value" >> "$_conf"
}

# 开启密钥登录模式 (关闭密码登录)
sshkey_on() {
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
    
    modify_sshd "UsePAM" "no"
    modify_sshd "PermitRootLogin" "prohibit-password"
    modify_sshd "PasswordAuthentication" "no"
    modify_sshd "PubkeyAuthentication" "yes"
    modify_sshd "ChallengeResponseAuthentication" "no"
    modify_sshd "KbdInteractiveAuthentication" "no"
    
    [ -d "/etc/ssh/sshd_config.d" ] && rm -rf /etc/ssh/sshd_config.d/* 2>/dev/null
    
    restart_ssh
    printf "${gl_lv}已切换至：仅限密钥登录 (密码功能已关闭)${gl_bai}\n"
}

# 恢复密码登录模式 (暴力清理并还原，同时彻底关闭证书登录)
ssh_password_on() {
    # 恢复密码模式必须开启 UsePAM
    modify_sshd "UsePAM" "yes"
    modify_sshd "PermitRootLogin" "yes"
    modify_sshd "PasswordAuthentication" "yes"
    # 核心修改：关闭证书登录功能
    modify_sshd "PubkeyAuthentication" "no"
    modify_sshd "ChallengeResponseAuthentication" "yes"
    modify_sshd "KbdInteractiveAuthentication" "yes"
    
    restart_ssh
    printf "${gl_huang}已切换至：仅限密码登录 (证书登录已完全禁用)${gl_bai}\n"
}

# 主菜单
sshkey_panel() {
    root_use
    while true; do
        clear
        # 获取当前状态 (取最后一行生效的配置)
        _p_stat=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config | tail -n 1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        _k_stat=$(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config | tail -n 1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        
        # 逻辑判断当前模式
        if [ "$_p_stat" = "no" ]; then
            _show_stat="${gl_hong}密钥模式 (禁密码)${gl_bai}"
        elif [ "$_k_stat" = "no" ]; then
            _show_stat="${gl_lv}密码模式 (禁证书)${gl_bai}"
        else
            _show_stat="${gl_huang}混合模式${gl_bai}"
        fi

        _key_count=$(grep -c "^ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo 0)

        printf "${gl_lv}FreeBSD 15 SSH 管理助手${gl_bai} [${_show_stat}]\n"
        echo "------------------------------------------------"
        echo "1. 生成新密钥对 (ED25519)"
        echo "2. 手动输入已有公钥"
        echo "3. 从 GitHub 导入公钥"
        echo "4. 查看已存公钥内容 (authorized_keys)"
        echo "5. 编辑公钥文件 (vi)"
        echo "6. 恢复密码登录 (仅限密码，禁用证书)"
        echo "0. 退出"
        echo "------------------------------------------------"
        echo "当前已存公钥数量: ${_key_count}"
        printf "${gl_huang}请选择: ${gl_bai}"
        read choice
        
        case "$choice" in
            1) 
                mkdir -p /root/.ssh && chmod 700 /root/.ssh
                ssh-keygen -t ed25519 -C "admin@vps" -f "/root/.ssh/sshkey" -N ""
                cat "/root/.ssh/sshkey.pub" >> /root/.ssh/authorized_keys
                printf "\n私钥已生成，务必复制保存:\n"
                cat "/root/.ssh/sshkey"
                sshkey_on
                printf "\n按回车继续..."; read _tmp ;;
            2) 
                printf "输入公钥内容: "; read _pk
                if [ -n "$_pk" ]; then
                    mkdir -p /root/.ssh && chmod 700 /root/.ssh
                    echo "$_pk" >> /root/.ssh/authorized_keys
                    chmod 600 /root/.ssh/authorized_keys
                    sshkey_on
                fi
                printf "按回车继续..."; read _tmp ;;
            3)
                printf "GitHub 用户名: "; read _un
                if [ -n "$_un" ]; then
                    mkdir -p /root/.ssh && chmod 700 /root/.ssh
                    fetch -o - "https://github.com/${_un}.keys" >> /root/.ssh/authorized_keys
                    chmod 600 /root/.ssh/authorized_keys
                    sshkey_on
                fi
                printf "按回车继续..."; read _tmp ;;
            4)
                echo "--- 当前 authorized_keys 内容 ---"
                [ -f /root/.ssh/authorized_keys ] && cat /root/.ssh/authorized_keys || echo "文件不存在"
                echo "--------------------------------"
                printf "按回车继续..."; read _tmp ;;
            5) vi /root/.ssh/authorized_keys ;;
            6)
                ssh_password_on
                printf "按回车继续..."; read _tmp ;;
            0) exit 0 ;;
        esac
    done
}

sshkey_panel
