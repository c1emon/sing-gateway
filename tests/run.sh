#!/bin/sh

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CTRL="$ROOT_DIR/tproxy_ctrl.sh"

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/tproxy-ctrl-test.XXXXXX")
FAKE_BIN="$WORKDIR/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/nft" <<'EOF'
#!/bin/sh
log=${FAKE_LOG:-/dev/null}
printf 'nft %s\n' "$*" >> "$log"

case " $* " in
    *" -f - "*)
        stdin_file="${log}.stdin"
        cat > "$stdin_file"
        printf 'nft stdin saved to %s\n' "$stdin_file" >> "$log"
        if [ "${FAKE_NFT_APPLY_FAIL:-0}" = 1 ]; then
            exit 1
        fi
        exit 0
        ;;
esac

case " $* " in
    *" delete table "*)
        if [ "${FAKE_NFT_DELETE_FAIL:-0}" = 1 ]; then
            exit 1
        fi
        ;;
esac

exit 0
EOF

cat > "$FAKE_BIN/ip" <<'EOF'
#!/bin/sh
log=${FAKE_LOG:-/dev/null}
printf 'ip %s\n' "$*" >> "$log"

if [ "$1" = "-6" ]; then
    family="-6"
    shift
else
    family=
fi

case "$1" in
    rule)
        case "$2" in
            show)
                if [ "${FAKE_IP_RULE_SHOW_PRESENT:-0}" = 1 ]; then
                    if [ -n "${FAKE_IP_RULE_SHOW_OUTPUT:-}" ]; then
                        printf '%s\n' "$FAKE_IP_RULE_SHOW_OUTPUT"
                    else
                        printf 'fwmark\n'
                    fi
                    exit 0
                fi
                exit 1
                ;;
            add)
                if [ "${FAKE_IP_RULE_ADD_FAIL:-0}" = 1 ]; then
                    exit 1
                fi
                exit 0
                ;;
            del)
                if [ "${FAKE_IP_RULE_DEL_FAIL:-1}" = 1 ]; then
                    exit 1
                fi
                exit 0
                ;;
        esac
        ;;
    route)
        case "$2" in
            replace)
                if [ "${FAKE_IP_ROUTE_FAIL:-0}" = 1 ]; then
                    exit 1
                fi
                exit 0
                ;;
            del)
                if [ "${FAKE_IP_ROUTE_DEL_FAIL:-1}" = 1 ]; then
                    exit 1
                fi
                exit 0
                ;;
        esac
        ;;
esac

exit 0
EOF

cat > "$FAKE_BIN/sysctl" <<'EOF'
#!/bin/sh
printf 'sysctl %s\n' "$*" >> "${FAKE_LOG:-/dev/null}"
exit 0
EOF

chmod +x "$FAKE_BIN/nft" "$FAKE_BIN/ip" "$FAKE_BIN/sysctl"

ORIG_PATH=$PATH
TOTAL=0
PASS=0
FAIL=0
SKIP=0

LAST_STDOUT=
LAST_STDERR=
LAST_LOG=
LAST_STATUS=

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup 0 1 2 3 15

reset_fake_env() {
    FAKE_NFT_DELETE_FAIL=0
    FAKE_NFT_APPLY_FAIL=0
    FAKE_IP_RULE_SHOW_PRESENT=0
    FAKE_IP_RULE_SHOW_OUTPUT=
    FAKE_IP_RULE_ADD_FAIL=0
    FAKE_IP_RULE_DEL_FAIL=1
    FAKE_IP_ROUTE_FAIL=0
    FAKE_IP_ROUTE_DEL_FAIL=1

    export FAKE_NFT_DELETE_FAIL FAKE_NFT_APPLY_FAIL
    export FAKE_IP_RULE_SHOW_PRESENT FAKE_IP_RULE_SHOW_OUTPUT
    export FAKE_IP_RULE_ADD_FAIL FAKE_IP_RULE_DEL_FAIL
    export FAKE_IP_ROUTE_FAIL FAKE_IP_ROUTE_DEL_FAIL
}

