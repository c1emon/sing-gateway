## Context

`scripts/tproxy_ctrl.sh` currently acts as a POSIX shell engine for generating nftables TPROXY rules and Linux policy routing. `scripts/sing-gateway` wraps it by resolving sing-box configuration, FakeIP ranges, TPROXY port, local proxy bypass options, and package-managed service integration.

The architecture documents now define a stricter production posture for the OPNsense single-arm proxy gateway model:

```text
被代理主机
  -> OPNsense 持有的 Proxy Gateway VIP
  -> OPNsense PBR / route-to
  -> Linux 代理网关 TPROXY
  -> sing-box proxy/direct/reject
  -> OPNsense 出站 NAT 或内部路由
```

The proxy gateway receives traffic from OPNsense on a DMZ/service interface while preserving original LAN client source addresses and original destination addresses. That makes broad TPROXY capture risky: internal services, management traffic, DNS already DNATed to the local listener, FakeIP traffic, local output traffic, and kernel-bypass traffic all need precise handling.

The current shell implementation can be hardened enough for the near-term requirement, but the scope is approaching a policy compiler. This design therefore keeps POSIX shell for this change while drawing a boundary: if future work needs richer topology inference, full CIDR overlap analysis, structured diagnostics, or multiple named policy profiles, the control engine should be migrated to Python or another structured language.

## Goals / Non-Goals

**Goals:**

- Keep `tproxy_ctrl.sh` as the low-level engine for this change.
- Encode the production safety requirements surfaced by `proxy_arch.md`, `opnsense_proxy_gateway_practice.md`, `tproxy_enhence.md`, and council review.
- Make nftables capture scoped, ordered, and auditable.
- Keep FakeIP handling ahead of private/reserved/custom bypass logic.
- Make DNS hijack opt-in and safe around local DNS listeners and infrastructure DNS.
- Make local output proxying symmetric with prerouting exclusions and loop prevention.
- Separate TPROXY local-route requirements from optional kernel bypass forwarding requirements.
- Preserve dry-run behavior so generated rules and side effects can be tested without root.

**Non-Goals:**

- Do not rewrite the controller in Python, Go, or Rust in this change.
- Do not infer OPNsense configuration automatically.
- Do not manage OPNsense PBR, NAT, bogon, or anti-spoofing rules from this script.
- Do not guarantee full topology correctness; external gateway configuration remains an explicit prerequisite.
- Do not introduce a daemon or long-running control process.

## Decisions

### Decision 1: Keep POSIX shell for this hardening pass

The near-term change will continue using POSIX shell because the repository already has shell scripts, shell-based packaging assumptions, and a dependency-free regression test suite.

Alternatives considered:

- **Python controller now**: better validation and CIDR handling, but adds runtime dependency and broadens the change beyond hardening.
- **Go/Rust single binary**: stronger long-term shape, but adds build and packaging complexity not justified for this immediate change.

Boundary: this is likely the last large complexity increase that should be made in pure shell. Future requirements for structured config, rich diagnostics, or complete network-set overlap validation should trigger a controller rewrite.

### Decision 2: Treat nftables rule order as an explicit policy pipeline

The generated prerouting pipeline should be conceptually ordered as:

```text
scope guard
  -> non TCP/UDP bypass
  -> local service / infrastructure bypass
  -> FakeIP TPROXY
  -> optional external DNS hijack
  -> private/custom bypass
  -> default TCP/UDP TPROXY
```

This ordering keeps FakeIP from being swallowed by private/reserved ranges such as `198.18.0.0/15`, protects local services, and makes DNS hijack apply only to remaining eligible DNS traffic.

The nftables hook priority must be deterministic and early enough for TPROXY. Divert and main TPROXY handling must not rely on ambiguous ordering between multiple base chains with unclear priorities.

### Decision 3: Scope inbound capture before doing any policy work

The controller should support an explicit inbound scope, at minimum ingress interface matching. Multi-interface support or an excluded-interface model should be considered during implementation because production gateways often have Docker, WireGuard, loopback, management, or virtual interfaces.

Unscoped prerouting capture is not acceptable for production use.

### Decision 4: DNS hijack remains opt-in and must be constrained

DNS hijack is useful only for selected external DNS interception. It must not intercept DNS traffic that OPNsense has intentionally DNATed to the proxy gateway DNS listener, nor internal DNS/AD/management DNS paths.

The rule model therefore treats DNS hijack as a late, constrained TPROXY path after local and infrastructure DNS bypasses, not as a blanket rule before all direct exclusions.

