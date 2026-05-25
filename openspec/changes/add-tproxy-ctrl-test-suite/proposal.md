## Why

`tproxy_ctrl.sh` now contains stricter validation, stack-specific nftables generation, local proxy bypass behavior, and idempotent setup/cleanup logic. These behaviors are security- and routing-sensitive, but the repository has no automated regression tests to catch future breakage.

This change adds a self-contained test suite that validates the script without requiring root privileges or real host networking changes.

## What Changes

- Add a POSIX `sh` test runner for `tproxy_ctrl.sh`.
- Add fake `nft`, `ip`, and `sysctl` command fixtures so non-dry-run paths can be tested safely.
- Cover CLI validation for actions, nft identifiers, marks, ports, route table IDs, UIDs, and FakeIP CIDRs.
- Cover dry-run nftables generation for default, IPv4-only, IPv6-only, and dual-stack modes.
- Cover DNS hijack, FakeIP, and `--proxy-local` output, including route marking and bypass ordering.
- Cover save/no-save behavior to ensure invalid inputs fail before writing generated scripts or invoking privileged commands.
- Cover idempotent setup/cleanup command sequencing and rollback behavior when routing setup fails after nft application.
- Keep the test suite dependency-free; no Bats, root access, real nftables, or network namespace setup is required.

## Capabilities

### New Capabilities
- `tproxy-control-test-suite`: Defines regression test coverage for `tproxy_ctrl.sh`, including validation, generated nftables scripts, fake privileged command sequencing, idempotency, and rollback behavior.

### Modified Capabilities

## Impact

- Affected code: new test files under `tests/`.
- Affected script under test: `tproxy_ctrl.sh`.
- No runtime behavior changes are intended for `tproxy_ctrl.sh`.
- No new external test framework or package dependency is introduced.
- Future development can run `sh tests/run.sh` locally or in CI without privileged host networking access.