fail_assert() {
    printf '    %s\n' "$*" >&2
    return 1
}

assert_status() {
    expected=$1
    actual=$2
    note=${3:-exit status}
    [ "$expected" = "$actual" ] || fail_assert "$note: expected $expected, got $actual"
}

assert_file_exists() {
    file=$1
    [ -e "$file" ] || fail_assert "expected file to exist: $file"
}

assert_file_not_exists() {
    file=$1
    [ ! -e "$file" ] || fail_assert "expected file to be absent: $file"
}

assert_file_empty() {
    file=$1
    [ ! -s "$file" ] || fail_assert "expected empty file: $file"
}

assert_contains() {
    file=$1
    needle=$2
    grep -F -q "$needle" "$file" || fail_assert "expected '$needle' in $file"
}

assert_not_contains() {
    file=$1
    needle=$2
    if grep -F -q "$needle" "$file"; then
        fail_assert "did not expect '$needle' in $file"
    fi
}

assert_same_files() {
    left=$1
    right=$2
    cmp -s "$left" "$right" || fail_assert "files differ: $left $right"
}

assert_count() {
    file=$1
    needle=$2
    expected=$3
    actual=$(awk -v pat="$needle" 'index($0, pat) { c++ } END { print c + 0 }' "$file")
    [ "$actual" = "$expected" ] || fail_assert "expected $expected matches for '$needle' in $file, got $actual"
}

assert_in_order() {
    file=$1
    shift
    prev=0
    for needle do
        line=$(grep -nF "$needle" "$file" | awk -F: 'NR==1 { print $1 }')
        [ -n "$line" ] || fail_assert "expected '$needle' in order check for $file"
        [ "$line" -gt "$prev" ] || fail_assert "expected '$needle' after previous match in $file"
        prev=$line
    done
}

assert_in_order_after() {
    file=$1
    marker=$2
    shift 2
    start=$(grep -nF "$marker" "$file" | awk -F: 'NR==1 { print $1 }')
    [ -n "$start" ] || fail_assert "expected marker '$marker' in $file"
    prev=$start
    for needle do
        line=$(awk -v pat="$needle" -v min="$prev" 'NR > min && index($0, pat) { print NR; exit }' "$file")
        [ -n "$line" ] || fail_assert "expected '$needle' after '$marker' in $file"
        [ "$line" -gt "$prev" ] || fail_assert "expected '$needle' after previous match in $file"
        prev=$line
    done
}

run_ctrl() {
    case_name=$1
    shift
    case_dir="$WORKDIR/$case_name"
    mkdir -p "$case_dir"
    stdout="$case_dir/stdout"
    stderr="$case_dir/stderr"
    log="$case_dir/fake.log"
    : > "$log"

    FAKE_LOG=$log
    export FAKE_LOG

    PATH="$FAKE_BIN:$ORIG_PATH" sh "$CTRL" "$@" >"$stdout" 2>"$stderr"
    status=$?

    LAST_STDOUT=$stdout
    LAST_STDERR=$stderr
    LAST_LOG=$log
    LAST_STATUS=$status
}

run_test() {
    TOTAL=$((TOTAL + 1))
    name=$1
    shift
    if ( set -e; "$@" ); then
        PASS=$((PASS + 1))
        printf 'ok %d - %s\n' "$TOTAL" "$name"
    else
        rc=$?
        if [ "$rc" -eq 2 ]; then
            SKIP=$((SKIP + 1))
            printf 'skip %d - %s\n' "$TOTAL" "$name"
        else
            FAIL=$((FAIL + 1))
            printf 'not ok %d - %s\n' "$TOTAL" "$name"
        fi
    fi
}

