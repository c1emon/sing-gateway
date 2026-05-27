## ADDED Requirements

### Requirement: Hardened rule generation coverage
The test suite SHALL validate dry-run nftables output for scoped prerouting capture, deterministic hook priority, divert ordering, local service bypass ordering, FakeIP precedence, DNS hijack safety, custom bypass sets, and default TPROXY fallback.

#### Scenario: Scoped prerouting dry-run assertion
- **WHEN** dry-run tests execute with configured ingress interface scope
- **THEN** assertions verify that generated prerouting TPROXY rules are guarded by that scope

#### Scenario: Rule order dry-run assertion
- **WHEN** dry-run tests execute with FakeIP, DNS hijack, local service bypass, and custom bypass configured together
- **THEN** assertions verify local service bypass precedes DNS hijack, FakeIP precedes private/custom bypass, and default TPROXY handling is last among eligible TCP/UDP paths

### Requirement: Hardened validation coverage
The test suite SHALL validate accepted and rejected inputs for new hardening options, including ingress interface lists, bypass CIDRs, service bypass ports, sysctl policy options, route marks, ignore marks, and FakeIP/bypass conflicts.

#### Scenario: Invalid ingress scope is rejected
- **WHEN** validation tests provide malformed ingress interface configuration
- **THEN** the script exits with an error before generated files or privileged command side effects

#### Scenario: FakeIP bypass conflict is rejected
- **WHEN** validation tests configure the same CIDR as both FakeIP and custom bypass
- **THEN** the script exits with an error before applying nftables or routing changes

#### Scenario: Ignore mark route mark conflict is rejected
- **WHEN** validation tests configure local proxying with identical ignore mark and route mark values
- **THEN** the script exits with an error before applying nftables or routing changes

### Requirement: Sysctl and forwarding side-effect coverage
The test suite SHALL validate sysctl-related behavior through fake commands, including rp_filter checks or application, forwarding behavior, and cleanup ownership boundaries.

#### Scenario: rp_filter unsafe state is detected
- **WHEN** side-effect simulation reports unsafe rp_filter values for configured TPROXY ingress scope
- **THEN** the script reports the unsafe state according to the configured sysctl policy

#### Scenario: Forwarding is not unconditional
- **WHEN** side-effect tests run setup without kernel bypass enabled
- **THEN** the fake command log does not show forwarding enabled solely as a TPROXY prerequisite

#### Scenario: Kernel bypass forwarding is explicit
- **WHEN** side-effect tests run setup with kernel bypass enabled
- **THEN** the fake command log records the expected forwarding checks or sysctl changes

### Requirement: Local output hardening coverage
The test suite SHALL validate that `--proxy-local` output rules use loop-prevention and bypass ordering equivalent to the hardened prerouting model where applicable.

#### Scenario: Output chain bypass order
- **WHEN** dry-run tests execute local proxying with local service bypass, custom bypass, FakeIP, and DNS hijack options
- **THEN** assertions verify ignore rules and local output bypasses appear before local DNS, FakeIP, and generic reroute rules

### Requirement: Documentation and diagnostics coverage
The test suite SHALL validate generated dry-run output and command diagnostics sufficiently to support production review before applying rules.

#### Scenario: Dry-run exposes hook priorities and scopes
- **WHEN** dry-run tests execute hardened configurations
- **THEN** generated output includes visible hook priorities, ingress scopes, bypass sets, and TPROXY target paths for review

#### Scenario: Optional nft parser validation covers hardened output
- **WHEN** optional nft parser validation is available
- **THEN** parser validation checks representative hardened generated rulesets without mutating host nftables state
