## Purpose
Define regression coverage for `scripts/tproxy_ctrl.sh`, `scripts/sing-gateway`, and related transparent proxy control behavior.

## Requirements

### Requirement: Dependency-free test entrypoint
The repository SHALL provide a POSIX shell test entrypoint that runs the `tproxy_ctrl.sh` regression suite without requiring external test frameworks or root privileges.

#### Scenario: Run full suite locally
- **WHEN** a developer runs `sh tests/run.sh` from the repository root
- **THEN** the test suite executes using only repository files and standard shell utilities
- **AND** the command exits successfully when all assertions pass

#### Scenario: Report failed assertions
- **WHEN** a test assertion fails
- **THEN** the test runner exits with a non-zero status
- **AND** the output identifies the failing test or assertion

### Requirement: CLI and input validation coverage
The test suite SHALL validate accepted and rejected CLI inputs for `tproxy_ctrl.sh`, including actions, stack values, nft table identifiers, route marks, TProxy ports, route table IDs, UIDs, and FakeIP CIDRs.

#### Scenario: Invalid action and option handling
- **WHEN** validation tests run with missing actions, unknown options, or invalid stack values
- **THEN** the script exits with an error for each invalid invocation

#### Scenario: nft table identifier boundaries
- **WHEN** validation tests run with safe nft table identifiers and unsafe identifiers such as hyphenated names, leading digits, empty names, or shell metacharacters
- **THEN** safe identifiers are accepted in dry-run mode
- **AND** unsafe identifiers are rejected before any save or privileged command side effect

#### Scenario: numeric option boundaries
- **WHEN** validation tests run with boundary values for route marks, TProxy ports, route table IDs, and UIDs
- **THEN** in-range decimal or hexadecimal values are accepted where supported
- **AND** negative, empty, malformed, and out-of-range values are rejected

#### Scenario: FakeIP CIDR boundaries
- **WHEN** validation tests run with representative valid and invalid IPv4 and IPv6 CIDRs
- **THEN** valid CIDRs are accepted for dry-run generation
- **AND** invalid CIDRs are rejected before any save or privileged command side effect

### Requirement: Dry-run nftables generation coverage
The test suite SHALL validate generated `--dry-run` nftables output for stack selection, family guards, DNS hijack, FakeIP, and local proxy behavior using targeted content and ordering assertions.

#### Scenario: stack-specific TProxy generation
- **WHEN** dry-run tests execute default, `--stack=v4`, `--stack=v6`, and `--stack=all` modes
- **THEN** IPv4 TProxy rules are generated only for enabled IPv4 modes with `meta nfproto ipv4` guards
- **AND** IPv6 TProxy rules are generated only for enabled IPv6 modes with `meta nfproto ipv6` guards

#### Scenario: DNS hijack marks policy-routed traffic
- **WHEN** dry-run tests execute DNS hijack modes
- **THEN** generated prerouting DNS rules set the configured route mark before TProxy acceptance
- **AND** generated local output DNS reroute rules set the configured route mark before accepting packets when local proxying is enabled

#### Scenario: FakeIP rules are family-specific and marked
- **WHEN** dry-run tests execute FakeIP modes for IPv4, IPv6, disabled-family, and dual-stack combinations
- **THEN** FakeIP rules are generated only for enabled address families
- **AND** generated FakeIP prerouting and local output rules set the configured route mark

#### Scenario: local proxy bypass ordering
- **WHEN** dry-run tests execute `--proxy-local` with ignore mark and ignore UID combinations
- **THEN** ignore-by-mark and ignore-by-UID bypass rules are generated independently
- **AND** bypass rules appear before DNS, FakeIP, direct, and generic reroute rules in the output chain

### Requirement: Safe side-effect simulation
The test suite SHALL validate non-dry-run behavior through fake `nft`, `ip`, and `sysctl` commands rather than real privileged host operations.

#### Scenario: setup command sequencing
- **WHEN** side-effect tests run `set` for IPv4, IPv6, and dual-stack modes with fake commands on `PATH`
- **THEN** the fake command log records the expected nft table convergence, forwarding enablement, route rule checks or additions, and local route replacement commands for the enabled families

#### Scenario: idempotent route setup
- **WHEN** fake `ip rule show` reports that the managed rule already exists
- **THEN** setup tests confirm that the script does not add a duplicate rule
- **AND** still replaces the managed local route

#### Scenario: cleanup tolerates absent state
- **WHEN** side-effect tests run `unset` while fake deletion commands report missing managed resources
- **THEN** the script exits successfully
- **AND** the fake command log contains cleanup attempts for the managed nftables and routing resources

#### Scenario: cleanup does not disable forwarding
- **WHEN** side-effect tests run `unset`
- **THEN** the fake command log does not contain commands that set IPv4 or IPv6 forwarding to disabled

### Requirement: Invalid input prevents side effects
The test suite SHALL prove that invalid inputs fail before generated nft scripts are saved or privileged commands are invoked.

#### Scenario: invalid save request does not write file
- **WHEN** tests run an invalid invocation with `--save=<file>`
- **THEN** the script exits with an error
- **AND** the requested save file is not created

#### Scenario: invalid non-dry-run request invokes no privileged commands
- **WHEN** tests run invalid non-dry-run invocations with fake privileged commands on `PATH`
- **THEN** the fake command log remains empty

### Requirement: Routing failure rollback coverage
The test suite SHALL validate rollback behavior when nft application succeeds but routing setup fails.

#### Scenario: route setup failure rolls back nft table
- **WHEN** fake `nft` application succeeds and fake route setup fails during `set`
- **THEN** the script exits with an error
- **AND** the fake command log shows a subsequent nft table deletion rollback for the managed table

### Requirement: Optional nft parser validation
The test suite SHOULD support optional generated nft script parser validation when a compatible `nft` binary is available, but this validation MUST NOT be required for the default suite to run.

#### Scenario: nft unavailable
- **WHEN** the default test suite runs on a system without `nft`
- **THEN** required tests still execute and can pass

#### Scenario: nft parser check enabled
- **WHEN** a compatible `nft` binary is available and parser validation is enabled
- **THEN** generated nft scripts are checked with safe parse or check mode without mutating host nftables state

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