test_cli_validation() {
    reset_fake_env

    run_ctrl cli-missing-action
    assert_status 1 "$LAST_STATUS" "missing action"
    assert_contains "$LAST_STDOUT" "ERROR: invalid action"

    run_ctrl cli-help --help
    assert_status 0 "$LAST_STATUS" "help exit status"
    assert_contains "$LAST_STDOUT" "Usage:"
    assert_contains "$LAST_STDOUT" "Options (tproxy):"

    run_ctrl cli-unknown --bogus
    assert_status 1 "$LAST_STATUS" "unknown option"
    assert_contains "$LAST_STDOUT" "ERROR: unknown parameter \"--bogus\""

    run_ctrl cli-stack-invalid set --stack=bogus --dry-run
    assert_status 1 "$LAST_STATUS" "invalid stack"
    assert_contains "$LAST_STDOUT" "ERROR: invalid stack: \"bogus\""
}

test_safe_nft_table_identifiers() {
    reset_fake_env

    run_ctrl nft-table-default set --dry-run
    assert_status 0 "$LAST_STATUS" "default table"
    assert_contains "$LAST_STDOUT" "table inet transparent_proxy"

    run_ctrl nft-table-custom set --nf-table=my_proxy --dry-run
    assert_status 0 "$LAST_STATUS" "custom table"
    assert_contains "$LAST_STDOUT" "table inet my_proxy"
    assert_not_contains "$LAST_STDOUT" "table inet transparent_proxy"
}

test_unsafe_nft_table_identifiers_rejected() {
    reset_fake_env

    run_ctrl nft-table-hyphen set --nf-table=bad-name --save="$WORKDIR/hyphen.nft" --dry-run
    assert_status 1 "$LAST_STATUS" "hyphenated name"
    assert_file_not_exists "$WORKDIR/hyphen.nft"
    assert_file_empty "$LAST_LOG"

    run_ctrl nft-table-leading-digit set --nf-table=1bad --save="$WORKDIR/digit.nft" --dry-run
    assert_status 1 "$LAST_STATUS" "leading digit"
    assert_file_not_exists "$WORKDIR/digit.nft"
    assert_file_empty "$LAST_LOG"

    run_ctrl nft-table-empty set --nf-table= --save="$WORKDIR/empty.nft" --dry-run
    assert_status 1 "$LAST_STATUS" "empty name"
    assert_file_not_exists "$WORKDIR/empty.nft"
    assert_file_empty "$LAST_LOG"

    run_ctrl nft-table-meta set --nf-table='bad;rm' --save="$WORKDIR/meta.nft" --dry-run
    assert_status 1 "$LAST_STATUS" "shell metacharacters"
    assert_file_not_exists "$WORKDIR/meta.nft"
    assert_file_empty "$LAST_LOG"
}

test_route_mark_boundaries() {
    reset_fake_env

    run_ctrl route-mark-decimal set --route-mark=16 --dry-run
    assert_status 0 "$LAST_STATUS" "decimal mark"
    assert_contains "$LAST_STDOUT" "meta mark set 16"

    run_ctrl route-mark-hex set --route-mark=0x10 --dry-run
    assert_status 0 "$LAST_STATUS" "hex mark"
    assert_contains "$LAST_STDOUT" "meta mark set 0x10"

    run_ctrl route-mark-invalid set --route-mark=4294967296 --dry-run
    assert_status 1 "$LAST_STATUS" "out of range mark"
    assert_contains "$LAST_STDOUT" "ERROR: invalid route mark"

    run_ctrl route-mark-malformed set --route-mark=0xg --dry-run
    assert_status 1 "$LAST_STATUS" "malformed mark"
    assert_contains "$LAST_STDOUT" "ERROR: invalid route mark"
}

