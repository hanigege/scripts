# hanigege/scripts

常用服务器运维脚本集合，覆盖 SSH 密钥登录、Linux iptables 防火墙、FreeBSD PF 防火墙、SSL 证书申请和 Docker 配置安装等场景。

Most scripts are interactive server operation helpers for SSH key login, Linux iptables, FreeBSD PF, SSL certificate issuing, and Docker configuration.

## 使用前请注意

- 建议先在测试机或新 SSH 会话中运行，确认不会锁死当前连接。
- SSH 和防火墙脚本会修改系统配置并重启服务，执行前请确认你有备用登录方式。
- 一键命令会从 `main` 分支下载最新脚本并立即执行。需要审计时，请先打开对应源码链接阅读。
- FreeBSD 推荐使用系统自带 `fetch`；Linux 推荐使用 `curl`。

## 中文说明

### Alpine root SSH 密钥管理

文件：[`alpine_root_ssh_key_manage.sh`](./alpine_root_ssh_key_manage.sh)

适用于 Alpine Linux 的 root 账户 SSH 密钥登录管理。支持生成 ED25519 密钥、手动导入公钥、从 GitHub 导入公钥、编辑和查看 `authorized_keys`，并关闭密码登录。

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/alpine_root_ssh_key_manage.sh -o /tmp/alpine_root_ssh_key_manage.sh && chmod +x /tmp/alpine_root_ssh_key_manage.sh && /tmp/alpine_root_ssh_key_manage.sh
```

### Alpine 普通用户 SSH 密钥管理

文件：[`alpine_user_ssh_key_manage.sh`](./alpine_user_ssh_key_manage.sh)

适用于 Alpine Linux 当前用户的 SSH 密钥登录管理。支持生成 ED25519 密钥、手动导入公钥、从 GitHub 导入公钥，并自动处理常见依赖和 SSH 配置。

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/alpine_user_ssh_key_manage.sh -o /tmp/alpine_user_ssh_key_manage.sh && chmod +x /tmp/alpine_user_ssh_key_manage.sh && /tmp/alpine_user_ssh_key_manage.sh
```

### Ubuntu SSH 密钥管理

文件：[`ubuntu_ssh_key_manage.sh`](./ubuntu_ssh_key_manage.sh)

适用于 Ubuntu/Debian 系统的 root SSH 密钥登录管理。支持生成 ED25519 密钥、导入现有公钥、从 GitHub 导入公钥，并禁用密码、PAM 和键盘交互认证。

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/ubuntu_ssh_key_manage.sh -o /tmp/ubuntu_ssh_key_manage.sh && chmod +x /tmp/ubuntu_ssh_key_manage.sh && sudo /tmp/ubuntu_ssh_key_manage.sh
```

### FreeBSD root SSH 管理

文件：[`freebsd_ssh_key_manage.sh`](./freebsd_ssh_key_manage.sh)

适用于 FreeBSD root 账户的 SSH 登录模式管理。支持生成密钥、导入公钥、从 GitHub 导入公钥、查看/编辑 `authorized_keys`，也支持恢复到仅密码登录模式。

```sh
fetch -o /tmp/freebsd_ssh_key_manage.sh https://raw.githubusercontent.com/hanigege/scripts/main/freebsd_ssh_key_manage.sh && chmod +x /tmp/freebsd_ssh_key_manage.sh && sh /tmp/freebsd_ssh_key_manage.sh
```

### FreeBSD 普通用户 SSH 管理

文件：[`freebsd_user_ssh_manager.sh`](./freebsd_user_ssh_manager.sh)

适用于 FreeBSD 普通用户的 SSH 登录管理。运行后先选择目标普通用户，再为该用户生成或导入公钥；脚本会禁用 root 登录和密码登录，适合更严格的 SSH 安全策略。

```sh
fetch -o /tmp/freebsd_user_ssh_manager.sh https://raw.githubusercontent.com/hanigege/scripts/main/freebsd_user_ssh_manager.sh && chmod +x /tmp/freebsd_user_ssh_manager.sh && sh /tmp/freebsd_user_ssh_manager.sh
```

### Debian/Ubuntu iptables 防火墙管理

文件：[`iptables_manager.sh`](./iptables_manager.sh)

适用于 Debian/Ubuntu 的交互式 iptables 管理工具。支持查看规则、放行端口、屏蔽 IP、删除规则、持久化保存、深度加固和紧急恢复全开。会自动安装 `iptables-persistent` 等依赖。

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/iptables_manager.sh -o /tmp/iptables_manager.sh && chmod +x /tmp/iptables_manager.sh && sudo /tmp/iptables_manager.sh
```

### FreeBSD PF 防火墙管理

文件：[`pf_manager.sh`](./pf_manager.sh)

适用于 FreeBSD PF 的交互式防火墙管理工具。支持维护 TCP/UDP 开放端口、自动保留当前 SSH 端口、持久化黑名单、手动封禁/解封 IP，以及安装每日自动释放过期黑名单任务。

```sh
fetch -o /root/pf-manager.sh https://raw.githubusercontent.com/hanigege/scripts/main/pf_manager.sh && chmod 700 /root/pf-manager.sh && /root/pf-manager.sh
```

### SSL 证书申请

文件：[`ssl.sh`](./ssl.sh)

