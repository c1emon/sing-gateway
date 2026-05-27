## Why

The transparent proxy control script is moving from a simple TPROXY helper toward a production gateway rule engine for the OPNsense single-arm proxy gateway architecture. Current rules already avoid full TCP/UDP interception, but they do not yet fully encode the safety boundaries required by `proxy_arch.md` and `opnsense_proxy_gateway_practice.md`.

This change hardens `scripts/tproxy_ctrl.sh` so it can safely generate and apply nftables, policy-routing, and related system checks for FakeIP, DNS hijack, local output proxying, and optional kernel bypass without accidentally capturing infrastructure, management, or loopback traffic.

## What Changes

- Add explicit inbound scope controls for TPROXY prerouting traffic, including allowed ingress interface support and room for multi-interface or excluded-interface designs.
- Harden nftables rule ordering and hook priorities so divert, FakeIP, DNS hijack, direct/bypass, and default TPROXY behavior run in deterministic order before route lookup.
- Add explicit bypass rules for local gateway addresses, DNS listeners, management ports, explicit proxy ports, TPROXY listener ports, health-check ports, infrastructure DNS, and custom bypass CIDRs.
- Treat FakeIP CIDRs as first-class TPROXY targets that take precedence over private/reserved/custom bypass ranges, with validation against conflicting bypass configuration.
- Make DNS hijack safer by default: it must not intercept DNS traffic already delivered to the proxy gateway DNS listener by OPNsense DNAT, nor internal/management DNS traffic.
- Clarify and enforce the distinction between sing-box `direct` outbound and nft/kernel bypass. Kernel bypass requires explicit configuration, forwarding/sysctl checks, and OPNsense PBR/NAT/anti-spoofing coordination.
- Add rp_filter and forwarding behavior checks appropriate for single-arm PBR topologies.
- Harden `--proxy-local` output-chain behavior with symmetric exclusions and loop-prevention checks.
- Preserve the near-term implementation as POSIX shell, but document that further expansion into a full policy compiler should trigger migration to a structured implementation language such as Python.
- Update the regression test requirements to cover the new rule ordering, validation, dry-run output, and side-effect behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `transparent-proxy-control`: Add production safety requirements for scoped TPROXY capture, deterministic nftables ordering, DNS hijack protection, FakeIP precedence, explicit bypass sets, sysctl checks, and kernel-bypass semantics.
- `tproxy-control-test-suite`: Extend regression coverage for the hardened transparent proxy control behavior.

## Impact

- Affected scripts:
  - `scripts/tproxy_ctrl.sh`
  - `scripts/sing-gateway`
- Affected documentation:
  - `tproxy_enhence.md`
  - potentially `docs/sing-gateway.md` and `README.md`
- Affected OpenSpec capabilities:
  - `transparent-proxy-control`
  - `tproxy-control-test-suite`
- Affected runtime systems:
  - nftables ruleset generation and hook priorities
  - Linux policy routing rules and route tables
  - `rp_filter`, IPv4 forwarding, and IPv6 forwarding checks
  - OPNsense PBR/DNAT/NAT coordination documented as an external prerequisite

No new runtime dependency is planned for this change. A future controller rewrite may introduce Python or another structured implementation language, but that is explicitly out of scope for this hardening change.
