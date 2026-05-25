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
- `tproxy.service`：用于运行控制脚本的 systemd 服务文件。
- `tests/run.sh`：无外部依赖的 POSIX shell 回归测试套件。
- `update_config.sh`：本地配置下载辅助脚本；可能包含环境相关 URL，因此已被 git 忽略。

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
