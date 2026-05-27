#!/bin/sh

set -e

ACTION=""
STACK="v4"

# Feature toggles derived from CLI options during validation.
ENABLE_FAKEIP="0"
ENABLE_FAKEIP_V4="0"
ENABLE_FAKEIP_V6="0"
PROXY_LOCAL="0"
HIJACK_DNS="0"
ENABLE_KERNEL_BYPASS="0"
RP_FILTER="off"

# Local-output loop prevention knobs for --proxy-local.
IGNORE_MARK=""
IGNORE_UID=""

# Optional capture scope and bypass inputs. CSV values are rendered into nft sets.
IN_IFACE=""
BYPASS4=""
BYPASS6=""
LOCAL_ADDR4=""
LOCAL_ADDR6=""
DNS_BYPASS4=""
DNS_BYPASS6=""
LOCAL_TCP_PORTS=""
LOCAL_UDP_PORTS=""
DNS_BYPASS_PORTS="53"

NF_TABLE="transparent_proxy"
TPROXY_PORT="9898"
ROUTE_TABLE4="100"
ROUTE_TABLE6="106"
ROUTE_MARK="0x01"

FAKEIP_V4=""
FAKEIP_V6=""

DRY_RUN="0"
SAVE="0"
SAVE_FILE="./tproxy.nft"

NFT_RULE=""

usage() {
    printf "setup tproxy gateway\n"

    printf 'Usage: %s action [options] \n' "$0"
    printf "\nAction:\n"
    printf '  %-10s %-20s\n' "set" "Setup"
    printf '  %-10s %-20s\n' "unset" "Clean"
    printf "\nOptions (general):\n"
    printf "  %-25s %-20s\n" "--save=<FILE>" "Save nft rule to FILE (default $SAVE_FILE)"
    printf "  %-25s %-20s\n" "--dry-run" "Dry run (default false)"
    printf "  %-25s %-20s\n" "-h, --help" "Show help info"
    printf "\nOptions (tproxy):\n"
    printf "  %-25s %-20s\n" "--stack=v4|v6|all" "Enable ip stack (default $STACK)"
    printf '  %-25s %-20s\n' "--nf-table=<NAME>" "Set nf table name (default $NF_TABLE)"
    printf '  %-25s %-20s\n' "--route-table4=<ID>" "Set ipv4 route table id (default $ROUTE_TABLE4, available when ipv4 enabled)"
    printf '  %-25s %-20s\n' "--route-table6=<ID>" "Set ipv6 route table id (default $ROUTE_TABLE6, available when ipv6 enabled)"
    printf '  %-25s %-20s\n' "--route-mark=<MARK>" "Set route mark (default $ROUTE_MARK)"
    printf '  %-25s %-20s\n' "--tproxy-port=<PORT>" "Set tproxy port (default $TPROXY_PORT)"
    printf '  %-25s %-20s\n' "--proxy-local" "Proxy local traffic (Default false)"
    printf '  %-25s %-20s\n' "--ignore-mark=<MARK>" "Ignore traffic of special mark (available when --proxy-local set)"
    printf '  %-25s %-20s\n' "--ignore-uid=<UID>" "Ignore traffic of special uid (available when --proxy-local set)"
    printf '  %-25s %-20s\n' "--in-iface=<iface[,iface...]>" "Allow-list ingress interfaces"
    printf '  %-25s %-20s\n' "--bypass4=<cidr[,cidr...]>" "Bypass ipv4 CIDRs"
    printf '  %-25s %-20s\n' "--bypass6=<cidr[,cidr...]>" "Bypass ipv6 CIDRs"
    printf '  %-25s %-20s\n' "--local-addr4=<csv>" "Bypass local ipv4 addresses"
    printf '  %-25s %-20s\n' "--local-addr6=<csv>" "Bypass local ipv6 addresses"
    printf '  %-25s %-20s\n' "--dns-bypass4=<csv>" "Bypass local DNS ipv4 addresses"
    printf '  %-25s %-20s\n' "--dns-bypass6=<csv>" "Bypass local DNS ipv6 addresses"
    printf '  %-25s %-20s\n' "--local-tcp-ports=<csv>" "Bypass local TCP ports"
    printf '  %-25s %-20s\n' "--local-udp-ports=<csv>" "Bypass local UDP ports"
    printf '  %-25s %-20s\n' "--dns-bypass-ports=<csv>" "Bypass local DNS ports (default 53)"
    printf '  %-25s %-20s\n' "--rp-filter=off|check|loose|strict|disable" "Set rp_filter policy"
    printf '  %-25s %-20s\n' "--enable-kernel-bypass" "Apply forwarding sysctls"
    printf "\nOptions (fakeip):\n"
    printf '  %-25s %-20s\n' "--fake-ip4=<IPV4>" "Set fakeip ipv4 cidr (available when ipv4 enabled)"
    printf '  %-25s %-20s\n' "--fake-ip6=<IPV6>" "Set fakeip ipv6 cidr (available when ipv6 enabled)"
    printf "\nOptions (dns):\n"
    printf '  %-25s %-20s\n' "--hijack-dns" "Hijack dns (default false)"
    printf "\n"
}