test_tproxy_port_boundaries() {
    reset_fake_env

    run_ctrl tproxy-port-low set --tproxy-port=1 --dry-run
    assert_status 0 "$LAST_STATUS" "lowest port"
    assert_contains "$LAST_STDOUT" ":1 counter accept"

    run_ctrl tproxy-port-high set --tproxy-port=65535 --dry-run
    assert_status 0 "$LAST_STATUS" "highest port"
    assert_contains "$LAST_STDOUT" ":65535 counter accept"

    run_ctrl tproxy-port-zero set --tproxy-port=0 --dry-run
    assert_status 1 "$LAST_STATUS" "port zero"
    assert_contains "$LAST_STDOUT" "ERROR: invalid tproxy port"

    run_ctrl tproxy-port-large set --tproxy-port=65536 --dry-run
    assert_status 1 "$LAST_STATUS" "port overflow"
    assert_contains "$LAST_STDOUT" "ERROR: invalid tproxy port"
}

test_route_table_boundaries() {
    reset_fake_env

    run_ctrl route-table-valid-v4 set --route-table4=1 --dry-run
    assert_status 0 "$LAST_STATUS" "ipv4 route table min"

    run_ctrl route-table-valid-v6 set --route-table6=4294967295 --dry-run
    assert_status 0 "$LAST_STATUS" "ipv6 route table max"

    run_ctrl route-table-invalid-v4 set --route-table4=0 --dry-run
    assert_status 1 "$LAST_STATUS" "ipv4 route table low"
    assert_contains "$LAST_STDOUT" "ERROR: invalid ipv4 route table id"

    run_ctrl route-table-invalid-v6 set --route-table6=4294967296 --dry-run
    assert_status 1 "$LAST_STATUS" "ipv6 route table high"
    assert_contains "$LAST_STDOUT" "ERROR: invalid ipv6 route table id"
}

test_uid_boundaries() {
    reset_fake_env

    run_ctrl uid-valid-low set --proxy-local --ignore-uid=0 --dry-run
    assert_status 0 "$LAST_STATUS" "uid zero"
    assert_contains "$LAST_STDOUT" "meta skuid == 0"

    run_ctrl uid-valid-high set --proxy-local --ignore-uid=4294967295 --dry-run
    assert_status 0 "$LAST_STATUS" "uid max"
    assert_contains "$LAST_STDOUT" "meta skuid == 4294967295"

    run_ctrl uid-invalid-negative set --proxy-local --ignore-uid=-1 --dry-run
    assert_status 1 "$LAST_STATUS" "negative uid"
    assert_contains "$LAST_STDOUT" "ERROR: invalid ignore uid"

    run_ctrl uid-invalid-garbage set --proxy-local --ignore-uid=abc --dry-run
    assert_status 1 "$LAST_STATUS" "garbage uid"
    assert_contains "$LAST_STDOUT" "ERROR: invalid ignore uid"
}

test_fakeip_cidr_validation() {
    reset_fake_env

    run_ctrl fakeip-v4-valid set --stack=v4 --fake-ip4=198.18.0.0/15 --dry-run
    assert_status 0 "$LAST_STATUS" "valid ipv4 fakeip"
    assert_contains "$LAST_STDOUT" "198.18.0.0/15"

    run_ctrl fakeip-v6-valid set --stack=v6 --fake-ip6=2001:db8::/32 --dry-run
    assert_status 0 "$LAST_STATUS" "valid ipv6 fakeip"
    assert_contains "$LAST_STDOUT" "2001:db8::/32"

    run_ctrl fakeip-v4-invalid set --stack=v4 --fake-ip4=300.1.2.3/24 --dry-run
    assert_status 1 "$LAST_STATUS" "invalid ipv4 fakeip"
    assert_contains "$LAST_STDOUT" "ERROR: invalid fakeip v4 cidr"

    run_ctrl fakeip-v6-invalid set --stack=v6 --fake-ip6=2001:db8::/129 --dry-run
    assert_status 1 "$LAST_STATUS" "invalid ipv6 fakeip"
    assert_contains "$LAST_STDOUT" "ERROR: invalid fakeip v6 cidr"
}