适用于 Debian/Ubuntu/CentOS/RHEL 的 Let's Encrypt 证书申请脚本。使用 `acme.sh` 的 standalone 模式申请证书，证书默认安装到 `/etc/ssl/<domain>/`，并配置自动续期。

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/ssl.sh -o /tmp/ssl.sh && chmod +x /tmp/ssl.sh && sudo /tmp/ssl.sh
```

### Docker 配置安装包

文件：[`docker.sh`](./docker.sh)

这是一个 Makeself 自解压安装包，包内包含 Docker 配置文件和安装脚本。可先用 `--info`、`--list`、`--check` 查看和校验，再执行安装。

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/docker.sh -o /tmp/docker.sh && chmod +x /tmp/docker.sh && /tmp/docker.sh --check && sudo /tmp/docker.sh
```

## English

### Alpine root SSH key manager

File: [`alpine_root_ssh_key_manage.sh`](./alpine_root_ssh_key_manage.sh)

Interactive SSH key manager for the Alpine Linux root account. It can generate an ED25519 key pair, import an existing public key, import keys from GitHub, edit/view `authorized_keys`, and disable password login.

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/alpine_root_ssh_key_manage.sh -o /tmp/alpine_root_ssh_key_manage.sh && chmod +x /tmp/alpine_root_ssh_key_manage.sh && /tmp/alpine_root_ssh_key_manage.sh
```

### Alpine user SSH key manager

File: [`alpine_user_ssh_key_manage.sh`](./alpine_user_ssh_key_manage.sh)

Interactive SSH key manager for the current Alpine Linux user. It can generate an ED25519 key pair, import public keys manually or from GitHub, install common dependencies, and refresh SSH server settings.

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/alpine_user_ssh_key_manage.sh -o /tmp/alpine_user_ssh_key_manage.sh && chmod +x /tmp/alpine_user_ssh_key_manage.sh && /tmp/alpine_user_ssh_key_manage.sh
```

### Ubuntu SSH key manager

File: [`ubuntu_ssh_key_manage.sh`](./ubuntu_ssh_key_manage.sh)

Interactive SSH key manager for Ubuntu/Debian servers. It can generate/import keys and harden `sshd_config` by disabling password, PAM, and keyboard-interactive authentication.

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/ubuntu_ssh_key_manage.sh -o /tmp/ubuntu_ssh_key_manage.sh && chmod +x /tmp/ubuntu_ssh_key_manage.sh && sudo /tmp/ubuntu_ssh_key_manage.sh
```

### FreeBSD root SSH manager

File: [`freebsd_ssh_key_manage.sh`](./freebsd_ssh_key_manage.sh)

Interactive SSH login manager for the FreeBSD root account. It can generate/import keys, import keys from GitHub, view/edit `authorized_keys`, and switch back to password-only login if needed.

```sh
fetch -o /tmp/freebsd_ssh_key_manage.sh https://raw.githubusercontent.com/hanigege/scripts/main/freebsd_ssh_key_manage.sh && chmod +x /tmp/freebsd_ssh_key_manage.sh && sh /tmp/freebsd_ssh_key_manage.sh
```

### FreeBSD user SSH manager

File: [`freebsd_user_ssh_manager.sh`](./freebsd_user_ssh_manager.sh)

Interactive SSH manager for a selected non-root FreeBSD user. It can generate/import keys for that user and apply a stricter policy that disables root login and password login.

```sh
fetch -o /tmp/freebsd_user_ssh_manager.sh https://raw.githubusercontent.com/hanigege/scripts/main/freebsd_user_ssh_manager.sh && chmod +x /tmp/freebsd_user_ssh_manager.sh && sh /tmp/freebsd_user_ssh_manager.sh
```

### Debian/Ubuntu iptables manager

File: [`iptables_manager.sh`](./iptables_manager.sh)

Interactive iptables manager for Debian/Ubuntu. It can view rules, open ports, block IP addresses, delete rules, persist rules, apply a hardened baseline, and reset the firewall to an open emergency mode.

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/iptables_manager.sh -o /tmp/iptables_manager.sh && chmod +x /tmp/iptables_manager.sh && sudo /tmp/iptables_manager.sh
```

### FreeBSD PF firewall manager

File: [`pf_manager.sh`](./pf_manager.sh)

Interactive PF firewall manager for FreeBSD. It keeps the current SSH TCP port open, manages TCP/UDP allowed ports, maintains a persistent blacklist, bans/unbans IPs, and can install a daily blacklist expiration cron job.

```sh
fetch -o /root/pf-manager.sh https://raw.githubusercontent.com/hanigege/scripts/main/pf_manager.sh && chmod 700 /root/pf-manager.sh && /root/pf-manager.sh
```

### SSL certificate issuer

File: [`ssl.sh`](./ssl.sh)

Let's Encrypt certificate helper for Debian/Ubuntu/CentOS/RHEL. It uses `acme.sh` standalone mode, installs certificates under `/etc/ssl/<domain>/`, and configures automatic renewal.

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/ssl.sh -o /tmp/ssl.sh && chmod +x /tmp/ssl.sh && sudo /tmp/ssl.sh
```

### Docker configuration installer

File: [`docker.sh`](./docker.sh)

A Makeself self-extracting installer that contains Docker configuration files and an installer script. You can inspect it with `--info`, list bundled files with `--list`, and verify it with `--check` before running it.

```sh
curl -fsSL https://raw.githubusercontent.com/hanigege/scripts/main/docker.sh -o /tmp/docker.sh && chmod +x /tmp/docker.sh && /tmp/docker.sh --check && sudo /tmp/docker.sh
```