is_integer() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

is_uint_range() {
    value=$1
    min=$2
    max=$3

    is_integer "$value" || return 1
    [ "$value" -ge "$min" ] 2>/dev/null || return 1
    [ "$value" -le "$max" ] 2>/dev/null || return 1
}

is_mark() {
    case "$1" in
        0x[0-9A-Fa-f]*|0X[0-9A-Fa-f]*) ;;
        *[!0-9]*|'') return 1 ;;
        *) ;;
    esac

    mark_dec=$(( $1 )) 2>/dev/null || return 1
    [ "$mark_dec" -ge 0 ] 2>/dev/null || return 1
    [ "$mark_dec" -le 4294967295 ] 2>/dev/null || return 1
}

is_nft_identifier() {
    case "$1" in
        ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;;
        *) return 0 ;;
    esac
}

is_iface_name() {
    case "$1" in
        ''|*[!A-Za-z0-9_.:-]*) return 1 ;;
        *) return 0 ;;
    esac
}

is_ipv4_token() {
    # Lightweight nft token filter for address lists; nft remains final parser.
    case "$1" in
        *.*.*.*|*.*.*.*/*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!0-9./]*) return 1 ;;
    esac
}

is_ipv6_token() {
    # Lightweight nft token filter for address lists; nft remains final parser.
    case "$1" in
        *:*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!0-9A-Fa-f:./%]*) return 1 ;;
    esac
}

csv_to_nft_list() {
    # Convert comma-separated CLI values into nft set syntax elements.
    out=""
    sep=""
    old_ifs=$IFS
    IFS=,
    for item in $1; do
        out=$out$sep$item
        sep=", "
    done
    IFS=$old_ifs
    printf '%s' "$out"
}

validate_csv_with() {
    values=$1
    label=$2
    checker=$3
    old_ifs=$IFS
    IFS=,
    for item in $values; do
        if [ -z "$item" ] || ! $checker "$item"; then
            IFS=$old_ifs
            echo "ERROR: invalid $label: \"$values\""
            usage
            exit 1
        fi
    done
    IFS=$old_ifs
}

csv_contains_exact() {
    values=$1
    needle=$2
    old_ifs=$IFS
    IFS=,
    for item in $values; do
        if [ "$item" = "$needle" ]; then
            IFS=$old_ifs
            return 0
        fi
    done
    IFS=$old_ifs
    return 1
}

validate_ipv4_cidr_csv() { validate_csv_with "$1" "$2" is_ipv4_cidr; }
validate_ipv6_cidr_csv() { validate_csv_with "$1" "$2" is_ipv6_cidr; }
validate_iface_csv() { validate_csv_with "$1" "$2" is_iface_name; }
validate_port_csv() { validate_csv_with "$1" "$2" is_uint_port; }

is_uint_port() {
    is_uint_range "$1" 1 65535
}

validate_ipv4_addr_csv() {
    values=$1
    label=$2
    old_ifs=$IFS
    IFS=,
    for item in $values; do
        case "$item" in
            *.*.*.*|*.*.*.*/*) is_ipv4_token "$item" || { IFS=$old_ifs; echo "ERROR: invalid $label: \"$values\""; usage; exit 1; } ;;
            *) IFS=$old_ifs; echo "ERROR: invalid $label: \"$values\""; usage; exit 1 ;;
        esac
    done
    IFS=$old_ifs
}

validate_ipv6_addr_csv() {
    values=$1
    label=$2
    old_ifs=$IFS
    IFS=,
    for item in $values; do
        is_ipv6_token "$item" || { IFS=$old_ifs; echo "ERROR: invalid $label: \"$values\""; usage; exit 1; }
    done
    IFS=$old_ifs
}

validate_rp_filter() {
    case "$1" in
        off|check|loose|strict|disable) return 0 ;;
        *) return 1 ;;
    esac
}

csv_or_empty() {
    [ -n "$1" ] || return 0
    printf '%s' "$1"
}

