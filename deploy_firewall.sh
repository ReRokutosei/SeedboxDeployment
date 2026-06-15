#!/bin/bash
# ============================================================================
# 部署防火墙规则，本脚本只需执行一次
#
# 修改配置后重新执行即可，脚本会自动覆盖旧规则
# ============================================================================

# ===================== 用户配置区 =====================

SSH_PORT=43210

# BT 监听端口（TCP 与 UDP 通常相同）
BT_TCP_PORT=54321
BT_UDP_PORT=54321

# 额外放行的 Web 端口（80 已默认放行，443 由黑名单逻辑单独处理）
# 如需放行其他端口请在此添加
WEB_PORTS=(80)

# 是否启用 IPv6（1=启用，0=禁用）
ENABLE_IPV6=1

# 邻居网段阻断（针对 443 端口，设为 "-" 表示不启用）
# 示例: NEIGHBOR_V4="10.0.0.0/8"
NEIGHBOR_V4="-"
NEIGHBOR_V6="-"

# 需要屏蔽的 ASN（云厂商）
# 格式: "ASN|名称"
ASNS=(
    "14061|DigitalOcean"
    "16509|AWS"
    "15169|Google_Cloud"
    "8075|Azure"
    "20473|Vultr"
    "31898|Oracle"
)


export PATH="/usr/sbin:/sbin:$PATH"

# ===================== 日志与颜色 =====================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERR]${NC}   $1"; }
die()  { err "$1"; exit 1; }

# 检查 IPv6
check_v6() {
    if [ "$ENABLE_IPV6" != "1" ]; then echo 0; return; fi
    if [ -f /proc/net/if_inet6 ] && [ "$(wc -l < /proc/net/if_inet6)" -gt 0 ]; then
        command -v ip6tables &>/dev/null && echo 1 || echo 0
    else
        echo 0
    fi
}

# 依赖检查
check_deps() {
    local missing=()
    for cmd in ipset iptables; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        err "Run: apt install -y ipset iptables"
        exit 1
    fi
    ok "Dependencies satisfied"

    if [ "$HAS_V6" = "1" ] && ! command -v ip6tables &>/dev/null; then
        warn "ip6tables not found, disabling IPv6"
        HAS_V6=0
    fi
}

# 安装 iptables-persistent（如果未安装）
install_persistent() {
    if dpkg -l iptables-persistent 2>/dev/null | grep -q '^ii'; then
        return 0
    fi
    log "Installing iptables-persistent..."
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true \
        | debconf-set-selections 2>/dev/null
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true \
        | debconf-set-selections 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent &>/dev/null \
        || warn "Could not install iptables-persistent, will fallback to manual save"
}

# 创建 ipset 集合
create_ipsets() {
    ipset create bad_asn_v4 hash:net family inet \
        hashsize 4096 maxelem 500000 -exist 2>/dev/null
    ipset create bad_p2p_v4 hash:net family inet \
        hashsize 65536 maxelem 1000000 -exist 2>/dev/null
    if [ "$HAS_V6" = "1" ]; then
        ipset create bad_asn_v6 hash:net family inet6 \
            hashsize 4096 maxelem 500000 -exist 2>/dev/null
    fi
    ok "ipset collections created"
}

# 部署 iptables 规则
deploy_v4() {
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -F
    iptables -X

    # 基础放行
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT

    # SSH
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    ok "Allow TCP port $SSH_PORT (SSH)"

    # Web
    for port in "${WEB_PORTS[@]}"; do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        ok "Allow TCP port $port (Web)"
    done

    # BT
    iptables -A INPUT -p tcp --dport "$BT_TCP_PORT" -j ACCEPT
    ok "Allow TCP port $BT_TCP_PORT (BT)"
    iptables -A INPUT -p udp --dport "$BT_UDP_PORT" -j ACCEPT
    ok "Allow UDP port $BT_UDP_PORT (BT DHT)"

    # 邻居阻断
    if [ "$NEIGHBOR_V4" != "-" ]; then
        iptables -A INPUT -p tcp --dport 443 -s "$NEIGHBOR_V4" -j DROP
        ok "Neighbor v4 blocked: $NEIGHBOR_V4 (port 443)"
    fi

    # 443: 先 DROP 黑名单，最后 ACCEPT
    iptables -A INPUT -p tcp --dport 443 -m set --match-set bad_asn_v4 src -j DROP
    iptables -A INPUT -p tcp --dport 443 -m set --match-set bad_p2p_v4 src -j DROP

    # 最终放行 443
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    ok "HTTPS rule: DROP(ASN) -> DROP(P2P) -> ACCEPT"
}

# 部署 ip6tables 规则
deploy_v6() {
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT

    ip6tables -F
    ip6tables -X

    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -i lo -j ACCEPT

    ip6tables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    for port in "${WEB_PORTS[@]}"; do
        ip6tables -A INPUT -p tcp --dport "$port" -j ACCEPT
    done

    ip6tables -A INPUT -p tcp --dport "$BT_TCP_PORT" -j ACCEPT
    ip6tables -A INPUT -p udp --dport "$BT_UDP_PORT" -j ACCEPT

    if [ "$NEIGHBOR_V6" != "-" ]; then
        ip6tables -A INPUT -p tcp --dport 443 -s "$NEIGHBOR_V6" -j DROP
        ok "Neighbor v6 blocked: $NEIGHBOR_V6 (port 443)"
    fi

    ip6tables -A INPUT -p tcp --dport 443 -m set --match-set bad_asn_v6 src -j DROP
    ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
    ok "IPv6 HTTPS rule: DROP(ASN) -> ACCEPT"
}

# 持久化
persist() {
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null
        ok "Rules saved via netfilter-persistent"
    else
        mkdir -p /etc/iptables
        ipset save > /etc/iptables/ipsets 2>/dev/null
        iptables-save > /etc/iptables/rules.v4
        [ "$HAS_V6" = "1" ] && ip6tables-save > /etc/iptables/rules.v6
        ok "Rules saved to /etc/iptables/"
        warn "Consider installing iptables-persistent for automatic restore on boot"
    fi
}

# 打印当前规则
print_rules() {
    echo ""
    echo -e "${CYAN}=== IPv4 INPUT Rules ===${NC}"
    iptables -L INPUT -v -n --line-numbers 2>/dev/null | head -20
    if [ "$HAS_V6" = "1" ]; then
        echo ""
        echo -e "${CYAN}=== IPv6 INPUT Rules ===${NC}"
        ip6tables -L INPUT -v -n --line-numbers 2>/dev/null | head -15
    fi
}

# 主流程
main() {
    if [ "$(id -u)" != "0" ]; then
        die "This script must be run as root"
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}  Firewall Deployment (One-Time Setup)${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    HAS_V6=$(check_v6)
    [ "$HAS_V6" = "1" ] && ok "IPv6 enabled" || warn "IPv6 disabled"

    check_deps
    create_ipsets

    echo ""
    log "Deploying IPv4 rules..."
    deploy_v4

    if [ "$HAS_V6" = "1" ]; then
        echo ""
        log "Deploying IPv6 rules..."
        deploy_v6
    fi

    echo ""
    log "Persisting rules..."
    install_persistent
    persist

    print_rules

    echo ""
    echo -e "${GREEN}Firewall deployed.${NC}"
    echo -e "${YELLOW}Next: run update_blacklists.sh to load ASN/P2P blacklists.${NC}"
    echo ""
}

main "$@"