test_dry_run_stack_selection() {
    reset_fake_env

    run_ctrl dryrun-default set --dry-run
    assert_status 0 "$LAST_STATUS" "default dry-run"
    assert_contains "$LAST_STDOUT" "meta nfproto ipv4"
    assert_not_contains "$LAST_STDOUT" "meta nfproto ipv6"

    run_ctrl dryrun-v4 set --stack=v4 --dry-run
    assert_status 0 "$LAST_STATUS" "v4 dry-run"
    assert_contains "$LAST_STDOUT" "meta nfproto ipv4"
    assert_not_contains "$LAST_STDOUT" "meta nfproto ipv6"

    run_ctrl dryrun-v6 set --stack=v6 --dry-run
    assert_status 0 "$LAST_STATUS" "v6 dry-run"
    assert_contains "$LAST_STDOUT" "meta nfproto ipv6"
    assert_not_contains "$LAST_STDOUT" "meta nfproto ipv4"

    run_ctrl dryrun-all set --stack=all --dry-run
    assert_status 0 "$LAST_STATUS" "all dry-run"
    assert_contains "$LAST_STDOUT" "meta nfproto ipv4"
    assert_contains "$LAST_STDOUT" "meta nfproto ipv6"
}

test_dns_hijack_and_local_reroute() {
    reset_fake_env

    run_ctrl dns-hijack set --stack=all --hijack-dns --dry-run
    assert_status 0 "$LAST_STATUS" "dns hijack dry-run"
    assert_contains "$LAST_STDOUT" "chain dns {"
    assert_contains "$LAST_STDOUT" "th dport 53 meta mark set 0x01 tproxy ip to :9898 counter accept"
    assert_contains "$LAST_STDOUT" "th dport 53 meta mark set 0x01 tproxy ip6 to :9898 counter accept"

    run_ctrl dns-reroute-local set --stack=all --proxy-local --ignore-mark=0x20 --hijack-dns --dry-run
    assert_status 0 "$LAST_STATUS" "dns reroute dry-run"
    assert_contains "$LAST_STDOUT" "chain reroute_dns {"
    assert_contains "$LAST_STDOUT" "th dport 53 meta mark set 0x01 counter accept"
    assert_contains "$LAST_STDOUT" "jump reroute_dns comment \"re-route dns\""
    assert_contains "$LAST_STDOUT" "chain reroute_dns {"
}

test_fakeip_stack_combinations() {
    reset_fake_env

    run_ctrl fakeip-v4-only set --stack=v4 --fake-ip4=198.18.0.0/15 --dry-run
    assert_status 0 "$LAST_STATUS" "fakeip v4 only"
    assert_contains "$LAST_STDOUT" "jump fakeip comment \"route fakeip\""
    assert_contains "$LAST_STDOUT" "ip daddr 198.18.0.0/15"
    assert_not_contains "$LAST_STDOUT" "ip6 daddr"

    run_ctrl fakeip-v6-only set --stack=v6 --fake-ip6=2001:db8::/32 --dry-run
    assert_status 0 "$LAST_STATUS" "fakeip v6 only"
    assert_contains "$LAST_STDOUT" "jump fakeip comment \"route fakeip\""
    assert_contains "$LAST_STDOUT" "ip6 daddr 2001:db8::/32"
    assert_not_contains "$LAST_STDOUT" "ip daddr 198.18.0.0/15"

    run_ctrl fakeip-disabled-family set --stack=v4 --fake-ip4=198.18.0.0/15 --fake-ip6=2001:db8::/32 --dry-run
    assert_status 0 "$LAST_STATUS" "fakeip disabled family"
    assert_contains "$LAST_STDOUT" "ip daddr 198.18.0.0/15"
    assert_not_contains "$LAST_STDOUT" "ip6 daddr 2001:db8::/32"

    run_ctrl fakeip-dual-stack set --stack=all --proxy-local --ignore-mark=0x20 --fake-ip4=198.18.0.0/15 --fake-ip6=2001:db8::/32 --dry-run
    assert_status 0 "$LAST_STATUS" "fakeip dual stack"
    assert_contains "$LAST_STDOUT" "ip daddr 198.18.0.0/15"
    assert_contains "$LAST_STDOUT" "ip6 daddr 2001:db8::/32"
    assert_contains "$LAST_STDOUT" "meta mark set 0x01 counter accept"
}

