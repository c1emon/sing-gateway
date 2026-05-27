## ADDED Requirements

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
