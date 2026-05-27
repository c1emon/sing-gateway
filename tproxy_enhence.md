# TPROXY 排除规则增强记录

本文记录对 `scripts/tproxy_ctrl.sh` 中 TPROXY/nftables 排除规则的检查结论与后续增强方向。

## 当前状态

当前脚本相比直接劫持所有 TCP/UDP 已经有基础保护：

- 非 TCP/UDP 直通：`meta l4proto != { tcp, udp }`。
- NTP `dport 123` 直通。
- IPv4 私有、保留、组播、广播地址段直通。
- IPv6 私有、保留、组播地址段直通。
- FakeIP 规则优先于 private/direct 规则处理。
- 本机流量代理时支持 `--ignore-mark` / `--ignore-uid` 防止代理环路。
- DNS 劫持为可选项：`--hijack-dns`。
- 包含 `divert` 链处理 transparent socket。

整体框架合理，但作为生产透明网关规则仍不完备。

## 本轮硬化决策

本轮继续保留 `tproxy_ctrl.sh` 为 POSIX shell 实现，不引入 Python/Go/Rust 运行时依赖。原因是当前仓库、Debian companion package 和回归测试都围绕无额外依赖的 shell 脚本组织；本次目标是规则硬化而不是重写控制器。

但该脚本已经接近“小型策略编译器”。后续如果需要完整 CIDR 重叠分析、多命名策略配置、拓扑自动推断、结构化诊断输出或 OPNsense 配置联动，应迁移到 Python 或其他结构化控制器，并使用标准库/成熟库处理网段、接口和策略模型。

### P0/P1 安全发现

- **hook priority 必须显式**：TPROXY prerouting 必须在路由查找前执行，且 dry-run 输出中应能看到确定的 numeric priority。`divert` 与主 prerouting 链不应依赖同优先级或隐式顺序。
- **divert 顺序必须独立且可审计**：transparent socket divert 需要先于主 TPROXY pipeline，并与入口范围保持一致，避免非目标接口上的连接被脚本误处理。
- **入口范围必须先判定**：生产部署应配置 `--in-iface=<iface[,iface...]>` allow-list。Docker、WireGuard、loopback、管理网卡或其他虚拟接口不应被默认纳入透明代理。
- **rp_filter 是单臂 PBR 前置风险**：来自 LAN/VLAN 的源地址经 OPNsense PBR 到达 DMZ/服务接口时，严格反向路径过滤可能在 nftables 前丢包。应使用 `--rp-filter=check` 检查，或显式 `--rp-filter=loose|disable` 应用安全值。
- **DNS hijack 必须排除本地/基础设施 DNS**：`--hijack-dns` 只适合劫持剩余的外部 DNS 流量；上游 DNAT 到 W 本机 DNS listener 的流量、AD/内部 DNS、管理 DNS 应通过 `--dns-bypass4/6`、`--local-addr4/6` 和端口绕过先接受。
- **FakeIP 必须优先于 private/custom bypass**：`198.18.0.0/15` 常同时属于 FakeIP 和保留地址。启用 FakeIP 时必须传 `--fake-ip4/6`，并在规则顺序上位于 private/custom bypass 之前；与 `--bypass4/6` 完全相同的 CIDR 应拒绝。
- **output 链需要对称绕过**：`--proxy-local` 必须先处理 ignore UID/mark、loopback、本机服务、DNS 绕过、FakeIP/custom bypass，再做通用 reroute，避免代理进程或本机监听服务形成回环。
- **kernel bypass 不等于 sing-box direct**：nft `accept` 只表示不进入 TPROXY，后续能否转发取决于 Linux forwarding、OPNsense NAT/防火墙/anti-spoofing/PBR 防环路。脚本不应把 forwarding 作为基础 TPROXY 的无条件前提；只有显式 `--enable-kernel-bypass` 才应用 forwarding sysctl。

## 主要风险与不完备点

### 1. 缺少入接口限定

当前 `prerouting` 链对所有入接口生效：

```nft
chain prerouting {
    type filter hook prerouting priority filter; policy accept;
```

如果 W 后续存在 Docker、WireGuard、虚拟网卡或管理网卡，可能误劫持非预期流量。

建议增加 `--in-iface=<IFACE>`，在 prerouting 中生成类似规则：

```nft
iifname $IN_IFACE ...
```

### 2. `--hijack-dns` 可能劫持本机 DNS 服务

当前 DNS hijack 在 `direct` 之前执行：

