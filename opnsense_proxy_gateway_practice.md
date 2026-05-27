# OPNsense 代理网关具体实践方法

本文是 `proxy_arch.md` 的 OPNsense 落地实践说明。

架构、角色定义、Proxy Gateway VIP 语义、FakeDNS/FakeIP 约束、PBR 边界、TPROXY 排除规则、direct/bypass 语义等均以 `proxy_arch.md` 为准。本文只说明在 OPNsense + 单网卡代理网关场景下，如何把该架构落地。

## 1. 适用范围

本文适用于以下部署形态：

- 主网关 / 防火墙使用 OPNsense。
- 代理网关运行 Linux + `sing-box`。
- 代理网关只有一个生产网卡，位于 OPNsense 可达的 DMZ 或服务网段。
- 被代理主机所在 LAN/VLAN 与代理网关不在同一二层网络。
- Proxy Gateway VIP 由 OPNsense 在各被代理子网中持有。
- OPNsense 通过精确 DNAT / port-forward 暴露代理网关服务端口。
- OPNsense 通过策略路由将需要透明代理的 TCP/UDP 流量导向代理网关。

本文不把代理网关描述为被代理主机的真实二层默认网关。被代理主机即使把默认网关配置为 Proxy Gateway VIP，流量也仍然首先进入 OPNsense，再由 OPNsense 按策略导向代理网关。

## 2. 示例拓扑

```text
                    Internet
                       │
                ┌──────┴──────┐
                │  OPNsense   │
                │ 主网关/防火墙 │
                └──┬───┬───┬──┘
             LAN_A LAN_B LAN_C  DMZ: 10.255.255.0/24
               │     │     │        │
        VIP: .100 .100 .100   ┌─────┴─────┐
                               │ 代理网关   │
                               │10.255.255.10│
                               │ sing-box  │
                               └───────────┘
```

示例地址：

| 对象 | 示例 |
|---|---|
| 代理网关 DMZ IP | `10.255.255.10/24` |
| OPNsense DMZ IP | `10.255.255.1/24` |
| LAN_A Proxy Gateway VIP | `192.168.1.100/24` |
| LAN_B Proxy Gateway VIP | `192.168.2.100/24` |
| LAN_C Proxy Gateway VIP | `192.168.3.100/24` |
| FakeIP CIDR | `198.18.0.0/15` |
| sing-box TPROXY 端口 | `12345` |

被代理主机可按目标模式选择：

- 仅显式代理：应用配置 HTTP/SOCKS5 代理地址。
- FakeDNS + FakeIP：DNS 指向代理 DNS 或由 OPNsense 转发到代理 DNS。
- VIP + PBR 透明代理：默认网关配置为对应子网的 Proxy Gateway VIP。

## 3. OPNsense 配置原则

### 3.1 不使用全端口 1:1 NAT 作为默认方案

不建议将以下规则作为默认方案：

```text
Proxy Gateway VIP:any -> 代理网关:any
```

原因：

- 暴露面过大。
- 容易混淆“访问 VIP 自身服务”和“经 VIP 作为默认网关转发”的流量。
- 不同 OPNsense / pf 规则组合下，binat、port-forward、filter、reply-to、route-to 的执行细节可能导致排错困难。

推荐拆成两类处理：

| 流量类型 | OPNsense 处理方式 | 到达代理网关时的目标地址 |
|---|---|---|
| 访问 VIP 上的 DNS / HTTP 代理 / SOCKS5 代理等服务 | 精确 DNAT / port-forward | 代理网关真实 IP + 对应服务端口 |
| 访问真实公网 IP 或 FakeIP 的普通转发流量 | PBR / route-to 到代理网关 | 保留原始目标 IP |

### 3.2 FakeIP 流量不能 DNAT

FakeDNS 返回的 FakeIP 必须原样到达代理网关，代理网关才能通过自身 FakeIP 映射还原域名。

因此：

```text
目的地址 = 198.18.0.0/15
动作 = PBR 到代理网关
不要 DNAT 为 10.255.255.10
```

### 3.3 PBR 规则必须收敛范围

不要使用过宽规则：

```text
协议 = any
源 = LAN net
目的 = any
网关 = 代理网关
```

推荐只导入需要透明代理的流量，例如：

```text
入接口 = 被代理 LAN/VLAN 接口
源地址 = 被代理主机组或被代理网段
协议 = TCP/UDP
目的地址 = FakeIP CIDR 或公网地址集合
网关 = 代理网关 DMZ IP
```

