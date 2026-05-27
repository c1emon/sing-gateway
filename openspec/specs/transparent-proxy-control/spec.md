## Purpose
Define behavior for transparent proxy control rule generation, policy routing setup, cleanup, diagnostics, and package-managed wrapper delegation.

## Requirements

### Requirement: Valid nftables identifiers and generated syntax
The control script SHALL generate nftables table, chain, set, and jump references that are syntactically valid for nftables under the documented default options. User-provided nftables identifiers MUST be validated before use in generated nftables scripts.

#### Scenario: Default nftables identifiers are valid
- **WHEN** the user runs a dry run with default options
- **THEN** the generated nftables script uses valid unquoted identifiers for the table and generated chains

#### Scenario: Invalid nftables table name is rejected
- **WHEN** the user provides a table name that is not a safe nftables identifier
- **THEN** the script exits with an error before applying or saving generated nftables rules

### Requirement: Stack-specific IPv4 and IPv6 rule generation
The control script SHALL generate TProxy and policy-routing behavior only for the address families enabled by `--stack`. IPv4 nftables TProxy rules MUST be guarded as IPv4 traffic, and IPv6 nftables TProxy rules MUST be guarded as IPv6 traffic when using an `inet` table.

#### Scenario: IPv4-only stack
- **WHEN** the user runs `set --stack=v4 --dry-run`
- **THEN** the generated nftables TProxy rules include IPv4 handling and do not include IPv6 TProxy handling

#### Scenario: IPv6-only stack
- **WHEN** the user runs `set --stack=v6 --dry-run`
- **THEN** the generated nftables TProxy rules include IPv6 handling and do not include IPv4 TProxy handling

#### Scenario: Dual-stack mode
- **WHEN** the user runs `set --stack=all --dry-run`
- **THEN** the generated nftables TProxy rules include both IPv4 and IPv6 handling with explicit protocol-family guards

### Requirement: DNS hijack traffic is marked for policy routing
When DNS hijack is enabled, DNS packets selected for TProxy or local reroute handling SHALL receive the configured route mark before being accepted into the policy-routing path.

#### Scenario: External DNS hijack marks traffic
- **WHEN** the user runs `set --hijack-dns --dry-run`
- **THEN** the generated prerouting DNS hijack rule sets the configured route mark before TProxy acceptance

#### Scenario: Local DNS reroute marks traffic
- **WHEN** the user runs `set --proxy-local --hijack-dns --dry-run`
- **THEN** the generated output DNS reroute rule sets the configured route mark before accepting the packet

### Requirement: FakeIP traffic is marked and family-specific
When FakeIP handling is configured, FakeIP rules SHALL be generated only for enabled address families with valid FakeIP CIDRs, and selected FakeIP traffic SHALL receive the configured route mark.

#### Scenario: IPv4 FakeIP in IPv4 stack
- **WHEN** the user runs `set --stack=v4 --fake-ip4=198.18.0.0/15 --dry-run`
- **THEN** the generated FakeIP rules include IPv4 FakeIP matching and mark the packet for routing

#### Scenario: IPv6 FakeIP in IPv6 stack
- **WHEN** the user runs `set --stack=v6 --fake-ip6=fc00::/18 --dry-run`
- **THEN** the generated FakeIP rules include IPv6 FakeIP matching and mark the packet for routing

#### Scenario: FakeIP for disabled family is rejected or omitted
- **WHEN** the user provides a FakeIP CIDR for an address family not enabled by `--stack`
- **THEN** the script does not generate active TProxy handling for the disabled address family

### Requirement: Local proxy bypass rules prevent common loops
When local proxying is enabled, the script SHALL support independent bypass rules for configured process UID and packet mark values. Bypass rules MUST be evaluated before DNS, FakeIP, direct, or generic local reroute rules.

#### Scenario: Ignore mark rule is generated
- **WHEN** the user runs `set --proxy-local --ignore-mark=0xff --dry-run`
- **THEN** the generated output chain contains a mark-based bypass rule before local reroute rules

#### Scenario: Ignore UID rule is generated
- **WHEN** the user runs `set --proxy-local --ignore-uid=1000 --dry-run`
- **THEN** the generated output chain contains a UID-based bypass rule before local reroute rules

#### Scenario: Invalid bypass value is rejected
- **WHEN** the user provides an invalid ignore mark or ignore UID
- **THEN** the script exits with an error before applying nftables or routing changes

### Requirement: Setup and cleanup are idempotent enough for repeated runs
The `set` and `unset` actions SHALL tolerate existing or missing nftables and policy-routing state for the exact resources managed by the script. A repeated action MUST NOT leave the system in a partially configured state when the intended state already exists or is already absent.

#### Scenario: Repeated setup
- **WHEN** the user runs `set` more than once with the same options
- **THEN** the second run completes successfully or converges the managed nftables and routing resources to the same configured state

#### Scenario: Repeated cleanup
- **WHEN** the user runs `unset` more than once with the same options
- **THEN** the second run completes successfully without failing solely because managed nftables or routing resources are already absent