is_ipv4_cidr() {
    case "$1" in
        *.*.*.*/*) ;;
        *) return 1 ;;
    esac

    addr=${1%/*}
    prefix=${1#*/}
    is_uint_range "$prefix" 0 32 || return 1

    old_ifs=$IFS
    IFS=.
    set -- $addr
    IFS=$old_ifs
    [ "$#" -eq 4 ] || return 1
    for octet do
        is_uint_range "$octet" 0 255 || return 1
    done
}

is_ipv6_cidr() {
    # 检查是否包含CIDR后缀
    case "$1" in
        */*) ;;
        *) return 1 ;;
    esac

    # 分割IP和CIDR部分
    ip_part="${1%/*}"
    cidr="${1#*/}"

    # 验证CIDR是否为0-128之间的数字
    if ! ( [ "$cidr" -eq "$cidr" ] 2>/dev/null && [ "$cidr" -ge 0 ] && [ "$cidr" -le 128 ] ); then
        return 1
    fi

    # 检查IPv6地址部分的合法性
    case $ip_part in
        # 允许双冒号出现一次，并替换以计算段数
        *::*)
            if [ "$(echo "$ip_part" | tr -cd ':' | wc -c)" -gt 7 ]; then
                return 1  # 超过7个冒号不合法
            fi
            temp=$(echo "$ip_part" | sed 's/::/:/g')  # 替换双冒号为单冒号
            ;;
        *)
            temp="$ip_part"
            ;;
    esac

    # 分割段并检查每段格式
    IFS=':'
    set -- $temp
    IFS=
    segment_count=0
    for seg do
        segment_count=$((segment_count + 1))
        # 空段仅在双冒号处允许
        if [ -z "$seg" ] && [ "$segment_count" -ne 1 ] && [ "$segment_count" -ne $# ]; then
            return 1
        fi
        # 每段必须是1-4位十六进制数
        if ! echo "$seg" | grep -qE '^[0-9a-fA-F]{1,4}$'; then
            return 1
        fi
    done

    # 根据是否包含双冒号验证段数
    case $ip_part in
        *::*)
            if [ $segment_count -gt 8 ]; then
                return 1
            fi
            ;;
        *)
            if [ $segment_count -ne 8 ]; then
                return 1
            fi
            ;;
    esac

    return 0
}

