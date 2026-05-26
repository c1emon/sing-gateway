## Why

The current Debian packaging has unsafe removal behavior and incomplete source/licensing metadata: package removal can clean host network state without proof that `sing-gateway` enabled it, purge can recursively delete administrator files under `/etc/sing-gateway`, and the package lacks a declared native source format and redistributable license metadata.

This change hardens the package lifecycle so installation remains inert, enabled integration is explicitly tracked, removal only cleans known managed state, and package metadata is suitable for GPL-3+ native Debian package distribution.

## What Changes

- Track enabled gateway integration with a persistent state file under `/var/lib/sing-gateway/`.
- Change active systemd drop-in installation from a copied file to a managed symlink pointing at the packaged template.
- Make `sing-gateway disable` and Debian `prerm remove|deconfigure` clean nftables and policy-routing state only when the enabled state file exists.
- Make cleanup use persisted parameters from the enabled state file rather than the current `/etc/sing-gateway/gateway.conf` values.
- Make purge cleanup non-recursive and safe for administrator-owned files under `/etc/sing-gateway`.
- Convert Debian source metadata to native package format.
- Remove duplicate documentation installation declarations.
- Declare GPL-3+ licensing in project and Debian metadata.
- Update documentation and lifecycle validation guidance for the new symlink/state behavior.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `sing-gateway-debian-package`: harden enable/disable, removal, purge, source-format, and licensing requirements for the Debian companion package.
- `debian-package-build-workflow`: update build and inspection expectations for native source format, GPL-3+ metadata, and lifecycle validation of state-backed cleanup.

## Impact

- Affected package metadata: `debian/control`, `debian/changelog`, `debian/copyright`, `debian/install`, `debian/source/format`, and possibly maintainer scripts.
- Affected lifecycle scripts: `debian/prerm`, `debian/postrm`.
- Affected CLI behavior: `sing-gateway enable`, `sing-gateway disable`, and cleanup behavior used during package removal.
- Affected documentation: `README.md`, `docs/sing-gateway.md`, and any package build/lifecycle validation notes.
- Affected tests: shell regression tests and package lifecycle validation should cover symlink drop-in creation, state-file cleanup, safe purge behavior, and no-cleanup behavior when no state file exists.
