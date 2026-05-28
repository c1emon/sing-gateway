## Purpose
Define tag-triggered GitHub Release publication for generated Debian package artifacts.

## Requirements

### Requirement: Tag-triggered Debian package release workflow
The repository SHALL provide a GitHub Actions workflow that publishes Debian package artifacts only for version tag pushes.

#### Scenario: Version tag starts release publishing
- **WHEN** a maintainer pushes a Git tag matching `v*`
- **THEN** the GitHub Actions release workflow SHALL run
- **AND** it SHALL build the Debian binary package from the repository checkout

#### Scenario: Non-tag changes do not publish releases
- **WHEN** a maintainer pushes a branch commit or opens a pull request
- **THEN** the GitHub Actions release workflow SHALL NOT create a GitHub Release
- **AND** it SHALL NOT upload release assets

### Requirement: Release version consistency gate
The release workflow SHALL require the pushed tag version to match the Debian changelog version before publishing artifacts.

#### Scenario: Matching tag and changelog versions continue
- **WHEN** the release workflow runs for tag `vX.Y.Z`
- **AND** `debian/changelog` declares version `X.Y.Z`
- **THEN** the workflow SHALL continue to package validation and publishing

#### Scenario: Mismatched tag and changelog versions fail before publishing
- **WHEN** the release workflow runs for tag `vX.Y.Z`
- **AND** `debian/changelog` declares a different version
- **THEN** the workflow SHALL fail before creating or updating release assets

### Requirement: Standard Debian tooling release build
The release workflow SHALL build release artifacts using standard Debian package tooling and the repository's existing Debian metadata.

#### Scenario: Package is built with canonical tooling
- **WHEN** the release workflow builds the package
- **THEN** it SHALL invoke `dpkg-buildpackage -us -uc -b` or an equivalent `debuild -us -uc -b` command
- **AND** package metadata and file installation rules SHALL remain sourced from `debian/` metadata files

### Requirement: Strict package validation before publishing
The release workflow SHALL validate the generated Debian package artifacts before uploading them to GitHub Release.

#### Scenario: Package inspection runs before upload
- **WHEN** the release workflow has built package artifacts
- **THEN** it SHALL inspect package metadata with `dpkg-deb --info`
- **AND** it SHALL inspect package contents with `dpkg-deb --contents`

#### Scenario: Lintian failure blocks release upload
- **WHEN** `lintian` reports a failure for the generated package artifacts
- **THEN** the release workflow SHALL fail
- **AND** it SHALL NOT upload Debian package artifacts to GitHub Release

### Requirement: GitHub Release artifact publication
The release workflow SHALL publish generated Debian package artifacts as GitHub Release assets after successful validation.

#### Scenario: Release assets are uploaded after validation succeeds
- **WHEN** the release workflow validation succeeds for tag `vX.Y.Z`
- **THEN** it SHALL create the corresponding GitHub Release if needed
- **AND** it SHALL upload the generated `.deb`, `.changes`, and `.buildinfo` artifacts as release assets

#### Scenario: Apt repository is not published
- **WHEN** the release workflow completes
- **THEN** it SHALL NOT publish apt repository metadata
- **AND** it SHALL NOT publish package index files such as `Packages`, `Release`, or `InRelease`
