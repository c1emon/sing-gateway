#!/bin/sh

set -e

ACTION=""
STACK="v4"
ENABLE_FAKEIP="0"
ENABLE_FAKEIP_V4="0"
ENABLE_FAKEIP_V6="0"
PROXY_LOCAL="0"
HIJACK_DNS="0"

IGNORE_MARK=""
IGNORE_UID=""

NF_TABLE="transparent-proxy"
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
    printf "\nOptions (fakeip):\n"
    printf '  %-25s %-20s\n' "--fake-ip4=<IPV4>" "Set fakeip ipv4 cidr (available when ipv4 enabled)"
    printf '  %-25s %-20s\n' "--fake-ip6=<IPV6>" "Set fakeip ipv6 cidr (available when ipv6 enabled)"
    printf "\nOptions (dns):\n"
    printf '  %-25s %-20s\n' "--hijack-dns" "Hijack dns (default false)"
    printf "\n"
}

is_integer() {
    case "${1#[+-]}" in  # 移除可能的前导符号（+ 或 -）
        '')   # 空字符串或仅有符号
            return 1 ;;
        *[!0-9]*)  # 包含非数字字符
            return 1 ;;
        *)    # 全为数字
            return 0 ;;
    esac
}

is_hex() {
    if echo "${1#[+-]}" | grep -qE "^(0x|0X)?[0-9A-Fa-f]+$"; then
        return 0
    else
        return 1
    fi
}

is_ipv4_cidr() {
    if echo "$1" | grep -qE "^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$"; then
        return 0
    else
        return 1
    fi
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
    # check ACTION
    if [ -z "$ACTION" ]; then
        echo "ERROR: invalid action"
        usage
        exit 1
    fi

    # check STACK
    case $STACK in
        v4|v6|all)
            ;;
        *)
            echo "ERROR: invalid stack: \"$STACK\""
            usage
            exit 1
            ;;
    esac

    # cehck NF_TABLE id is not empty
    if [ -z "${NF_TABLE}" ]; then
        echo "ERROR: invalid nf table: \"$NF_TABLE\""
        usage
        exit 1
    fi

    # check ROUTE_TABLE id is number
    case $STACK in
        v4)
            if ! is_integer "$ROUTE_TABLE4"; then
                echo "ERROR: invalid ipv4 route table id: \"$ROUTE_TABLE4\""
                usage
                exit 1
            fi
            # check 
            if [ -n "$FAKEIP_V4" ]; then
                if is_ipv4_cidr "$FAKEIP_V4"; then
                    ENABLE_FAKEIP_V4="1"
                    ENABLE_FAKEIP="1"
                else
                    echo "ERROR: invalid fakeip v4 cidr: \"$FAKEIP_V4\""
                    usage
                    exit 1
                fi
            fi
            ;;
        v6)
            if ! is_integer "$ROUTE_TABLE6"; then
                echo "ERROR: invalid ipv6 route table id: \"$ROUTE_TABLE6\""
                usage
                exit 1
            fi

            if [ -n "$FAKEIP_V6" ]; then
                if is_ipv6_cidr "$FAKEIP_V6"; then
                    ENABLE_FAKEIP_V6="1"
                    ENABLE_FAKEIP="1"
                else
                    echo "ERROR: invalid fakeip v6 cidr: \"$FAKEIP_V6\""
                    usage
                    exit 1
                fi
            fi
            ;;
        all)
            if ! is_integer "$ROUTE_TABLE4"; then
                echo "ERROR: invalid ipv4 route table id: \"$ROUTE_TABLE4\""
                usage
                exit 1
            fi
            if ! is_integer "$ROUTE_TABLE6"; then
                echo "ERROR: invalid ipv6 route table id: \"$ROUTE_TABLE6\""
                usage
                exit 1
            fi
            # check 
            if [ -n "$FAKEIP_V4" ]; then
                if is_ipv4_cidr "$FAKEIP_V4"; then
                    ENABLE_FAKEIP_V4="1"
                    ENABLE_FAKEIP="1"
                else
                    echo "ERROR: invalid fakeip v4 cidr: \"$FAKEIP_V4\""
                    usage
                    exit 1
                fi
            fi

            if [ -n "$FAKEIP_V6" ]; then
                if is_ipv6_cidr "$FAKEIP_V6"; then
                    ENABLE_FAKEIP_V6="1"
                    ENABLE_FAKEIP="1"
                else
                    echo "ERROR: invalid fakeip v6 cidr: \"$FAKEIP_V6\""
                    usage
                    exit 1
                fi
            fi
            ;;
    esac

    # check ROUTE_MARK is int or hex
    if ! is_hex "$ROUTE_MARK"; then
        echo "ERROR: invalid route mark: \"$ROUTE_MARK\""
        usage
        exit 1
    fi

    # check TPROXY_PORT is int
    if ! is_integer "$TPROXY_PORT"; then
        echo "ERROR: invalid tproxy port: \"$TPROXY_PORT\""
        usage
        exit 1
    fi

    # check PROXY_LOCAL
    if [ "$PROXY_LOCAL" = "1" ]; then
        if ! is_hex "$IGNORE_MARK"; then
            if ! is_integer "$IGNORE_UID"; then
                echo "ERROR: invalid ignore mark(\"$IGNORE_MARK\") or uid(\"$IGNORE_UID\")"
                usage
                exit 1
            fi
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
    DNS_PRE=""
    DNS_PRE_CHAIN=""
    DNS_OUTPUT=""
    DNS_OUTPUT_CHAIN=""

    if [ "$HIJACK_DNS" = "1" ]; then
        DNS_PRE="jump dns comment \"route dns\""
        DNS_PRE_CHAIN="chain dns {
            meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT counter accept
        }