必须排除：

- OPNsense 自身接口地址和 VIP。
- 代理网关自身 IP。
- DMZ 网段。
- 内部网段。
- RFC1918、CGNAT、link-local、loopback、multicast、broadcast 等特殊地址。
- DHCP、NTP、内部 DNS、AD、LDAP、SMB、打印、监控等基础设施服务。
- ICMP，至少不能破坏 PMTUD 相关 ICMP。
- VPN、IPsec、GRE、ESP 等特殊协议。
- 管理网段和故障恢复通道。

## 4. OPNsense 实施步骤

### 4.1 创建 Proxy Gateway VIP

在每个需要使用代理网关入口的 LAN/VLAN 接口上创建 IP Alias：

1. 进入 **Firewall → Virtual IPs → Settings**。
2. 点击 `+`。
3. **Mode** 选择 `IP Alias`。
4. **Interface** 选择对应 LAN/VLAN 接口。
5. **Address** 填写该子网内的 Proxy Gateway VIP，例如 `192.168.1.100/24`。
6. 为其他被代理子网重复创建。

这些 VIP 由 OPNsense 持有并响应 ARP。代理网关不持有这些 VIP。

### 4.2 创建代理网关 Gateway 对象

1. 进入 **System → Gateways → Single**。
2. 添加代理网关：
   - **Name**：`GW_PROXY`
   - **Interface**：DMZ 接口
   - **Gateway IP**：`10.255.255.10`
3. 开启或配置健康检查地址。健康检查对象可使用代理网关 DMZ IP，或另行提供专用健康检查服务。

如果后续需要 Fail-open，可通过网关监控、规则禁用、脚本或自动化配置在代理网关不可用时撤销 PBR。

### 4.3 为 VIP 上的服务配置精确 DNAT / port-forward

如果被代理主机需要通过 Proxy Gateway VIP 访问代理网关 DNS 或显式代理端口，在 OPNsense 上配置精确端口转发。

进入 **Firewall → NAT → Port Forward**，分别添加需要的端口。

DNS 示例：

```text
Interface: LAN_A
Protocol: TCP/UDP
Destination: LAN_A Proxy Gateway VIP
Destination port: 53
Redirect target IP: 10.255.255.10
Redirect target port: 53
Filter rule association: Add associated filter rule
```

HTTP 代理示例：

```text
Destination: Proxy Gateway VIP
Destination port: HTTP_PROXY_PORT
Redirect target IP: 10.255.255.10
Redirect target port: HTTP_PROXY_PORT
```

SOCKS5 代理示例：

```text
Destination: Proxy Gateway VIP
Destination port: SOCKS5_PORT
Redirect target IP: 10.255.255.10
Redirect target port: SOCKS5_PORT
```

不要把 VIP 的所有端口整体转发到代理网关。只开放 DNS、显式代理、健康检查等确实需要被访问的服务端口。

### 4.4 创建别名 Alias

建议先创建别名，降低规则复杂度。

进入 **Firewall → Aliases**，可创建：

| Alias | 示例内容 | 用途 |
|---|---|---|
| `PROXY_CLIENTS` | 需要透明代理的主机或网段 | PBR 源地址 |
| `PROXY_GATEWAY` | `10.255.255.10` | 排除代理网关自身 |
| `FAKEIP_NETS` | `198.18.0.0/15` | FakeIP PBR |
| `INTERNAL_NETS` | RFC1918、DMZ、管理网段、内部服务网段 | PBR 排除 |
| `INFRA_SERVERS` | DNS、AD、NTP、监控、打印等服务器 | PBR 排除 |
| `BYPASS_PORTS` | DHCP、NTP、LDAP、SMB 等端口 | PBR 排除 |

OPNsense 默认 bogon / reserved 地址策略可能会拦截 `198.18.0.0/15`。需要确保 FakeIP CIDR 在相关接口和规则中被允许导向代理网关，而不是被当作异常公网目的地址丢弃。

### 4.5 配置 FakeIP PBR

在每个被代理 LAN/VLAN 接口上添加规则，放在普通允许出站规则之前。

示例：

```text
Action: Pass
Interface: LAN_A
Protocol: TCP/UDP
Source: PROXY_CLIENTS 或 LAN_A net
Destination: FAKEIP_NETS
Gateway: GW_PROXY
```

该规则只负责把 FakeIP 目的流量送到代理网关，不能做 DNAT。

### 4.6 配置真实公网目的流量 PBR

