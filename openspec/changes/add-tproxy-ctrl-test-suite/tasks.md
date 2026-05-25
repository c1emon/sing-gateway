## 1. Test Runner Foundation

- [ ] 1.1 Create `tests/run.sh` as the POSIX shell test entrypoint.
- [ ] 1.2 Add test runner bookkeeping for pass/fail counts, temporary workspace setup, and cleanup.
- [ ] 1.3 Add assertion helpers for exit status, stdout/stderr content, file existence, command log content, and line ordering.
- [ ] 1.4 Ensure `sh tests/run.sh` can be run from the repository root without external dependencies.

## 2. Fake Privileged Commands

- [ ] 2.1 Add fake `nft`, `ip`, and `sysctl` command setup for tests via a temporary `PATH`.
- [ ] 2.2 Record fake command invocations to a test log for side-effect assertions.
- [ ] 2.3 Make fake `nft` consume stdin for `-f -` and support simulated delete/apply failures.
- [ ] 2.4 Make fake `ip` support rule-present simulation, route failure simulation, and delete failure simulation.
- [ ] 2.5 Make fake `sysctl` record forwarding enablement without changing host settings.

## 3. CLI and Validation Tests

- [ ] 3.1 Add tests for missing action, help output, unknown option, and invalid stack handling.
- [ ] 3.2 Add tests for default and custom safe nft table identifiers.
- [ ] 3.3 Add tests rejecting unsafe nft table identifiers before save or privileged side effects.
- [ ] 3.4 Add route mark boundary tests for decimal and hexadecimal valid values and malformed or out-of-range invalid values.
- [ ] 3.5 Add TProxy port boundary tests for valid and invalid values.
- [ ] 3.6 Add route table ID boundary tests for IPv4 and IPv6 table options.
- [ ] 3.7 Add UID boundary tests for `--ignore-uid` with `--proxy-local`.
- [ ] 3.8 Add IPv4 and IPv6 FakeIP CIDR validation tests for representative valid and invalid CIDRs.

## 4. Dry-Run nftables Output Tests

- [ ] 4.1 Add dry-run tests for default, `--stack=v4`, `--stack=v6`, and `--stack=all` modes.
- [ ] 4.2 Assert IPv4 TProxy rules include `meta nfproto ipv4` guards and are omitted when IPv4 is disabled.
- [ ] 4.3 Assert IPv6 TProxy rules include `meta nfproto ipv6` guards and are omitted when IPv6 is disabled.
- [ ] 4.4 Add DNS hijack tests asserting prerouting DNS rules set the configured route mark before TProxy acceptance.
- [ ] 4.5 Add local DNS reroute tests asserting output DNS rules set the configured route mark before accepting packets.
- [ ] 4.6 Add FakeIP tests for IPv4-only, IPv6-only, disabled-family, and dual-stack combinations.
- [ ] 4.7 Assert FakeIP prerouting and local output rules set the configured route mark.
- [ ] 4.8 Add `--proxy-local` tests for ignore mark only, ignore UID only, and both bypass mechanisms.
- [ ] 4.9 Assert local bypass rules appear before DNS, FakeIP, direct, and generic reroute rules in the output chain.

## 5. Save and Invalid Side-Effect Tests

- [ ] 5.1 Add tests confirming valid `--save=<file>` writes generated nft output.
- [ ] 5.2 Add tests confirming invalid invocations with `--save=<file>` do not create the save file.
- [ ] 5.3 Add tests confirming invalid non-dry-run invocations leave the fake privileged command log empty.
- [ ] 5.4 Add tests confirming `--proxy-local` without `--ignore-mark` or `--ignore-uid` fails before side effects.

## 6. Fake Command Side-Effect Tests

- [ ] 6.1 Add non-dry-run `set` tests for IPv4 mode command sequencing.
- [ ] 6.2 Add non-dry-run `set` tests for IPv6 mode command sequencing.
- [ ] 6.3 Add non-dry-run `set --stack=all` tests confirming both IPv4 and IPv6 route setup commands are logged.
- [ ] 6.4 Add idempotent route setup tests confirming existing rules are not duplicated and local routes are replaced.
- [ ] 6.5 Add `unset` tests confirming managed nft and route cleanup commands are attempted.
- [ ] 6.6 Add cleanup tolerance tests where fake delete commands report missing resources and `unset` still exits successfully.
- [ ] 6.7 Add tests confirming `unset` does not log IPv4 or IPv6 forwarding disable commands.
- [ ] 6.8 Add rollback tests where nft application succeeds but route setup fails and the managed nft table is deleted afterward.

## 7. Optional nft Parser Checks and Documentation

- [ ] 7.1 Add optional generated nft parser checks that run only when a compatible `nft` binary is available or explicitly enabled.
- [ ] 7.2 Ensure default `sh tests/run.sh` passes on systems without real `nft`.
- [ ] 7.3 Document the test command and optional nft parser behavior in the test runner output or repository documentation.

## 8. Verification

- [ ] 8.1 Run `sh tests/run.sh` and confirm all required tests pass.
- [ ] 8.2 Run `openspec status --change add-tproxy-ctrl-test-suite` and confirm the change remains apply-ready.
