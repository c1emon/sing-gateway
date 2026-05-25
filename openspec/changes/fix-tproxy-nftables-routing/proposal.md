## Why

`tproxy_ctrl.sh` currently generates nftables and routing configuration that can fail under default settings or common sing-box TProxy scenarios. The highest-risk issues affect nft identifier validity, IPv4/IPv6 family selection, DNS hijack routing marks, local proxy bypass rules, and repeated setup/cleanup reliability.

This change makes the existing POSIX shell script safer and more predictable without rewriting it in another language or changing its primary CLI purpose.

## What Changes

- Fix nftables rule generation so default table/chain names and generated rules are syntactically valid.
- Generate IPv4 and IPv6 TProxy rules according to `--stack=v4|v6|all`, including explicit protocol-family guards in the `inet` table.
- Ensure DNS hijack and FakeIP/FakeDNS forwarding paths set the routing mark required by policy routing.
- Fix `--proxy-local` ignore handling so `--ignore-mark` and `--ignore-uid` work independently and prevent local proxy loops.
- Improve `set`/`unset` behavior so repeated runs and partial existing state do not leave the host in a broken half-configured state.
- Tighten validation for nft identifiers, marks, ports, route table IDs, UIDs, and FakeIP CIDRs before generating privileged commands.
- Preserve the shell implementation and avoid introducing a new runtime language or service manager integration.

## Capabilities

### New Capabilities
- `transparent-proxy-control`: Defines correct and safe behavior for configuring nftables-based sing-box TProxy, DNS/FakeIP handling, local traffic proxying, and setup/cleanup operations.

### Modified Capabilities

## Impact

- Affected code: `tproxy_ctrl.sh`.
- Affected runtime systems: Linux nftables, policy routing (`ip rule`, `ip route`), IPv4/IPv6 forwarding sysctls, sing-box TProxy listener behavior.
- CLI compatibility: existing actions and options should remain available; semantics become stricter for invalid inputs.
- No new language runtime, daemon, package dependency, or systemd integration is introduced.