check() {
    # Validate all user input before writing files or touching nft/ip/sysctl.
    if [ -z "$ACTION" ]; then
        echo "ERROR: invalid action"
        usage
        exit 1
    fi

    case $STACK in
        v4|v6|all)
            ;;
        *)
            echo "ERROR: invalid stack: \"$STACK\""
            usage
            exit 1
            ;;
    esac

    # NF_TABLE is emitted unquoted in nft syntax, so keep it identifier-only.
    if ! is_nft_identifier "$NF_TABLE"; then
        echo "ERROR: invalid nf table: \"$NF_TABLE\""
        usage
        exit 1
    fi

    if ! is_uint_range "$ROUTE_TABLE4" 1 4294967295; then
        echo "ERROR: invalid ipv4 route table id: \"$ROUTE_TABLE4\""
        usage
        exit 1
    fi
    if ! is_uint_range "$ROUTE_TABLE6" 1 4294967295; then
        echo "ERROR: invalid ipv6 route table id: \"$ROUTE_TABLE6\""
        usage
        exit 1
    fi

    if ! validate_rp_filter "$RP_FILTER"; then
        echo "ERROR: invalid rp_filter policy: \"$RP_FILTER\""
        usage
        exit 1
    fi

    if [ -n "$IN_IFACE" ]; then
        validate_iface_csv "$IN_IFACE" "in-iface"
    fi
    [ -z "$BYPASS4" ] || validate_ipv4_cidr_csv "$BYPASS4" "bypass4"
    [ -z "$BYPASS6" ] || validate_ipv6_cidr_csv "$BYPASS6" "bypass6"
    [ -z "$LOCAL_ADDR4" ] || validate_ipv4_addr_csv "$LOCAL_ADDR4" "local-addr4"
    [ -z "$LOCAL_ADDR6" ] || validate_ipv6_addr_csv "$LOCAL_ADDR6" "local-addr6"
    [ -z "$DNS_BYPASS4" ] || validate_ipv4_addr_csv "$DNS_BYPASS4" "dns-bypass4"
    [ -z "$DNS_BYPASS6" ] || validate_ipv6_addr_csv "$DNS_BYPASS6" "dns-bypass6"
    [ -z "$LOCAL_TCP_PORTS" ] || validate_port_csv "$LOCAL_TCP_PORTS" "local-tcp-ports"
    [ -z "$LOCAL_UDP_PORTS" ] || validate_port_csv "$LOCAL_UDP_PORTS" "local-udp-ports"
    [ -z "$DNS_BYPASS_PORTS" ] || validate_port_csv "$DNS_BYPASS_PORTS" "dns-bypass-ports"

    if [ -n "$FAKEIP_V4" ]; then
        if is_ipv4_cidr "$FAKEIP_V4"; then
            case $STACK in
                v4|all)
                    ENABLE_FAKEIP_V4="1"
                    ENABLE_FAKEIP="1"
                    ;;
            esac
        else
            echo "ERROR: invalid fakeip v4 cidr: \"$FAKEIP_V4\""
            usage
            exit 1
        fi
    fi

    if [ "$PROXY_LOCAL" = "1" ] && [ -n "$IGNORE_MARK" ] && [ "$IGNORE_MARK" = "$ROUTE_MARK" ]; then
        echo "ERROR: --proxy-local conflicts with ignore-mark equal to route-mark"
        usage
        exit 1
    fi

    if [ -n "$FAKEIP_V4" ] && [ -n "$BYPASS4" ] && csv_contains_exact "$BYPASS4" "$FAKEIP_V4"; then
        echo "ERROR: fakeip v4 conflicts with bypass4"
        usage
        exit 1
    fi
    if [ -n "$FAKEIP_V6" ] && [ -n "$BYPASS6" ] && csv_contains_exact "$BYPASS6" "$FAKEIP_V6"; then
        echo "ERROR: fakeip v6 conflicts with bypass6"
        usage
        exit 1
    fi

    if [ -n "$FAKEIP_V6" ]; then
        if is_ipv6_cidr "$FAKEIP_V6"; then
            case $STACK in
                v6|all)
                    ENABLE_FAKEIP_V6="1"
                    ENABLE_FAKEIP="1"
                    ;;
            esac
        else
            echo "ERROR: invalid fakeip v6 cidr: \"$FAKEIP_V6\""
            usage
            exit 1
        fi
    fi

    # ROUTE_MARK is a valid uint32 mark in decimal or hex.
    if ! is_mark "$ROUTE_MARK"; then
        echo "ERROR: invalid route mark: \"$ROUTE_MARK\""
        usage
        exit 1
    fi

    # TPROXY_PORT is a valid TCP/UDP port.
    if ! is_uint_range "$TPROXY_PORT" 1 65535; then
        echo "ERROR: invalid tproxy port: \"$TPROXY_PORT\""
        usage
        exit 1
    fi

    # Local output proxying must exclude the proxy process to avoid loops.
    if [ "$PROXY_LOCAL" = "1" ]; then
        if [ -z "$IGNORE_MARK" ] && [ -z "$IGNORE_UID" ]; then
            echo "ERROR: --proxy-local requires --ignore-mark or --ignore-uid to avoid local proxy loops"
            usage
            exit 1
        fi
        if [ -n "$IGNORE_MARK" ] && ! is_mark "$IGNORE_MARK"; then
            echo "ERROR: invalid ignore mark: \"$IGNORE_MARK\""
            usage
            exit 1
        fi
        if [ -n "$IGNORE_UID" ] && ! is_uint_range "$IGNORE_UID" 0 4294967295; then
            echo "ERROR: invalid ignore uid: \"$IGNORE_UID\""
            usage
            exit 1
        fi
    fi
    
}

while [ "$1" != "" ]; do
    PARAM=$(echo "$1" | awk -F= '{print $1}')
    VALUE=$(echo "$1" | awk -F= '{print $2}')
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        set)
            ACTION="set"
            ;;
        unset)
            ACTION="unset"
            ;;
        --stack)
            STACK=$VALUE
            ;;
        --nf-table)
            NF_TABLE=$VALUE
            ;;
        --route-table4)
            ROUTE_TABLE4=$VALUE
            ;;
        --route-table6)
            ROUTE_TABLE6=$VALUE
            ;;
        --route-mark)
            ROUTE_MARK=$VALUE
            ;;
        --tproxy-port)
            TPROXY_PORT=$VALUE
            ;;
        --proxy-local)
            PROXY_LOCAL="1"
            ;;
        --in-iface)
            IN_IFACE=$VALUE
            ;;
        --bypass4)
            BYPASS4=$VALUE
            ;;
        --bypass6)
            BYPASS6=$VALUE
            ;;
        --local-addr4)
            LOCAL_ADDR4=$VALUE
            ;;
        --local-addr6)
            LOCAL_ADDR6=$VALUE
            ;;
        --dns-bypass4)
            DNS_BYPASS4=$VALUE
            ;;
        --dns-bypass6)
            DNS_BYPASS6=$VALUE
            ;;
        --local-tcp-ports)
            LOCAL_TCP_PORTS=$VALUE
            ;;
        --local-udp-ports)
            LOCAL_UDP_PORTS=$VALUE
            ;;
        --dns-bypass-ports)
            DNS_BYPASS_PORTS=$VALUE
            ;;
        --rp-filter)
            RP_FILTER=$VALUE
            ;;
        --enable-kernel-bypass)
            ENABLE_KERNEL_BYPASS="1"
            ;;
        --ignore-mark)
            IGNORE_MARK=$VALUE
            ;;
        --ignore-uid)
            IGNORE_UID=$VALUE
            ;;
        --fake-ip4)
            FAKEIP_V4=$VALUE
            ;;
        --fake-ip6)
            FAKEIP_V6=$VALUE
            ;;
        --hijack-dns)
            HIJACK_DNS="1"
            ;;
        --save)
            if [ -n "$VALUE" ]; then
                SAVE_FILE=$VALUE
            fi
            SAVE="1"
            ;;
        --dry-run)
            DRY_RUN="1"
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done
check



