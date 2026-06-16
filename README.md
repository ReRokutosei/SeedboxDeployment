# 自建 Seedbox 部署指南

## 背景

在此之前的很长一段时间里，我一直使用 Windows 本机运行 qBEE 追番。日常使用倒也没什么大问题，只是偶尔会系统卡顿一下（尤其在我播放音频的时候尤为明显），而且网络也似乎时不时被运营商Q，多少有些不便。再考虑到长期全天做种对 SSD 有读写负担，索性迁移到 VPS 上

前阵子我买了某芬兰厂家的普通 Seedbox（无 root 权限的普通盒子），但没想到短时间内就经历了两次服务宕机，发工单也没真人，都是AI敷衍回复。虽然有一键搭建脚本，但它们大多面向 PT 刷流场景，又或者里面预装很多东西等等之类的，于是我便想着，为什么我不自己搞一台大盘机做 Seedbox 呢？

但最近硬盘内存涨价，连带服务器也水涨船高，便宜的大盘机基本都处于售罄状态，更何况是版权宽松的芬兰、荷兰和卢森堡等地的机器，特别是较为知名的 BuyVM，即便补货也是被脚本秒了。要么去继续蹲，要么溢价收……

在我各种搜索之后，（虽然得到的案例不多）知道了我的需求貌似处于一个中间地带，被 DMCA 投诉的对象一般是热门美剧、英剧、好莱坞大片或主流流媒体平台（Netflix、Disney+、HBO等）的独家剧集，而 Mikan、Naya 这类动漫则通常都是经由字幕组烧录重编码，文件哈希已经改变（除了 Raw 生肉搬运、部分由 Netflix 发行的动漫），版权方很难追溯。那么我就想，是不是不一定需要找版权宽松地区的机器？这样选择范围变广了，再考虑到我需要通过 OpenList 在线观看，那在预算有限的情况下，优先选择美西地区的大盘机……

因此，我决定铤而走险，试试在 DMCA 最严格的 US 尝试 BT 下载

以本文记录我个人的操作流程，供日后参考

## 适用人群

本文面向**以 RSS 订阅追番为主**、希望将 BT 下载与日常电脑分离的个人用户，适合以下读者：

- 了解 Linux 基础操作
- 拥有一台 VPS（2C2G 或 1C2G 起步）和一个个人域名
- 希望设备简单解耦

> [!CAUTION]
> 本文**不适合** PT 刷流或冲上传量的玩家
> 
> 文中配置追求保守、不被投诉，需要自动刷流请参考其他专门教程

---

