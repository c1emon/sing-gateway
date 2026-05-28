## ADDED Requirements

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