```nft
$DNS_PRE
$FAKEIP_PRE
jump direct
```

如果网关设备已经将 `VIP:53 -> W:53` 做 DNAT，到达 W 时目的地址是 `W_IP:53`。启用 `--hijack-dns` 后，该请求会被 TPROXY 到代理端口，而不是到 W 的 DNS listener。

在当前架构下：

- 如果 DNS 已由网关 DNAT 到 W:53，默认不应启用 `--hijack-dns`。
- 或者 DNS hijack 前必须显式排除本机 DNS 监听地址/端口：

```nft
ip daddr $W_IP th dport 53 accept
ip6 daddr $W_IP6 th dport 53 accept
```

### 3. FakeIP 依赖参数，忘传会被 private 规则放行

`private` 集合中包含 `198.18.0.0/15`，而这通常也是 FakeIP IPv4 段。

启用 `--fake-ip4=198.18.0.0/15` 时，因为 fakeip chain 在 direct 前执行，FakeIP 可以进入 TPROXY。

但如果忘记传 `--fake-ip4`，FakeIP 会匹配 private 规则而被直通，不会进入 TPROXY。

建议：

- 文档明确 FakeIP 模式必须配置 `--fake-ip4` / `--fake-ip6`。
- 或将 FakeIP 段从默认 private 集合中拆出，按模式单独处理。

### 4. 缺少显式本机服务排除

当前主要依赖 private 地址段间接排除 W 自身服务。虽然多数情况下可工作，但不够清晰，也不利于审计。

建议显式排除：

- W IP / W IPv6。
- DNS 监听端口。
- SSH/管理端口。
- sing-box 显式代理端口。
- TPROXY 监听端口。
- 健康检查端口。

示例：

```nft
ip daddr $W_IP accept
ip6 daddr $W_IP6 accept
```

或更细粒度：

```nft
ip daddr $W_IP tcp dport { 22, 53, 7890, 9898 } accept
ip daddr $W_IP udp dport { 53, 9898 } accept
```

### 5. 缺少可配置 bypass CIDR

当前 private/private6 集合是硬编码的，但实际架构中还应排除：

- 所有 LAN 子网。
- DMZ 子网。
- 网关所有接口 IP/VIP。
- 内部 DNS/NTP/AD/LDAP/SMB。
- VPN 网段。
- 管理网段。

建议增加：

```sh
--bypass4=cidr,cidr,...
--bypass6=cidr,cidr,...
```

并生成对应 nft set。

### 6. raw bypass / direct 转发语义仍需明确

脚本中的 `direct` 是 nftables 层面的 `accept`，表示不交给 TPROXY，但这不等于业务层面的“安全直连”。

如果网关设备已经将某些公网流量策略路由到 W，而 W 上 nft accept 了这些包，Linux 会按普通路由转发它们。

这要求额外满足：

- `ip_forward=1`。
- W 默认路由回网关设备。
- 网关 DMZ 允许源为 LAN 子网的包进入。
- 出站 NAT 覆盖这类“从 DMZ 进入、源仍为 LAN”的流量。
- 防环路规则正确。

否则 bypass 流量可能黑洞或形成环路。

## 建议优先级

### 必须增强

1. 增加 `--in-iface`，限定 TPROXY 只处理指定入口接口流量。
2. `--hijack-dns` 前排除本机 DNS 监听地址/端口。
3. FakeIP 模式下强制或明确要求传入 `--fake-ip4` / `--fake-ip6`。
4. 增加显式本机服务排除。

### 建议增强

1. 增加 `--bypass4` / `--bypass6` 支持自定义排除网段。
2. 将 FakeIP 段从默认 private set 中拆分为独立逻辑。
3. 支持管理端口、DNS 端口、显式代理端口、健康检查端口的参数化排除。

### 文档需明确

1. `--hijack-dns` 与“网关 DNAT VIP:53 -> W:53”不应默认同时启用。
2. nft `accept` 的 bypass 流量是否允许三层转发。
3. 如果允许 raw bypass，网关侧必须配套 DMZ anti-spoofing、出站 NAT、防环路和状态防火墙规则。

## 当前结论

`scripts/tproxy_ctrl.sh` 的 TPROXY 排除规则方向正确，适合作为基础版本；但作为单臂透明代理网关的生产规则，仍需补充入接口限定、DNS 保护、FakeIP 强约束、本机服务显式排除、自定义 bypass CIDR，以及 raw bypass 的网关侧配套说明。
