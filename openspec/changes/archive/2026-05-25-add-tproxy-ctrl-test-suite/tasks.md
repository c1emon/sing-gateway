## 1. Test Runner Foundation

- [x] 1.1 Create `tests/run.sh` as the POSIX shell test entrypoint.
- [x] 1.2 Add test runner bookkeeping for pass/fail counts, temporary workspace setup, and cleanup.
- [x] 1.3 Add assertion helpers for exit status, stdout/stderr content, file existence, command log content, and line ordering.
- [x] 1.4 Ensure `sh tests/run.sh` can be run from the repository root without external dependencies.

## 2. Fake Privileged Commands

- [x] 2.1 Add fake `nft`, `ip`, and `sysctl` command setup for tests via a temporary `PATH`.
- [x] 2.2 Record fake command invocations to a test log for side-effect assertions.
- [x] 2.3 Make fake `nft` consume stdin for `-f -` and support simulated delete/apply failures.
- [x] 2.4 Make fake `ip` support rule-present simulation, route failure simulation, and delete failure simulation.
- [x] 2.5 Make fake `sysctl` record forwarding enablement without changing host settings.

## 3. CLI and Validation Tests

- [x] 3.1 Add tests for missing action, help output, unknown option, and invalid stack handling.
- [x] 3.2 Add tests for default and custom safe nft table identifiers.
- [x] 3.3 Add tests rejecting unsafe nft table identifiers before save or privileged side effects.
- [x] 3.4 Add route mark boundary tests for decimal and hexadecimal valid values and malformed or out-of-range invalid values.
- [x] 3.5 Add TProxy port boundary tests for valid and invalid values.
- [x] 3.6 Add route table ID boundary tests for IPv4 and IPv6 table options.
- [x] 3.7 Add UID boundary tests for `--ignore-uid` with `--proxy-local`.
- [x] 3.8 Add IPv4 and IPv6 FakeIP CIDR validation tests for representative valid and invalid CIDRs.

## 4. Dry-Run nftables Output Tests

- [x] 4.1 Add dry-run tests for default, `--stack=v4`, `--stack=v6`, and `--stack=all` modes.
- [x] 4.2 Assert IPv4 TProxy rules include `meta nfproto ipv4` guards and are omitted when IPv4 is disabled.
- [x] 4.3 Assert IPv6 TProxy rules include `meta nfproto ipv6` guards and are omitted when IPv6 is disabled.
- [x] 4.4 Add DNS hijack tests asserting prerouting DNS rules set the configured route mark before TProxy acceptance.
- [x] 4.5 Add local DNS reroute tests asserting output DNS rules set the configured route mark before accepting packets.
- [x] 4.6 Add FakeIP tests for IPv4-only, IPv6-only, disabled-family, and dual-stack combinations.
- [x] 4.7 Assert FakeIP prerouting and local output rules set the configured route mark.
- [x] 4.8 Add `--proxy-local` tests for ignore mark only, ignore UID only, and both bypass mechanisms.
- [x] 4.9 Assert local bypass rules appear before DNS, FakeIP, direct, and generic reroute rules in the output chain.

## 5. Save and Invalid Side-Effect Tests

- [x] 5.1 Add tests confirming valid `--save=<file>` writes generated nft output.
- [x] 5.2 Add tests confirming invalid invocations with `--save=<file>` do not create the save file.
- [x] 5.3 Add tests confirming invalid non-dry-run invocations leave the fake privileged command log empty.
- [x] 5.4 Add tests confirming `--proxy-local` without `--ignore-mark` or `--ignore-uid` fails before side effects.

## 6. Fake Command Side-Effect Tests

- [x] 6.1 Add non-dry-run `set` tests for IPv4 mode command sequencing.
- [x] 6.2 Add non-dry-run `set` tests for IPv6 mode command sequencing.
- [x] 6.3 Add non-dry-run `set --stack=all` tests confirming both IPv4 and IPv6 route setup commands are logged.
- [x] 6.4 Add idempotent route setup tests confirming existing rules are not duplicated and local routes are replaced.
- [x] 6.5 Add `unset` tests confirming managed nft and route cleanup commands are attempted.
- [x] 6.6 Add cleanup tolerance tests where fake delete commands report missing resources and `unset` still exits successfully.
- [x] 6.7 Add tests confirming `unset` does not log IPv4 or IPv6 forwarding disable commands.
- [x] 6.8 Add rollback tests where nft application succeeds but route setup fails and the managed nft table is deleted afterward.

## 7. Optional nft Parser Checks and Documentation

- [x] 7.1 Add optional generated nft parser checks that run only when a compatible `nft` binary is available or explicitly enabled.
- [x] 7.2 Ensure default `sh tests/run.sh` passes on systems without real `nft`.
- [x] 7.3 Document the test command and optional nft parser behavior in the test runner output or repository documentation.

## 8. Verification

- [x] 8.1 Run `sh tests/run.sh` and confirm all required tests pass.
- [x] 8.2 Run `openspec status --change add-tproxy-ctrl-test-suite` and confirm the change remains apply-ready.