### Decision 5: FakeIP is a first-class capture target

FakeIP ranges must be configured and validated when FakeIP behavior is expected. They are not ordinary private/bogon ranges in this architecture. FakeIP rules must run before private/custom bypass rules, and user-provided bypass ranges must not silently override FakeIP capture.

Because complete CIDR overlap detection is awkward in POSIX shell, implementation can choose one of two near-term approaches:

1. Reject exact duplicate FakeIP/bypass values and rely on FakeIP-before-bypass ordering for broader overlaps.
2. Implement limited overlap detection for IPv4 while documenting IPv6 limitations.

A future Python controller should use standard CIDR overlap primitives.

### Decision 6: Kernel bypass is explicit, not implied by nft accept

An nftables `accept` in prerouting means the packet continues through normal kernel processing. It does not mean sing-box direct outbound was used, nor that forwarding will succeed.

If the destination is local, the packet is delivered locally. If the destination is non-local and forwarding is enabled, the packet may be routed onward. This requires OPNsense-side NAT, anti-spoofing, PBR loop prevention, and firewall rules.

The script should not treat `ip_forward=1` as a universal TPROXY prerequisite. Forwarding is only required when kernel bypass is intentionally supported.

### Decision 7: `rp_filter` is a deployment safety prerequisite

In the single-arm PBR topology, the proxy gateway can receive packets on the DMZ interface whose source addresses belong to LAN/VLAN networks. Strict reverse-path filtering can drop these packets before TPROXY processing.

The controller should at least check and warn/fail for unsafe `rp_filter` values, with an option to apply safe settings if that fits the package policy. The requirement applies to `all`, `default`, and relevant ingress interfaces.

### Decision 8: `--proxy-local` needs symmetric exclusions

Local output rerouting must not capture the proxy process itself, local DNS listeners, loopback, management traffic, explicit proxy listeners, the TPROXY listener, or health-check paths. `ignore-mark` and `route-mark` must not conflict.

The output chain should reuse the same conceptual bypass sets where possible, but implementation may render separate output-safe rules because nftables match primitives differ between prerouting and output.

## Risks / Trade-offs

- **Shell complexity grows too large** → Keep the change bounded to hardening and document future migration triggers.
- **CIDR overlap validation is incomplete in shell** → Ensure rule ordering preserves FakeIP precedence and add tests for exact conflicts; document limitations and future Python path.
- **Incorrect hook priority breaks TPROXY semantics** → Add dry-run assertions and optional nft parser validation for priority and chain order.
- **DNS hijack disrupts internal DNS or AD** → Require explicit bypasses and make hijack opt-in only.
- **Kernel bypass creates loops through OPNsense PBR** → Make kernel bypass explicit and document OPNsense prerequisites; do not imply that nft accept is equivalent to safe direct outbound.
- **Changing forwarding behavior affects unrelated host networking** → Avoid disabling forwarding on cleanup and avoid enabling forwarding unless kernel bypass is explicitly requested or existing behavior must be preserved for compatibility.
- **IPv6 behavior is assumed from IPv4** → Require explicit IPv6 mode documentation and tests for ICMPv6/ND/RA/PMTUD bypass.

## Migration Plan

1. Extend specs and tests first around generated dry-run output and validation behavior.
2. Update `tproxy_enhence.md` to reflect the final hardened requirement set and shell boundary.
3. Implement script changes behind explicit CLI/config options with conservative defaults.
4. Preserve existing invocation behavior where safe, but surface warnings or failures for unsafe combinations.
5. Update `scripts/sing-gateway` to pass through new options from gateway configuration.
6. Validate with fake command tests, dry-run nft output assertions, and optional nft parser checks.

Rollback remains `tproxy_ctrl.sh unset` / `sing-gateway unset`, which removes managed nftables and policy-routing state. Sysctl changes require special care: if this change applies sysctls, it must either record ownership or document that cleanup does not restore prior global host networking state.

## Open Questions

- Should unsafe `rp_filter` be a hard failure, a warning, or auto-fixed by default?
- Should kernel bypass be represented by an explicit option such as `--enable-kernel-bypass`?
- Should custom bypass CIDR overlap with FakeIP be hard-failed only for exact matches in shell, or should this change attempt broader IPv4 overlap detection?
- Should ingress scoping use allow-list only (`--in-iface`) or also support deny-list (`--exclude-iface`)?
- Should this change rename `--bypass4/6` to `--kernel-bypass4/6` or keep shorter names with explicit documentation?
