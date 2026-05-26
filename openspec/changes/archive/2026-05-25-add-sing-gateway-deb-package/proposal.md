## Why

Transparent proxy gateway users currently must manually copy `tproxy_ctrl.sh`, discover sing-box runtime details, and maintain a fragile systemd drop-in by hand. A Debian companion package can make the gateway mode repeatable and diagnosable while preserving the official sing-box package and service ownership.

## What Changes

- Add an inert `sing-gateway` Debian companion package that depends on the official `sing-box` package and required Linux networking tools.
- Add a `sing-gateway` CLI wrapper that validates sing-box configuration, resolves effective TProxy gateway options, and delegates network mutation to `tproxy_ctrl.sh`.
- Add explicit `sing-gateway enable` / `sing-gateway disable` lifecycle commands for installing or removing a `sing-box.service` systemd drop-in.
- Integrate with `sing-box.service` using fail-closed `ExecStartPre=check`, `ExecStartPost=set`, and `ExecStopPost=unset` commands when enabled.
- Add diagnostics commands that show the resolved gateway configuration, final `tproxy_ctrl.sh` command, and generated nftables rules before activation.
- Add Debian removal behavior that cleans managed integration state on package removal while avoiding service restarts or network disruption during package upgrades.
- Add tests covering package inertness, wrapper inference, enable/disable behavior, systemd drop-in semantics, and maintainer-script cleanup.

## Capabilities

### New Capabilities
- `sing-gateway-debian-package`: Debian companion package installation, explicit enable/disable flow, systemd lifecycle integration, sing-box configuration inference, diagnostics, and package cleanup behavior.

### Modified Capabilities
- `transparent-proxy-control`: Installed wrapper usage and lifecycle integration introduce a higher-level control surface around the existing low-level TProxy control behavior without changing the low-level nftables and routing contract.

## Impact

- Adds Debian packaging files and package metadata.
- Adds a `sing-gateway` CLI wrapper and installs `tproxy_ctrl.sh` under a package-managed library path.
- Adds a package-managed default configuration at `/etc/sing-gateway/gateway.conf`.
- Adds a systemd drop-in template for `sing-box.service`, activated only by explicit user command.
- Adds runtime dependencies on `sing-box`, `nftables`, `iproute2`, `procps`, `jq`, and `systemd`.
- Extends the shell test suite to cover wrapper, packaging, and maintainer-script behavior without mutating host networking state.