### Requirement: Cleanup does not disable unrelated forwarding configuration
The `unset` action MUST NOT unconditionally disable IPv4 or IPv6 forwarding that may have been enabled for unrelated host networking.

#### Scenario: Unset leaves global forwarding ownership intact
- **WHEN** the user runs `unset`
- **THEN** the script removes its managed nftables and routing resources without blindly setting IPv4 or IPv6 forwarding sysctls to disabled

### Requirement: Privileged command inputs are strictly validated
The script SHALL validate all user-provided values that are interpolated into nftables scripts or privileged routing commands, including route marks, route table IDs, TProxy ports, UIDs, nft table names, and FakeIP CIDRs.

#### Scenario: Invalid numeric option is rejected before side effects
- **WHEN** the user provides an out-of-range TProxy port, route table ID, UID, or mark
- **THEN** the script exits with an error before applying nftables or routing changes

#### Scenario: Invalid FakeIP CIDR is rejected before side effects
- **WHEN** the user provides an invalid IPv4 or IPv6 FakeIP CIDR
- **THEN** the script exits with an error before applying nftables or routing changes

### Requirement: Package-managed wrapper delegation
The transparent proxy control implementation SHALL support being invoked by a package-managed wrapper as the low-level engine for nftables and policy-routing setup, cleanup, and dry-run diagnostics.

#### Scenario: Wrapper delegates setup to control script
- **WHEN** `sing-gateway set` resolves a valid effective gateway configuration
- **THEN** it invokes the packaged `tproxy_ctrl.sh set` command with explicit stack, table, route, mark, TProxy port, FakeIP, DNS hijack, and local-proxy bypass options as applicable

#### Scenario: Wrapper delegates cleanup to control script
- **WHEN** `sing-gateway unset` runs during service stop, failure cleanup, disable, or package removal
- **THEN** it invokes the packaged `tproxy_ctrl.sh unset` command with the same managed table, route table, mark, and stack context used for setup where available
- **AND** cleanup tolerates absent managed resources

#### Scenario: Wrapper delegates diagnostics to dry-run
- **WHEN** `sing-gateway print-nft` runs
- **THEN** it invokes the packaged `tproxy_ctrl.sh set --dry-run` path to generate nftables output without mutating host network state

### Requirement: Scoped prerouting capture
The control script SHALL restrict prerouting TPROXY handling to explicitly configured ingress scope when scope options are provided. Traffic outside the configured ingress scope MUST bypass the script-managed TPROXY rules.

#### Scenario: Single ingress interface is scoped
- **WHEN** the user runs `set --in-iface=eth0 --dry-run`
- **THEN** the generated prerouting rules only apply TPROXY handling to packets entering `eth0`

#### Scenario: Multiple ingress interfaces are scoped
- **WHEN** the user configures more than one allowed ingress interface
- **THEN** generated prerouting rules apply TPROXY handling only to packets entering one of the allowed interfaces

### Requirement: Deterministic prerouting pipeline and hook priority
The control script SHALL generate nftables prerouting rules with deterministic hook priorities and rule ordering suitable for TPROXY before route lookup. Divert handling, scoped capture, local-service bypass, FakeIP handling, DNS hijack, direct/custom bypass, and default TPROXY handling MUST have an explicit order.

#### Scenario: Hook priority is visible in dry-run output
- **WHEN** the user runs `set --dry-run`
- **THEN** generated nftables output declares the prerouting hook priorities used for divert and main TPROXY handling

#### Scenario: FakeIP precedes private bypass
- **WHEN** the user runs `set --fake-ip4=198.18.0.0/15 --dry-run`
- **THEN** generated FakeIP TPROXY handling appears before private, reserved, or custom bypass handling for IPv4 destinations

#### Scenario: Local-service bypass precedes DNS hijack
- **WHEN** the user runs `set --hijack-dns --dry-run` with local DNS listener exclusions configured
- **THEN** generated local DNS listener bypass rules appear before generated DNS hijack rules

### Requirement: Explicit local service bypass
The control script SHALL support explicit bypass configuration for proxy gateway service addresses and ports. Bypassed local services MUST include DNS listeners, management ports, explicit HTTP/SOCKS proxy ports, TPROXY listener ports, and health-check ports when configured.

#### Scenario: Local DNS listener bypass is generated
- **WHEN** the user configures a local service bypass for the proxy gateway DNS listener
- **THEN** packets destined to that local DNS listener are accepted before DNS hijack or default TPROXY rules

#### Scenario: TPROXY listener is not exposed as ordinary service traffic
- **WHEN** the user configures the TPROXY listener port as a local service bypass
- **THEN** packets destined to that local listener are not recursively TPROXY intercepted by generated prerouting rules

### Requirement: DNS hijack safety
When DNS hijack is enabled, the control script SHALL only hijack eligible DNS traffic after excluding local DNS listeners, internal DNS servers, management DNS paths, and configured DNS bypass destinations. DNS traffic explicitly delivered to the proxy gateway DNS listener by upstream DNAT MUST NOT be hijacked.

