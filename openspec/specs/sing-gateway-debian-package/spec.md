## ADDED Requirements

### Requirement: Inert Debian companion package installation
The package SHALL install `sing-gateway` as a Debian companion package for sing-box without enabling gateway integration or mutating host network state during installation, and its Debian metadata SHALL be complete enough to build the binary package with standard Debian tooling from source scripts stored under a dedicated source directory.

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

#### Scenario: Source scripts install to stable package paths
- **WHEN** the package is built from source scripts stored under `scripts/`
- **THEN** the package installs `scripts/sing-gateway` as `/usr/bin/sing-gateway`
- **AND** it installs `scripts/tproxy_ctrl.sh` as `/usr/lib/sing-gateway/tproxy_ctrl.sh`
- **AND** the package remains architecture-independent

### Requirement: State-backed managed integration tracking
The `sing-gateway` CLI SHALL persist enabled integration state under `/var/lib/sing-gateway/` so later cleanup uses the parameters that were active when integration was enabled.

#### Scenario: Enable records cleanup parameters
- **WHEN** the user runs `sing-gateway enable` as root and the command succeeds
- **THEN** the command writes an enabled-state file under `/var/lib/sing-gateway/`
- **AND** the file records the effective stack, nftables table name, route table IDs, route mark, active drop-in path, and packaged drop-in target needed for future cleanup

#### Scenario: Cleanup uses persisted parameters
- **WHEN** `sing-gateway disable` cleans managed nftables and policy-routing state
- **THEN** it uses cleanup parameters from the enabled-state file
- **AND** it does not derive cleanup identifiers from the current `/etc/sing-gateway/gateway.conf`

#### Scenario: Missing state prevents network cleanup
- **WHEN** `sing-gateway disable` or Debian package removal runs and no enabled-state file exists
- **THEN** it does not invoke `tproxy_ctrl.sh unset`
- **AND** it does not delete nftables tables or policy-routing rules

### Requirement: Managed systemd drop-in symlink
The `sing-gateway` CLI SHALL activate systemd integration by creating a managed symlink from the active systemd drop-in path to the packaged drop-in template.

#### Scenario: Enable creates symlinked drop-in
- **WHEN** the user runs `sing-gateway enable` as root and the command succeeds
- **THEN** `/etc/systemd/system/sing-box.service.d/10-sing-gateway.conf` is a symlink
- **AND** the symlink target is the packaged template under `/usr/lib/sing-gateway/sing-box.service.d/`

#### Scenario: Disable removes only managed symlink
- **WHEN** `sing-gateway disable` removes active systemd integration
- **THEN** it removes the active drop-in only if it is the managed symlink to the packaged template
- **AND** it does not delete a regular file or unrelated symlink at the active drop-in path

### Requirement: Native GPL-3+ Debian package metadata
The Debian package metadata SHALL describe `sing-gateway` as a native Debian source package with GPL-3+ licensing.

#### Scenario: Source format is native
- **WHEN** the Debian source metadata is inspected
- **THEN** `debian/source/format` declares `3.0 (native)`
- **AND** the changelog version does not include a Debian revision suffix

#### Scenario: License metadata permits GPL-3+ redistribution
- **WHEN** project and Debian copyright metadata are inspected
- **THEN** they declare GPL-3+ licensing terms
- **AND** Debian copyright metadata points to the system GPL-3 license text location where appropriate

#### Scenario: Documentation is installed through a single Debian mechanism
- **WHEN** Debian package file-installation metadata is inspected
- **THEN** each documentation file is declared for installation through one Debian helper mechanism only

### Requirement: Explicit enable and disable commands
The `sing-gateway` CLI SHALL require explicit user action to activate or deactivate systemd integration for `sing-box.service`, and deactivation SHALL only clean network state that is proven to have been enabled through persisted `sing-gateway` state.

#### Scenario: Enable installs drop-in without restarting service
- **WHEN** the user runs `sing-gateway enable` as root and validation succeeds
- **THEN** the command installs an active `sing-box.service` drop-in under `/etc/systemd/system/sing-box.service.d/` as a managed symlink to the packaged template
- **AND** it writes enabled integration state under `/var/lib/sing-gateway/`
- **AND** it reloads systemd manager configuration
- **AND** it does not start or restart sing-box
- **AND** it tells the user to restart sing-box to apply the integration

#### Scenario: Enable refuses invalid configuration
- **WHEN** the user runs `sing-gateway enable` and configuration validation fails
- **THEN** the command exits with a non-zero status
- **AND** it does not install or modify the active drop-in
- **AND** it does not write enabled integration state

#### Scenario: Force enable only bypasses pre-enable validation
- **WHEN** the user runs `sing-gateway enable --force`
- **THEN** the command installs the active drop-in without requiring current validation success
- **AND** subsequent `sing-box.service` starts still run fail-closed `sing-gateway check`

#### Scenario: Disable removes integration and cleans managed state
- **WHEN** the user runs `sing-gateway disable` as root and enabled integration state exists
- **THEN** the command removes the active `sing-box.service` drop-in if it is the managed symlink
- **AND** it performs best-effort cleanup of managed nftables and policy-routing state using persisted enabled-state parameters
- **AND** it removes the enabled-state file after cleanup is attempted
- **AND** it reloads systemd manager configuration
- **AND** it does not start or restart sing-box

#### Scenario: Disable without state avoids network cleanup
- **WHEN** the user runs `sing-gateway disable` as root and no enabled integration state exists
- **THEN** the command does not invoke nftables or policy-routing cleanup
- **AND** it does not delete unmanaged active drop-in files
- **AND** it reloads systemd manager configuration only if integration files were changed

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
The package SHALL avoid disrupting active gateway state during upgrades and SHALL clean network state on removal only when persisted `sing-gateway` enabled state exists.

#### Scenario: Package upgrade preserves active integration
- **WHEN** the package is upgraded
- **THEN** maintainer scripts do not remove the active drop-in
- **AND** they do not call `sing-gateway unset`
- **AND** they do not restart sing-box

#### Scenario: Package removal cleans state-backed managed integration
- **WHEN** the package is removed rather than upgraded and the enabled-state file exists
- **THEN** maintainer scripts remove the active drop-in if it is the managed symlink
- **AND** they perform best-effort cleanup of managed nftables and policy-routing state using persisted enabled-state parameters while package commands are still available
- **AND** they remove the enabled-state file after cleanup is attempted
- **AND** they do not restart sing-box

#### Scenario: Package removal without state avoids network cleanup
- **WHEN** the package is removed rather than upgraded and no enabled-state file exists
- **THEN** maintainer scripts do not call `sing-gateway disable`
- **AND** they do not invoke `tproxy_ctrl.sh unset`
- **AND** they do not delete nftables tables or policy-routing rules

#### Scenario: Package purge removes residual managed files safely
- **WHEN** the package is purged
- **THEN** maintainer scripts remove residual enabled-state files and managed drop-in symlinks where safe
- **AND** they remove empty package-created directories with non-recursive directory removal
- **AND** they do not recursively delete `/etc/sing-gateway`
- **AND** they tolerate missing non-essential dependencies
