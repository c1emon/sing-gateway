## Context

The project has two executable shell scripts in the repository root:

```text
sing-gateway
tproxy_ctrl.sh
```

These scripts are source files, while the root directory also contains documentation, Debian packaging metadata, OpenSpec artifacts, tests, and helper files. The installed Debian layout is already well-defined and should remain unchanged:

```text
/usr/bin/sing-gateway
/usr/lib/sing-gateway/tproxy_ctrl.sh
```

The change is a source-tree organization refactor only. Runtime behavior, package names, installed command paths, and systemd drop-in contents must remain stable.

## Goals / Non-Goals

**Goals:**
- Move executable source scripts into a dedicated `scripts/` directory.
- Keep `sing-gateway` and `tproxy_ctrl.sh` executable and independently testable from the source checkout.
- Preserve Debian package installed paths and package contents.
- Update tests and documentation so source-tree references point at `scripts/`.
- Keep the package architecture-independent.

**Non-Goals:**
- No behavior changes to `sing-gateway` or `tproxy_ctrl.sh`.
- No changes to installed Debian paths, command names, or systemd hook commands.
- No split into `bin/` and `lib/` directories at this time.
- No redesign of shell script internals.

## Decisions

### Use `scripts/` for source shell entrypoints

Move both executable source files to:

```text
scripts/sing-gateway
scripts/tproxy_ctrl.sh
```

Rationale: both files are shell scripts and both can be invoked directly during development. `scripts/` communicates source-tree location without implying compiled library code.

Alternatives considered:
- `src/`: conventional for source code, but heavier than needed for a shell-only project.
- `bin/`: suggests installed command layout and could be confused with `/usr/bin`.
- `bin/` plus `lib/`: clearer layering, but over-structures two scripts while `tproxy_ctrl.sh` remains a directly runnable tool.

### Preserve installed Debian paths

Only `debian/install` source paths should change. The destination paths remain:

```text
scripts/sing-gateway usr/bin/
scripts/tproxy_ctrl.sh usr/lib/sing-gateway/
```

Rationale: installed users and systemd drop-ins depend on `/usr/bin/sing-gateway` and `/usr/lib/sing-gateway/tproxy_ctrl.sh`, not the repository source layout.

### Keep tests path-driven

The shell test suite should keep using top-level variables for script paths, updated to:

```sh
CTRL="$ROOT_DIR/scripts/tproxy_ctrl.sh"
GATEWAY="$ROOT_DIR/scripts/sing-gateway"
```

Rationale: this keeps the rest of the test harness unchanged and preserves fixture behavior that copies the low-level control script into temporary test directories.

## Risks / Trade-offs

- **Missed root-level references** → Use repository-wide search for `sing-gateway` and `tproxy_ctrl.sh`, then update only source-path references; leave installed-path and command-name references unchanged.
- **Confusing source paths with installed paths** → Documentation should distinguish source checkout examples (`scripts/tproxy_ctrl.sh`) from installed package paths (`/usr/bin/sing-gateway`, `/usr/lib/sing-gateway/tproxy_ctrl.sh`).
- **Package content drift** → Run shell regression tests and Debian package build/inspection to confirm installed paths remain unchanged.
- **Executable bit loss during move** → Preserve file modes when moving scripts and validate direct execution through tests.

## Migration Plan

1. Create `scripts/` and move `sing-gateway` and `tproxy_ctrl.sh` into it, preserving executable modes.
2. Update `debian/install` source paths only; keep destination paths unchanged.
3. Update `tests/run.sh` top-level script path variables and any source-location assertions.
4. Update README source-checkout examples from `sh tproxy_ctrl.sh ...` to `sh scripts/tproxy_ctrl.sh ...`.
5. Run `sh tests/run.sh` locally.
6. Run Debian package build and inspection commands in a Debian environment to verify installed paths remain unchanged.

Rollback is straightforward: move the scripts back to the repository root and revert the source-path updates in packaging, tests, and docs.

## Open Questions

- None. Default path is `scripts/` with installed Debian paths preserved.
