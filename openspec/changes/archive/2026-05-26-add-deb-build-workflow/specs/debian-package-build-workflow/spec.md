## ADDED Requirements

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
The repository SHALL document how maintainers inspect the generated Debian package artifact before installing it.

#### Scenario: Metadata inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a command to inspect package control metadata such as package name, version, architecture, dependencies, maintainer, and description

#### Scenario: File layout inspection is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a command to inspect the file paths that the package will install

#### Scenario: Debian policy review is documented
- **WHEN** a maintainer follows the package inspection workflow
- **THEN** it includes a lintian review step for the generated package artifacts

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

### Requirement: Optional build helper preserves Debian tooling semantics
Any convenience build helper SHALL remain a thin wrapper around the canonical Debian package build command.

#### Scenario: Helper delegates to canonical tooling
- **WHEN** the repository provides a helper such as a script or Make target for building the Debian package
- **THEN** the helper invokes standard Debian build tooling rather than assembling package contents independently

#### Scenario: Helper does not duplicate package metadata
- **WHEN** the repository provides a Debian package build helper
- **THEN** package metadata and file installation rules remain sourced from `debian/` metadata files
