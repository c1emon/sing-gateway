## ADDED Requirements

### Requirement: Inert Debian companion package installation
The package SHALL install `sing-gateway` as a Debian companion package for sing-box without enabling gateway integration or mutating host network state during installation, and its Debian metadata SHALL be complete enough to build the binary package with standard Debian tooling.

#### Scenario: Install leaves integration inactive
- **WHEN** the user installs the `sing-gateway` Debian package
- **THEN** the package installs the CLI, low-level control script, default configuration, documentation, and systemd drop-in template
- **AND** it does not create an active `sing-box.service` drop-in
- **AND** it does not restart sing-box, invoke nftables, change policy routing, or change sysctl forwarding values

#### Scenario: Package declares runtime dependencies
- **WHEN** the package metadata is inspected
- **THEN** it declares dependencies on sing-box, nftables, iproute2, procps, jq, and systemd-compatible service management

#### Scenario: Package metadata supports standard binary builds
- **WHEN** a maintainer builds the package with standard Debian binary package tooling
- **THEN** required Debian metadata such as package control information, changelog, copyright information, build rules, and file installation rules are present
- **AND** the build produces a `sing-gateway` binary package without relying on a custom package assembler

### Requirement: Explicit enable and disable commands
The `sing-gateway` CLI SHALL require explicit user action to activate or deactivate systemd integration for `sing-box.service`.

#### Scenario: Enable installs drop-in without restarting service
- **WHEN** the user runs `sing-gateway enable` as root and validation succeeds
- **THEN** the command installs an active `sing-box.service` drop-in under `/etc/systemd/system/sing-box.service.d/`
- **AND** it reloads systemd manager configuration
- **AND** it does not start or restart sing-box
- **AND** it tells the user to restart sing-box to apply the integration

#### Scenario: Enable refuses invalid configuration
- **WHEN** the user runs `sing-gateway enable` and configuration validation fails
- **THEN** the command exits with a non-zero status
- **AND** it does not install or modify the active drop-in

#### Scenario: Force enable only bypasses pre-enable validation
- **WHEN** the user runs `sing-gateway enable --force`
- **THEN** the command installs the active drop-in without requiring current validation success
- **AND** subsequent `sing-box.service` starts still run fail-closed `sing-gateway check`

#### Scenario: Disable removes integration and cleans managed state
- **WHEN** the user runs `sing-gateway disable` as root
- **THEN** the command removes the active `sing-box.service` drop-in if present
- **AND** it performs best-effort cleanup of managed nftables and policy-routing state
- **AND** it reloads systemd manager configuration
- **AND** it does not start or restart sing-box

### Requirement: sing-box service lifecycle integration
When enabled, `sing-gateway` SHALL integrate with `sing-box.service` through systemd drop-in lifecycle hooks that validate before start, apply after successful start, and clean up after stop or failure.

#### Scenario: Start validates before sing-box launches
- **WHEN** `sing-box.service` starts with sing-gateway integration enabled
- **THEN** systemd runs `sing-gateway check` before the sing-box `ExecStart`
- **AND** a failed check prevents sing-box from starting and marks the unit failed

#### Scenario: Gateway rules apply after sing-box starts
- **WHEN** sing-box `ExecStart` succeeds with sing-gateway integration enabled
- **THEN** systemd runs `sing-gateway set`
- **AND** a failed set marks the unit failed and triggers best-effort cleanup of managed gateway state

#### Scenario: Gateway rules clean up after stop or failure
- **WHEN** `sing-box.service` stops, fails during startup, or exits unexpectedly with sing-gateway integration enabled
- **THEN** systemd runs `sing-gateway unset` as post-stop cleanup
- **AND** cleanup tolerates already-absent managed resources

### Requirement: Local sing-box configuration discovery and validation
The wrapper SHALL discover and validate local sing-box configuration before deriving gateway settings or mutating network state.

#### Scenario: Explicit config path takes precedence
- **WHEN** `/etc/sing-gateway/gateway.conf` defines an explicit sing-box config file or config directory
- **THEN** the wrapper uses that explicit source instead of inferring from `sing-box.service`

#### Scenario: Service metadata is used when config is not explicit
- **WHEN** the gateway configuration does not define a sing-box config source
- **THEN** the wrapper inspects `sing-box.service` metadata to infer config file, config directory, working directory, and service user where available

#### Scenario: Default config path is used only when present
- **WHEN** no explicit or service-derived config path is available
- **THEN** the wrapper uses `/etc/sing-box/config.json` only if that file exists
- **AND** otherwise exits with a clear configuration discovery error