gen_nft_rule() {
    # Build a deterministic policy pipeline:
    # scope -> non-TCP/UDP/local bypass -> FakeIP -> DNS hijack -> bypass -> TPROXY.
    SCOPE_GUARD=""
    LOCAL_BYPASS_RULES=""
    BYPASS_RULES=""
    DNS_PRE=""
    DNS_CHAIN=""
    OUTPUT_PRE_RULES=""
    OUTPUT_DNS_RULES=""

    TPROXY_V4_RULE=""
    TPROXY_V6_RULE=""

    case $STACK in
        v4|all)
            TPROXY_V4_RULE="meta nfproto ipv4 meta l4proto { tcp, udp } meta mark set $ROUTE_MARK tproxy ip to :$TPROXY_PORT counter accept"
            ;;
    esac
    case $STACK in
        v6|all)
            TPROXY_V6_RULE="meta nfproto ipv6 meta l4proto { tcp, udp } meta mark set $ROUTE_MARK tproxy ip6 to :$TPROXY_PORT counter accept"
            ;;
    esac

    if [ -n "$IN_IFACE" ]; then
        # Allow-list mode: packets from non-selected interfaces leave untouched.
        SCOPE_GUARD="iifname != { $(csv_to_nft_list "$IN_IFACE") } counter accept comment \"ingress scope\""
    fi

    # Local service and infrastructure bypasses are shared by prerouting and output.
    if [ -n "$LOCAL_ADDR4" ]; then
        LOCAL_BYPASS_RULES=$LOCAL_BYPASS_RULES"
            meta nfproto ipv4 ip daddr { $(csv_to_nft_list "$LOCAL_ADDR4") } counter accept comment \"local IPv4\""
        OUTPUT_PRE_RULES=$OUTPUT_PRE_RULES"
            meta nfproto ipv4 ip daddr { $(csv_to_nft_list "$LOCAL_ADDR4") } counter accept comment \"local IPv4\""
    fi
    if [ -n "$LOCAL_ADDR6" ]; then
        LOCAL_BYPASS_RULES=$LOCAL_BYPASS_RULES"
            meta nfproto ipv6 ip6 daddr { $(csv_to_nft_list "$LOCAL_ADDR6") } counter accept comment \"local IPv6\""
        OUTPUT_PRE_RULES=$OUTPUT_PRE_RULES"
            meta nfproto ipv6 ip6 daddr { $(csv_to_nft_list "$LOCAL_ADDR6") } counter accept comment \"local IPv6\""
    fi
    if [ -n "$LOCAL_TCP_PORTS" ]; then
        LOCAL_BYPASS_RULES=$LOCAL_BYPASS_RULES"
            meta l4proto tcp th dport { $(csv_to_nft_list "$LOCAL_TCP_PORTS") } counter accept comment \"local TCP\""
        OUTPUT_PRE_RULES=$OUTPUT_PRE_RULES"
            meta l4proto tcp th dport { $(csv_to_nft_list "$LOCAL_TCP_PORTS") } counter accept comment \"local TCP\""
    fi
    if [ -n "$LOCAL_UDP_PORTS" ]; then
        LOCAL_BYPASS_RULES=$LOCAL_BYPASS_RULES"
            meta l4proto udp th dport { $(csv_to_nft_list "$LOCAL_UDP_PORTS") } counter accept comment \"local UDP\""
        OUTPUT_PRE_RULES=$OUTPUT_PRE_RULES"
            meta l4proto udp th dport { $(csv_to_nft_list "$LOCAL_UDP_PORTS") } counter accept comment \"local UDP\""
    fi
    if [ -n "$DNS_BYPASS4" ]; then
        LOCAL_BYPASS_RULES=$LOCAL_BYPASS_RULES"
            meta nfproto ipv4 ip daddr { $(csv_to_nft_list "$DNS_BYPASS4") } counter accept comment \"dns bypass IPv4\""
        OUTPUT_PRE_RULES=$OUTPUT_PRE_RULES"
            meta nfproto ipv4 ip daddr { $(csv_to_nft_list "$DNS_BYPASS4") } counter accept comment \"dns bypass IPv4\""
    fi
    if [ -n "$DNS_BYPASS6" ]; then
        LOCAL_BYPASS_RULES=$LOCAL_BYPASS_RULES"
            meta nfproto ipv6 ip6 daddr { $(csv_to_nft_list "$DNS_BYPASS6") } counter accept comment \"dns bypass IPv6\""
        OUTPUT_PRE_RULES=$OUTPUT_PRE_RULES"
            meta nfproto ipv6 ip6 daddr { $(csv_to_nft_list "$DNS_BYPASS6") } counter accept comment \"dns bypass IPv6\""
    fi

    case $STACK in
        v4|all)
            # Private/reserved ranges stay after FakeIP so 198.18.0.0/15 can be proxied.
            BYPASS_RULES=$BYPASS_RULES"
            meta nfproto ipv4 ip daddr @private counter accept comment \"private IPv4\""
            ;;
    esac
    case $STACK in
        v6|all)
            BYPASS_RULES=$BYPASS_RULES"
            meta nfproto ipv6 ip6 daddr @private6 counter accept comment \"private IPv6\""
            ;;
    esac
    if [ -n "$BYPASS4" ]; then
        BYPASS_RULES=$BYPASS_RULES"
            meta nfproto ipv4 ip daddr { $(csv_to_nft_list "$BYPASS4") } counter accept comment \"custom bypass IPv4\""
    fi
    if [ -n "$BYPASS6" ]; then
        BYPASS_RULES=$BYPASS_RULES"
            meta nfproto ipv6 ip6 daddr { $(csv_to_nft_list "$BYPASS6") } counter accept comment \"custom bypass IPv6\""
    fi

    if [ "$HIJACK_DNS" = "1" ]; then
        # DNS hijack is intentionally late; local/DNS bypass rules are emitted first.
        DNS_PRE="jump dns comment \"route dns\""
        DNS_PRE_V4_CHAIN=""
        DNS_PRE_V6_CHAIN=""
        case $STACK in
            v4|all)
                DNS_PRE_V4_CHAIN="meta nfproto ipv4 meta l4proto { tcp, udp } th dport { $(csv_to_nft_list "$DNS_BYPASS_PORTS") } meta mark set $ROUTE_MARK tproxy ip to :$TPROXY_PORT counter accept"
                ;;
        esac
        case $STACK in
            v6|all)
                DNS_PRE_V6_CHAIN="meta nfproto ipv6 meta l4proto { tcp, udp } th dport { $(csv_to_nft_list "$DNS_BYPASS_PORTS") } meta mark set $ROUTE_MARK tproxy ip6 to :$TPROXY_PORT counter accept"
                ;;
        esac
        DNS_CHAIN="chain dns {
            $DNS_PRE_V4_CHAIN
            $DNS_PRE_V6_CHAIN
        }
