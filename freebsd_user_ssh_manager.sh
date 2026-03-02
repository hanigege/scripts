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
modify_sshd() {
    _param=$1
    _value=$2
    _conf="/etc/ssh/sshd_config"
    
    sed -i '' "/$_param/d" "$_conf"
    echo "$_param $_value" >> "$_conf"
}

# 开启密钥登录模式 (仅限普通用户，彻底关闭密码和 root 登录)
sshkey_on() {
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
    
    modify_sshd "UsePAM" "no"
    modify_sshd "PermitRootLogin" "no"  # 核心：禁止 root 登录
    modify_sshd "PasswordAuthentication" "no"
    modify_sshd "PubkeyAuthentication" "yes"
    modify_sshd "ChallengeResponseAuthentication" "no"
    modify_sshd "KbdInteractiveAuthentication" "no"
    
    [ -d "/etc/ssh/sshd_config.d" ] && rm -rf /etc/ssh/sshd_config.d/* 2>/dev/null
    
    restart_ssh
    printf "${gl_lv}已切换至：仅限普通用户密钥登录 (Root 及密码功能已关闭)${gl_bai}\n"
}

# 恢复密码登录模式 (仅限普通用户密码，禁用证书和 root)
ssh_password_on() {
    modify_sshd "UsePAM" "yes"
    modify_sshd "PermitRootLogin" "no"  # 核心：密码模式下也禁止 root
    modify_sshd "PasswordAuthentication" "yes"
    modify_sshd "PubkeyAuthentication" "no"
    modify_sshd "ChallengeResponseAuthentication" "yes"
    modify_sshd "KbdInteractiveAuthentication" "yes"
    
    restart_ssh
    printf "${gl_huang}已切换至：仅限普通用户密码登录 (Root 及证书登录已禁用)${gl_bai}\n"
}

# 初始化获取目标普通用户
init_target_user() {
    while true; do
        printf "${gl_huang}请输入要配置证书登录的普通用户名 (不可用 root): ${gl_bai}"
        read target_user
        if id "$target_user" >/dev/null 2>&1; then
            if [ "$target_user" = "root" ]; then
                echo "错误：目标用户不能是 root！请重新输入。"
                continue
            fi
            # 获取该用户的家目录和所属主组
            user_home=$(pw usershow "$target_user" | cut -d: -f9)
            user_group=$(id -gn "$target_user")
            break
        else
            echo "错误：系统不存在用户 $target_user，请先使用 adduser 创建！"
        fi
    done
}

# 修复家目录 .ssh 权限的通用函数
fix_ssh_perms() {
    chown -R "$target_user:$user_group" "$user_home/.ssh"
    chmod 700 "$user_home/.ssh"
    [ -f "$user_home/.ssh/authorized_keys" ] && chmod 600 "$user_home/.ssh/authorized_keys"
}

# 主菜单
sshkey_panel() {
    root_use
    init_target_user

    while true; do
        clear
        _p_stat=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config | tail -n 1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        _k_stat=$(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config | tail -n 1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        _r_stat=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config | tail -n 1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        
        if [ "$_p_stat" = "no" ] && [ "$_r_stat" = "no" ]; then
            _show_stat="${gl_hong}纯净密钥模式 (禁密码, 禁Root)${gl_bai}"
        elif [ "$_k_stat" = "no" ] && [ "$_r_stat" = "no" ]; then
            _show_stat="${gl_lv}普通密码模式 (禁证书, 禁Root)${gl_bai}"
        else
            _show_stat="${gl_huang}未锁定状态 (Root可能开启)${gl_bai}"
        fi

        _key_count=$(grep -c "^ssh-" "$user_home/.ssh/authorized_keys" 2>/dev/null || echo 0)

        printf "${gl_lv}FreeBSD 15 SSH 管理助手${gl_bai} [${_show_stat}]\n"
        echo "操作目标用户: ${gl_huang}${target_user}${gl_bai} (家目录: ${user_home})"
        echo "------------------------------------------------"
        echo "1. 为 ${target_user} 生成新密钥对 (ED25519)"
        echo "2. 为 ${target_user} 手动输入已有公钥"
        echo "3. 为 ${target_user} 从 GitHub 导入公钥"
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
                mkdir -p "$user_home/.ssh"
                ssh-keygen -t ed25519 -C "${target_user}@vps" -f "$user_home/.ssh/sshkey" -N ""
                cat "$user_home/.ssh/sshkey.pub" >> "$user_home/.ssh/authorized_keys"
                fix_ssh_perms
                printf "\n私钥已生成，务必复制保存:\n"
                cat "$user_home/.ssh/sshkey"
                sshkey_on
                printf "\n按回车继续..."; read _tmp ;;
            2) 
                printf "输入公钥内容: "; read _pk
                if [ -n "$_pk" ]; then
                    mkdir -p "$user_home/.ssh"
                    echo "$_pk" >> "$user_home/.ssh/authorized_keys"
                    fix_ssh_perms
                    sshkey_on
                fi
                printf "按回车继续..."; read _tmp ;;
            3)
                printf "GitHub 用户名: "; read _un
                if [ -n "$_un" ]; then
                    mkdir -p "$user_home/.ssh"
                    fetch -o - "https://github.com/${_un}.keys" >> "$user_home/.ssh/authorized_keys"
                    fix_ssh_perms
                    sshkey_on
                fi
                printf "按回车继续..."; read _tmp ;;
            4)
                echo "--- 当前 authorized_keys 内容 ---"
                [ -f "$user_home/.ssh/authorized_keys" ] && cat "$user_home/.ssh/authorized_keys" || echo "文件不存在"
                echo "--------------------------------"
                printf "按回车继续..."; read _tmp ;;
            5) vi "$user_home/.ssh/authorized_keys" ;;
            6)
                ssh_password_on
                printf "按回车继续..."; read _tmp ;;
            0) exit 0 ;;
        esac
    done
}

sshkey_panel