- [自建 Seedbox 部署指南](#自建-seedbox-部署指南)
  - [背景](#背景)
  - [适用人群](#适用人群)
  - [零、 准备工作](#零-准备工作)
  - [一、 系统基础防护](#一-系统基础防护)
    - [1.1 系统基础优化](#11-系统基础优化)
      - [1.1.1 清除厂家模板](#111-清除厂家模板)
      - [1.1.2 开启 BBR 网络加速](#112-开启-bbr-网络加速)
      - [1.1.3 增大 Swap（可选）](#113-增大-swap可选)
      - [1.1.4 切换默认 Shell 为 Bash](#114-切换默认-shell-为-bash)
    - [1.2 SSH 密钥登录](#12-ssh-密钥登录)
      - [1.2.1 生成密钥对](#121-生成密钥对)
      - [1.2.2 上传公钥至服务器](#122-上传公钥至服务器)
      - [1.2.3 加固 SSH 配置](#123-加固-ssh-配置)
      - [1.2.4 测试连接](#124-测试连接)
      - [1.2.5 配置本地快捷登录](#125-配置本地快捷登录)
    - [1.3 创建新用户](#13-创建新用户)
      - [1.3.1 创建用户并设置登录密码](#131-创建用户并设置登录密码)
      - [1.3.2 将用户加入 sudo 组](#132-将用户加入-sudo-组)
      - [1.3.3 配置免密 sudo （可选、谨慎！）](#133-配置免密-sudo-可选谨慎)
      - [1.3.4 将公钥复制给新用户](#134-将公钥复制给新用户)
      - [1.3.5 更新本地 SSH config](#135-更新本地-ssh-config)
    - [1.4 部署 Fail2ban](#14-部署-fail2ban)
    - [1.5 部署防火墙](#15-部署防火墙)
      - [1.5.1 禁用 UFW](#151-禁用-ufw)
      - [1.5.2 创建防火墙部署脚本](#152-创建防火墙部署脚本)
      - [1.5.3 修改配置并首次部署](#153-修改配置并首次部署)
      - [1.5.4 创建黑名单更新脚本](#154-创建黑名单更新脚本)
      - [1.5.5 首次加载黑名单](#155-首次加载黑名单)
      - [1.5.6 设置自动更新](#156-设置自动更新)
      - [1.5.7 验证规则](#157-验证规则)
  - [二、 安装应用与反代网关](#二-安装应用与反代网关)
    - [2.1 目录初始化](#21-目录初始化)
    - [2.2 安装并配置 qBittorrent EE](#22-安装并配置-qbittorrent-ee)
      - [2.2.1 安装 qBEE](#221-安装-qbee)
      - [2.2.2 编写服务](#222-编写服务)
    - [2.3 安装并配置 PeerBanHelper (PBH)](#23-安装并配置-peerbanhelper-pbh)
      - [2.3.1 配置 Java 25 运行环境](#231-配置-java-25-运行环境)
      - [2.3.2 下载并解压 PBH](#232-下载并解压-pbh)
      - [2.3.3 编写 Systemd 守护进程](#233-编写-systemd-守护进程)
    - [2.4 安装并配置 OpenList (流媒体面板)](#24-安装并配置-openlist-流媒体面板)
    - [2.5 部署 Caddy 网关统一反代](#25-部署-caddy-网关统一反代)
      - [2.5.1 Cloudflare DNS 设置](#251-cloudflare-dns-设置)
      - [2.5.2 安装 Caddy](#252-安装-caddy)
      - [2.5.3 配置 Caddyfile 路由](#253-配置-caddyfile-路由)
  - [三、启动并配置应用](#三启动并配置应用)
    - [3.1 启动 qBEE](#31-启动-qbee)
    - [3.2 启动 PBH](#32-启动-pbh)
    - [3.3 启动 OpenList](#33-启动-openlist)
  - [四、 进阶可选配置](#四-进阶可选配置)
    - [4.1 更换 WebUI 为 VueTorrent](#41-更换-webui-为-vuetorrent)
    - [4.2 自动清理过期番剧](#42-自动清理过期番剧)
    - [4.3 优化线路跳转（Mihomo 代理转发）](#43-优化线路跳转mihomo-代理转发)
    - [4.4 配置下载通知（Telegram Bot）](#44-配置下载通知telegram-bot)
      - [4.4.1 创建 Telegram Bot](#441-创建-telegram-bot)
      - [4.4.2 获取 Chat ID](#442-获取-chat-id)
      - [4.4.3 创建通知脚本](#443-创建通知脚本)
      - [4.4.4 绑定到 qBEE](#444-绑定到-qbee)
      - [4.4.5 预期效果](#445-预期效果)
    - [4.5 部署零信任隧道](#45-部署零信任隧道)
      - [4.5.1 在云端创建隧道](#451-在云端创建隧道)
      - [4.5.2 在 Seedbox 上安装连接器](#452-在-seedbox-上安装连接器)
      - [4.5.3 在网页端配置 SSH 路由](#453-在网页端配置-ssh-路由)
      - [4.5.4 增加 SSH 配置块](#454-增加-ssh-配置块)
  - [附：qBEE 参考配置](#附qbee-参考配置)
    - [限速](#限速)
    - [连接数](#连接数)
    - [队列](#队列)
    - [做种限制](#做种限制)
    - [BitTorrent](#bittorrent)
    - [高级 — 内存](#高级--内存)
    - [高级 — 线程](#高级--线程)
    - [高级 — 磁盘](#高级--磁盘)
    - [高级 — 网络与 Peer](#高级--网络与-peer)
  - [附：端口速查](#附端口速查)


## 零、 准备工作

在开始之前，请做好以下准备：

1. **一个个人域名**：用于反代访问
2. **一个通过支付验证的 Cloudflare 账号**：将域名托管至 Cloudflare
3. **一台 VPS**：拥有 root 且建议 2GB RAM 起步

> [!TIP]
> 本文中的 `your_vps_ip`、`yourname`、`yourdomain.com` 均为占位符，实际操作时请替换为你的真实 IP、用户名和域名

---

## 一、 系统基础防护

### 1.1 系统基础优化

#### 1.1.1 清除厂家模板

使用 root 账密进行 ssh 登录

```bash
ssh root@192.0.2.100  # 改为你的 IP，回车后输入密码
```

部分服务商的系统模板可能包含首次开机脚本，建议清除，没有则跳过

```bash
sudo crontab -e
```

进入编辑界面后，寻找类似 `@reboot /admin/firstbootkvm yes` 的行，将其删除并保存

#### 1.1.2 开启 BBR 网络加速

把系统自带的 BBR 拥塞控制开启，能直接拉升机器的公网吞吐量：

```bash
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
```

#### 1.1.3 增大 Swap（可选）

对于 2GB RAM 的 VPS，qBEE 和 PBH 同时运行时内存吃紧，适当增大 Swap 可提供缓冲：

```bash
# 查看当前 Swap
sudo swapon --show

# 创建 2G Swap 文件（可根据磁盘余量调整大小）
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 写入 fstab 使其重启后自动挂载
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

降低 swappiness 让系统优先使用物理内存：

```bash
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

| swappiness | 行为 |
| :-: | :-: |
| 0 | 不用 swap（如果 RAM 充足，可以完全不用）      |
| 10 | 物理内存接近耗尽时才动用 swap（**推荐**）    |
| 20 | 较保守的折中值                               |
| 60 | 系统默认，较早换出到 swap                     |

> 数值越低，系统越倾向保留物理内存，避免磁盘 I/O；但同时 OOM 风险略增。常规场景设为 10 即可。

#### 1.1.4 切换默认 Shell 为 Bash

Debian 12 Template 默认将 `/bin/sh` 指向 `dash`，不是 `bash`。本文所有脚本均以 `#!/bin/bash` 声明，**不受影响**，但个别系统脚本和交互环境可能行为异常（比如在 PowerShell 7 中主机名无彩色、部分 sh 脚本语法报错）

将默认 Shell 切换为 bash：

```bash
# 查看当前指向
ls -l /bin/sh

# 重新配置（选择“否”，不使用 dash）
sudo dpkg-reconfigure dash

# 确认已切换
ls -l /bin/sh
```

执行后应看到 `/bin/sh -> bash`。

### 1.2 SSH 密钥登录

#### 1.2.1 生成密钥对

在本地电脑（本文以 Windows 为例）打开 PowerShell 7，生成一把新密钥对：

```powershell
cd ~
ssh-keygen -t ed25519 -C "随便取名比如seedbox" -f ~/.ssh/id_ed25519_seedbox
```

回车后，会提示你设置密码（passphrase），如果嫌麻烦可以直接连按两次回车跳过即可

#### 1.2.2 上传公钥至服务器

密钥生成后，在本地 PowerShell 中运行以下命令，将公钥上传到服务器（注意将 `your_vps_ip` 替换为真实 IP）

```powershell
$pubKey = Get-Content "$HOME\.ssh\id_ed25519_seedbox.pub"
$pubKey | ssh root@your_vps_ip "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

#### 1.2.3 加固 SSH 配置

然后，回到 VPS SSH 窗口，编辑 SSH 配置文件：

```Bash
nano /etc/ssh/sshd_config
```

修改或取消注释以下行：

```text
Port 43210                  # 修改为任意高位端口
PasswordAuthentication no   # 禁用密码登录
PubkeyAuthentication yes    # 允许密钥登录
```

顺便查看是否存在这一行 `Include /etc/ssh/sshd_config.d/*.conf`

如有，在保存退出 `/etc/ssh/sshd_config` 的编辑后，输入：

```bash
ls -R /etc/ssh/sshd_config.d/
```

如果看到输出结果是 `50-cloud-init.conf`，则继续输入：

```bash
sudo nano /etc/ssh/sshd_config.d/50-cloud-init.conf
```

将里面的 `PasswordAuthentication yes` 改为 `PasswordAuthentication no`

重启 SSH 服务使变更生效：

```bash
sudo systemctl restart sshd
```

注意，重启服务后，先别关闭当前的 SSH 终端窗口，先开一个新的终端窗口，测试一下能不能用新端口和密钥成功连上，如果连不上，在原来的窗口里把配置改回来

#### 1.2.4 测试连接

从本地 Windows 测试连接的命令是：

```powershell
cd ~/.ssh
ssh -i ./id_ed25519_seedbox -p 43210 root@your_vps_ip
```

如果私钥设置了 passphrase，在连接时会提示输入；如果没有设置，则直接登录

#### 1.2.5 配置本地快捷登录

如果希望后续不用每次都输路径和端口，也可以在本地添加一个配置块：

```powershell
notepad $HOME/.ssh/config 
```

回车后会打开一个记事本编辑器，输入以下内容：

```text
Host seedbox
    HostName your_vps_ip
    User root
    Port 43210
    IdentityFile ~/.ssh/id_ed25519_seedbox
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Ctrl+S 保存后，即可用以下命令登录：

```powershell
ssh seedbox
```

### 1.3 创建新用户

为贯彻最小权限原则，我们不使用 `root` 登录，创建一个专用用户来运行服务和管理文件

> [!TIP]
> 以下步骤仍在当前的 root SSH 会话中执行，完成后将切换到新用户

#### 1.3.1 创建用户并设置登录密码
```bash
# 创建用户 yourname（UID 1000，带 home 目录）
useradd -m -u 1000 yourname

# 设置密码（必须设置，否则无法使用 sudo）
passwd yourname
```
> [!NOTE]
> 系统会提示你输入两次密码，虽然我们主要用密钥登录，但 **`sudo` 默认需要用户有密码**，否则会报错 `user is not in the sudoers file` 或 `no password set`

#### 1.3.2 将用户加入 sudo 组
```bash
# Debian/Ubuntu 系列
usermod -aG sudo yourname
```

#### 1.3.3 配置免密 sudo （可选、谨慎！）
> [!CAUTION]
> 跳过密码验证会降低安全性，仅建议在**个人独占、无敏感数据**的 VPS 上使用

如果你希望执行 `sudo` 时**不用输密码**，编辑 sudoers 文件：

```bash
visudo
```

在文件末尾添加一行：

```text
yourname ALL=(ALL) NOPASSWD: ALL
```

Ctrl+O 、回车、 Ctrl+X 保存退出

> [!TIP]
> 比较推荐的方法是保留密码验证，只对特定命令免密
> 
> 比如 `sudo systemctl restart qbittorrent`
> 
> 本教程为简化流程采用全局免密

#### 1.3.4 将公钥复制给新用户

在**本地 PowerShell** 中运行（注意将 `your_vps_ip` 替换为真实 IP）：

```powershell
$pubKey = Get-Content "$HOME\.ssh\id_ed25519_seedbox.pub"
$pubKey | ssh root@your_vps_ip "mkdir -p /home/yourname/.ssh && chmod 700 /home/yourname/.ssh && cat >> /home/yourname/.ssh/authorized_keys && chmod 600 /home/yourname/.ssh/authorized_keys && chown -R yourname:yourname /home/yourname/.ssh"
```

#### 1.3.5 更新本地 SSH config

打开你本地的 `$HOME/.ssh/config`，追加新用户的配置块：

```text
Host seedbox-yourname
    HostName your_vps_ip
    User yourname
    Port 43210
    IdentityFile ~/.ssh/id_ed25519_seedbox
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

保存后，即可用 `ssh seedbox-yourname` 登录，再通过 `sudo` 执行管理命令

---

### 1.4 部署 Fail2ban

虽然已经禁用了密码登录，但公网上的端口探测依然会消耗系统资源

Fail2ban 可以动态封禁那些反复试探的 IP

```bash
sudo apt update && sudo apt install fail2ban -y
```

创建自定义配置，注意将 `port` 改为你之前设置的 SSH 端口：

```bash
sudo nano /etc/fail2ban/jail.local
```

写入：

```ini
[sshd]
enabled = true
port = 43210
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 86400
```

> 10 分钟内输错 3 次密码，封禁该 IP 24 小时

启动并设置开机自启：

```bash
sudo systemctl enable --now fail2ban
```

---

### 1.5 部署防火墙

本文采用以下设计：

- **防火墙规则**（iptables）：长期稳定，部署一次即可，后续无需变动
- **黑名单数据**（ipset）：定期更新，独立脚本执行，不影响现有防火墙规则

```
防火墙规则 (deploy_firewall.sh)     → 执行一次即可
        ↓
     ipset 集合
        ↓
ASN 黑名单 (update_blacklists.sh)  → 每周自动更新
P2P 黑名单 (update_blacklists.sh)  → 每周自动更新
```

#### 1.5.1 禁用 UFW

如果你之前启用过 UFW，先关掉：

```bash
sudo ufw disable
sudo systemctl stop ufw
sudo systemctl disable ufw
```

#### 1.5.2 创建防火墙部署脚本

防火墙部署脚本只需**执行一次**（或修改端口配置后重新执行）：

```bash
sudo nano /usr/local/bin/deploy_firewall.sh
```

粘贴以下脚本：

[deploy_firewall.sh](deploy_firewall.sh)

#### 1.5.3 修改配置并首次部署

用 `nano` 打开脚本后，修改开头的**用户配置区**：

```bash
# SSH 端口
SSH_PORT=43210

# BT 监听端口
BT_TCP_PORT=54321
BT_UDP_PORT=54321

# 额外放行的 Web 端口（80 已默认放行）
WEB_PORTS=(80)

# 邻居网段阻断（设为 "-" 表示不启用）
NEIGHBOR_V4="-"
NEIGHBOR_V6="-"
```

> [!NOTE]
> 443 端口不在 `WEB_PORTS` 中配置，而是由脚本内部的 DROP→ACCEPT 逻辑单独处理，使得黑名单规则正常生效

赋予执行权限并运行：

```bash
sudo chmod +x /usr/local/bin/deploy_firewall.sh
sudo /usr/local/bin/deploy_firewall.sh
```

脚本会：
1. 创建 ipset 集合（`bad_asn_v4`、`bad_asn_v6`、`bad_p2p_v4`）
2. 清空原有 iptables 规则并部署新规则
3. 安装 `iptables-persistent` 并保存规则（重启后自动恢复）

> [!NOTE]
> 此脚本只负责部署防火墙规则，**不会下载或加载黑名单数据**
> 
> 此时 ipset 集合为空，所有 443 请求都可以正常访问

#### 1.5.4 创建黑名单更新脚本

黑名单更新脚本负责下载 ASN/P2P 数据并更新 ipset 集合，**不修改防火墙规则**：

```bash
sudo nano /usr/local/bin/update_blacklists.sh
```

粘贴以下脚本：

[update_blacklists.sh](update_blacklists.sh)

赋予执行权限：

```bash
sudo chmod +x /usr/local/bin/update_blacklists.sh
```

脚本说明：

- **原子更新**：创建新集合 → 导入数据 → `ipset swap` 切换 → 销毁旧集合，切换耗时毫秒级，更新期间不会出现空集合窗口
- **缓存机制**：将解析后的 CIDR 列表存入 `/var/lib/seedbox-firewall/`，下次运行时对比 SHA256，数据未变化则跳过更新
- **容错处理**：下载失败不销毁现有集合，部分源失败不影响已成功的更新

#### 1.5.5 首次加载黑名单

```bash
sudo /usr/local/bin/update_blacklists.sh
```

首次运行会下载并导入所有 ASN 和 P2P 黑名单（目前约 47+ 万条），耗时取决于网络和 VPS 性能

> [!NOTE]
> 由于脚本采用原子 swap 更新，首次运行时 `deploy_firewall.sh` 创建的集合可能为空，需要等待导入完成后才会有数据
> 
> 后续每周运行时，当前集合始终保持有效，不受更新过程影响

#### 1.5.6 设置自动更新

P2P 黑名单更新频率较低，建议**每周**执行一次：

```bash
sudo crontab -e
```

末尾添加一行（每周日凌晨 4 点）：

```cron
0 4 * * 0 /usr/local/bin/update_blacklists.sh > /var/log/blacklist-update.log 2>&1
```

如果你希望更高频率，改为每日：

```cron
0 4 * * * /usr/local/bin/update_blacklists.sh > /var/log/blacklist-update.log 2>&1
```

> [!NOTE]
> 该 cron 任务只更新 ipset 数据，**不修改防火墙规则、不会中断网络连接**

#### 1.5.7 验证规则

```bash
sudo iptables -L INPUT -v -n --line-numbers
```

你应该看到类似的输出：

```
Chain INPUT (policy DROP)
num   pkts bytes target     prot opt in     out     source               destination
1        0     0 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
2        0     0 ACCEPT     0    --  lo     *       0.0.0.0/0            0.0.0.0/0
3        0     0 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:43210
4        0     0 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:80
5        0     0 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:54321
6        0     0 ACCEPT    17    --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:54321
7        0     0 DROP       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:443 match-set bad_asn_v4 src
8        0     0 DROP       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:443 match-set bad_p2p_v4 src
9        0     0 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:443
```

> [!NOTE]
> 443 端口的处理逻辑是「先匹配 ASN 黑名单 DROP → 再匹配 P2P 黑名单 DROP → 最后默认 ACCEPT 」
> 
> 即如果请求来源命中任一名单则直接丢弃，否则放行
> 
> 不要把 443 放在放行端口列表中，否则黑名单将完全失效

验证 ipset 集合数据量：

```bash
sudo ipset list bad_asn_v4 | grep "Number of entries"
sudo ipset list bad_p2p_v4 | grep "Number of entries"
```

预期输出示例：

```
Number of entries: 3421
Number of entries: 468200
```

---

## 二、 安装应用与反代网关

所有业务应用均在普通用户下运行，应用启动后，统一由 Caddy 接管公网流量

### 2.1 目录初始化

以普通用户（如 `yourname`）登录，执行：

```bash
# 数据落盘区
mkdir -p ~/downloads/anime
mkdir -p ~/downloads/animetemp
mkdir -p ~/downloads/bd_archive
```

### 2.2 安装并配置 qBittorrent EE

#### 2.2.1 安装 qBEE

```bash
# 安装依赖
sudo apt install -y unzip

# 下载静态编译包（一般选择 x86_64 架构即可）
wget https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/latest/download/qbittorrent-enhanced-nox_x86_64-linux-musl_static.zip

# 解压
unzip qbittorrent-enhanced-nox_x86_64-linux-musl_static.zip

# 将二进制文件移动到本机软件目录并赋予执行权限
sudo mv qbittorrent-nox /usr/local/bin/qbittorrent-nox
sudo chmod +x /usr/local/bin/qbittorrent-nox

# 清理安装包
rm qbittorrent-enhanced-nox_x86_64-linux-musl_static.zip
```

#### 2.2.2 编写服务

```bash
sudo nano /etc/systemd/system/qbittorrent.service
```

将以下内容粘贴进去：

```ini
[Unit]
Description=qBittorrent Command Line Client
After=network.target

[Service]
Type=exec
User=yourname
Group=yourname
UMask=002
ExecStart=/usr/local/bin/qbittorrent-nox
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

> [!TIP]
> `UMask=002` 能确保 qBEE 下载的文件，默认权限是 775 （目录）和 664 （文件）
> 
> 对于后续 OpenList 读取或者 rclone 拖回本地都极其友好，不会卡权限

保存并退出（Ctrl+O 回车，Ctrl+X）后，拉起服务：

```Bash
sudo systemctl enable --now qbittorrent
```

然后停止以生成配置文件：
```bash
sudo systemctl stop qbittorrent
```

nano 打开 `~/.config/qBittorrent/qBittorrent.conf`，在 `[Preferences]` 区域添加/修改：

```ini
WebUI\Address=127.0.0.1
```
此操作将面板死锁在本地环回地址

顺便将其中的`Session\Port=54321` 记下来，该端口就是上面提到的 BT 监听端口


### 2.3 安装并配置 PeerBanHelper (PBH)

接下来保持 qBEE 不启动，继续配置 PBH

#### 2.3.1 配置 Java 25 运行环境

目前PBH 最新版需要 Java 25，先下载一个纯净绿色的 Java 25 放到 `/opt` 下专门给 PBH 用：

```bash
# 创建 Java 25 目录
sudo mkdir -p /opt/java25

# 下载 Java 25
wget -O jdk25.tar.gz "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"

# 解压到专属目录
sudo tar -xzf jdk25.tar.gz -C /opt/java25 --strip-components=1

# 删除压缩包
rm jdk25.tar.gz
```

#### 2.3.2 下载并解压 PBH

让程序和数据都待在之前创建的 `yourname` 专属目录里：

```bash
# 进入配置目录
mkdir -p /home/yourname/seedbox/config/pbh
cd /home/yourname/seedbox/config/pbh

# 下载安装包
wget https://github.com/PBH-BTN/PeerBanHelper/releases/download/v9.3.14/PeerBanHelper_9.3.14.zip

# 解压
unzip PeerBanHelper_9.3.14.zip

# 删掉安装包
rm PeerBanHelper_9.3.14.zip
```

#### 2.3.3 编写 Systemd 守护进程


```bash
sudo nano /etc/systemd/system/peerbanhelper.service
```

将下面的内容粘贴进去（强制以 `yourname` 用户运行，并指定使用我们刚准备好的 Java 25）：

```ini
[Unit]
Description=PeerBanHelper Daemon
After=network.target

[Service]
Type=simple
User=yourname
Group=yourname
WorkingDirectory=/home/yourname/seedbox/config/pbh/PeerBanHelper
ExecStart=/opt/java25/bin/java -jar /home/yourname/seedbox/config/pbh/PeerBanHelper/PeerBanHelper.jar
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

保存并退出


### 2.4 安装并配置 OpenList (流媒体面板)

1. **二进制部署：**

```bash
# 1. 创建 OpenList 专属工作目录
mkdir -p /home/yourname/seedbox/config/openlist
cd /home/yourname/seedbox/config/openlist

# 2. 下载 OpenList 最新的 linux-amd64 包
wget https://github.com/OpenListTeam/OpenList/releases/latest/download/openlist-linux-amd64.tar.gz

# 3. 解压并赋予权限
tar -zxf openlist-linux-amd64.tar.gz
sudo mv openlist /usr/local/bin/openlist
sudo chmod +x /usr/local/bin/openlist

# 4. 清理安装包
rm openlist-linux-amd64.tar.gz

```

2. **Systemd 守护：** 

编写守护进程
```bash
sudo nano /etc/systemd/system/openlist.service
```

将以下内容粘贴进去：

```ini
[Unit]
Description=OpenList Web File Manager
After=network.target

[Service]
Type=simple
User=yourname
Group=yourname
WorkingDirectory=/home/yourname/seedbox/config/openlist
ExecStart=/usr/local/bin/openlist server
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
保存并退出


### 2.5 部署 Caddy 网关统一反代

各面板现已隐藏在 `127.0.0.1`，使用 Caddy 将其安全发布并自动维护 HTTPS 证书

总共需要在 Cloudflare 上配置三个子域名

#### 2.5.1 Cloudflare DNS 设置

登录 Cloudflare 控制台，为你的主域名 `<yourdomain.com>` 增添三个 **A 记录**：

1. `qbee` -> 指向 **Seedbox 的公网 IP**
2. `openlist` -> 指向 **Seedbox 的公网 IP**
3. `pbh` -> 指向 **Seedbox 的公网 IP**

> [!NOTE]
> 这三个域名的“代理状态”全部请保持为 **小灰云（仅限 DNS）**
> 
> 后续 OpenList 传输大流量视频时直连跑满带宽，不走 Cloudflare CDN，以免违反 TOS 导致封号

#### 2.5.2 安装 Caddy

使用 Caddy 官方针对 Debian 的软件源进行原生安装：

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

# 导入 GPG 密钥
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

# 添加官方软件源
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list

# 更新并安装
sudo apt update
sudo apt install caddy -y
```

#### 2.5.3 配置 Caddyfile 路由

清空再打开 Caddyfile：

```bash
sudo > /etc/caddy/Caddyfile
sudo nano /etc/caddy/Caddyfile
```

将下面这段配置粘贴进去：

```caddyfile
# 1. qBittorrent Enhanced Edition 面板
qbee.yourdomain.com {
    reverse_proxy localhost:8080

    log {
        output file /var/log/caddy/qbee_access.log
    }
}

# 2. OpenList 媒体看番面板
openlist.yourdomain.com {
    reverse_proxy localhost:5244

    log {
        output file /var/log/caddy/openlist_access.log
    }
}

# 3. PeerBanHelper 管理面板
pbh.yourdomain.com {
    reverse_proxy localhost:9898

    log {
        output file /var/log/caddy/pbh_access.log
    }
}
```

保存并退出，然后启动 Caddy 服务：

> [!TIP]
> Caddy 会在首次启动时**自动向 Let's Encrypt 申请免费 SSL 证书**
> 
> 为三个子域名启用 HTTPS，无需任何额外配置

```bash
sudo systemctl enable --now caddy
```

## 三、启动并配置应用

基础设施已就绪，现在可以正式启动 qBEE 和 PBH ：

### 3.1 启动 qBEE

```bash
# 启动 qBEE
sudo systemctl start qbittorrent

# 查看并记录首次启动的随机密码
sudo journalctl -u qbittorrent | grep -i password
```

此时，在本地 Windows 的浏览器中进入 `https://qbee.yourdomain.com`

初始账号为 admin，使用刚才抓取的随机密码登录进去后

首先去 `Tools -> Options -> Web UI` 修改随机初始密码与账户名（不推荐继续使用 admin）

假设修改为：
```
user: yourname
password: 12345678 # 仅作教程示例，请使用强密码！
```

保存后，按 F5 刷新网址重新登陆一遍即可

接着，根据个人喜好进行设置，VPS 配置较低的用户可参考文末的【附：qBEE 参考配置】

```
默认保存路径（完成时）：/home/yourname/downloads/anime
默认下载路径（未完成的种子）：/home/yourname/downloads/animetemp
```

### 3.2 启动 PBH

```bash
sudo systemctl enable --now peerbanhelper
sudo systemctl status peerbanhelper
```

在本地 Windows 的浏览器中直接输入 `https://pbh.yourdomain.com`

登录 token 为随机生成，建议使用浏览器密码管理器保存

接下来跟随界面指引，创建 BTN 账号或登录已有账号（输入已有的 App ID 和 Secret）

接着`连接下载器`，填下以下信息（未提及的保持默认）

```
类型：qBittorrentEE
名称：随便
地址：http://127.0.0.1:8080
用户名：yourname
密码：12345678 # 仅作教程示例，请使用强密码！

```

接着前往 PBH 的设置页->基础设置->WebUI，将前缀(Prefix)改为`https://pbh.yourdomain.com`

> 因为我们使用了 Caddy 反代，这里需要修改为外部可以访问的域名，否则 PBH 无法把封禁列表传给 qBEE


（可选）继续往下滑，调整封禁日志保留时间默认存半年的日志，建议改成 15 天或 30 天即可

最后一步，屏蔽 CN IP

设置->规则订阅->地区->新增->输入 `CN` （必须是大写）即可，这样 PBH 就会自动在后台将所有来自 CN 的 IP 地址拉入 qBEE 的黑名单中

### 3.3 启动 OpenList

```bash
# 拉起并设置开机自启
sudo systemctl daemon-reload
sudo systemctl enable --now openlist

# 直接强制设定管理员密码（复杂强密码需要使用单引号）
/usr/local/bin/openlist admin set '1111111111111'
```

在 Windows 浏览器打开 `https://openlist.yourdomain.com`

登录后，在 管理 -> 用户，找到 `guest` 账号，点击编辑并勾选 `停用`，禁止游客登陆；

接着在个人资料将初始用户名 `admin` 修改为 `yourname`；

再接着挂载由 qBEE 下好的视频： `存储` -> `添加`

```
驱动：本机存储
挂载路径：/动漫
根文件夹路径： /home/yourname/downloads/anime
```

点击最底部的 `添加` 即可保存

最后加固一下，设置 -> 站点，将底部的 `Robots.txt` 改为

```
User-agent: *
Disallow: /
```

---

## 四、 进阶可选配置

### 4.1 更换 WebUI 为 VueTorrent
如果看腻了 qBEE 的默认样式，可尝试更换为 [VueTorrent](https://github.com/VueTorrent/VueTorrent)

```bash
cd ~

# 下载构建产物
wget https://github.com/VueTorrent/VueTorrent/releases/latest/download/vuetorrent.zip

# 解压
unzip vuetorrent.zip

# 清理
rm vuetorrent.zip
```

接着登录 qBEE WebUI，进入 设置 -> WebUI -> 

启用备用 WebUI，输入：

```
/home/yourname/vuetorrent
```

刷新网页即可

### 4.2 自动清理过期番剧

qBEE 下载的番剧会长期占用磁盘空间，本脚本定期扫描 `anime` 目录，将**超过 120 天且未在 qBEE 中做种**的旧番自动删除，防止磁盘被撑爆

> [!NOTE]
> 触发条件：文件最后修改时间距今超过 `EXPIRE_DAYS`（默认 120 天），且该文件名不在 qBEE 当前种子列表中

编写脚本：

```bash
cd ~ && mkdir -p script && cd script && nano qb_cleaner.sh
```

填入以下内容（注意将 `QB_PASS` 和 `PORT` 改为你的实际值）：

```bash
#!/bin/bash
QB_USER="yourname"
QB_PASS='你的qB WebUI密码'

# qBittorrent WebUI 端口（默认 8080），非 BT 监听端口
PORT="8080"
API_URL="http://127.0.0.1:${PORT}/api/v2"
COOKIE_FILE="/tmp/qb_cookies_cleaner.txt"

ANIME_DIR="/home/yourname/downloads/anime"
BD_ARCHIVE_DIR="/home/yourname/downloads/bd_archive"
EXPIRE_DAYS=120

# 登录 qB API 并获取所有种子名称
curl -s -c "$COOKIE_FILE" \
    --data-urlencode "username=$QB_USER" \
    --data-urlencode "password=$QB_PASS" \
    "${API_URL}/auth/login" > /dev/null

ACTIVE_NAMES=$(curl -s -b "$COOKIE_FILE" \
    "${API_URL}/torrents/info" | jq -r '.[] | .name')

# 扫描过期的目录/文件，跳过仍在做种的
find "$ANIME_DIR" -mindepth 1 -maxdepth 1 -mtime +$EXPIRE_DAYS | while read -r ITEM; do
    if [[ "$ITEM" == *"$BD_ARCHIVE_DIR"* ]]; then continue; fi
    
    BASE_NAME=$(basename "$ITEM")
    if echo "$ACTIVE_NAMES" | grep -F -x -q "$BASE_NAME"; then
        continue
    else
        rm -rf "$ITEM"
    fi
done

rm -f "$COOKIE_FILE"
```

赋予执行权限：

```bash
chmod +x ~/script/qb_cleaner.sh
```

接着每日清晨 8 点自动执行：

```bash
crontab -e
```

写入：

```text
0 8 * * * /home/yourname/script/qb_cleaner.sh >> ~/script/qb_cleaner.log 2>&1
```

### 4.3 优化线路跳转（Mihomo 代理转发）

假设，你的 seedbox 在 LA，但是线路很差，但是恰好你又有另一台 LA 优化线路的机，并且很巧还搭建好了魔法，那么可利用本地 Mihomo 客户端将优化节点作为 SSH 跳板

如果你的 mihomo rules 最后是 match，那么当你访问你的 seedbox 时，大概率会被自动捕获并走 proxy，但我们可以简单加一个 tunnel 字段，使得 mihomo 不必每次都去匹配 rules ：

1. 在 Mihomo 配置文件中添加顶级字段`tunnels`：

```yaml
tunnels:
  # 类型，监听本地端口，目标地址与端口，出站节点/节点组
  # 将目标地址与端口改为你seedbox的ip与ssh端口
  - tcp,127.0.0.1:33333,your_vps_ip:43210,魔法节点
  # - tcp,127.0.0.1:33333,your_vps_ip:43210,魔法节点策略组
```

2. 接着在本地添加 ssh config 配置块：

```powershell
notepad $HOME/.ssh/config 
```

```text
Host seedbox-mihomo
    HostName 127.0.0.1
    Port 33333
    User yourname
    IdentityFile ~/.ssh/id_ed25519_seedbox
```

如果顺利，当你执行`ssh seedbox-mihomo`时，mihomo 日志显示的连接类型应为`Tunnel`

此方法需要 mihomo 保持启动状态，~~更多玩法自行研究吧~~

### 4.4 配置下载通知（Telegram Bot）

在本地 Windows 上我习惯使用`下载完成后发送电子邮件通知`，但 VPS 环境下配置 SMTP 既繁琐又不安全，因此我使用 Telegram Bot 进行通知

**前置条件**：拥有一个 Telegram 账号

#### 4.4.1 创建 Telegram Bot

在 Telegram 中搜索 `@BotFather`，依次发送以下指令：

1. `/newbot` —— 创建新 Bot
2. 输入 Bot 显示名称（任意）
3. 输入 Bot 用户名（必须以 `bot` 结尾）

完成后 BotFather 会返回一段消息，其中包含：

```
Use this token to access the HTTP API:
1234567890:BBA2XXjn4YjgHmPqdvd-nK7AbuvCkuSVPzs
```

**妥善保存此 token**，持有它即可控制你的 Bot

然后在 TG 搜索你刚创建的 Bot 用户名，将其添加到聊天列表

#### 4.4.2 获取 Chat ID

> 第三方 TG 客户端可以直接看到自己的 ID

往你的 Bot 发送一条任意消息（如 `hello`），然后在浏览器访问以下网址（替换 `TOKEN`）：

```
https://api.telegram.org/bot<TOKEN>/getUpdates
```

返回的 JSON 中 `"chat":{"id":123123123}` 即为你的 Chat ID，记录下来

#### 4.4.3 创建通知脚本

```bash
cd ~/script && nano tg_notify.sh
```

```bash
#!/bin/bash

# --- 配置区 ---
BOT_TOKEN="1234567890:BBA2XXjn4YjgHmPqdvd-nK7AbuvCkuSVPzs" # 输入从 BotFather 获得的 token
CHAT_ID="123123123" # 输入你的 Chat ID

# --- 接收 qBEE 传参 ---
TORRENT_NAME="$1"
SIZE_BYTES="$2"
SAVE_PATH="$3"

SIZE_MB=$((SIZE_BYTES / 1024 / 1024))

MESSAGE="🎉 <b>Seedbox 下载完成</b>%0A%0A🎬 名称：${TORRENT_NAME}%0A💾 大小：${SIZE_MB} MB%0A📁 路径：${SAVE_PATH}"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" > /dev/null
```

赋予执行权限：

```bash
chmod +x ~/script/tg_notify.sh
```

#### 4.4.4 绑定到 qBEE

打开 qBEE WebUI → 设置 → 下载，勾选 `种子下载完成时运行外部程序`，填入：

```
/home/yourname/script/tg_notify.sh "%N" "%Z" "%D"
```

> `%N` = 种子名称，`%Z` = 文件大小（字节），`%D` = 保存路径

#### 4.4.5 预期效果

当种子下载完成时，你将在 Telegram 收到：

```
🎉 Seedbox 下载完成

🎬 名称：[FLsnow][Star-Detective_Precure][20][1080p]
💾 大小：977 MB
📁 路径：/home/yourname/downloads/anime/07-名侦探光之美少女
```

### 4.5 部署零信任隧道

利用 Cloudflare Tunnel 实现无端口的隐蔽内网穿透

#### 4.5.1 在云端创建隧道

1. 登录你的 Cloudflare 账号，进入 **Zero Trust** 面板
2. 在左侧菜单找到 **Networks (网络)** -> **Tunnels (隧道)**
3. 点击 **Add a tunnel (添加隧道)**
4. 选择 **Cloudflared**，点击 Next
5. 给它起个名字（比如 `Seedbox-Main`），点击 Save tunnel

#### 4.5.2 在 Seedbox 上安装连接器

1. 在面板的下一步里，选择环境为 **Debian** -> **64-bit**
2. 下面会生成一个超级长的安装命令（貌似共三个命令），大概长这样：
`sudo cloudflared service install eyJhIjoi...（一长串 Token）...`
3. 把这整些命令复制到 Seedbox 的 SSH 终端里运行逐个执行即可
4. 运行完毕后，CF 网页端底部会弹出一个绿色的 `Connected`（已连接）状态，点击 Next

#### 4.5.3 在网页端配置 SSH 路由

* **Subdomain (子域名):** 填入 `seedbox-ssh`
* **Domain (域名):** 下拉选择你的 `yourdomain.com`
* **Path (路径):** 留空
* **Type (服务类型):** 下拉选择 `SSH`
* **URL:** 填入 `localhost:你的非标 SSH 端口` (比如 `localhost:43210`)

点击 **Save tunnel**即可


#### 4.5.4 增加 SSH 配置块

依然是打开 Windows 的 `~/.ssh/config`，加入这段：

```powershell
notepad $HOME/.ssh/config 
```

```text
Host seedbox-cf
    HostName seedbox-ssh.yourdomain.com
    User yourname
    IdentityFile ~/.ssh/id_ed25519_seedbox
    IdentitiesOnly yes
    ProxyCommand cloudflared access ssh --hostname %h
```

下次可以使用 `ssh seedbox-cf` 通过隧道访问 SSH

至此，Seedbox 部署完毕

## 附：qBEE 参考配置

适用于 2GB RAM VPS 的保守配置，以下为本人实际使用参数，请根据自身情况调整，**切勿照抄**

> 本人 VPS 带宽 10 Gbps，位于美西洛杉矶
> 
> 长时间占用上传通道可能给邻居或宿主机带来负担，违反 TOS 导致封号
> 
> 再加上 US 并非版权宽松地区，低调限速以规避部分投诉风险

### 限速

- 全局上传限速：500 Mbps
- 启用备用限速
  - 备用限速时段：16:00 – 02:00 (UTC+8)
  - 备用上传速度：80 Mbps
  - 备用下载速度：300 Mbps

### 连接数

- 全局最大连接数：300
- 单种最大连接数：50
- 全局上传槽：30
- 单种上传槽：5

### 队列

- 活动下载：3
- 活动上传：5
- 活动总数：10
- 启用种子队列：开

### 做种限制

- 分享率达到：1.5
- 做种时间达到：7200 分钟
- 非活跃做种时间达到：7200 分钟

当`分享率 ≥1.5` 或 `做种满 5 天` 或 `非活跃 5 天后` 自动移除

### BitTorrent

- DHT：开
- PeX：开
- LSD：关
- 加密模式：优先加密

### 高级 — 内存

- RAM 使用限制：384 MiB

### 高级 — 线程

- 异步 I/O 线程：2
- 哈希校验线程：1

### 高级 — 磁盘

- 文件池大小：50
- 校验时内存增量：32 MiB
- 预分配文件：关
- 磁盘缓存：64 MiB
- 磁盘缓存过期时间：60 秒
- 磁盘队列大小：1024 KiB
- 读缓存模式：启用系统缓存
- 写缓存模式：启用系统缓存

### 高级 — 网络与 Peer

- 每秒传出连接数：10
- Socket Backlog：30
- μTP-TCP 混合模式：优先使用 TCP
- 单个 Peer 最大未完成请求：250
- 允许来自同一 IP 的多个连接：关
- 上传连接策略：最快上传

---

## 附：端口速查

| 端口  | 协议     | 用途               | 在何处配置                 |
| ----- | -------- | ------------------ | -------------------------- |
| 43210 | TCP      | SSH                | `sshd_config` / 防火墙脚本 |
| 80    | TCP      | HTTP（Caddy 反代） | 防火墙脚本                 |
| 443   | TCP      | HTTPS（Caddy）     | Caddy 自动 / 防火墙脚本    |
| 8080  | TCP      | qBEE WebUI         | qBittorrent 默认           |
| 54321 | TCP/UDP  | BT 监听             | qBittorrent / 防火墙脚本   |
| 9898  | TCP      | PBH WebUI          | PBH 默认                   |
| 5244  | TCP      | OpenList WebUI     | OpenList 默认              |