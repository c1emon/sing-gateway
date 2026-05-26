# sing-gateway Debian companion package

`sing-gateway` is an inert companion package for the official `sing-box`
package. Installation only places files on disk: it does not enable a systemd
drop-in, restart sing-box, call nftables, change routes, or alter sysctl values.

## Installed files

- `/usr/bin/sing-gateway` - user-facing wrapper CLI.
- `/usr/lib/sing-gateway/tproxy_ctrl.sh` - low-level nftables/routing engine.
- `/usr/lib/sing-gateway/sing-box.service.d/10-sing-gateway.conf` - packaged
  drop-in template.
- `/etc/sing-gateway/gateway.conf` - conffile for explicit overrides.
- `/var/lib/sing-gateway/enabled` - created only by `sing-gateway enable`; this
  state file is the authority for managed cleanup parameters.

## Building the Debian package

Builds use standard Debian metadata under `debian/` as the source of truth.
Install the local build and inspection tools in a Debian or Ubuntu environment:

```sh
sudo apt-get update
sudo apt-get install --no-install-recommends \
  build-essential devscripts debhelper lintian dpkg-dev
```

Runtime package dependencies are declared in `debian/control`; the package
depends on `sing-box`, `nftables`, `iproute2`, `procps`, `jq`, and `systemd`.
The repository metadata required by Debian tooling includes `debian/control`,
`debian/changelog`, `debian/copyright`, `debian/source/format`, `debian/rules`,
`debian/install`, `debian/docs`, and maintainer scripts. Debhelper automatically
records files installed under `/etc` as conffiles.

From the repository root, the canonical binary package build command is:

```sh
dpkg-buildpackage -us -uc -b
```

`debuild -us -uc -b` is an equivalent convenience invocation when `devscripts`
is installed. The optional `make deb` target is only a thin wrapper around
`dpkg-buildpackage -us -uc -b`; it does not duplicate package metadata or file
lists.

Build artifacts are emitted in the parent directory of the repository, for
example:

```text
../sing-gateway_<version>_all.deb
../sing-gateway_<version>_<arch>.changes
../sing-gateway_<version>_<arch>.buildinfo
```

Inspect the generated artifact before installing it:

```sh
test "$(cat debian/source/format)" = "3.0 (native)"
dpkg-parsechangelog --show-field Version | grep -v -- '-'
grep -R "GPL-3+" LICENSE debian/copyright
grep -R "/usr/share/common-licenses/GPL-3" debian/copyright
dpkg-deb --info ../sing-gateway_*_all.deb
dpkg-deb --contents ../sing-gateway_*_all.deb
lintian ../sing-gateway_<version>_<arch>.changes ../sing-gateway_*_all.deb
```

The source format must be `3.0 (native)`, the changelog version must not include
a Debian revision suffix such as `-1`, and project/Debian copyright metadata
must declare GPL-3+ licensing. The package metadata inspection should show the
`sing-gateway` package name, version, architecture, dependencies, maintainer,
and description. The file layout should include `/usr/bin/sing-gateway`,
`/usr/lib/sing-gateway/tproxy_ctrl.sh`, the packaged drop-in template under
`/usr/lib/sing-gateway/sing-box.service.d/`, the
`/etc/sing-gateway/gateway.conf` conffile, and documentation under
`/usr/share/doc/sing-gateway/`.

## Package lifecycle validation

Run install/remove/purge validation only in a disposable Debian or Ubuntu test
environment such as a VM or container, not on a workstation that has production
networking state.

```sh
sudo apt-get install ./../sing-gateway_*_all.deb
test ! -e /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
command -v sing-gateway
dpkg -L sing-gateway
```

Installation must remain inert: it must not create the active
`/etc/systemd/system/sing-box.service.d/10-sing-gateway.conf` drop-in, start or
restart `sing-box.service`, call nftables, change policy routing, or change
sysctl forwarding values. Gateway activation still requires an explicit
`sudo sing-gateway enable` followed by the operator-controlled sing-box restart.

