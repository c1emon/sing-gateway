## Context

The repository currently provides `tproxy_ctrl.sh`, a low-level POSIX shell script that configures nftables and Linux policy routing for a sing-box TProxy gateway. Users must manually install the script, inspect sing-box configuration, derive TProxy/FakeIP options, and maintain a `sing-box.service` drop-in. This creates fragile upgrades and unsafe failure modes: sing-box can run without gateway rules, gateway rules can point at the wrong port, or package removal can leave stale routing state.

The change introduces `sing-gateway` as a Debian companion package for the official sing-box package. It does not replace sing-box or rewrite the upstream service. Instead, it installs an inert wrapper and an optional systemd drop-in that the user explicitly enables.

## Goals / Non-Goals

**Goals:**
- Package the gateway integration as a Debian package that is inert immediately after installation.
- Provide a `sing-gateway` CLI for explicit enable/disable, validation, diagnostics, and lifecycle actions.
- Bind gateway setup/cleanup to `sing-box.service` only after explicit enablement.
- Resolve effective gateway options from explicit gateway configuration, sing-box service metadata, and sing-box JSON configuration.
- Fail closed when required values are missing, conflicting, or ambiguous.
- Keep low-level nftables and policy-routing mutation inside `tproxy_ctrl.sh`.
- Clean managed integration state on package removal without disrupting upgrades.

**Non-Goals:**
- Rebuild, fork, or vendor the sing-box binary.
- Publish an APT repository or release pipeline.
- Support RPM/APK/Homebrew packaging.
- Fetch remote subscriptions or download sing-box configuration from the internet.
- Edit the user's sing-box configuration automatically.
- Implement an interactive TUI/Web UI.
- Automatically enable gateway integration during package install.

## Decisions

### Companion package, not enhanced sing-box package

`sing-gateway` will depend on `sing-box` rather than rebuild it. This preserves the official sing-box installation path and avoids tracking upstream binary, service, and security updates.

Alternatives considered:
- Rebuild sing-box with bundled gateway integration: tighter control, but high maintenance and upgrade risk.
- Replace `sing-box.service` `ExecStart`: full lifecycle control, but fragile across upstream service changes.

### Installation is inert; enablement is explicit

Package installation will install files and a default conffile, but it will not create an active drop-in, restart sing-box, or mutate nftables/routing. Users activate integration with `sing-gateway enable`, then apply it with `systemctl restart sing-box`.

This separates package deployment from high-risk network behavior.

### Use a systemd drop-in for lifecycle integration

When enabled, `sing-gateway` installs a drop-in for `sing-box.service` with:

```ini
[Service]
ExecStartPre=+/usr/bin/sing-gateway check
ExecStartPost=+/usr/bin/sing-gateway set
ExecStopPost=+/usr/bin/sing-gateway unset
```

`check` is side-effect-free and runs before sing-box starts. `set` runs after sing-box has started, preventing gateway rules from forwarding traffic to an unavailable TProxy listener. `unset` runs after stop/failure as cleanup. The `+` prefix ensures gateway commands run with root privileges even if sing-box itself runs as `User=sing-box`.

### Fail-closed configuration resolution

The wrapper resolves exactly one effective configuration from:

1. `/etc/sing-gateway/gateway.conf` explicit settings.
2. `sing-box.service` metadata such as `ExecStart` and `User`.
3. Validated sing-box JSON configuration.
4. Safe defaults for routing tables, marks, and nft table names.

If resolution finds no TProxy inbound, multiple TProxy inbounds without a configured tag, conflicting FakeIP ranges, missing ports, or unsafe `proxy-local` bypass settings, the command fails before mutating network state.

### Use `jq` for JSON parsing and sing-box CLI for validation

The package depends on `jq` rather than hand-parsing JSON in POSIX shell. The wrapper calls `sing-box check` before parsing and may use `sing-box merge` for directory-based configuration when available. Parsing is limited to local sing-box configuration; remote fetch is out of scope.

### Keep `tproxy_ctrl.sh` as the low-level engine

The wrapper does not duplicate nftables or routing logic. It computes a final `tproxy_ctrl.sh` command and delegates `set`, `unset`, and dry-run nft generation to the existing script. This preserves existing tests and the established low-level contract.

### Debian removal cleans managed state; upgrades do not disrupt

`prerm remove` performs best-effort cleanup of the active drop-in and managed gateway state while package files still exist. `prerm upgrade` does not unset routing or remove integration, avoiding network disruption during package upgrades. `postrm purge` removes residual configuration and drop-in files best-effort without assuming non-essential dependencies remain.

## Risks / Trade-offs

- **Risk: systemd drop-in fails after upstream sing-box service changes** → Keep the drop-in minimal and avoid overriding `ExecStart`, `User`, capabilities, or working directory.
- **Risk: automatic inference chooses the wrong inbound or FakeIP range** → Fail on ambiguity and require explicit `TPROXY_INBOUND_TAG` or explicit override values.
- **Risk: package removal leaves stale networking state** → Clean in `prerm remove` while package commands are still available; keep cleanup idempotent and best-effort.
- **Risk: `jq` dependency increases package footprint** → Accept the small dependency to avoid unsafe shell JSON parsing.
- **Risk: `ExecStartPost` failure leaves sing-box running while unit is failed** → Make `sing-gateway set` transactional and run best-effort `unset` on failure; keep `ExecStopPost` cleanup as a second layer.
- **Risk: local proxy loops** → Preserve `tproxy_ctrl.sh` validation and require explicit/valid ignore UID or mark when `PROXY_LOCAL=1`; never infer `ignore-uid=0` for root-run sing-box.