test_proxy_local_bypass_ordering() {
    reset_fake_env

    run_ctrl proxy-local-order set --stack=all --proxy-local --ignore-mark=0x20 --ignore-uid=1000 --hijack-dns --fake-ip4=198.18.0.0/15 --fake-ip6=2001:db8::/32 --dry-run
    assert_status 0 "$LAST_STATUS" "proxy-local ordering"
    assert_contains "$LAST_STDOUT" "chain output {"
    assert_in_order_after "$LAST_STDOUT" "chain output {" \
        "meta mark == 0x20 counter accept comment \"ignore outbound pkts by mark\"" \
        "meta skuid == 1000 counter accept comment \"ignore outbound pkts by uid\"" \
        "jump reroute_dns comment \"re-route dns\"" \
        "jump reroute_fakeip comment \"re-route fakeip\"" \
        "jump direct" \
        "meta l4proto { tcp, udp } meta mark set 0x01 counter accept comment \"re-route\""

    run_ctrl proxy-local-mark-only set --stack=all --proxy-local --ignore-mark=0x20 --dry-run
    assert_status 0 "$LAST_STATUS" "ignore mark only"
    assert_contains "$LAST_STDOUT" "meta mark == 0x20 counter accept comment \"ignore outbound pkts by mark\""
    assert_not_contains "$LAST_STDOUT" "ignore outbound pkts by uid"

    run_ctrl proxy-local-uid-only set --stack=all --proxy-local --ignore-uid=1000 --dry-run
    assert_status 0 "$LAST_STATUS" "ignore uid only"
    assert_contains "$LAST_STDOUT" "meta skuid == 1000 counter accept comment \"ignore outbound pkts by uid\""
    assert_not_contains "$LAST_STDOUT" "ignore outbound pkts by mark"
}

test_save_and_validation_side_effects() {
    reset_fake_env

    save_file="$WORKDIR/generated.nft"
    run_ctrl save-valid set --nf-table=my_proxy --save="$save_file" --dry-run
    assert_status 0 "$LAST_STATUS" "valid save"
    assert_file_exists "$save_file"
    assert_same_files "$save_file" "$LAST_STDOUT"

    run_ctrl save-invalid set --nf-table=bad-name --save="$WORKDIR/invalid-save.nft" --dry-run
    assert_status 1 "$LAST_STATUS" "invalid save request"
    assert_file_not_exists "$WORKDIR/invalid-save.nft"
    assert_file_empty "$LAST_LOG"

    run_ctrl invalid-non-dry-run set --stack=bogus
    assert_status 1 "$LAST_STATUS" "invalid non-dry-run"
    assert_file_empty "$LAST_LOG"

    run_ctrl proxy-local-needs-ignore set --proxy-local --dry-run
    assert_status 1 "$LAST_STATUS" "proxy-local requires ignore"
    assert_file_empty "$LAST_LOG"
}

test_set_sequence_ipv4() {
    reset_fake_env

    run_ctrl set-v4 set --stack=v4
    assert_status 0 "$LAST_STATUS" "set v4"
    assert_in_order "$LAST_LOG" \
        "nft delete table inet transparent_proxy" \
        "nft -f -" \
        "sysctl -w net.ipv4.ip_forward=1" \
        "ip rule show fwmark 0x01 table 100" \
        "ip rule add fwmark 0x01 table 100" \
        "ip route replace local 0.0.0.0/0 dev lo table 100"
}

test_set_sequence_ipv6() {
    reset_fake_env

    run_ctrl set-v6 set --stack=v6
    assert_status 0 "$LAST_STATUS" "set v6"
    assert_in_order "$LAST_LOG" \
        "nft delete table inet transparent_proxy" \
        "nft -f -" \
        "sysctl -w net.ipv6.conf.all.forwarding=1" \
        "ip -6 rule show fwmark 0x01 table 106" \
        "ip -6 rule add fwmark 0x01 table 106" \
        "ip -6 route replace local ::/0 dev lo table 106"
}