如果采用方式三并希望透明代理真实 IP 目的流量，再添加真实公网目的流量 PBR。

推荐通过“先排除，后导流”的顺序：

1. 允许或直连内部 / 基础设施 / 管理 / VPN 流量，不设置 `GW_PROXY`。
2. 对需要透明代理的 TCP/UDP 公网流量设置 `GW_PROXY`。

示例导流规则：

```text
Action: Pass
Interface: LAN_A
Protocol: TCP/UDP
Source: PROXY_CLIENTS
Destination: 公网地址集合，或 !INTERNAL_NETS
Gateway: GW_PROXY
```

具体写法取决于 OPNsense 版本和 Alias 支持能力。关键是不要让内部服务、管理通道、ICMP、DHCP、NTP、AD/LDAP/SMB、VPN 等误入代理网关。

### 4.7 出站 NAT

代理网关自身访问互联网时，通常需要由 OPNsense 对 DMZ 网段做出站 NAT。

进入 **Firewall → NAT → Outbound**，确认以下流量可以出网：

```text
Source: 10.255.255.0/24 或 10.255.255.10
Translation: WAN address
```

如果只允许 `sing-box` 代理程序 direct 出站，则重点覆盖代理网关真实 IP 出网。

如果允许内核三层转发 bypass，则需要额外设计是否保留被代理主机源 IP、是否允许 DMZ 入接口上出现源地址为 LAN 网段的流量，以及对应 NAT / anti-spoofing 规则。

### 4.8 DMZ 入方向规则

需要允许代理网关出站到 OPNsense，再由 OPNsense 转发或 NAT 到目标网络。

至少需要确认：

- 代理网关到互联网的 TCP/UDP 出站允许。
- 代理网关到必要内部 DNS / NTP / 管理服务的访问符合策略。
- 如果允许 kernel bypass，DMZ 接口需要有明确规则允许来自代理网关或来自被代理主机源地址的返回路径，并避免再次 PBR 回代理网关形成环路。

## 5. 代理网关 Linux 配置要点

### 5.1 基础网络

示例：

```text
IP: 10.255.255.10/24
Gateway: 10.255.255.1
```

关闭或放宽 `rp_filter`：

```bash
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
```

如果允许内核三层转发 bypass，再启用 IP forwarding：

```bash
sysctl -w net.ipv4.ip_forward=1
```

如果所有流量都必须进入 sing-box，由 sing-box 决定 proxy/direct/reject，则不应把 IP forwarding 当作默认必需项；是否开启取决于是否允许 kernel bypass。

### 5.2 TPROXY 本地路由

示例：

```bash
ip rule add fwmark 0x1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
```

### 5.3 TPROXY 规则

TPROXY 不应无条件劫持所有 TCP/UDP。规则应限定入接口并排除本机服务、代理服务端口、DNS 端口、管理端口、内部网段和保留地址。

下面只是结构示例，实际应按 nftables / iptables 版本、接口名、端口和地址段改写：

```bash
# 示例变量
LAN_IN_IF="eth0"
TPROXY_PORT="12345"
MARK="0x1"

# 伪代码：先 return 排除项，再对剩余 TCP/UDP TPROXY
# - 排除 10.255.255.10 本机服务
# - 排除 53、HTTP_PROXY_PORT、SOCKS5_PORT、SSH/管理端口
# - 排除 RFC1918 / link-local / multicast / broadcast / 内部网段
# - 排除不需要代理的基础设施服务
# - 仅处理从 OPNsense 导入的 TCP/UDP 流量
```

如果使用 nftables，建议把排除列表做成 set，避免规则难以维护。

### 5.4 sing-box 入站示例

TPROXY 入站示例：

```json
{
  "type": "tproxy",
  "tag": "tproxy-in",
  "listen": "::",
  "listen_port": 12345,
  "tcp_fast_open": true,
  "udp_fragment": true,
  "sniff": true,
  "sniff_override_destination": false
}
```

DNS / FakeIP 配置应确保：

- DNS 查询确实进入该代理网关。
- FakeIP CIDR 与 OPNsense 上的 `FAKEIP_NETS` 一致。
- FakeIP 映射生命周期与客户端 DNS 缓存匹配。
- 多代理网关场景下，DNS 查询和后续 FakeIP 连接命中同一代理网关，或共享 FakeIP 映射状态。

## 6. 典型流量路径

### 6.1 DNS 请求

