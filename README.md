# tproxy

用于 TProxy 网关场景的透明代理控制脚本，负责配置 Linux nftables 和策略路由。

## 功能说明

`tproxy_ctrl.sh` 会生成并应用一个 `inet` nftables 表，可用于：

- 将 TCP/UDP 流量重定向到本机 TProxy 端口。
- 启用 IPv4、IPv6 或双栈透明代理路由。
- 劫持 DNS 流量，并将其送入 TProxy 路径。
- 为 IPv4 和/或 IPv6 FakeIP CIDR 流量设置代理路由。
- 可选地代理本机发出的流量，并通过 mark 或 UID 绕过指定流量以避免代理回环。
- 为带 mark 的流量配置 Linux 策略路由规则和本地路由。
- 清理脚本管理的 nftables 表和策略路由。

脚本面向具备 `nft`、`ip`、`sysctl` 的 Linux 系统。非 dry-run 的实际应用操作通常需要 root 权限。

## 文件说明

- `tproxy_ctrl.sh`：主控制脚本，用于设置和清理 TProxy 相关规则。
- `sing-gateway`：Debian companion package 的用户入口，用于发现 sing-box 配置、验证并委托 `tproxy_ctrl.sh`。
- `packaging/`、`debian/`：`sing-gateway` 包的默认配置、systemd drop-in 模板和 Debian 打包元数据。
- `tests/run.sh`：无外部依赖的 POSIX shell 回归测试套件。
- `Makefile`：可选维护者辅助入口，`make deb` 仅委托标准 Debian 构建工具。

## 使用方法

查看帮助：

```sh
sh tproxy_ctrl.sh --help
```

以 dry-run 方式生成默认 IPv4 规则：

```sh
sh tproxy_ctrl.sh set --dry-run
```

以 dry-run 方式生成双栈 nftables 规则：

```sh
sh tproxy_ctrl.sh set --stack=all --dry-run
```

将生成的 nftables 规则保存到文件：

```sh
sh tproxy_ctrl.sh set --stack=all --save=./tproxy.nft --dry-run
```

应用 IPv4 TProxy 路由：

```sh
sudo sh tproxy_ctrl.sh set --stack=v4
```

应用双栈 TProxy 路由，并启用 DNS 劫持和 FakeIP 路由：

```sh
sudo sh tproxy_ctrl.sh set \
  --stack=all \
  --hijack-dns \
  --fake-ip4=198.18.0.0/15 \
  --fake-ip6=fc00::/18
```

代理本机发出的流量，并通过 ignore mark 避免回环：

```sh
sudo sh tproxy_ctrl.sh set \
  --proxy-local \
  --ignore-mark=0x20
```

代理本机发出的流量，并绕过指定 UID 的代理进程：

```sh
sudo sh tproxy_ctrl.sh set \
  --proxy-local \
  --ignore-uid=1000
```

清理脚本管理的 nftables 和路由状态：

```sh
sudo sh tproxy_ctrl.sh unset
```

## systemd 集成

Debian 系统上推荐使用 `sing-gateway` companion package 提供的显式启用流程。安装包本身是惰性的，不会创建 active drop-in、重启 sing-box、调用 nftables、修改路由或修改 sysctl。

典型流程：

```sh
sudo sing-gateway check
sudo sing-gateway print-command
sudo sing-gateway print-nft
sudo sing-gateway enable
sudo systemctl restart sing-box.service
```

`sing-gateway enable` 会验证配置，把 `/etc/systemd/system/sing-box.service.d/10-sing-gateway.conf` 创建为指向 `/usr/lib/sing-gateway/sing-box.service.d/10-sing-gateway.conf` 的受管 symlink，写入 `/var/lib/sing-gateway/enabled` 作为后续清理依据，执行 `systemctl daemon-reload`，并提示用户重启 sing-box；它不会自动启动或重启 sing-box。需要临时跳过启用前验证时可使用 `sing-gateway enable --force`，但服务启动时仍会通过 `ExecStartPre=+sing-gateway check` 失败关闭。`--force` 只跳过启用前验证；清理 state 仍来自 `gateway.conf` 中显式配置的值或默认值，而不是完整解析后的 sing-box 配置。

禁用集成：

```sh
sudo sing-gateway disable
```

该命令只会移除指向打包模板的受管 symlink，并且仅在 `/var/lib/sing-gateway/enabled` 存在时才使用其中记录的启用时参数清理 nftables/策略路由状态；不会根据当前 `gateway.conf` 推断清理目标，也不会删除普通文件或无关 symlink。更多 Debian 包说明见 `docs/sing-gateway.md`。