"
        if [ "$PROXY_LOCAL" = "1" ]; then
            OUTPUT_DNS_RULES="jump reroute_dns comment \"re-route dns\""
            DNS_OUTPUT_CHAIN="chain reroute_dns {
            meta l4proto { tcp, udp } th dport { $(csv_to_nft_list "$DNS_BYPASS_PORTS") } meta mark set $ROUTE_MARK counter accept
        }
"
        fi
    fi

    FAKEIP_V4_PRE_CHAIN=""
    FAKEIP_V4_OUTPUT_CHAIN=""
    if [ "$ENABLE_FAKEIP_V4" = "1" ]; then
        FAKEIP_V4_PRE_CHAIN="meta nfproto ipv4 meta l4proto { tcp, udp } ip daddr $FAKEIP_V4 meta mark set $ROUTE_MARK tproxy ip to :$TPROXY_PORT counter accept"
        if [ "$PROXY_LOCAL" = "1" ]; then
            FAKEIP_V4_OUTPUT_CHAIN="meta nfproto ipv4 meta l4proto { tcp, udp } ip daddr $FAKEIP_V4 meta mark set $ROUTE_MARK counter accept"
        fi
    fi

    FAKEIP_V6_PRE_CHAIN=""
    FAKEIP_V6_OUTPUT_CHAIN=""
    if [ "$ENABLE_FAKEIP_V6" = "1" ]; then
        FAKEIP_V6_PRE_CHAIN="meta nfproto ipv6 meta l4proto { tcp, udp } ip6 daddr $FAKEIP_V6 meta mark set $ROUTE_MARK tproxy ip6 to :$TPROXY_PORT counter accept"
        if [ "$PROXY_LOCAL" = "1" ]; then
            FAKEIP_V6_OUTPUT_CHAIN="meta nfproto ipv6 meta l4proto { tcp, udp } ip6 daddr $FAKEIP_V6 meta mark set $ROUTE_MARK counter accept"
        fi
    fi

    FAKEIP_PRE_CHAIN=""
    FAKEIP_OUTPUT_CHAIN=""
    FAKEIP_PRE=""
    FAKEIP_OUTPUT=""
    if [ "$ENABLE_FAKEIP" = "1" ]; then
        # FakeIP is a capture target, not a private-range bypass.
        FAKEIP_PRE="jump fakeip comment \"route fakeip\""
        FAKEIP_PRE_CHAIN="chain fakeip {
            $FAKEIP_V4_PRE_CHAIN
            $FAKEIP_V6_PRE_CHAIN
        }