#### Scenario: sing-box config validation precedes parsing
- **WHEN** the wrapper resolves a sing-box configuration source
- **THEN** it validates the source with the sing-box CLI before deriving TProxy or FakeIP settings
- **AND** validation failure prevents all nftables, routing, and sysctl side effects

### Requirement: Effective gateway option resolution
The wrapper SHALL resolve exactly one effective TProxy gateway configuration from explicit gateway settings, sing-box metadata, sing-box JSON, and safe defaults.

#### Scenario: Single TProxy inbound is selected automatically
- **WHEN** the validated sing-box configuration contains exactly one inbound with `type` equal to `tproxy`
- **THEN** the wrapper uses that inbound to infer the TProxy listen port

#### Scenario: Multiple TProxy inbounds require tag selection
- **WHEN** the validated sing-box configuration contains multiple TProxy inbounds and no `TPROXY_INBOUND_TAG` is configured
- **THEN** the wrapper exits with a clear ambiguity error before network side effects

#### Scenario: Configured TProxy tag selects matching inbound
- **WHEN** multiple TProxy inbounds exist and `TPROXY_INBOUND_TAG` is configured
- **THEN** the wrapper selects the inbound whose tag exactly matches the configured tag
- **AND** it fails if no matching inbound exists

#### Scenario: Conflicting TProxy port is rejected
- **WHEN** both an explicit TProxy port and a sing-box TProxy inbound port are available but differ
- **THEN** the wrapper exits with a clear conflict error before network side effects

#### Scenario: Unique FakeIP ranges are inferred
- **WHEN** the validated sing-box configuration defines a unique IPv4 or IPv6 FakeIP range
- **THEN** the wrapper passes the corresponding FakeIP CIDR to `tproxy_ctrl.sh`

#### Scenario: Conflicting FakeIP ranges are rejected
- **WHEN** the validated sing-box configuration defines multiple conflicting FakeIP ranges for the same address family
- **THEN** the wrapper exits with a clear ambiguity error before network side effects

#### Scenario: DNS hijack is explicit
- **WHEN** the sing-box configuration contains DNS settings but gateway configuration does not enable DNS hijack
- **THEN** the wrapper does not pass `--hijack-dns` to `tproxy_ctrl.sh`

#### Scenario: Local proxy requires safe bypass
- **WHEN** gateway configuration enables local proxying
- **THEN** the wrapper provides an explicit or safely inferred ignore UID or ignore mark
- **AND** it fails if sing-box appears to run as root and no explicit bypass is configured

### Requirement: Diagnostics expose resolved behavior
The CLI SHALL provide diagnostics that let users inspect the resolved gateway behavior before enabling or restarting sing-box.

#### Scenario: Check reports resolved configuration
- **WHEN** the user runs `sing-gateway check`
- **THEN** the command validates the configuration and prints the resolved sing-box source, selected TProxy inbound, effective stack, FakeIP ranges, local-proxy bypass, and DNS-hijack setting
- **AND** it performs no nftables, routing, or sysctl mutation

#### Scenario: Print command shows delegated low-level invocation
- **WHEN** the user runs `sing-gateway print-command`
- **THEN** the command prints the exact `tproxy_ctrl.sh` command that would be used for setup
- **AND** it performs no nftables, routing, or sysctl mutation

#### Scenario: Print nft shows generated rules
- **WHEN** the user runs `sing-gateway print-nft`
- **THEN** the command prints the nftables rules generated through `tproxy_ctrl.sh set --dry-run`
- **AND** it performs no nftables, routing, or sysctl mutation

### Requirement: Debian removal and upgrade behavior
The package SHALL avoid disrupting active gateway state during upgrades while cleaning managed integration state on removal.

#### Scenario: Package upgrade preserves active integration
- **WHEN** the package is upgraded
- **THEN** maintainer scripts do not remove the active drop-in
- **AND** they do not call `sing-gateway unset`
- **AND** they do not restart sing-box

#### Scenario: Package removal cleans managed integration
- **WHEN** the package is removed rather than upgraded
- **THEN** maintainer scripts remove the active drop-in if present
- **AND** they perform best-effort cleanup of managed nftables and policy-routing state while package commands are still available
- **AND** they do not restart sing-box

#### Scenario: Package purge removes residual configuration
- **WHEN** the package is purged
- **THEN** maintainer scripts remove residual sing-gateway configuration and drop-in files where safe
- **AND** they tolerate missing non-essential dependencies