## Debian 包构建与检查

在 Debian/Ubuntu 构建环境中安装维护者工具：

```sh
sudo apt-get update
sudo apt-get install --no-install-recommends \
  build-essential devscripts debhelper lintian dpkg-dev
```

标准构建路径以 `debian/` 元数据为唯一事实来源：

```sh
dpkg-buildpackage -us -uc -b
```

安装 `devscripts` 后也可以使用等价命令：

```sh
debuild -us -uc -b
```

可选的本地辅助命令 `make deb` 只是调用 `dpkg-buildpackage -us -uc -b`，不会复制包元数据或文件列表。

构建产物会写入仓库父目录，通常包括：

```text
../sing-gateway_<version>_all.deb
../sing-gateway_<version>_<arch>.changes
../sing-gateway_<version>_<arch>.buildinfo
```

安装前检查包元数据、文件列表和 lintian 输出：

```sh
test "$(cat debian/source/format)" = "3.0 (native)"
dpkg-parsechangelog --show-field Version | grep -v -- '-'
grep -R "GPL-3+" LICENSE debian/copyright
dpkg-deb --info ../sing-gateway_*_all.deb
dpkg-deb --contents ../sing-gateway_*_all.deb
lintian ../sing-gateway_<version>_<arch>.changes ../sing-gateway_*_all.deb
```

`debian/source/format` 应为 `3.0 (native)`，`debian/changelog` 版本不应包含 Debian revision 后缀（例如 `-1`），项目 `LICENSE` 与 `debian/copyright` 应声明 GPL-3+，并在 Debian 版权元数据中指向 `/usr/share/common-licenses/GPL-3`。`dpkg-deb --info` 应展示包名、版本、架构、依赖、维护者和描述；文件列表应包含 CLI、控制脚本、默认配置、文档和 systemd drop-in 模板。

建议只在一次性 Debian/Ubuntu VM 或容器中测试安装生命周期：

```sh
sudo apt-get install ./../sing-gateway_*_all.deb
test ! -e /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
command -v sing-gateway
dpkg -L sing-gateway
sudo sing-gateway enable
test -L /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
test "$(readlink /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf)" = "/usr/lib/sing-gateway/sing-box.service.d/10-sing-gateway.conf"
test -f /var/lib/sing-gateway/enabled
sudo apt-get remove sing-gateway
test ! -e /etc/systemd/system/sing-box.service.d/10-sing-gateway.conf
sudo install -d /etc/sing-gateway
printf keep | sudo tee /etc/sing-gateway/admin.keep >/dev/null
sudo apt-get purge sing-gateway
test -f /etc/sing-gateway/admin.keep
sudo rm -f /etc/sing-gateway/admin.keep
rmdir /etc/sing-gateway 2>/dev/null || true
```

还应验证没有 `/var/lib/sing-gateway/enabled` 时执行 package remove 不会调用 `sing-gateway disable`、`tproxy_ctrl.sh unset`、nftables 或策略路由清理。安装包必须保持惰性：安装时不创建 active drop-in、不启动或重启 sing-box、不调用 nftables、不修改路由或 sysctl。只有显式运行 `sing-gateway enable` 才会启用集成；remove/purge 清理路径也不应启动或重启服务。purge 只用 `rmdir` 清理空目录，不会递归删除 `/etc/sing-gateway` 中的管理员文件。

### 手动 drop-in

如果使用发行版或上游提供的 `sing-box.service`，建议通过 systemd drop-in 添加规则，不直接修改原始 service 文件，以保持升级兼容性：

```sh
sudo systemctl edit sing-box.service
```

只需要添加 `ExecStartPost` 和 `ExecStopPost`：

```ini
[Service]
ExecStartPost=+/etc/sing-box/tproxy_ctrl.sh set --route-table4=100 --route-mark=0x01 --tproxy-port=9898 --fake-ip4=198.18.0.1/15 --hijack-dns --proxy-local --ignore-uid=990
ExecStopPost=+/etc/sing-box/tproxy_ctrl.sh unset --route-table4=100 --route-mark=0x01 --tproxy-port=9898 --fake-ip4=198.18.0.1/15 --hijack-dns --proxy-local --ignore-uid=990
```

说明：

