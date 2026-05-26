## 1. Source Layout

- [x] 1.1 Create `scripts/` and move `sing-gateway` into `scripts/sing-gateway` while preserving executable mode.
- [x] 1.2 Move `tproxy_ctrl.sh` into `scripts/tproxy_ctrl.sh` while preserving executable mode.
- [x] 1.3 Ensure no root-level script copies remain after the move.

## 2. Packaging and Tests

- [x] 2.1 Update `debian/install` to source scripts from `scripts/` while preserving installed paths under `/usr/bin/` and `/usr/lib/sing-gateway/`.
- [x] 2.2 Update `tests/run.sh` script path variables and source-location assertions for the new `scripts/` layout.
- [x] 2.3 Keep test fixtures and systemd drop-in behavior unchanged after the source move.

## 3. Documentation and Specs

- [x] 3.1 Update README source-checkout examples from root-level script paths to `scripts/tproxy_ctrl.sh`.
- [x] 3.2 Update package documentation or maintainer notes to distinguish source script paths from installed package paths where needed.
- [x] 3.3 Verify OpenSpec specs continue to require stable installed paths after the source layout change.

## 4. Validation

- [x] 4.1 Run `sh tests/run.sh` and confirm the full regression suite passes.
- [x] 4.2 Build the Debian package in a Debian environment and inspect contents to confirm `/usr/bin/sing-gateway` and `/usr/lib/sing-gateway/tproxy_ctrl.sh` are installed.
- [x] 4.3 Run lintian/package inspection commands documented for maintainers.