"
        if [ "$PROXY_LOCAL" = "1" ]; then
            FAKEIP_OUTPUT="jump reroute_fakeip comment \"re-route fakeip\""
            FAKEIP_OUTPUT_CHAIN="chain reroute_fakeip {
            $FAKEIP_V4_OUTPUT_CHAIN
            $FAKEIP_V6_OUTPUT_CHAIN
        }
"
        fi
    fi

    IGNORE_UID_RULE=""
    IGNORE_MARK_RULE=""
    if [ -n "$IGNORE_UID" ]; then
        IGNORE_UID_RULE="meta skuid == $IGNORE_UID counter accept comment \"ignore outbound pkts by uid\""
    fi
    if [ -n "$IGNORE_MARK" ]; then
        IGNORE_MARK_RULE="meta mark == $IGNORE_MARK counter accept comment \"ignore outbound pkts by mark\""
    fi

    OUTPUT_CHAIN=""
    if [ "$PROXY_LOCAL" = "1" ]; then
        # Output reroute mirrors prerouting exclusions before marking local traffic.
        OUTPUT_CHAIN="## re-route local traffic
        chain output {
                type route hook output priority filter; policy accept;
                $IGNORE_MARK_RULE
                $IGNORE_UID_RULE
                meta oifname "lo" counter accept comment \"loopback\"
                jump direct
                jump local_bypass
                $OUTPUT_PRE_RULES
                $OUTPUT_DNS_RULES
                $FAKEIP_OUTPUT
                jump bypass
                meta l4proto { tcp, udp } meta mark set $ROUTE_MARK counter accept comment \"re-route\"
        }"
    fi

    NFT_RULE="#!/usr/sbin/nft -f

table inet $NF_TABLE
flush table inet $NF_TABLE

table inet $NF_TABLE {
        set private {
            type ipv4_addr
            flags interval
            elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
                        169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24,
                        192.88.99.0/24, 192.168.0.0/16, 198.18.0.0/15, 198.51.100.0/24,
                        203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4 }
        }

        set private6 {
            type ipv6_addr
            flags interval
            elements = { ::/128, ::1/128, ::ffff:0:0/96, 100::/64,
                        64:ff9b::/96, 2001::/32, 2001:10::/28, 2001:20::/28,
                        2001:db8::/32, 2002::/16, fc00::/7, fe80::/10,
                        ff00::/8 }
        }

        chain direct {
            meta l4proto != { tcp, udp } counter accept
            th dport 123 counter accept comment \"time sync\"
        }

        chain local_bypass {
            $LOCAL_BYPASS_RULES
        }

        $DNS_CHAIN
        $FAKEIP_PRE_CHAIN
        $FAKEIP_OUTPUT_CHAIN
        $DNS_OUTPUT_CHAIN
        chain bypass {
            $BYPASS_RULES
        }
        chain prerouting {
            type filter hook prerouting priority -149; policy accept;
            $SCOPE_GUARD
            jump direct
            jump local_bypass
            $FAKEIP_PRE
            $DNS_PRE
            jump bypass
            ## go to tproxy
            $TPROXY_V4_RULE
            $TPROXY_V6_RULE
        }

        $OUTPUT_CHAIN

        ## https://ovear.info/post/509 for better performance
        chain divert {
                type filter hook prerouting priority -150; policy accept;
                $SCOPE_GUARD
                meta l4proto tcp socket transparent 1 meta mark set $ROUTE_MARK accept
        }
}
"
}