- `+` 表示该命令以 root 权限执行，用于配置 nftables、策略路由和 sysctl。
- `sing-box.service` 默认已经使用 `User=sing-box` 运行，通常不需要在 drop-in 中再次手动配置 `User=` / `Group=`。
- 启用 `--proxy-local` 时必须通过 `--ignore-uid=<UID>` 或 `--ignore-mark=<MARK>` 跳过 sing-box 自身流量，避免代理回环。
- `--ignore-uid` 需要填写数字 UID，可用 `id -u sing-box` 查看；上例中的 `990` 仅为示例值。

应用并检查最终合并结果：

```sh
sudo systemctl daemon-reload
sudo systemctl restart sing-box.service
systemctl cat sing-box.service
```

## 参数说明

通用参数：

- `set`：生成/应用 nftables 与策略路由配置。
- `unset`：移除脚本管理的 nftables 与策略路由配置。
- `--dry-run`：只打印将要执行或生成的内容，不实际应用。
- `--save=<FILE>`：将生成的 nftables 规则保存到文件。
- `-h`、`--help`：显示帮助信息。

TProxy 参数：

- `--stack=v4|v6|all`：启用 IPv4、IPv6 或双栈。默认值：`v4`。
- `--nf-table=<NAME>`：nftables 表名。必须是安全标识符：只能包含字母、数字和下划线，且不能以数字开头。
- `--route-table4=<ID>`：IPv4 路由表 ID。默认值：`100`。
- `--route-table6=<ID>`：IPv6 路由表 ID。默认值：`106`。
- `--route-mark=<MARK>`：用于策略路由的包 mark。默认值：`0x01`。
- `--tproxy-port=<PORT>`：本机 TProxy 端口。默认值：`9898`。
- `--proxy-local`：重路由本机 output 流量。
- `--ignore-mark=<MARK>`：绕过带有该 mark 的本机 output 流量。
- `--ignore-uid=<UID>`：绕过来自该 UID 的本机 output 流量。

FakeIP 与 DNS 参数：

- `--fake-ip4=<CIDR>`：IPv4 FakeIP CIDR，仅在启用 IPv4 时生效。
- `--fake-ip6=<CIDR>`：IPv6 FakeIP CIDR，仅在启用 IPv6 时生效。
- `--hijack-dns`：将 DNS 流量送入 TProxy 路径。

## 安全注意事项

- 建议先使用 `--dry-run` 检查生成的 nftables 规则。
- 非 dry-run 的 `set` 会调用 `nft`、`ip` 和 `sysctl`，可能改变主机路由和防火墙状态。
- `unset` 会移除脚本管理的 nftables 表和策略路由，但不会关闭 IPv4 或 IPv6 转发。
- `--proxy-local` 必须配合 `--ignore-mark` 或 `--ignore-uid` 使用；否则脚本会拒绝执行，以避免本机代理回环。
- 如果 nftables 规则已应用但路由设置失败，脚本会尝试回滚脚本管理的 nftables 表。

## 测试

在仓库根目录运行完整测试套件：

```sh
sh tests/run.sh
```

测试套件使用 POSIX `sh` 编写，不依赖 Bats、Python、Node 等外部测试框架。测试会在临时目录中创建假的 `nft`、`ip` 和 `sysctl` 命令，因此不需要 root 权限，也不会修改宿主机网络状态。

测试覆盖范围包括：

- CLI 参数校验和边界值检查。
- 安全与不安全的 nft 表名。
- route mark、TProxy 端口、路由表 ID、UID、FakeIP CIDR。
- IPv4、IPv6、双栈 dry-run 规则生成。
- DNS 劫持、FakeIP、本机代理绕过规则及规则顺序。
- 合法/非法调用下的保存与不保存行为。
- 使用 fake 命令验证非 dry-run 命令调用顺序。
- 幂等路由设置和清理容错。
- nftables 应用成功但路由设置失败时的回滚行为。

如果系统存在兼容的 Linux `nft` 命令，可以启用可选的真实 nft 解析校验：

```sh
TPROXY_TEST_NFT_CHECK=1 sh tests/run.sh
```

默认情况下该解析校验会跳过，因此测试套件可在没有 nftables 的环境中通过，包括 macOS 开发机。

## 开发流程

涉及行为变更时，建议使用本仓库的 OpenSpec 流程：

```text
/opsx-explore → /opsx-propose → new session → /opsx-apply → /opsx-verify → /opsx-archive
```

提交前建议运行：

```sh
sh tests/run.sh
git diff --check
```
