## ADDED Requirements

### Requirement: Native package metadata validation workflow
The repository SHALL document validation steps for inspecting native Debian source metadata and GPL-3+ licensing metadata before package distribution.

#### Scenario: Native source format inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a check that `debian/source/format` declares `3.0 (native)`
- **AND** it includes a check that the changelog version is native and does not include a Debian revision suffix

#### Scenario: GPL-3+ metadata inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a check that project and Debian copyright metadata declare GPL-3+ licensing

### Requirement: State-backed lifecycle validation workflow
The repository SHALL document validation steps for safe state-backed enable, disable, remove, and purge behavior.

#### Scenario: Enable state and symlink validation is documented
- **WHEN** a maintainer follows the package lifecycle validation workflow
- **THEN** it includes checks that `sing-gateway enable` creates a managed systemd drop-in symlink
- **AND** it includes checks that enabled integration state is written under `/var/lib/sing-gateway/`

#### Scenario: Removal without state validation is documented
- **WHEN** a maintainer follows the package lifecycle validation workflow
- **THEN** it includes a check that package removal without an enabled-state file does not invoke nftables or policy-routing cleanup

#### Scenario: Purge safety validation is documented
- **WHEN** a maintainer follows the package lifecycle validation workflow
- **THEN** it includes a check that purge does not recursively delete administrator-created files under `/etc/sing-gateway`
