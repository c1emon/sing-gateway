## 1. Debian Metadata Completion

- [x] 1.1 Add or verify required Debian metadata for standard binary package builds, including changelog and copyright information.
- [x] 1.2 Confirm Debian install rules place the CLI, control script, default configuration, documentation, and drop-in template in the expected package paths.
- [x] 1.3 Confirm maintainer scripts preserve inert install behavior and avoid service start or restart operations.

## 2. Build Workflow Documentation

- [x] 2.1 Document required local build tools and package prerequisites for Debian/Ubuntu maintainers.
- [x] 2.2 Document the canonical `dpkg-buildpackage -us -uc -b` build command and equivalent `debuild -us -uc -b` option.
- [x] 2.3 Document expected build artifact names and output locations.
- [x] 2.4 Document package metadata, package contents, and lintian inspection commands.

## 3. Lifecycle Validation Guidance

- [x] 3.1 Document safe test-environment installation of the built `.deb` artifact.
- [x] 3.2 Document checks that installation remains inert and does not create the active `sing-box.service` drop-in.
- [x] 3.3 Document checks for installed commands, package-owned files, explicit enable behavior, remove behavior, and purge cleanup.

## 4. Optional Convenience Automation

- [x] 4.1 Add a thin local build helper only if it delegates to standard Debian build tooling and does not duplicate package metadata.
- [x] 4.2 Document that the helper is optional and that Debian metadata remains the source of truth.

## 5. Verification

- [x] 5.1 Run the existing shell regression test suite.
- [x] 5.2 Build the Debian binary package with standard Debian tooling in a suitable Debian/Ubuntu environment.
- [x] 5.3 Inspect the generated artifact metadata and file contents.
- [x] 5.4 Run lintian review on generated package artifacts and record any accepted warnings.
  - Accepted warnings from local artifact review: `initial-upload-closes-no-bugs`, `no-manual-page`.
