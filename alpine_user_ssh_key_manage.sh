#!/bin/ash

# 动态获取当前用户家目录和用户名
USER_NAME=$(whoami)
USER_HOME=$(eval echo ~$USER_NAME)

# 颜色定义
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_hong='\033[31m'
gl_bai='\033[0m'
gl_hui='\e[37m'

# 初始化检查
init_check() {
    # 1. 如果不是 root 且没安装 sudo，尝试安装 sudo
    if [ "$USER_NAME" != "root" ] && ! command -v sudo >/dev/null 2>&1; then
        echo -e "${gl_huang}检测到缺失 sudo，正在尝试安装...${gl_bai}"
        # 此时可能无法安装，除非 apk 权限已放开或当前环境允许
        su -c "apk add --no-cache sudo" || { echo -e "${gl_hong}错误: 无法安装 sudo，请先以 root 权限运行 'apk add sudo'${gl_bai}"; exit 1; }
    fi

    # 2. 自动安装其他必要依赖
    if ! command -v curl >/dev/null 2>&1 || ! command -v nano >/dev/null 2>&1 || ! command -v ssh-keygen >/dev/null 2>&1; then
        echo -e "${gl_huang}检查并安装必要依赖...${gl_bai}"
        if [ "$USER_NAME" = "root" ]; then
            apk add --no-cache curl nano openssh-keygen openssh-client >/dev/null 2>&1
        else
            sudo apk add --no-cache curl nano openssh-keygen openssh-client >/dev/null 2>&1
        fi
    fi
}

# 重启 SSH 服务
restart_ssh() {
    [ "$USER_NAME" = "root" ] && rc-service sshd restart >/dev/null 2>&1 || sudo rc-service sshd restart >/dev/null 2>&1
}

# 核心功能：修改 SSH 配置并查缺补漏
sshkey_on() {
    local conf="/etc/ssh/sshd_config"
    local run_cmd=""
    [ "$USER_NAME" != "root" ] && run_cmd="sudo"

    # 1. 备份原始配置
    [ ! -f "${conf}.bak" ] && $run_cmd cp "$conf" "${conf}.bak"

    # 定义目标配置项 (核心安全项)
    configs="
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM no
"

    # 2. 利用 sed 修改已有项 (包含被注释的行)
    echo "$configs" | while read -r line; do
        [ -z "$line" ] && continue
        key=$(echo "$line" | awk '{print $1}')
        val=$(echo "$line" | awk '{print $2}')
        $run_cmd sed -i "s|^\s*#\?\s*$key\s.*|$key $val|g" "$conf"
    done

    # 3. 查缺补漏：如果 key 在文件中完全不存在，则追加到末尾
    echo "$configs" | while read -r line; do
        [ -z "$line" ] && continue
        key=$(echo "$line" | awk '{print $1}')
        if ! grep -qi "^\s*$key\s" "$conf"; then
            echo "$line" | $run_cmd tee -a "$conf" >/dev/null
        fi
    done

    # 4. 彻底禁用子配置干扰
    $run_cmd sed -i 's/^Include /#Include /g' "$conf"
    [ -d /etc/ssh/sshd_config.d ] && $run_cmd rm -f /etc/ssh/sshd_config.d/*

    restart_ssh
    echo -e "${gl_lv}SSH 安全配置已强制刷新，密钥模式已生效${gl_bai}"
    sleep 2
}

# 确保当前用户 .ssh 目录存在
ensure_ssh_dir() {
    [ ! -d "$USER_HOME/.ssh" ] && mkdir -p "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"
    [ ! -f "$USER_HOME/.ssh/authorized_keys" ] && touch "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
}

# 功能：生成密钥对
add_sshkey() {
    ensure_ssh_dir
    local key_path="$USER_HOME/.ssh/sshkey"
    [ -f "$key_path" ] && rm -f "$key_path" "${key_path}.pub"
    
    ssh-keygen -t ed25519 -C "$USER_NAME@alpine" -f "$key_path" -N ""
    cat "${key_path}.pub" >> "$USER_HOME/.ssh/authorized_keys"
    
    echo -e "\n${gl_lv}密钥对生成成功！${gl_bai}"
    echo "------------------------------------------------"
    cat "$key_path"
    echo "------------------------------------------------"
    sshkey_on
}

# 功能：手动导入
import_sshkey() {
    ensure_ssh_dir
    printf "${gl_hui}请粘贴公钥内容: ${gl_bai}"
    read pub_content
    [ -z "$pub_content" ] && return 1

    echo "$pub_content" >> "$USER_HOME/.ssh/authorized_keys"
    echo -e "${gl_lv}导入成功！${gl_bai}"
    sshkey_on
}

# 功能：GitHub 导入
import_github() {
    ensure_ssh_dir
    printf "${gl_hui}请输入 GitHub 用户名: ${gl_bai}"
    read username
    if [ -n "$username" ]; then
        curl -fsSL "https://github.com/${username}.keys" >> "$USER_HOME/.ssh/authorized_keys"
        echo -e "${gl_lv}GitHub 公钥导入完成${gl_bai}"
        sshkey_on
    fi
}

# 主菜单
sshkey_panel() {
    init_check
    while true; do
        clear
        REAL_STATUS=$(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
        IS_KEY_ENABLED="${gl_hui}未启用${gl_bai}"
        [ "$REAL_STATUS" = "yes" ] && IS_KEY_ENABLED="${gl_lv}已启用${gl_bai}"
        
        echo -e "用户: ${gl_lv}${USER_NAME}${gl_bai} | SSH 密钥管理 ${IS_KEY_ENABLED}"
        echo "------------------------------------------------"
        echo "1. 生成新密钥对 (ED25519)"
        echo "2. 手动输入已有公钥"
        echo "3. 从 GitHub 导入公钥"
        echo "4. 编辑公钥文件 (authorized_keys)"
        echo "5. 查看当前密钥信息"
        echo "0. 退出"
        echo "------------------------------------------------"
        printf "请输入选择: "
        read choice
        case $choice in
            1) add_sshkey ;;
            2) import_sshkey ;;
            3) import_github ;;
            4) nano "$USER_HOME/.ssh/authorized_keys" ;;
            5)
                echo -e "\n${gl_huang}--- 已授权公钥 ($USER_NAME) ---${gl_bai}"
                [ -s "$USER_HOME/.ssh/authorized_keys" ] && cat "$USER_HOME/.ssh/authorized_keys" || echo "空"
                echo -e "\n${gl_huang}--- 本地生成的私钥 (如有) ---${gl_bai}"
                [ -f "$USER_HOME/.ssh/sshkey" ] && cat "$USER_HOME/.ssh/sshkey" || echo "无"
                printf "\n按回车继续..."; read dummy ;;
            0) exit 0 ;;
            *) echo "无效选择"; sleep 1 ;;
        esac
    done
}

sshkey_panel