test_set_sequence_dual_stack() {
    reset_fake_env

    run_ctrl set-all set --stack=all
    assert_status 0 "$LAST_STATUS" "set all"
    assert_contains "$LAST_LOG" "sysctl -w net.ipv4.ip_forward=1"
    assert_contains "$LAST_LOG" "sysctl -w net.ipv6.conf.all.forwarding=1"
    assert_in_order "$LAST_LOG" \
        "ip rule show fwmark 0x01 table 100" \
        "ip rule add fwmark 0x01 table 100" \
        "ip route replace local 0.0.0.0/0 dev lo table 100" \
        "ip -6 rule show fwmark 0x01 table 106" \
        "ip -6 rule add fwmark 0x01 table 106" \
        "ip -6 route replace local ::/0 dev lo table 106"
}

test_idempotent_route_setup() {
    reset_fake_env
    FAKE_IP_RULE_SHOW_PRESENT=1
    FAKE_IP_RULE_SHOW_OUTPUT='fwmark 0x01 table 100'
    export FAKE_IP_RULE_SHOW_PRESENT FAKE_IP_RULE_SHOW_OUTPUT

    run_ctrl idempotent-route set --stack=v4
    assert_status 0 "$LAST_STATUS" "idempotent route"
    assert_contains "$LAST_LOG" "ip rule show fwmark 0x01 table 100"
    assert_not_contains "$LAST_LOG" "ip rule add fwmark 0x01 table 100"
    assert_contains "$LAST_LOG" "ip route replace local 0.0.0.0/0 dev lo table 100"
}

test_unset_cleanup_attempts() {
    reset_fake_env

    run_ctrl unset-cleanup unset --stack=all
    assert_status 0 "$LAST_STATUS" "unset cleanup"
    assert_contains "$LAST_LOG" "nft delete table inet transparent_proxy"
    assert_contains "$LAST_LOG" "nft delete table inet transparent-proxy"
    assert_contains "$LAST_LOG" "ip rule del fwmark 0x01 table 100"
    assert_contains "$LAST_LOG" "ip -6 rule del fwmark 0x01 table 106"
    assert_contains "$LAST_LOG" "ip route del local 0.0.0.0/0 dev lo table 100"
    assert_contains "$LAST_LOG" "ip -6 route del local ::/0 dev lo table 106"
}

test_unset_tolerates_missing_state() {
    reset_fake_env
    FAKE_NFT_DELETE_FAIL=1
    export FAKE_NFT_DELETE_FAIL

    run_ctrl unset-missing unset --stack=all
    assert_status 0 "$LAST_STATUS" "unset missing"
    assert_contains "$LAST_LOG" "nft delete table inet transparent_proxy"
    assert_contains "$LAST_LOG" "ip rule del fwmark 0x01 table 100"
    assert_contains "$LAST_LOG" "ip -6 rule del fwmark 0x01 table 106"
}

test_unset_does_not_disable_forwarding() {
    reset_fake_env

    run_ctrl unset-forwarding unset --stack=all
    assert_status 0 "$LAST_STATUS" "unset forwarding"
    assert_not_contains "$LAST_LOG" "net.ipv4.ip_forward=0"
    assert_not_contains "$LAST_LOG" "net.ipv6.conf.all.forwarding=0"
}

test_rollback_on_route_failure() {
    reset_fake_env
    FAKE_IP_ROUTE_FAIL=1
    export FAKE_IP_ROUTE_FAIL

    run_ctrl rollback-route-fail set --stack=v4
    assert_status 1 "$LAST_STATUS" "rollback route failure"
    assert_in_order "$LAST_LOG" \
        "nft delete table inet transparent_proxy" \
        "nft -f -" \
        "sysctl -w net.ipv4.ip_forward=1" \
        "ip rule show fwmark 0x01 table 100" \
        "ip rule add fwmark 0x01 table 100" \
        "ip route replace local 0.0.0.0/0 dev lo table 100"
    assert_count "$LAST_LOG" "nft delete table inet transparent_proxy" 2
}

