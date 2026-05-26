## Why

The repository currently keeps executable shell scripts at the root, mixed with project metadata, documentation, packaging, tests, and OpenSpec artifacts. Moving source scripts into a dedicated directory makes the source tree easier to scan while preserving the installed Debian package layout and command names.

## What Changes

- Move the source files `sing-gateway` and `tproxy_ctrl.sh` into `scripts/`.
- Preserve installed Debian package paths: `/usr/bin/sing-gateway` and `/usr/lib/sing-gateway/tproxy_ctrl.sh`.
- Update package installation metadata, tests, and documentation to refer to the new source-tree paths.
- Keep runtime command behavior, systemd drop-in content, Debian package names, and installed paths unchanged.
- No breaking changes for installed package users.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `sing-gateway-debian-package`: clarify that package builds may source executable shell scripts from a dedicated source directory while installing the same CLI and low-level control script paths.
- `debian-package-build-workflow`: update documented maintainer validation expectations so source-tree examples and package inspection remain accurate after the script source move.

## Impact

- Affected source layout: root-level `sing-gateway` and `tproxy_ctrl.sh` move to `scripts/`.
- Affected packaging metadata: `debian/install` source paths.
- Affected tests: test harness script path variables and any assertions about source file locations.
- Affected documentation: README source-tree examples and any maintainer notes that reference root-level script paths.
- Affected validation: shell regression suite and Debian package build/inspection commands should confirm installed paths remain unchanged.