Exercise the explicit enable path and package-owned files in the test
environment:

```sh
sudo sing-gateway check
sudo sing-gateway print-command
sudo sing-gateway print-nft
sudo sing-gateway enable
test -L /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
test "$(readlink /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf)" = "/usr/lib/sing-gateway/sing-box.service.d/10-sing-gateway.conf"
test -f /var/lib/sing-gateway/enabled
grep "^NF_TABLE=" /var/lib/sing-gateway/enabled
```

Validate removal and purge cleanup without expecting service restarts:

```sh
sudo apt-get remove sing-gateway
test ! -e /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
test ! -e /var/lib/sing-gateway/enabled
sudo install -d /etc/sing-gateway
printf keep | sudo tee /etc/sing-gateway/admin.keep >/dev/null
sudo apt-get purge sing-gateway
test -f /etc/sing-gateway/admin.keep
sudo rm -f /etc/sing-gateway/admin.keep
rmdir /etc/sing-gateway 2>/dev/null || true
```

Maintainer scripts may reload systemd after removing drop-ins, but they must not
start or restart `sing-box.service`. Also validate removal from a state where
`/var/lib/sing-gateway/enabled` is absent: package removal must not call
`sing-gateway disable`, `tproxy_ctrl.sh unset`, nftables cleanup, or policy route
cleanup. Purge cleanup is intentionally non-recursive and uses `rmdir` for empty
directories so administrator-created files under `/etc/sing-gateway` survive.

## Recommended flow

```sh
sudo sing-gateway check
sudo sing-gateway print-command
sudo sing-gateway print-nft
sudo sing-gateway enable
sudo systemctl restart sing-box.service
```

`enable` validates by default, installs the active drop-in as a symlink from
`/etc/systemd/system/sing-box.service.d/10-sing-gateway.conf` to the packaged
template under `/usr/lib/sing-gateway/sing-box.service.d/`, writes
`/var/lib/sing-gateway/enabled`, reloads systemd, and prints the restart command.
It does not start or restart sing-box itself.

If current validation cannot run yet but you still want to install the drop-in,
use:

```sh
sudo sing-gateway enable --force
```

`--force` skips the pre-enable validation step only; it still writes cleanup
state from the explicit/default gateway settings already loaded from
`gateway.conf`, not from a full sing-box config resolution.

Runtime starts remain fail-closed because the drop-in still executes
`sing-gateway check` before sing-box starts.

## Disable and removal

```sh
sudo sing-gateway disable
```

`disable` removes the active drop-in only when it is the managed symlink to the
packaged template. If `/var/lib/sing-gateway/enabled` exists, `disable` uses the
persisted enable-time values from that file for best-effort nftables and policy
routing cleanup, then removes the state file. If the state file is absent,
`disable` does not invoke network cleanup and does not infer cleanup identifiers
from the current `/etc/sing-gateway/gateway.conf`.

Package upgrades preserve any active drop-in and do not unset gateway state.
Package removal runs best-effort cleanup through `sing-gateway disable` only when
the enabled-state file exists and package commands are still available. Purge
removes residual enabled-state files and managed symlinks where safe, but never
recursively deletes `/etc/sing-gateway`.

## Configuration notes

`/etc/sing-gateway/gateway.conf` can set explicit values such as
`SING_BOX_CONFIG_FILE`, `SING_BOX_CONFIG_DIR`, `TPROXY_INBOUND_TAG`,
`TPROXY_PORT`, `STACK`, `FAKEIP_V4`, `FAKEIP_V6`, `HIJACK_DNS`, `PROXY_LOCAL`,
`IGNORE_UID`, and `IGNORE_MARK`.

When no explicit sing-box source is configured, `sing-gateway` inspects
`sing-box.service` metadata for config paths and service user, then falls back
to `/etc/sing-box/config.json` only if that file exists.
