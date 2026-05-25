## 1. Validation and Naming

- [x] 1.1 Change generated default nftables identifiers to safe underscore-based names.
- [x] 1.2 Add strict validation for user-provided nft table names before rule generation.
- [x] 1.3 Tighten validation for route marks, route table IDs, TProxy ports, UIDs, and FakeIP CIDRs.
- [x] 1.4 Ensure invalid inputs fail before saving nft scripts or applying nft/routing side effects.

## 2. Stack-Specific nftables Rule Generation

- [x] 2.1 Refactor nft rule generation into IPv4 and IPv6 fragments selected by `--stack`.
- [x] 2.2 Add `meta nfproto ipv4` guards to all IPv4 TProxy rules in the `inet` table.
- [x] 2.3 Add `meta nfproto ipv6` guards to all IPv6 TProxy rules in the `inet` table.
- [x] 2.4 Ensure `--stack=v4` omits IPv6 TProxy handling and `--stack=v6` omits IPv4 TProxy handling.

## 3. DNS and FakeIP Routing Behavior

- [x] 3.1 Update prerouting DNS hijack rules to set the configured route mark before TProxy acceptance.
- [x] 3.2 Keep local output DNS reroute rules marked before accepting packets.
- [x] 3.3 Generate FakeIP rules only for enabled address families with valid configured CIDRs.
- [x] 3.4 Ensure FakeIP prerouting and local output rules set the configured route mark consistently.

## 4. Local Proxy Bypass and Loop Prevention

- [x] 4.1 Fix `--ignore-mark` generation so it uses the configured ignore mark variable.
- [x] 4.2 Generate ignore-by-mark and ignore-by-UID rules independently when each option is provided.
- [x] 4.3 Place local bypass rules before DNS, FakeIP, direct, and generic reroute rules in the output chain.
- [x] 4.4 Decide and implement whether `--proxy-local` requires at least one bypass mechanism or emits a clear warning/error.

## 5. Idempotent Setup and Cleanup

- [x] 5.1 Make nft table application converge managed rules without failing on existing managed state.
- [x] 5.2 Make route rule and local route setup tolerate already-existing managed entries.
- [x] 5.3 Make route rule, local route, and nft table cleanup tolerate already-absent managed entries.
- [x] 5.4 Remove unconditional disabling of IPv4 and IPv6 forwarding during `unset`.
- [x] 5.5 Keep setup failure behavior predictable if nft application succeeds but routing setup fails.

## 6. Verification

- [x] 6.1 Verify `--dry-run` output for default, `--stack=v4`, `--stack=v6`, and `--stack=all` modes.
- [x] 6.2 Verify dry-run output for DNS hijack, FakeIP, and `--proxy-local` combinations.
- [x] 6.3 Verify invalid nft table names, marks, ports, UIDs, route table IDs, and FakeIP CIDRs fail before side effects.
- [x] 6.4 If `nft` is available, validate generated nft scripts with nft dry-run/check mode or an equivalent safe parse step.
- [x] 6.5 Run `openspec status --change fix-tproxy-nftables-routing` and confirm the change remains apply-ready.