set_nft() {
    # Replace only the script-managed inet table.
    nft delete table inet "$NF_TABLE" 2>/dev/null || true
    printf '%s' "$NFT_RULE" | nft -f -
}

unset_nft() {
    nft delete table inet "$NF_TABLE" 2>/dev/null || true
    if [ "$NF_TABLE" = "transparent_proxy" ]; then
        nft delete table inet transparent-proxy 2>/dev/null || true
    fi
}

set_route4() {
    # TPROXY local routes do not require forwarding; kernel bypass opts in to it.
    if [ "$ENABLE_KERNEL_BYPASS" = "1" ]; then
        sysctl -w net.ipv4.ip_forward=1 || return 1
    fi
    apply_rp_filter_ipv4 || return 1
    ip rule show fwmark "$ROUTE_MARK" table "$ROUTE_TABLE4" | grep -q . || ip rule add fwmark "$ROUTE_MARK" table "$ROUTE_TABLE4"
    ip route replace local 0.0.0.0/0 dev lo table "$ROUTE_TABLE4"
}

set_route6() {
    if [ "$ENABLE_KERNEL_BYPASS" = "1" ]; then
        sysctl -w net.ipv6.conf.all.forwarding=1 || return 1
    fi
    ip -6 rule show fwmark "$ROUTE_MARK" table "$ROUTE_TABLE6" | grep -q . || ip -6 rule add fwmark "$ROUTE_MARK" table "$ROUTE_TABLE6"
    ip -6 route replace local ::/0 dev lo table "$ROUTE_TABLE6"
}

rp_filter_targets() {
    # Linux rp_filter is IPv4-only; apply to global defaults and scoped ingress ifaces.
    base=$1
    printf '%s\n' "$base.all.rp_filter" "$base.default.rp_filter"
    if [ -n "$IN_IFACE" ]; then
        old_ifs=$IFS
        IFS=,
        for iface in $IN_IFACE; do
            printf '%s\n' "$base.$iface.rp_filter"
        done
        IFS=$old_ifs
    fi
}

apply_rp_filter_values() {
    base=$1
    value=$2
    for target in $(rp_filter_targets "$base"); do
        sysctl -w "$target=$value"
    done
}

check_rp_filter_values() {
    base=$1
    for target in $(rp_filter_targets "$base"); do
        current=$(sysctl -n "$target" 2>/dev/null || printf 0)
        case "$current" in
            1)
                echo "ERROR: rp_filter strict value detected on $target"
                return 1
                ;;
        esac
    done
}

apply_rp_filter_ipv4() {
    case "$RP_FILTER" in
        off) ;;
        check) check_rp_filter_values net.ipv4.conf ;;
        loose) apply_rp_filter_values net.ipv4.conf 2 ;;
        strict) apply_rp_filter_values net.ipv4.conf 1 ;;
        disable) apply_rp_filter_values net.ipv4.conf 0 ;;
    esac
}

set_route() {
    case $STACK in
        v4)
            set_route4
            ;;
        v6)
            set_route6
            ;;
        all)
            set_route4
            set_route6
            ;;
    esac
}

unset_route4() {
    while ip rule del fwmark "$ROUTE_MARK" table "$ROUTE_TABLE4" 2>/dev/null; do :; done
    ip route del local 0.0.0.0/0 dev lo table "$ROUTE_TABLE4" 2>/dev/null || true
}

unset_route6() {
    while ip -6 rule del fwmark "$ROUTE_MARK" table "$ROUTE_TABLE6" 2>/dev/null; do :; done
    ip -6 route del local ::/0 dev lo table "$ROUTE_TABLE6" 2>/dev/null || true
}

unset_route() {
    case $STACK in
        v4)
            unset_route4
            ;;
        v6)
            unset_route6
            ;;
        all)
            unset_route4
            unset_route6
            ;;
    esac
}

case $ACTION in
    set)
    # Apply nft first, then routing/sysctl. Roll back nft if routing setup fails.
    gen_nft_rule
    if [ "$SAVE" = "1" ]; then
        printf '%s\n' "$NFT_RULE" > "$SAVE_FILE"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        printf '%s\n' "$NFT_RULE"
        exit
    fi
    set_nft
    if ! set_route; then
        echo "ERROR: routing setup failed; rolling back nftables table" >&2
        unset_nft
        exit 1
    fi
        ;;
    unset)
        if [ "$DRY_RUN" = "1" ]; then
            echo "unset route && clean up nf table"
            exit
        fi
        unset_nft
        unset_route
        ;;
esac
