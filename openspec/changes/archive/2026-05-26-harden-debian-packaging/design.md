## Context

`sing-gateway` is intentionally inert when installed as a Debian companion package: users must explicitly enable the `sing-box.service` integration before the package mutates nftables, policy routing, or systemd unit state. Review of the current packaging found lifecycle gaps that weaken that guarantee:

- `prerm remove|deconfigure` can call `sing-gateway disable` without proof that this package previously enabled integration.
- `sing-gateway disable` currently derives cleanup parameters from current configuration, which may differ from the parameters used when gateway state was enabled.
- `postrm purge` recursively deletes `/etc/sing-gateway`, which may contain administrator-owned files.
- The active systemd drop-in is copied into `/etc`, so packaged template updates do not flow to enabled installations.
- Debian source and copyright metadata are not yet aligned with a redistributable native GPL-3+ package.

This change deliberately does not support migration of old enabled installations that lack the new state file. Absence of the new state file means removal must not clean network state.

## Goals / Non-Goals

**Goals:**
- Preserve inert install behavior.
- Make enable/disable state explicit through `/var/lib/sing-gateway/enabled`.
- Use persisted enable-time cleanup parameters for `disable` and package removal cleanup.
- Install the active systemd drop-in as a managed symlink to the packaged template.
- Ensure package removal only cleans network state when the state file proves `sing-gateway` enabled it.
- Ensure purge avoids recursive deletion of administrator-owned configuration directories.
- Convert Debian metadata to native source format and GPL-3+ licensing.
- Remove duplicate documentation installation rules.

**Non-Goals:**
- No compatibility or migration path for old copy-based drop-ins that predate the state file.
- No automatic service start, restart, or stop during install, enable, disable, remove, upgrade, or purge.
- No automatic synchronization of user-edited `/etc` drop-in files; the enabled drop-in is expected to be a symlink.
- No redesign of `tproxy_ctrl.sh` rule generation beyond passing persisted cleanup parameters.

## Decisions

### State file is the authority for managed cleanup

`sing-gateway enable` will write an enabled-state file under `/var/lib/sing-gateway/enabled` after successful validation and drop-in activation. The file will contain only shell-safe assignment values needed to clean the state that was enabled, such as:

```sh
STACK='v4'
NF_TABLE='transparent_proxy'
ROUTE_TABLE4='100'
ROUTE_TABLE6='106'
ROUTE_MARK='0x01'
DROPIN_FILE='/etc/systemd/system/sing-box.service.d/10-sing-gateway.conf'
DROPIN_TARGET='/usr/lib/sing-gateway/sing-box.service.d/10-sing-gateway.conf'
```

Rationale: cleanup must reflect enable-time state, not whatever `/etc/sing-gateway/gateway.conf` says later.

Alternatives considered:
- Current config cleanup: simple but can clean the wrong nftables table or route table after config changes.
- Drop-in existence only: proves systemd integration may exist, but does not capture cleanup parameters.
- Marker comments only: helps identify files, but does not solve stale cleanup parameters.

### No state file means no network cleanup

Package removal and `sing-gateway disable` will only invoke `tproxy_ctrl.sh unset` through persisted state when `/var/lib/sing-gateway/enabled` exists. If the state file is absent, package removal will not attempt network cleanup.

Rationale: this favors safety over legacy cleanup. The user explicitly chose not to support old-version migration.

### Active drop-in is a symlink to the packaged template

`sing-gateway enable` will create:

```text
/etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
  -> /usr/lib/sing-gateway/sing-box.service.d/10-sing-gateway.conf
```

Rationale: the drop-in is static lifecycle glue, while user configuration belongs in `/etc/sing-gateway/gateway.conf`. Symlinking lets package upgrades update lifecycle hooks without copying new template content into `/etc`.

If the active drop-in path exists and is not the managed symlink, enable should refuse unless an explicit force behavior is already intended for replacing active integration. Disable should not delete a non-managed file.

### Purge is non-recursive and conservative

`postrm purge` will remove known state files and managed drop-in links where safe, then remove empty directories with `rmdir`. It will not recursively delete `/etc/sing-gateway`.

Rationale: Debian purge may remove package conffiles, but maintainer scripts should not delete administrator-created files in a configuration directory.

### Package is native and GPL-3+

The package will use `3.0 (native)` source format and changelog versioning without a Debian revision suffix. Project and Debian copyright metadata will declare GPL-3+.

Rationale: this repository treats Debian metadata as the canonical package source and the user selected GPL-3+ redistribution terms.

## Risks / Trade-offs

- **Old enabled installations may be left behind** → Accepted. This change intentionally does not infer or migrate old state without the new state file.
- **State file can become stale if users manually mutate nftables/routes** → Cleanup remains best-effort and limited to recorded managed identifiers.
- **Users may replace the symlink with a regular file** → Disable should avoid deleting non-managed files and may warn; documentation should explain that drop-in customization is unsupported and configuration belongs in `gateway.conf`.
- **Native package format changes version semantics** → Changelog version must drop the `-1` Debian revision to remain consistent with `3.0 (native)`.
- **GPL-3+ licensing affects downstream obligations** → Documentation and copyright metadata should be explicit so redistribution terms are clear.

## Migration Plan

1. Add native source format and GPL-3+ metadata.
2. Update `sing-gateway enable` to create the symlink and write state.
3. Update `sing-gateway disable` to read state, clean using persisted parameters, remove managed symlink, and remove state.
4. Update maintainer scripts to rely on the state file for removal cleanup and to use conservative purge cleanup.
5. Update documentation and tests.

Rollback is manual: remove the state file and managed symlink, then run explicit cleanup commands if needed. Package scripts must not infer legacy state during rollback.

## Open Questions

- Should `sing-gateway enable --force` replace an existing regular drop-in at the active path, or should it only bypass configuration validation? Default design keeps `--force` limited to validation bypass unless implementation review finds existing behavior requires replacement.
- Should state-file writes be atomic via temporary file plus rename? Recommended yes, but exact helper shape is an implementation detail.