test_nft_apply_failure() {
    reset_fake_env
    FAKE_NFT_APPLY_FAIL=1
    export FAKE_NFT_APPLY_FAIL

    run_ctrl nft-apply-fail set --stack=v4
    assert_status 1 "$LAST_STATUS" "nft apply failure"
    assert_contains "$LAST_LOG" "nft -f -"
    assert_not_contains "$LAST_LOG" "sysctl -w net.ipv4.ip_forward=1"
}

test_optional_nft_parser_check() {
    reset_fake_env

    run_ctrl nft-parser-gen set --save="$WORKDIR/parser.nft" --dry-run
    assert_status 0 "$LAST_STATUS" "parser fixture generation"
    assert_file_exists "$WORKDIR/parser.nft"

    if [ "${TPROXY_TEST_NFT_CHECK:-0}" != 1 ]; then
        printf 'SKIP optional nft parser check (set TPROXY_TEST_NFT_CHECK=1 to enable)\n'
        return 2
    fi

    real_nft=$(PATH="$ORIG_PATH" command -v nft 2>/dev/null || true)
    if [ -z "$real_nft" ]; then
        printf 'SKIP optional nft parser check (real nft not found on PATH)\n'
        return 2
    fi

    if "$real_nft" -c -f "$WORKDIR/parser.nft" >/dev/null 2>"$WORKDIR/parser-check.err"; then
        return 0
    fi

    cat "$WORKDIR/parser-check.err" >&2
    fail_assert "optional nft parser check failed with $real_nft"
}

main() {
    printf 'tproxy_ctrl.sh regression suite\n'
    printf 'Run: sh tests/run.sh\n'
    printf 'Optional nft parser check: set TPROXY_TEST_NFT_CHECK=1 to enable real nft validation when available\n\n'

    run_test "CLI validation" test_cli_validation
    run_test "Safe nft table identifiers" test_safe_nft_table_identifiers
    run_test "Unsafe nft table identifiers" test_unsafe_nft_table_identifiers_rejected
    run_test "Route mark boundaries" test_route_mark_boundaries
    run_test "TProxy port boundaries" test_tproxy_port_boundaries
    run_test "Route table boundaries" test_route_table_boundaries
    run_test "UID boundaries" test_uid_boundaries
    run_test "FakeIP CIDR validation" test_fakeip_cidr_validation
    run_test "Dry-run stack selection" test_dry_run_stack_selection
    run_test "DNS hijack and reroute" test_dns_hijack_and_local_reroute
    run_test "FakeIP stack combinations" test_fakeip_stack_combinations
    run_test "Proxy-local bypass ordering" test_proxy_local_bypass_ordering
    run_test "Save and validation side effects" test_save_and_validation_side_effects
    run_test "IPv4 set sequence" test_set_sequence_ipv4
    run_test "IPv6 set sequence" test_set_sequence_ipv6
    run_test "Dual-stack set sequence" test_set_sequence_dual_stack
    run_test "Idempotent route setup" test_idempotent_route_setup
    run_test "Unset cleanup attempts" test_unset_cleanup_attempts
    run_test "Unset tolerates missing state" test_unset_tolerates_missing_state
    run_test "Unset does not disable forwarding" test_unset_does_not_disable_forwarding
    run_test "Rollback on route failure" test_rollback_on_route_failure
    run_test "nft apply failure" test_nft_apply_failure
    run_test "Optional nft parser check" test_optional_nft_parser_check

    printf '\nSummary: %d passed, %d failed, %d skipped, %d total\n' "$PASS" "$FAIL" "$SKIP" "$TOTAL"
    [ "$FAIL" -eq 0 ]
}

main "$@"