#### Scenario: DNATed proxy DNS is bypassed
- **WHEN** DNS hijack is enabled and the user configures the proxy gateway DNS listener as a bypass destination
- **THEN** generated rules accept traffic to that DNS listener before DNS hijack handling

#### Scenario: External DNS remains eligible for hijack
- **WHEN** DNS hijack is enabled and DNS traffic does not match local or configured DNS bypasses
- **THEN** generated rules mark and TPROXY the eligible DNS traffic

### Requirement: FakeIP precedence and conflict handling
The control script SHALL treat configured FakeIP CIDRs as TPROXY capture targets that take precedence over private, reserved, and custom bypass CIDRs. The script MUST reject or explicitly warn about user configuration that would cause FakeIP CIDRs to be bypassed.

#### Scenario: FakeIP is captured despite reserved range membership
- **WHEN** the user configures `--fake-ip4=198.18.0.0/15 --dry-run`
- **THEN** generated rules TPROXY that FakeIP range before any rule that accepts private or reserved IPv4 destinations

#### Scenario: Exact FakeIP bypass conflict is rejected
- **WHEN** the user configures the same CIDR as both FakeIP and custom bypass
- **THEN** the script exits with an error before applying nftables or routing changes

### Requirement: Custom kernel bypass sets
The control script SHALL support configured IPv4 and IPv6 destination bypass CIDRs that are accepted before default TPROXY handling. These bypasses represent nft/kernel bypass and MUST be documented separately from sing-box `direct` outbound behavior.

#### Scenario: Custom IPv4 bypass is generated
- **WHEN** the user runs `set --bypass4=10.0.0.0/8,192.168.0.0/16 --dry-run`
- **THEN** generated rules accept matching IPv4 destinations before default TPROXY handling

#### Scenario: Custom IPv6 bypass is generated
- **WHEN** the user runs `set --stack=all --bypass6=fc00::/7,fe80::/10 --dry-run`
- **THEN** generated rules accept matching IPv6 destinations before default TPROXY handling

### Requirement: Kernel bypass prerequisites are explicit
The control script SHALL distinguish TPROXY local-route setup from kernel bypass forwarding. IPv4 or IPv6 forwarding MUST NOT be treated as a universal TPROXY prerequisite; forwarding requirements SHALL be tied to explicit kernel-bypass behavior or documented compatibility mode.

#### Scenario: TPROXY setup can avoid unconditional forwarding
- **WHEN** kernel bypass is not enabled by configuration
- **THEN** setup does not require enabling IP forwarding solely for TPROXY local-route handling

#### Scenario: Kernel bypass requires forwarding acknowledgement
- **WHEN** kernel bypass behavior is enabled
- **THEN** setup checks or applies the required forwarding state and surfaces the external OPNsense NAT, anti-spoofing, and PBR loop-prevention prerequisites

### Requirement: Reverse path filtering safety
The control script SHALL check or configure reverse path filtering state needed for single-arm proxy gateway operation. Unsafe `rp_filter` values for `all`, `default`, or configured ingress interfaces MUST be reported before applying rules, unless the script is explicitly configured to set safe values.

#### Scenario: Unsafe rp_filter is reported
- **WHEN** setup detects strict reverse path filtering on an ingress path used for TPROXY
- **THEN** the script reports the unsafe setting before applying or completing gateway setup

#### Scenario: Safe rp_filter can be applied explicitly
- **WHEN** the user opts into automatic sysctl adjustment
- **THEN** setup applies safe `rp_filter` values for the relevant scopes before completing gateway setup

### Requirement: Local output proxying uses symmetric exclusions
When local proxying is enabled, generated output rules SHALL bypass loopback, ignored process UID, ignored mark, local service listeners, DNS bypass destinations, custom bypass CIDRs, and proxy process traffic before local DNS, FakeIP, or default reroute handling.

#### Scenario: Ignore mark cannot conflict with route mark
- **WHEN** the user configures `--proxy-local` with the same value for ignore mark and route mark
- **THEN** the script exits with an error before applying nftables or routing changes

#### Scenario: Local service bypass applies in output mode
- **WHEN** the user runs `set --proxy-local` with local service bypasses configured
- **THEN** generated output rules bypass those local service destinations before generic local reroute handling

### Requirement: IPv6 control behavior is explicit
The control script SHALL make IPv6 TPROXY behavior explicit through stack selection, IPv6 FakeIP configuration, IPv6 bypasses, and IPv6 non-TCP/UDP bypass. ICMPv6, neighbor discovery, router advertisement, multicast listener discovery, and PMTUD-related traffic MUST NOT be captured by TPROXY rules.

#### Scenario: IPv6 control plane traffic is bypassed
- **WHEN** the user runs `set --stack=v6 --dry-run`
- **THEN** generated rules bypass non-TCP/UDP IPv6 traffic before any IPv6 TPROXY handling

#### Scenario: IPv6 disabled mode omits IPv6 handling
- **WHEN** the user runs `set --stack=v4 --dry-run`
- **THEN** generated rules do not contain active IPv6 TPROXY, FakeIP, or custom IPv6 bypass handling
