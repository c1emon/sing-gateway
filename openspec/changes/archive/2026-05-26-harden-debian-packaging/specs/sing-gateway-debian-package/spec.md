## ADDED Requirements

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

## MODIFIED Requirements

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
