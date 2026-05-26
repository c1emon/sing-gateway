## 1. Package Layout and Defaults

- [x] 1.1 Create Debian packaging skeleton for the `sing-gateway` companion package.
- [x] 1.2 Install `tproxy_ctrl.sh` into `/usr/lib/sing-gateway/` and expose `/usr/bin/sing-gateway` as the user-facing CLI.
- [x] 1.3 Add package metadata with runtime dependencies on sing-box, nftables, iproute2, procps, jq, and systemd.
- [x] 1.4 Add safe default `/etc/sing-gateway/gateway.conf` as a conffile with integration disabled until explicit enablement.
- [x] 1.5 Add documentation and examples for install, check, enable, restart, disable, and removal flows.

## 2. Systemd Integration Commands

- [x] 2.1 Add a packaged `sing-box.service` drop-in template using `ExecStartPre=+sing-gateway check`, `ExecStartPost=+sing-gateway set`, and `ExecStopPost=+sing-gateway unset`.
- [x] 2.2 Implement `sing-gateway enable` to validate by default, install the active drop-in, reload systemd, avoid restarting sing-box, and print next-step guidance.
- [x] 2.3 Implement `sing-gateway enable --force` to install the drop-in without bypassing runtime fail-closed checks.
- [x] 2.4 Implement `sing-gateway disable` to remove the active drop-in, best-effort unset managed gateway state, reload systemd, and avoid restarting sing-box.

## 3. Configuration Discovery and Validation

- [x] 3.1 Implement loading and validation for `/etc/sing-gateway/gateway.conf` explicit settings.
- [x] 3.2 Implement sing-box service metadata discovery for ExecStart-derived config paths/directories and service user.
- [x] 3.3 Implement fallback to `/etc/sing-box/config.json` only when no explicit or service-derived source exists and the file is present.
- [x] 3.4 Invoke sing-box config validation before parsing or network mutation.
- [x] 3.5 Use jq-based parsing to select TProxy inbounds, infer ports, infer FakeIP ranges, and detect conflicts or ambiguity.
- [x] 3.6 Implement safe local-proxy bypass inference and reject root-user inference without explicit ignore UID or mark.

## 4. Wrapper Lifecycle and Diagnostics

- [x] 4.1 Implement `sing-gateway check` as a side-effect-free resolver that prints effective configuration and fails closed on errors.
- [x] 4.2 Implement `sing-gateway print-command` to display the exact delegated `tproxy_ctrl.sh set` invocation.
- [x] 4.3 Implement `sing-gateway print-nft` through `tproxy_ctrl.sh set --dry-run` without mutating host network state.
- [x] 4.4 Implement `sing-gateway set` to apply the resolved configuration through packaged `tproxy_ctrl.sh` and clean up best-effort on failure.
- [x] 4.5 Implement `sing-gateway unset` to clean managed resources through packaged `tproxy_ctrl.sh` using available managed context.

## 5. Debian Maintainer Script Behavior

- [x] 5.1 Add maintainer scripts that keep install inert and do not start, restart, enable, or mutate network state during install.
- [x] 5.2 Ensure package upgrade preserves active drop-ins and does not unset managed gateway state.
- [x] 5.3 Ensure package removal removes active drop-ins and performs best-effort managed cleanup while package commands remain available.
- [x] 5.4 Ensure package purge removes residual sing-gateway configuration and drop-in files while tolerating missing non-essential dependencies.

## 6. Tests and Verification

- [x] 6.1 Extend the shell test suite with fake sing-box, systemctl, id, nft, ip, and sysctl commands for wrapper behavior.
- [x] 6.2 Test inert install/package layout expectations and dependency metadata.
- [x] 6.3 Test enable/disable behavior, including validation failure, force enable, no service restart, and drop-in content.
- [x] 6.4 Test config discovery precedence, TProxy inbound selection, FakeIP inference, DNS hijack explicitness, and local-proxy bypass safety.
- [x] 6.5 Test lifecycle commands delegate to packaged `tproxy_ctrl.sh` with expected arguments and preserve dry-run diagnostics as side-effect-free.
- [x] 6.6 Test maintainer-script remove, purge, and upgrade behavior with fake system commands.
- [x] 6.7 Run `sh tests/run.sh` and `git diff --check` before marking implementation complete.