```text
被代理主机
  -> Proxy Gateway VIP:53
  -> OPNsense port-forward
  -> 代理网关:53
  -> sing-box DNS 返回 FakeIP
  -> OPNsense 有状态反向转换
  -> 被代理主机收到 DNS 响应
```

### 6.2 FakeIP 访问

```text
被代理主机
  -> 198.18.0.123:443
  -> OPNsense FakeIP PBR，保留目标地址
  -> 代理网关 TPROXY
  -> sing-box 根据 FakeIP 还原域名
  -> proxy/direct/reject
  -> OPNsense 出站 NAT
  -> Internet
```

### 6.3 真实公网 IP 透明代理

```text
被代理主机
  -> 真实公网 IP:443
  -> OPNsense 公网目的 PBR
  -> 代理网关 TPROXY
  -> sing-box 依赖规则、SNI/sniff 或 IP 规则处理
  -> OPNsense 出站 NAT
  -> Internet
```

### 6.4 内部与基础设施流量

```text
被代理主机
  -> 内部 DNS / AD / NTP / 管理网段 / VPN 等
  -> OPNsense 普通防火墙与路由规则
  -> 不导入代理网关
```

## 7. 验证清单

### 7.1 VIP 所有权

- 被代理主机 ARP Proxy Gateway VIP 时，响应 MAC 应为 OPNsense 或 HA 虚拟 MAC。
- 代理网关不应配置这些 VIP。

### 7.2 DNS / FakeIP

- 被代理主机查询代理 DNS 能得到 FakeIP。
- OPNsense 上能看到 DNS 端口转发状态。
- 代理网关上能看到 DNS 查询来源为真实被代理主机 IP，或符合预期的来源地址。

### 7.3 FakeIP 路由

- 被代理主机访问 FakeIP 时，OPNsense 将流量 route-to / PBR 到 `GW_PROXY`。
- 代理网关收到的目标地址仍是 FakeIP。
- 不存在 FakeIP 到代理网关真实 IP 的 DNAT。

### 7.4 PBR 排除

- 内部网段访问不进入代理网关。
- DHCP、NTP、AD、LDAP、SMB、管理端口、VPN 流量不进入代理网关。
- ICMP / PMTUD 不被错误导入 TPROXY 或阻断。

### 7.5 回程路径

- 代理网关默认路由指向 OPNsense DMZ IP。
- 代理出站流量由 OPNsense 执行出站 NAT。
- OPNsense 状态表能看到完整连接状态。

### 7.6 故障回退

- 代理网关不可用时，明确采用 Fail-closed 还是 Fail-open。
- Fail-open 场景下，确认 PBR 撤销后流量不会继续黑洞。
- Fail-closed 场景下，确认阻断符合预期且不会影响管理通道。

## 8. 常见错误

1. **把代理网关当成客户端真实默认网关**  
   正确理解是：OPNsense 持有 VIP，代理网关只是 OPNsense PBR 选中的 next-hop。

2. **对 VIP 做全端口 1:1 NAT**  
   推荐只对 DNS、HTTP/SOCKS5 代理等必要服务端口做精确 DNAT。

3. **把 FakeIP DNAT 到代理网关真实 IP**  
   这会破坏 FakeIP 与域名映射，还原域名失败。

4. **PBR 使用 `source LAN net, destination any, protocol any`**  
   容易误导内部、管理、ICMP、VPN、基础设施流量，并可能形成 bypass 环路。

5. **TPROXY 劫持所有 TCP/UDP**  
   必须排除本机服务、DNS、显式代理、管理端口、内部网段和不需要代理的基础设施服务。

6. **混淆 direct 与 bypass**  
   `sing-box direct` 是代理程序接管后的直连出站；kernel bypass 是内核三层转发原始包。两者对应的 OPNsense NAT、anti-spoofing、环路风险不同。

## 9. 与 `proxy_arch.md` 的关系

本文只描述 OPNsense 上的具体配置方法和验证步骤。

如本文与 `proxy_arch.md` 在架构原则上存在差异，以 `proxy_arch.md` 为准。实施前必须先确认：

1. Proxy Gateway VIP 由 OPNsense 持有。
2. VIP 服务访问走精确 DNAT / port-forward。
3. FakeIP 与真实公网目的普通流量走 PBR，且保留原始目标地址。
4. PBR 与 TPROXY 都有完整排除规则。
5. DNS、IPv6、MTU/PMTUD、HA、健康检查、direct/bypass、安全暴露面已有明确策略。
