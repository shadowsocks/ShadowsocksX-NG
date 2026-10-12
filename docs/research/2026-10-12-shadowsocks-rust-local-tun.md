# shadowsocks-rust `local-tun` 与 NG2 接入变更研究

> 研究日期：2026-10-12（Asia/Shanghai）。这是调研时点的能力与候选方案记录，不代表方案已被采纳。
>
> 上游当前 master：`a1bb24282b607eb77f76b8518727fdbde91b96db`（2026-10-11）。产品基线：v1.25.0，`ab388c7466d21f979430e33cc9ef10e22fb05955`。两者分别核对，不能把 master 的修正归入产品二进制。
>
> 本地代码快照：`dc643497029237eacda71b1b533cce1d844c8d05`。研究只读源码与二进制帮助信息，没有创建 TUN、修改路由/DNS 或启动提权代理。

## 结论

**上游已有 macOS TUN 数据面，NG2 支持它的主要工作是系统网络接管与生命周期，而不是多加一个监听端口。** 官方 README 明确列出 macOS，并给出 `--protocol tun` 示例；实际实现使用 `tun` crate 的 L3 设备和用户态 TCP/UDP 转发。[README](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/README.md#L472-L501)、[TunBuilder](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/mod.rs#L64-L140)

三个关键判断：

1. **现有官方 v1.25.0 二进制已经包含 `local-tun`，无需为了 TUN 本身立即重编译。** `full` 包含 `local-tun`；官方 Darwin release workflow 使用 `full`。本机 `--help` 也实际列出 `tun`、TUN 参数和 FD socket 参数。FakeDNS 是另一件事：`local-fake-dns` 在 `full-extra`，本机帮助没有 `fake-dns`。[Cargo features](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/Cargo.toml#L58-L108)、[release workflow](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/.github/workflows/build-release.yml#L143-L178)、[vendor 清单](../../ShadowsocksX-NG2/Vendor/sslocal/manifest.json)
2. **helper 创建设备、把 FD 交给普通用户 sslocal 的方案有源码级阻塞，不能仅凭存在参数就认定可用。** v1.25.0 锁定 `tun 0.8.14`。该依赖的 macOS `raw_fd` 路径不建立 `ctl`/设备名，而 sslocal 开始服务时必读设备 address/netmask；前者会返回 `InvalidConfig`。这是源码推导，尚未进行真实设备实验。[锁定依赖](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/Cargo.lock)、[依赖 raw_fd 路径](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L69-L84)、[依赖 address](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L359-L369)、[sslocal run](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/mod.rs#L154-L183)
3. **必须另建路由、DNS、防回环、退出恢复和网络切换管理。** 上游创建/配置设备不等于把系统默认流量送入它。依赖可以在 address/destination/netmask 全部提供时添加该设备子网的 IPv4 路由，但没有产品需要的默认路由、DNS service 配置、VPN 协调或恢复事务。[依赖配置与子网路由](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L164-L170)、[route 实现](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L242-L274)、[上游 TUN 服务完整实现](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/mod.rs)

## 1. 上游接口与能力边界

### 配置

TUN 是 `locals[]` 中的 `protocol: "tun"`，不是 `local-tunnel`。后者是固定目标的 TCP/UDP tunnel listener。TUN local 不要求 SOCKS 式地址/端口，可以与其他 local 同存；TCP/UDP 取决于 `mode`，不要依赖默认的 `tcp_only`。[协议解析与配置检查](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/config.rs#L1027-L1116)、[TUN local 校验](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/config.rs#L1300-L1360)、[默认 mode](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/mod.rs#L64-L74)

示意配置片段（不是可直接部署的完整 VPN 配置）：

```json
{
  "locals": [{
    "protocol": "tun",
    "mode": "tcp_and_udp",
    "tun_interface_address": "10.255.0.1/24"
  }],
  "outbound_bind_interface": "en0"
}
```

CLI 对应 `--protocol tun`、`--tun-interface-name`、`--tun-interface-address`、`--tun-interface-destination`、Unix 平台的 `--tun-device-fd-from-path`。没有面向 JSON/CLI 的 `tun_device_fd` 整数参数；整数 raw FD 是 Rust 库内 `LocalConfig` 字段。不能把 XPC 传过来的数字当作跨进程有效 FD。[CLI 定义](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/src/service/local.rs#L425-L463)、[配置字段](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/config.rs#L1168-L1185)

macOS 自建设备时名称必须是 `utunN`，可省略让系统分配；README Linux 的 `tun0` 不能照搬到 macOS。`outbound_bind_interface: en0` 只是例子，真实出口可能是 Ethernet、Wi-Fi 或其他 VPN，需要动态判定。[依赖名称处理](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L86-L103)、[macOS outbound socket 绑定](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks/src/net/sys/unix/bsd/macos.rs#L272-L311)

### 数据面

| 能力 | 源码核对后的边界 |
| --- | --- |
| TCP | smoltcp 在本机终止应用侧 TCP，再通过普通 socket/Shadowsocks 连接目标；不是原样承载远端 IP 报文。 |
| UDP / QUIC | UDP datagram 进入现有 UDP association manager；需要 `tcp_and_udp`、远端 Shadowsocks UDP 能力，以及插件/网络实际可用。 |
| ICMP | 交给本地 smoltcp interface，未发送到远端 Shadowsocks；ping 不证明目标服务器可达。v1.25.0 缺少 `auto-icmp-echo-reply` feature，master 已加入，不能保证产品基线回复 Echo。 |
| IPv6 | 解析 IPv6，TCP 用户态栈配置 IPv6 默认路由，UDP 回包支持 IPv6；这不等于 macOS 地址/路由配置已经双栈完成。依赖 macOS 地址/alias setter 仅支持 IPv4。 |
| 其他协议 / LAN discovery | 未识别 IP 协议忽略；broadcast、multicast、unspecified 地址过滤。不能承诺透明承载全部 IP 协议或 mDNS。 |
| MTU / 分片 | TCP stack 从设备读取 MTU，失败回退 1500；没有 TUN MTU JSON/CLI 字段。UDP 与 IPv6 extension/fragment 路径不能凭编译 feature 宣称完整兼容，需覆盖大包、QUIC、PMTU、IPv6 extension headers 实验。 |

来源：[协议分派与过滤](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/mod.rs#L270-L397)、[TCP stack](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/tcp.rs#L258-L301)、[TCP 转发](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/tcp.rs#L573-L613)、[UDP 包构造](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/udp.rs)、[IPv6 packet header 处理](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/ip_packet.rs)、[macOS IPv4 setter](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L372-L389)、[v1.25.0 smoltcp features](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/Cargo.toml#L184-L197)、[master ICMP feature](https://github.com/shadowsocks/shadowsocks-rust/blob/a1bb24282b607eb77f76b8518727fdbde91b96db/crates/shadowsocks-service/Cargo.toml#L185-L200)

### ACL、DNS 与 FakeDNS

TUN 从 IP 报文得到目标 IP，不会自动获得应用最初请求的域名；TCP 仍进入 AutoProxyClientStream，UDP 仍走公共 association，因此现有 IP ACL 路由能力可复用。域名规则完整保真需要额外 DNS 策略；不要把 SOCKS 的 domain-address 语义直接等同 TUN。[TCP 目标构造](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/tcp.rs#L596-L613)、[TCP ACL 决策](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/net/tcp/auto_proxy_stream.rs)、[UDP association](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/net/udp/association.rs)

上游 `local-dns` 在回答查询后缓存 IP→ACL forward 决策，后续 IP 连接可读该缓存。它不是可靠的一对一域名恢复：共享 IP、缓存过期、DNS 被其他 resolver/DoH/DoT 绕过都需要明确产品语义。FakeDNS 能为查询分配 fake IP，再映射回 domain，但须启用 feature、DNS 导流和 fake-address 网络路由；当前官方 `full` 不带该 feature，选用它会触及本仓库禁止随意自编译/换最新版本的 vendor 政策。[DNS cache 写入](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/dns/server.rs)、[cache 使用](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/context.rs#L155-L202)、[FakeDNS 映射](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/context.rs)、[vendor 政策](../../ShadowsocksX-NG2/README.md#外部二进制供应链)

DNS 方案至少要同时决定：系统 resolver 如何进入受控 DNS local、内部解析 Shadowsocks server/plugin hostname 如何保留 bootstrap 出口、IPv4/IPv6 fake 池是否覆盖、停用时恢复谁拥有的 DNS 配置、DoH/DoT 的域名规则降级行为。上游 TUN 服务本身没有 DNS 劫持或系统 DNS 设置接口；捕获 UDP/53 后按目标 IP 转发也不等于接入 `local-dns`。[TUN UDP 分派](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/tun/mod.rs#L347-L381)

## 2. macOS 权限与 FD 交接：最先需要验证的风险

直接创建路径通过 `PF_SYSTEM/SYSPROTO_CONTROL` 连接 `com.apple.net.utun_control`，随后通过 ioctl 配地址、netmask、UP flags；系统网络修改需要特权管理边界。不能把当前普通用户 LaunchAgent 添加 TUN local 就当作完成。这里没有执行提权实测，因此不声称某个 macOS 版本上每一步的具体 errno。[macOS 设备建立](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L106-L170)、[ioctl](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L335-L389)

`tun_device_fd_from_path` 的角色分工很具体：**sslocal 删除旧 socket 文件并监听 UDS，helper 作为客户端连接并发送 FD**；sslocal 阻塞等待收到 FD 才继续创建 local。接收代码没有显式的超时、caller authentication 或收到后的 socket 文件清理，因此产品包装层还须承担路径权限、session 关联、超时和恢复；不要把它当成现成的安全 IPC 协议。[接收实现](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/mod.rs#L466-L521)

更关键的是上述 **raw_fd startup blocker**：依赖构造 raw FD 设备时立即返回，跳过 configure，且不保存 address/name/ctl；即使 helper 已把接口配置好，`device.address()` 仍从缺失的 ctl 读而失败。`TunBuilder.address()` 也不能弥补这条路径。这意味着「root 只开设备 → FD → 官方普通用户 sslocal」必须先修复上游接口或换成另一个数据面集成方案。master 使用同一依赖与初始化路径，不能假定升级 master 已解决。[依赖 raw_fd](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/src/platform/macos/device.rs#L69-L84)、[master run](https://github.com/shadowsocks/shadowsocks-rust/blob/a1bb24282b607eb77f76b8518727fdbde91b96db/crates/shadowsocks-service/src/local/tun/mod.rs#L154-L183)

若直接由提权 sslocal 建设备，则要重新审视 secret/runtime 文件信任、可执行文件签名验证和 SIP003 plugin 权限继承；普通用户可编辑的 runtime/plugin 请求不能自然升级为 root 执行授权。上游 plugin 是 sslocal 启动的子进程。[plugin 启动](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks/src/plugin/ss_plugin.rs)

Network Extension 是另一个候选架构，不能宣称 raw utun 必须使用它。`NEPacketTunnelProvider.packetFlow` 公共 API 是 packet read/write；不能把依赖 README 中 `valueForKeyPath: socket.fileDescriptor` 的技巧当作 Apple 保证的公共 FD API。采用 NE 需要 extension target、entitlement/签名/分发和 public packetFlow 与引擎的适配。Apple TN3120 对 packet tunnel 的用途有约束，并建议 macOS 上按适用情况使用 transparent proxy；因此也不能把 NE 描述为直接包装 `local-tun` 就能完成的方案。[Apple packetFlow](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider/packetflow)、[NE entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)、[Apple TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)、[依赖 README 的 FD 示例](https://github.com/meh/rust-tun/blob/d77c12a7f5536e3f72e668c5b00a4164d5acced2/README.md)

## 3. 对 NG2 的重要变更清单（研究时点快照）

以下是工作规模评估，不是已确认的实施设计。

| 领域 | 已核实的集成边界 | 若支持 TUN 的必要变更 |
| --- | --- | --- |
| 产品模型 | `ProxyMode` 是 rule/global/direct；`ListenerMode` 是本地监听范围；`ProxySettings` 分离 agent/systemProxy 开关。 | 独立表达流量接管方式 system proxy / TUN；规则模式与监听地址继续保留各自含义。确定是否互斥、如何切换、direct 在 TUN 下的行为。 |
| Runtime contract | `SslocalRuntimeDocument` 要求 address/port；校验只接受 SOCKS tcp_and_udp 与最多一个 HTTP tcp_only。 | 引入有类型的 TUN local，不以假端口满足校验；声明设备、出口、DNS 和 session 标识；调整结构变化/重启协议。 |
| 权限 / helper | 现有 helper 只有 system proxy apply/clear；agent 是用户进程。 | 新的受限设备/网络请求协议与授权、caller/session 所有权；避免 generic root command 或 root 启动用户插件；先解 FD blocker。 |
| 防回环 / 出口 | 上游有 `outbound_bind_interface`，macOS 实现 IP_BOUND_IF/IPV6_BOUND_IF。 | 管理 Shadowsocks server、UDP、直连 ACL、插件 socket、内部 DNS bootstrap 的出口；服务器多 IP 与切换时原子更新；Wi-Fi/Ethernet/VPN 切换后重新选择。单独排除服务器 IP 不覆盖全部直连流量。 |
| 系统路由 | 当前只接管系统 proxy 字典。 | 接管目标 IPv4/IPv6 route、LAN/loopback 排除、已有 VPN/多用户策略；配置路由前先验证数据面；失败恢复 session 所拥有的改变。 |
| DNS / 规则 | 当前 ACL 分流依据 SOCKS/HTTP 入站目标，不等于 TUN 域名识别。 | 确定真实 DNS cache 或 FakeDNS 方案；明确泄漏/DoH 与规则降级边界；保存/恢复 DNS 变更，不自动改成另一种规则语义。 |
| Readiness / 状态 | AgentListening 逐 local TCP 连接，ACL acceptance 看 PID socket owner。 | TUN 不能按 local_port 探活；新增设备身份、地址、routes、DNS、出口与端到端代理验证；分别报告 process ready / capture ready / healthy。 |
| 生命周期 | 用户 LaunchAgent 可在 GUI 退出后存活并 KeepAlive 重启；当前结构变更重启、server-only SIGUSR1。 | TUN session 跨 restart、crash、睡眠、网络切换、注销、卸载的恢复；不能仅靠 GUI deinit；DNS/route 的外部修改要按所有权协调。 |
| Vendor / 分发 | 固定官方版本、hash 和签名工具。 | TUN 基础 feature 已存在；若修复 FD 或使用 FakeDNS，另行决定上游升级/自建供应链与签名、版本锁定，不能静默替换。 |

本地依据：[settings](../../ShadowsocksX-NG2/Domain/Settings/ProxySettings.swift)、[mode](../../ShadowsocksX-NG2/Domain/Rules/ProxyMode.swift)、[runtime document](../../ShadowsocksX-NG2/Domain/Runtime/SslocalRuntimeDocument.swift)、[runtime plan](../../ShadowsocksX-NG2/Domain/Runtime/ProxyRuntimePlan.swift)、[wrapper](../../ShadowsocksX-NG2/Agent/main.swift)、[readiness](../../ShadowsocksX-NG2/Agent/AgentListening.swift)、[helper contract](../../ShadowsocksX-NG2/Domain/SystemProxy/SystemProxyHelperContract.swift)、[helper caller validation](../../ShadowsocksX-NG2/Domain/SystemProxy/SystemProxyHelperListenerDelegate.swift)、[LaunchAgent](../../ShadowsocksX-NG2/LaunchAgent/com.qiuyuzhou.ShadowsocksX-NG2.agent.plist)、[vendor](../../ShadowsocksX-NG2/README.md#外部二进制供应链)。防回环推论依据：[TCP auto proxy](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks-service/src/local/net/tcp/auto_proxy_stream.rs)、[macOS socket 绑定](https://github.com/shadowsocks/shadowsocks-rust/blob/ab388c7466d21f979430e33cc9ef10e22fb05955/crates/shadowsocks/src/net/sys/unix/bsd/macos.rs)。

## 4. 推荐的下一步与验收门槛

**先做可恢复、单机、有明确边界的真实系统原型，再选择产品架构。** 第一阶段只回答直接创建设备能否工作、FD 交接阻塞如何解决、双栈 TCP/UDP 出口是否避开回环；暂不把 UI/完整域名分流作为原型目标。候选包括：上游修复后采用 helper+FD 的最小权限架构；受控提权数据面但禁止用户插件进入 root；按 Apple 适用范围重新评估 NE/transparent proxy 架构。后两种不能绕开完整授权与生命周期设计。

原型验收至少包含：

- 使用固定 binary/source，分别测直接 create 和 helper FD attach；能明确输出 utun 身份、权限失败与 startup failure。
- IPv4/IPv6 TCP、UDP DNS、QUIC、大包/MTU；ICMP 只作为局部栈测试，不当作远端可达证明。
- rule/global/direct、域名规则与共享 IP、bootstrap DNS、服务器域名多地址、插件出口；未支持项显式失败或降级。
- 路由生效前验证出口；Wi-Fi/Ethernet/VPN 切换、睡眠唤醒、代理 child crash、agent restart、GUI 退出、注销。
- 每次失败与停用后检查 routes/DNS；保留其他进程/用户在期间做的系统网络改变，不用无条件全局清除。
- 真正生成流量并核对出口、路由和 DNS，区分静态/source 证据、process readiness 与系统行为。

## 5. 本次证据与未验证范围

- 已阅读官方 shadowsocks-rust 当前 master、v1.25.0 tag 源码和 release workflow；依赖从官方 crates.io 下载 `tun 0.8.14`，其 `.cargo_vcs_info.json` 固定到 `d77c12a7f5536e3f72e668c5b00a4164d5acced2`，用于避免把依赖 master 当作锁定版本。
- 已执行仓库 vendor 的 `--version` / `--help`：`shadowsocks 1.25.0`，`tun` 和 TUN/FD/outbound-bind 参数存在；`fake-dns` 不在协议选项中。
- 未编译、未运行 TUN、未修改系统网络、未测试授权/回环/恢复/性能。FD startup blocker 是精确依赖链的源码结论，需要有界实测复现后再决定修复路径。
- 上游说明“支持 macOS”证明实现存在，不能替代当前 macOS 上的产品级可靠性、VPN 协调与退出恢复验证。
