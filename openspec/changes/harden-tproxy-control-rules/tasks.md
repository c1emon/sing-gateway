## 1. Requirements and Documentation Alignment

- [ ] 1.1 Update `tproxy_enhence.md` to include council P0/P1 findings: hook priority, divert ordering, rp_filter, DNS hijack exclusions, FakeIP/bypass conflict handling, output-chain symmetry, and kernel-bypass semantics.
- [ ] 1.2 Document the short-term decision to keep `tproxy_ctrl.sh` as POSIX shell and the future migration triggers for Python or another structured controller.
- [ ] 1.3 Update user-facing documentation with OPNsense prerequisites for FakeIP PBR, DNS DNAT, bogon exceptions, PMTUD/ICMP handling, and kernel-bypass loop prevention.

## 2. CLI and Configuration Surface

- [ ] 2.1 Add ingress scope options for allowed interfaces and decide whether to support multi-interface allow-list, excluded-interface list, or both.
- [ ] 2.2 Add custom IPv4/IPv6 bypass CIDR options and validate their syntax before side effects.
- [ ] 2.3 Add local service bypass options for DNS, management, explicit proxy, TPROXY listener, and health-check ports or addresses.
- [ ] 2.4 Add or define sysctl policy options for rp_filter and forwarding checks/application.
- [ ] 2.5 Add explicit kernel-bypass enablement or compatibility-mode semantics so forwarding is not implied by basic TPROXY setup.
- [ ] 2.6 Extend `scripts/sing-gateway` configuration loading and command delegation to pass through the new control options.

## 3. nftables Rule Generation

- [ ] 3.1 Rework generated prerouting chains into an explicit ordered pipeline: scope guard, non-TCP/UDP bypass, local/infrastructure bypass, FakeIP, optional DNS hijack, private/custom bypass, default TPROXY.
- [ ] 3.2 Make nftables hook priorities deterministic and suitable for TPROXY before route lookup.
- [ ] 3.3 Ensure divert handling order is explicit and scoped consistently with the rest of prerouting capture.
- [ ] 3.4 Ensure FakeIP handling always precedes private, reserved, and custom bypass handling.
- [ ] 3.5 Ensure DNS hijack excludes local DNS listeners and configured internal/management DNS destinations before hijacking remaining eligible DNS traffic.
- [ ] 3.6 Generate IPv6 handling only for enabled stacks and preserve ICMPv6/ND/RA/MLD/PMTUD bypass through non-TCP/UDP acceptance.

## 4. Validation and System State

- [ ] 4.1 Reject or warn on FakeIP/custom-bypass conflicts according to the design decision selected during implementation.
- [ ] 4.2 Reject `--proxy-local` configurations where `ignore-mark` conflicts with `route-mark`.
- [ ] 4.3 Check or apply safe rp_filter values for `all`, `default`, and configured ingress interfaces according to selected sysctl policy.
- [ ] 4.4 Stop treating IP forwarding as an unconditional TPROXY prerequisite; tie forwarding behavior to explicit kernel-bypass semantics or compatibility mode.
- [ ] 4.5 Preserve cleanup ownership boundaries for nftables, policy routing, forwarding, and rp_filter state.

## 5. Local Output Hardening

- [ ] 5.1 Rework `--proxy-local` output rules so ignore UID/mark, loopback, local service bypasses, DNS bypasses, FakeIP, custom bypass, and generic reroute have deterministic ordering.
- [ ] 5.2 Ensure local DNS reroute does not capture local DNS listener traffic or proxy process traffic.
- [ ] 5.3 Ensure local output behavior is covered for IPv4-only, IPv6-only, and dual-stack modes.

## 6. Tests

- [ ] 6.1 Extend validation tests for new ingress scope, bypass CIDR, local service bypass, sysctl policy, kernel-bypass, and mark-conflict options.
- [ ] 6.2 Extend dry-run tests for hook priorities, divert order, scoped prerouting, local service bypass, FakeIP precedence, DNS hijack exclusions, custom bypass, and default TPROXY fallback.
- [ ] 6.3 Extend fake side-effect tests for rp_filter checks/application, forwarding behavior, policy-routing setup, and cleanup boundaries.
- [ ] 6.4 Extend local output tests for `--proxy-local` bypass ordering and loop prevention.
- [ ] 6.5 Extend optional nft parser validation cases for representative hardened generated rulesets.

## 7. Verification

- [ ] 7.1 Run the dependency-free shell regression suite.
- [ ] 7.2 Run representative `scripts/tproxy_ctrl.sh set --dry-run` commands for IPv4, IPv6, dual-stack, FakeIP, DNS hijack, custom bypass, kernel-bypass, and local proxy combinations.
- [ ] 7.3 Review generated nftables output against `proxy_arch.md` and `opnsense_proxy_gateway_practice.md` rule-order expectations.
- [ ] 7.4 Run OpenSpec verification for the change before implementation is considered complete.
