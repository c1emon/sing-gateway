## Context

`tproxy_ctrl.sh` is a POSIX shell control script for configuring sing-box transparent proxying with Linux nftables and policy routing. It currently generates an `inet` nftables table containing prerouting TProxy rules, optional DNS/FakeIP handling, optional local output marking, and setup/cleanup of `ip rule`/`ip route` state.

The council review identified correctness issues in generated nft syntax, protocol-family handling, local traffic bypass, DNS marking, and operational idempotency. Because the script runs privileged commands, the design must favor strict validation and predictable failure behavior over permissive input handling.

## Goals / Non-Goals

**Goals:**
- Keep the implementation as a shell script and preserve the existing `set`/`unset` action model.
- Generate nftables rules that are valid for default options and for `--stack=v4`, `--stack=v6`, and `--stack=all`.
- Ensure IPv4 and IPv6 TProxy rules in an `inet` table are family-specific and only generated when enabled.
- Ensure DNS hijack and FakeIP rules set the policy-routing mark before TProxy/reroute handling.
- Make `--proxy-local`, `--ignore-mark`, and `--ignore-uid` safe enough to prevent common local proxy loops.
- Make repeated `set`/`unset` operations tolerate already-existing or already-removed state.
- Validate user-provided values before inserting them into nftables or routing commands.

**Non-Goals:**
- Rewriting the script in Python, Go, or another language.
- Adding systemd unit management, sing-box config generation, or automatic sing-box process detection.
- Designing a full test framework beyond shell/nft dry-run-oriented validation hooks or documented verification commands.
- Changing sing-box itself or requiring a different TProxy listener mode.

## Decisions

1. **Use safe nft identifiers rather than relying on quoted names.**
   - Decision: change generated default identifiers to underscore-based names and validate custom table names against a strict identifier pattern.
   - Rationale: unquoted names containing `-` can fail to parse, and quoting every generated reference is easy to miss.
   - Alternative considered: keep hyphenated names and quote all table/chain references. This is more fragile and still requires validation.

2. **Generate stack-specific nft rule fragments.**
   - Decision: build separate IPv4 and IPv6 rule fragments, then include only the fragments enabled by `--stack` and corresponding FakeIP options.
   - Rationale: current unconditional rules can affect the wrong address family when only one stack is configured.
   - Alternative considered: keep both families in all modes and rely on absent routes to make one ineffective. This creates confusing behavior and potential blackholes.

3. **Guard `inet` TProxy rules with `meta nfproto`.**
   - Decision: every IPv4 TProxy rule uses `meta nfproto ipv4`; every IPv6 TProxy rule uses `meta nfproto ipv6`.
   - Rationale: `inet` tables can see both families; family-specific TProxy expressions must not be reached by the wrong family.
   - Alternative considered: use separate `ip` and `ip6` tables. That would be a larger structural rewrite and duplicate shared logic.

4. **Treat DNS/FakeIP paths as marked policy-routing paths.**
   - Decision: prerouting DNS and FakeIP TProxy rules set `ROUTE_MARK`; local output DNS/FakeIP reroute rules set `ROUTE_MARK` before accepting.
   - Rationale: policy routing depends on the mark to route packets to local loopback for TProxy delivery.
   - Alternative considered: rely on TProxy without explicit mark. This is unreliable for the existing route setup.

5. **Make local proxy bypass explicit and independently validated.**
   - Decision: generate ignore-by-mark and ignore-by-uid rules independently when provided; validate each provided value separately; document or enforce the need for at least one bypass mechanism when local proxying is enabled.
   - Rationale: local proxying is the highest loop-risk mode, especially for sing-box's own upstream connections and DNS.
   - Alternative considered: allow `--proxy-local` without any bypass. This is simpler but unsafe for common deployments.

6. **Favor idempotent operations with conservative sysctl handling.**
   - Decision: use replace-or-delete-tolerant behavior for nft/routing state and avoid unconditionally disabling forwarding on `unset`.
   - Rationale: repeated setup/cleanup is common during testing, and the host may already use forwarding for unrelated networking.
   - Alternative considered: keep hard failures for all duplicate/missing state. This makes partial failures and reruns painful.

## Risks / Trade-offs

- **Stricter input validation rejects previously accepted values** → Mitigate by keeping valid documented values working and producing clear error messages.
- **Changing default nft identifier names may leave old hyphenated tables from prior runs** → Mitigate by documenting cleanup or optionally attempting best-effort deletion of the old default table name during unset.
- **Idempotent route cleanup can hide unexpected duplicate rules** → Mitigate by matching the exact fwmark/table/local route tuple and avoiding broad deletes.
- **Not disabling forwarding on unset changes prior behavior** → Mitigate by documenting that the script no longer owns global forwarding state once enabled, or by only restoring saved state if such persistence is added later.
- **Local proxy loop prevention depends on correct sing-box UID/mark configuration** → Mitigate with validation, clear usage errors/warnings, and generated ignore rules that run before reroute rules.
