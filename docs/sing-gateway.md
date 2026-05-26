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
`debian/changelog`, `debian/copyright`, `debian/rules`, `debian/install`,
`debian/docs`, and maintainer scripts. Debhelper automatically records files
installed under `/etc` as conffiles.

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
dpkg-deb --info ../sing-gateway_*_all.deb
dpkg-deb --contents ../sing-gateway_*_all.deb
lintian ../sing-gateway_<version>_<arch>.changes ../sing-gateway_*_all.deb
```

The metadata inspection should show the `sing-gateway` package name, version,
architecture, dependencies, maintainer, and description. The file layout should
include `/usr/bin/sing-gateway`, `/usr/lib/sing-gateway/tproxy_ctrl.sh`, the
packaged drop-in template under `/usr/lib/sing-gateway/sing-box.service.d/`,
the `/etc/sing-gateway/gateway.conf` conffile, and documentation under
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
test -e /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
```

Validate removal and purge cleanup without expecting service restarts:

```sh
sudo apt-get remove sing-gateway
test ! -e /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
sudo apt-get purge sing-gateway
test ! -d /etc/sing-gateway
```

Maintainer scripts may reload systemd after removing drop-ins, but they must not
start or restart `sing-box.service`.

## Recommended flow

```sh
sudo sing-gateway check
sudo sing-gateway print-command
sudo sing-gateway print-nft
sudo sing-gateway enable
sudo systemctl restart sing-box.service
```

`enable` validates by default, installs the active drop-in under
`/etc/systemd/system/sing-box.service.d/`, reloads systemd, and prints the
restart command. It does not start or restart sing-box itself.

If current validation cannot run yet but you still want to install the drop-in,
use:

```sh
sudo sing-gateway enable --force
```

Runtime starts remain fail-closed because the drop-in still executes
`sing-gateway check` before sing-box starts.

## Disable and removal

```sh
sudo sing-gateway disable
```

`disable` removes the active drop-in, best-effort cleans managed nftables and
policy routing state, reloads systemd, and does not restart sing-box.

Package upgrades preserve any active drop-in and do not unset gateway state.
Package removal runs best-effort cleanup while package commands are still
available. Purge removes residual `/etc/sing-gateway` configuration and active
drop-in files where safe.

## Configuration notes

`/etc/sing-gateway/gateway.conf` can set explicit values such as
`SING_BOX_CONFIG_FILE`, `SING_BOX_CONFIG_DIR`, `TPROXY_INBOUND_TAG`,
`TPROXY_PORT`, `STACK`, `FAKEIP_V4`, `FAKEIP_V6`, `HIJACK_DNS`, `PROXY_LOCAL`,
`IGNORE_UID`, and `IGNORE_MARK`.

When no explicit sing-box source is configured, `sing-gateway` inspects
`sing-box.service` metadata for config paths and service user, then falls back
to `/etc/sing-box/config.json` only if that file exists.
