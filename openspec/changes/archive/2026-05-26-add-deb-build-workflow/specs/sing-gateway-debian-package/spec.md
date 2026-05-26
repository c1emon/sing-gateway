## MODIFIED Requirements

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
