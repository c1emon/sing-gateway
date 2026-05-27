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
