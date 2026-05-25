## ADDED Requirements

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
