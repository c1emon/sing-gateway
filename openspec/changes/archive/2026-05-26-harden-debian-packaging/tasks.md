## 1. Debian Metadata

- [x] 1.1 Add `debian/source/format` with `3.0 (native)` and update `debian/changelog` to native versioning without a Debian revision suffix.
- [x] 1.2 Update project and Debian copyright metadata to declare GPL-3+ licensing, including adding or updating the top-level license file.
- [x] 1.3 Remove duplicate documentation installation so each documentation file is installed through a single Debian helper mechanism.

## 2. State-Backed CLI Lifecycle

- [x] 2.1 Add state-file path handling for `/var/lib/sing-gateway/enabled`, including safe directory creation and atomic state-file writes.
- [x] 2.2 Persist enable-time cleanup parameters after successful `sing-gateway enable` resolution.
- [x] 2.3 Update `sing-gateway enable` to create the active systemd drop-in as a managed symlink to the packaged template.
- [x] 2.4 Update `sing-gateway disable` to use persisted state parameters for cleanup rather than current gateway configuration.
- [x] 2.5 Ensure `sing-gateway disable` does not invoke network cleanup when no enabled-state file exists.
- [x] 2.6 Ensure `sing-gateway disable` removes only the managed drop-in symlink and does not delete unrelated regular files or symlinks.

## 3. Debian Maintainer Scripts

- [x] 3.1 Update `debian/prerm` so `remove|deconfigure` cleans integration only when the enabled-state file exists.
- [x] 3.2 Preserve upgrade behavior so package upgrades do not remove the active drop-in, call unset, or restart sing-box.
- [x] 3.3 Update `debian/postrm purge` to remove residual enabled-state files and managed symlink paths safely.
- [x] 3.4 Ensure purge uses non-recursive directory removal and never recursively deletes `/etc/sing-gateway`.

## 4. Documentation

- [x] 4.1 Update README and Debian package documentation to describe symlink-based drop-in activation.
- [x] 4.2 Document `/var/lib/sing-gateway/enabled` as the authority for managed cleanup and removal behavior.
- [x] 4.3 Update maintainer build and inspection workflow documentation for native source format and GPL-3+ metadata.
- [x] 4.4 Update lifecycle validation documentation for enable state, symlink checks, removal without state, and safe purge behavior.

## 5. Tests and Validation

- [x] 5.1 Add or update shell regression tests for symlink drop-in creation and managed symlink removal.
- [x] 5.2 Add or update tests for state-file creation and persisted-parameter cleanup.
- [x] 5.3 Add or update tests proving no network cleanup is invoked when the enabled-state file is absent.
- [x] 5.4 Add or update tests for safe purge behavior that preserves administrator-created files under `/etc/sing-gateway`.
- [x] 5.5 Run the project regression test suite and Debian package build/lint inspection commands documented for maintainers.
