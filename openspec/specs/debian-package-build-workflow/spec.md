## Purpose
Define maintainer-facing Debian package build, inspection, validation, and release publication workflows.

## Requirements

### Requirement: Maintainer build workflow documentation
The repository SHALL document a complete maintainer workflow for building the `sing-gateway` Debian binary package with standard Debian tooling.

#### Scenario: Build prerequisites are documented
- **WHEN** a maintainer reads the Debian package build workflow
- **THEN** it lists the required Debian build tools and package dependencies needed to build and inspect the package locally

#### Scenario: Canonical build command is documented
- **WHEN** a maintainer reads the Debian package build workflow
- **THEN** it identifies `dpkg-buildpackage -us -uc -b` or an equivalent `debuild -us -uc -b` invocation as the canonical binary package build path

#### Scenario: Artifact location is documented
- **WHEN** a maintainer builds the Debian package from the repository root
- **THEN** the workflow explains where the `.deb`, `.changes`, and `.buildinfo` artifacts are expected to appear

### Requirement: Package artifact inspection workflow
The repository SHALL document how maintainers inspect the generated Debian package artifact before installing it, including verification that source-tree script organization does not change installed script paths.

#### Scenario: Metadata inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a command to inspect package control metadata such as package name, version, architecture, dependencies, maintainer, and description

#### Scenario: File layout inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a command to inspect the file paths that the package will install
- **AND** it includes checking that `/usr/bin/sing-gateway` and `/usr/lib/sing-gateway/tproxy_ctrl.sh` remain present after moving source scripts under `scripts/`

#### Scenario: Debian policy review is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a lintian review step for the generated package artifacts

### Requirement: Native package metadata validation workflow
The repository SHALL document validation steps for inspecting native Debian source metadata and GPL-3+ licensing metadata before package distribution.

#### Scenario: Native source format inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a check that `debian/source/format` declares `3.0 (native)`
- **AND** it includes a check that the changelog version is native and does not include a Debian revision suffix

#### Scenario: GPL-3+ metadata inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a check that project and Debian copyright metadata declare GPL-3+ licensing

### Requirement: Package lifecycle validation workflow
The repository SHALL document validation steps for installing, enabling, removing, and purging the built Debian package in a safe test environment.

#### Scenario: Install inertness is validated
- **WHEN** a maintainer follows the package lifecycle validation workflow
- **THEN** it includes a check that package installation does not create the active `sing-box.service` drop-in
- **AND** it confirms that gateway activation still requires explicit `sing-gateway enable`

#### Scenario: Installed commands and files are validated
- **WHEN** a maintainer follows the package lifecycle validation workflow
- **THEN** it includes checks for the installed `sing-gateway` command and expected package-owned files

#### Scenario: Remove and purge behavior is validated
- **WHEN** a maintainer follows the package lifecycle validation workflow
- **THEN** it includes remove and purge checks that exercise maintainer-script cleanup behavior without requiring service restarts

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

### Requirement: Optional build helper preserves Debian tooling semantics
Any convenience build helper SHALL remain a thin wrapper around the canonical Debian package build command.

#### Scenario: Helper delegates to canonical tooling
- **WHEN** the repository provides a helper such as a script or Make target for building the Debian package
- **THEN** the helper invokes standard Debian build tooling rather than assembling package contents independently

#### Scenario: Helper does not duplicate package metadata
- **WHEN** the repository provides a Debian package build helper
- **THEN** package metadata and file installation rules remain sourced from `debian/` metadata files

### Requirement: GitHub Release publication workflow documentation
The repository SHALL document how maintainers publish Debian package artifacts to GitHub Release through the tag-triggered release workflow.

#### Scenario: Release trigger is documented
- **WHEN** a maintainer reads the Debian package build workflow
- **THEN** it SHALL explain that GitHub Release package publication is triggered only by pushing tags matching `v*`

#### Scenario: Version consistency rule is documented
- **WHEN** a maintainer reads the Debian package build workflow
- **THEN** it SHALL explain that the tag version without the leading `v` must match the version declared in `debian/changelog`

#### Scenario: Release artifacts are documented
- **WHEN** a maintainer reads the Debian package build workflow
- **THEN** it SHALL identify the `.deb`, `.changes`, and `.buildinfo` files as GitHub Release assets produced by the release workflow

#### Scenario: Apt repository non-goal is documented
- **WHEN** a maintainer reads the Debian package build workflow
- **THEN** it SHALL state that the workflow publishes GitHub Release assets only
- **AND** it SHALL state that the workflow does not publish an apt repository or apt package indexes
