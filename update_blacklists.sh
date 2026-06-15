#!/bin/bash
# ============================================================================
# 更新 ASN & P2P 黑名单
#
# 使用方式：
#   首次：sudo ./update_blacklists.sh
#   定期：sudo crontab -e
#         0 4 * * 0 /usr/local/bin/update_blacklists.sh > /var/log/blacklist-update.log 2>&1
# ============================================================================

# ===================== 用户配置区（与 deploy_firewall.sh 保持一致） =====================

# 需要屏蔽的 ASN
ASNS=(
    "14061|DigitalOcean"
    "16509|AWS"
    "15169|Google_Cloud"
    "8075|Azure"
    "20473|Vultr"
    "31898|Oracle"
)

# P2P 黑名单数据源
declare -A P2P_SOURCES=(
    ["Naunter_Mega"]="https://raw.githubusercontent.com/Naunter/BT_BlockLists/master/bt_blocklists.gz"
    ["mxdpeep_Comprehensive"]="https://raw.githubusercontent.com/mxdpeep/p2p-blocklist-creator/master/blocklist.p2p"
    ["eMule_Security"]="http://upd.emule-security.org/ipfilter.zip"
)

# 缓存目录
CACHE_DIR="/var/lib/seedbox-firewall"


export PATH="/usr/sbin:/sbin:$PATH"
set -o pipefail

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
ln()   { echo "------------------------------"; }
fmt()  { printf "%'d" "$1"; }

# 检查 IPv6
check_v6() {
    if [ -f /proc/net/if_inet6 ] && [ "$(wc -l < /proc/net/if_inet6)" -gt 0 ]; then
        command -v ip6tables &>/dev/null && echo 1 || echo 0
    else
        echo 0
    fi
}

# 依赖检查
check_deps() {
    local missing=()
    for cmd in curl gunzip awk python3 ipset whois md5sum sha256sum; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        die "Missing: ${missing[*]}. Run: apt install -y curl gzip gawk python3 ipset iproute2 whois"
    fi

    # 检查 ipsets 是否存在
    if ! ipset list bad_asn_v4 &>/dev/null || ! ipset list bad_p2p_v4 &>/dev/null; then
        die "ipsets not found. Run deploy_firewall.sh first."
    fi
}

# ===================== 缓存函数 =====================

init_cache() {
    mkdir -p "$CACHE_DIR" 2>/dev/null || { die "Cannot create $CACHE_DIR"; }
}

get_cached_hash() {
    local name="$1"
    local hashfile="${CACHE_DIR}/${name}.sha256"
    [ -f "$hashfile" ] && cat "$hashfile" || echo ""
}

set_cached_hash() {
    local name="$1" hash="$2"
    echo "$hash" > "${CACHE_DIR}/${name}.sha256"
}

is_changed() {
    local name="$1" cidr_file="$2"
    if [ ! -s "$cidr_file" ]; then
        return 0  # 空文件视为有变化（或错误）
    fi
    local new_hash=$(sha256sum "$cidr_file" | awk '{print $1}')
    local old_hash=$(get_cached_hash "$name")
    if [ "$new_hash" = "$old_hash" ] && [ -n "$old_hash" ]; then
        return 1  # 未变化
    fi
    return 0  # 有变化
}

update_cache() {
    local name="$1" cidr_file="$2"
    local new_hash=$(sha256sum "$cidr_file" | awk '{print $1}')
    set_cached_hash "$name" "$new_hash"
}

# ===================== ASN 更新 =====================