"
        if [ "$PROXY_LOCAL" = "1" ]; then
            DNS_OUTPUT="jump reroute-dns comment \"re-route dns\""
            DNS_OUTPUT_CHAIN="chain reroute-dns {
            meta l4proto { tcp, udp } th dport 53 meta mark set $ROUTE_MARK counter accept
        }
"
        fi
    fi

    FAKEIP_V4_PRE_CHAIN=""
    FAKEIP_V4_OUTPUT_CHAIN=""
    if [ "$ENABLE_FAKEIP_V4" = "1" ]; then
        FAKEIP_V4_PRE_CHAIN="meta l4proto { tcp, udp } ip daddr $FAKEIP_V4 meta mark set $ROUTE_MARK tproxy ip to :$TPROXY_PORT counter accept"
        if [ "$PROXY_LOCAL" = "1" ]; then
            FAKEIP_V4_OUTPUT_CHAIN="meta l4proto { tcp, udp } ip daddr $FAKEIP_V4 meta mark set $ROUTE_MARK counter accept"
        fi
    fi

    FAKEIP_V6_PRE_CHAIN=""
    FAKEIP_V6_OUTPUT_CHAIN=""
    if [ "$ENABLE_FAKEIP_V6" = "1" ]; then
        FAKEIP_V6_PRE_CHAIN="meta l4proto { tcp, udp } ip6 daddr $FAKEIP_V6 meta mark set $ROUTE_MARK tproxy ip6 to :$TPROXY_PORT counter accept"
        if [ "$PROXY_LOCAL" = "1" ]; then
            FAKEIP_V6_OUTPUT_CHAIN="meta l4proto { tcp, udp } ip6 daddr $FAKEIP_V6 meta mark set $ROUTE_MARK counter accept"
        fi
    fi

    FAKEIP_PRE_CHAIN=""
    FAKEIP_OUTPUT_CHAIN=""
    FAKEIP_PRE=""
    FAKEIP_OUTPUT=""
    if [ "$ENABLE_FAKEIP" = "1" ]; then
        FAKEIP_PRE="jump fakeip comment \"route fakeip\""
        FAKEIP_PRE_CHAIN="chain fakeip {
            $FAKEIP_V4_PRE_CHAIN
            $FAKEIP_V6_PRE_CHAIN
        }
