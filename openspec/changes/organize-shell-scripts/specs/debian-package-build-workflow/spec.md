## MODIFIED Requirements

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