update_asn() {
    log "Fetching ASN routes from RADb..."

    local work="/tmp/asn-update-$$"
    mkdir -p "$work"
    local v4_cidr="${CACHE_DIR}/asn_v4.cidr"
    local v6_cidr="${CACHE_DIR}/asn_v6.cidr"
    local v4_tmp="${work}/asn_v4.cidr"
    local v6_tmp="${work}/asn_v6.cidr"

    true > "$v4_tmp"
    [ "$HAS_V6" = "1" ] && true > "$v6_tmp"

    local v4_total=0 v6_total=0

    for ITEM in "${ASNS[@]}"; do
        ASN="${ITEM%%|*}"
        NAME="${ITEM##*|}"

        local whois_out="${work}/whois_${ASN}.txt"
        if ! timeout 20 whois -h whois.radb.net -- "-i origin AS${ASN}" > "$whois_out" 2>/dev/null; then
            warn "AS${ASN} ${NAME}: whois timeout or failed"
            rm -f "$whois_out"
            continue
        fi

        # 提取 v4 路由
        local v4_count=$(awk '/^route:/ {print $2}' "$whois_out" | grep -v '^$' | tee -a "$v4_tmp" | wc -l)
        v4_total=$((v4_total + v4_count))

        if [ "$HAS_V6" = "1" ]; then
            local v6_count=$(awk '/^route6:/ {print $2}' "$whois_out" | grep -v '^$' | tee -a "$v6_tmp" | wc -l)
            v6_total=$((v6_total + v6_count))
        fi

        log "  AS${ASN} ${NAME}: v4=${v4_count} v6=${HAS_V6:+"$v6_count"}"
        rm -f "$whois_out"
    done

    # 更新 v4
    local v4_updated=0
    if [ "$v4_total" -lt 50 ]; then
        warn "ASN v4 too few entries ($v4_total), keeping existing set"
    elif is_changed "asn_v4" "$v4_tmp"; then
        log "ASN v4 changed, swapping ipset..."
        local new_set="bad_asn_v4_new"
        ipset create "$new_set" hash:net family inet hashsize 4096 maxelem 500000 -exist 2>/dev/null
        {
            echo "create $new_set hash:net family inet hashsize 4096 maxelem 500000 -exist"
            awk '{print "add '"$new_set"' " $0}' "$v4_tmp"
        } | ipset restore -exist 2>/dev/null
        ipset swap "$new_set" bad_asn_v4
        ipset destroy "$new_set" 2>/dev/null
        cp "$v4_tmp" "$v4_cidr"
        update_cache "asn_v4" "$v4_tmp"
        v4_updated=1
        ok "ASN v4 updated: $(fmt $(wc -l < "$v4_cidr")) entries"
    else
        ok "ASN v4 unchanged ($(fmt $v4_total) entries), skipped"
    fi

    # 更新 v6
    if [ "$HAS_V6" = "1" ]; then
        if [ "$v6_total" -lt 50 ]; then
            warn "ASN v6 too few entries ($v6_total), keeping existing set"
        elif is_changed "asn_v6" "$v6_tmp"; then
            log "ASN v6 changed, swapping ipset..."
            local new_set="bad_asn_v6_new"
            ipset create "$new_set" hash:net family inet6 hashsize 4096 maxelem 500000 -exist 2>/dev/null
            {
                echo "create $new_set hash:net family inet6 hashsize 4096 maxelem 500000 -exist"
                awk '{print "add '"$new_set"' " $0}' "$v6_tmp"
            } | ipset restore -exist 2>/dev/null
            ipset swap "$new_set" bad_asn_v6
            ipset destroy "$new_set" 2>/dev/null
            cp "$v6_tmp" "$v6_cidr"
            update_cache "asn_v6" "$v6_tmp"
            ok "ASN v6 updated: $(fmt $(wc -l < "$v6_cidr")) entries"
        else
            ok "ASN v6 unchanged ($(fmt $v6_total) entries), skipped"
        fi
    fi

    rm -rf "$work"
}

# ===================== P2P 更新 =====================

download_p2p_source() {
    local name="$1" url="$2" out="$3"
    printf "  %-25s " "${name}..."

    if ! curl -sL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 \
        "$url" -o "$out"; then
        echo -e "${RED}FAIL${NC}"
        return 1
    fi

    # Auto-detect compression and decompress
    if command -v file &>/dev/null; then
        if file "$out" | grep -q "gzip compressed"; then
            mv "$out" "${out}.gz"
            gunzip -c "${out}.gz" > "$out" 2>/dev/null
            rm -f "${out}.gz"
        elif file "$out" | grep -q "Zip archive"; then
            mv "$out" "${out}.zip"
            unzip -p "${out}.zip" > "$out" 2>/dev/null
            rm -f "${out}.zip"
        fi
    fi

    if [ -s "$out" ]; then
        echo -e "${GREEN}OK${NC} ($(fmt $(wc -l < "$out")) lines)"
        return 0
    fi

    echo -e "${RED}FAIL${NC}"
    return 1
}