"
        if [ "$PROXY_LOCAL" = "1" ]; then
            FAKEIP_OUTPUT="jump reroute-fakeip comment \"re-route fakeip\""
            FAKEIP_OUTPUT_CHAIN="chain reroute-fakeip {
            $FAKEIP_V4_OUTPUT_CHAIN
            $FAKEIP_V6_OUTPUT_CHAIN
        }
"
        fi
    fi

    IGNORE_UID_RULE=""
    IGNORE_MASK_RULE=""
    if [ -n "$IGNORE_UID" ]; then
        IGNORE_UID_RULE="meta skuid == $IGNORE_UID counter accept comment \"ignore outbound pkts by uid\""
    fi
    if [ -n "$IGNORE_MASK" ]; then
        IGNORE_MASK_RULE="meta mark $IGNORE_MARK counter accept comment \"ignore outbound pkts by mark\""
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
                ip daddr @private counter accept comment \"private IPv4\"
                ip6 daddr @private6 counter accept comment \"private IPv6\"
	}

        $DNS_PRE_CHAIN
        $DNS_OUTPUT_CHAIN
        $FAKEIP_PRE_CHAIN
        $FAKEIP_OUTPUT_CHAIN
        chain prerouting {
                type filter hook prerouting priority filter; policy accept;
                $DNS_PRE
                $FAKEIP_PRE
                jump direct
                ## go to tproxy
                meta l4proto { tcp, udp } meta mark set $ROUTE_MARK tproxy ip to :$TPROXY_PORT counter accept
                meta l4proto { tcp, udp } meta mark set $ROUTE_MARK tproxy ip6 to :$TPROXY_PORT counter accept
        }

        ## re-route local traffic
        chain output {
                type route hook output priority filter; policy accept;
                $IGNORE_UID_RULE
                $IGNORE_MASK_RULE
                $DNS_OUTPUT
                $FAKEIP_OUTPUT
                jump direct
                meta l4proto { tcp, udp } meta mark set $ROUTE_MARK counter accept comment \"re-route\"
        }

        ## https://ovear.info/post/509 for better performance
        chain divert {
                type filter hook prerouting priority mangle; policy accept;
                meta l4proto tcp socket transparent 1 meta mark set $ROUTE_MARK accept
        }
}
"
}

set_nft() {
    printf '%s' "$NFT_RULE" | nft -f -
}

unset_nft() {
    nft delete table inet "$NF_TABLE"
}

set_route4() {
    sysctl -w net.ipv4.ip_forward=1
    ip rule add fwmark "$ROUTE_MARK" table "$ROUTE_TABLE4"
    ip route add local 0.0.0.0/0 dev lo table "$ROUTE_TABLE4"
}

set_route6() {
    sysctl -w net.ipv6.conf.all.forwarding=1
    ip -6 rule add fwmark "$ROUTE_MARK" table "$ROUTE_TABLE6"
    ip -6 route add local ::/0 dev lo table "$ROUTE_TABLE6"
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
    sysctl -w net.ipv4.ip_forward=0
    ip rule del fwmark "$ROUTE_MARK" table "$ROUTE_TABLE4"
    ip route del local 0.0.0.0/0 dev lo table "$ROUTE_TABLE4"
}

unset_route6() {
    sysctl -w net.ipv6.conf.all.forwarding=0
    ip -6 rule del fwmark "$ROUTE_MARK" table "$ROUTE_TABLE6"
    ip -6 route del local ::/0 dev lo table "$ROUTE_TABLE6"
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
    gen_nft_rule
    if [ "$SAVE" = "1" ]; then
        echo "$NFT_RULE" > "$SAVE_FILE"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        echo "$NFT_RULE"
        exit
    fi
    set_nft
    set_route
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