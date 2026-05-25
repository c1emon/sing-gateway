## Context

The repository currently has no automated tests for `tproxy_ctrl.sh`. The script is a POSIX shell program that validates CLI inputs, generates nftables scripts, and applies privileged `nft`, `ip`, and `sysctl` side effects for transparent proxy routing.

The most important behaviors can be validated without root by combining dry-run output checks with fake command fixtures. The test suite should stay lightweight because this project has no existing test framework, package manager, or Makefile convention.

## Goals / Non-Goals

**Goals:**
- Provide a single command, `sh tests/run.sh`, that runs the regression suite.
- Keep tests portable to POSIX `sh` without requiring Bats or another external test framework.
- Validate argument parsing and input validation boundaries.
- Validate generated nftables dry-run output for stack selection, DNS hijack, FakeIP, and local proxy bypass behavior.
- Validate non-dry-run command sequencing through fake `nft`, `ip`, and `sysctl` commands.
- Verify invalid inputs fail before saving nft scripts or invoking privileged commands.
- Verify idempotent setup/cleanup and rollback behavior without changing host networking state.

**Non-Goals:**
- Do not require root privileges, network namespaces, real nftables state, or actual policy routing changes.
- Do not introduce Bats, Python, Node, or other test dependencies.
- Do not change `tproxy_ctrl.sh` behavior unless implementation of the test suite reveals a bug that must be fixed in a later change.
- Do not attempt full nftables semantic validation beyond text assertions and optional parse checks when `nft` is available.

## Decisions

1. **Use a dependency-free POSIX shell test runner.**
   - Decision: implement `tests/run.sh` as the required test entrypoint with minimal assertion helpers embedded or sourced from local test files.
   - Rationale: the project is a shell-script repository with no test framework; avoiding dependencies keeps local and CI execution simple.
   - Alternative considered: Bats. It improves readability but adds an external dependency that is not necessary for this scope.

2. **Generate or provide fake privileged commands for side-effect tests.**
   - Decision: run side-effect tests with a temporary `PATH` that resolves `nft`, `ip`, and `sysctl` to fake commands that log invocations and can simulate selected failures.
   - Rationale: this validates non-dry-run paths without root and without mutating the host.
   - Alternative considered: only test `--dry-run`. That would miss command sequencing, idempotency, cleanup tolerance, and rollback behavior.

3. **Separate required tests from optional real nft parse checks.**
   - Decision: the default suite must pass without real `nft`; optional parse checks can run when `nft` is installed and explicitly enabled or safely auto-detected.
   - Rationale: many development environments, especially macOS, do not have Linux nftables installed.
   - Alternative considered: require `nft --check`. This would make the suite unavailable on common developer machines.

4. **Favor behavior assertions over exact full-output snapshots.**
   - Decision: assert key lines, absence of disabled-family rules, and ordering of important rules instead of snapshotting whole nft scripts.
   - Rationale: full snapshots are brittle when formatting changes; targeted assertions better encode the contract.
   - Alternative considered: golden files for every generated mode. This is easier to inspect but noisier to maintain.

5. **Use table-driven validation cases where practical.**
   - Decision: group boundary values for marks, ports, route tables, UIDs, nft identifiers, and CIDRs into compact loops.
   - Rationale: validation coverage should be broad without making the test file repetitive.
   - Alternative considered: one standalone test function per boundary case. This is explicit but unnecessarily verbose.

## Risks / Trade-offs

- Text assertions can miss nft syntax errors → Mitigate with optional `nft --check` parse validation when available.
- Fake commands can drift from real command behavior → Keep fake behavior minimal and focused on the script's expected invocation contract.
- POSIX shell assertions can become hard to read as coverage grows → Use clear helper names and sectioned test output; split helpers later if needed.
- Tests might overfit to formatting → Assert semantic substrings and ordering rather than entire generated scripts.
- The current argument parser truncates option values after the first `=` → Avoid treating embedded `=` values as supported behavior unless explicitly specified later.