update_p2p() {
    log "Fetching P2P blocklists..."

    local work="/tmp/p2p-update-$$"
    mkdir -p "$work/cache"
    local raw="${work}/raw.tmp"
    local cidr_out="${CACHE_DIR}/p2p_v4.cidr"
    local cidr_tmp="${work}/p2p_v4.cidr"

    > "$raw"

    local ok_count=0 fail_count=0
    for name in "${!P2P_SOURCES[@]}"; do
        local url="${P2P_SOURCES[$name]}"
        local cache_file="${work}/cache/$(echo "$url" | md5sum | cut -d' ' -f1).dat"
        if download_p2p_source "$name" "$url" "$cache_file"; then
            cat "$cache_file" >> "$raw"
            ((ok_count++))
        else
            ((fail_count++))
        fi
    done

    if [ "$ok_count" -eq 0 ]; then
        err "All P2P sources failed, keeping existing ipset"
        rm -rf "$work"
        return 1
    fi

    log "P2P raw lines: $(fmt $(wc -l < "$raw")) | ${ok_count} OK, ${fail_count} failed"

    # 解析 IP 范围（支持 range 和 CIDR 格式）
    local processed="${work}/processed.tmp"
    awk '
    function ip2dec(ip) {
        split(ip, a, ".")
        return (a[1]*16777216) + (a[2]*65536) + (a[3]*256) + a[4]
    }
    {
        name = "P2P"; content = $0
        if ($0 ~ /^[A-Za-z0-9_]+:/) {
            split($0, p, ":")
            name = p[1]; content = p[2]
        }
        # IP-range: 1.2.3.4-5.6.7.8
        if (match(content, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            split(substr(content, RSTART, RLENGTH), ips, "-")
            s = ip2dec(ips[1]); e = ip2dec(ips[2])
            if (s <= e) print name "," s "," e
        }
        # CIDR: 1.2.3.0/24
        else if (match(content, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+/)) {
            split(substr(content, RSTART, RLENGTH), parts, "/")
            s = ip2dec(parts[1])
            e = s + (2 ^ (32 - parts[2])) - 1
            print name "," s "," e
        }
    }' "$raw" | sort -t',' -k1,1 -k2,2n > "$processed"

    local range_count=$(wc -l < "$processed")

    # 合并连续范围，转换为 CIDR
    awk -F',' '
    function dec2ip(d) {
        return sprintf("%d.%d.%d.%d",
            d/16777216%256, d/65536%256, d/256%256, d%256)
    }
    NR==1 { n=$1; s=$2; e=$3; next }
    $1==n && $2<=e+1 { if($3>e) e=$3; next }
    { printf "%s %s\n", dec2ip(s), dec2ip(e); n=$1; s=$2; e=$3 }
    END { if(NR>0) printf "%s %s\n", dec2ip(s), dec2ip(e) }
    ' "$processed" | sort -u | python3 -c "
import sys, ipaddress
for line in sys.stdin:
    start, end = line.strip().split()
    for net in ipaddress.summarize_address_range(
        ipaddress.IPv4Address(start), ipaddress.IPv4Address(end)
    ):
        print(net)
" > "$cidr_tmp"

    local final_count=$(wc -l < "$cidr_tmp")
    local savings=$((range_count - final_count))
    local pct=$((range_count > 0 ? (savings * 100 / range_count) : 0))
    log "P2P merged: $(fmt $final_count) CIDR entries (${pct}% reduction)"

    # 缓存检查 + 原子更新
    if is_changed "p2p_v4" "$cidr_tmp"; then
        log "P2P data changed, swapping ipset..."
        local new_set="bad_p2p_v4_new"
        ipset create "$new_set" hash:net family inet hashsize 65536 maxelem 1000000 -exist 2>/dev/null
        {
            echo "create $new_set hash:net family inet hashsize 65536 maxelem 1000000 -exist"
            awk '{print "add '"$new_set"' " $0}' "$cidr_tmp"
        } | ipset restore -exist 2>/dev/null
        ipset swap "$new_set" bad_p2p_v4
        ipset destroy "$new_set" 2>/dev/null
        cp "$cidr_tmp" "$cidr_out"
        update_cache "p2p_v4" "$cidr_tmp"
        ok "P2P v4 updated: $(fmt $final_count) entries"
    else
        ok "P2P v4 unchanged ($(fmt $final_count) entries), skipped"
    fi

    rm -rf "$work"
}

# ===================== 打印统计 =====================

print_summary() {
    echo ""
    ln
    local asn_v4=$(ipset list bad_asn_v4 2>/dev/null | grep "Number of entries" | awk '{print $NF}')
    local p2p_v4=$(ipset list bad_p2p_v4 2>/dev/null | grep "Number of entries" | awk '{print $NF}')
    echo "  ASN v4:  ${asn_v4:-0} entries"
    echo "  P2P v4:  ${p2p_v4:-0} entries"
    if [ "$HAS_V6" = "1" ]; then
        local asn_v6=$(ipset list bad_asn_v6 2>/dev/null | grep "Number of entries" | awk '{print $NF}')
        echo "  ASN v6:  ${asn_v6:-0} entries"
    fi
    ln
}

# ===================== 主流程 =====================

main() {
    if [ "$(id -u)" != "0" ]; then
        die "This script must be run as root"
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}  Blacklist Update${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    HAS_V6=$(check_v6)
    [ "$HAS_V6" = "1" ] && ok "IPv6 enabled" || warn "IPv6 disabled"

    check_deps
    init_cache

    echo ""
    log "Updating ASN blacklists..."
    update_asn

    echo ""
    log "Updating P2P blacklists..."
    update_p2p

    print_summary

    echo -e "${GREEN}Blacklist update complete.${NC}"
    echo ""
}

main "$@"
