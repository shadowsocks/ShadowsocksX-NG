# sslocal ACL 与当前 PAC 方案对比研究

> 研究日期：2026-09-24  
> 上游基线：`shadowsocks-rust` v1.25.0，commit `ab388c7466d21f979430e33cc9ef10e22fb05955`。  
> 证据范围：上游仓库源码、上游 README/config schema、上游 release 与 issue；未使用博客或其他二手材料。本文只写研究结论，不修改 NG2 源码、配置或产品文档。

## 结论摘要

1. `sslocal` ACL 是本地入站代理收到目标地址后做的“直连 / 通过 Shadowsocks server”选择器。它支持默认黑名单/白名单、域名精确匹配、子域匹配、正则、IP 与 CIDR；它不是 macOS 系统代理配置器，也不是一个能直接输出 PAC 的规则引擎。
2. ACL 不支持本地客户端侧的 `BLOCK` 动作。`[outbound_block_*]` 属于 `ssserver` 的远端出站阻断语义，不能当作 sslocal 的本地阻断规则。
3. ACL 在启动/配置构造时读入并编译到内存。v1.25.0 的 `SIGUSR1` 重载路径只把新配置中的 `server` 列表交给 balancer，不替换已运行 local context 中的 ACL；修改 ACL 文件后需要重启 sslocal 才能可靠生效。
4. 对本仓库而言，“macOS 全局 SOCKS + sslocal ACL”技术上可行，但不是当前 PAC 的等价替换。它会把决策点从系统 PAC 的 `FindProxyForURL` 移到 sslocal 收到的目标地址；URL 路径、端口、HTTP 方法、进程和未使用 SOCKS 的应用不在同一个能力边界内。
5. 推荐把它作为一种新的、明确命名的“ACL 全局 SOCKS”运行模式进行验证；不要直接把现有 PAC 模式的产品语义改名为 ACL。至少应先验证域名/IP/DNS、UDP、多个 local、ACL 变更期间的重启收敛，以及真实 macOS SystemConfiguration 和应用兼容性。

## 1. ACL 文件格式与规则语义

### 1.1 上游定义的 section

上游 README 和 `crates/shadowsocks-service/src/acl/mod.rs` 都把 local 与 remote 的 section 分开。对 `sslocal` 有效的是：

| Section | 含义 |
| --- | --- |
| `[proxy_all]` | `BlackList`：未命中的目标默认走 Shadowsocks proxy；默认模式也是这个模式 |
| `[bypass_all]` | `WhiteList`：未命中的目标默认直连 |
| `[bypass_list]` | 命中后直连 |
| `[proxy_list]` | 命中后走 Shadowsocks proxy |

README 把 `[reject_all]`、`[accept_all]`、`[black_list]`、`[white_list]` 主要描述为 `ssserver` 客户端访问控制；但 v1.25.0 parser 同时把 `[black_list]` 当作 local 的 `bypass_list` 别名、把 `[white_list]` 当作 local 的 `proxy_list` 别名。`[outbound_block_all]`、`[outbound_allow_all]`、`[outbound_block_list]`、`[outbound_allow_list]` 才是明确的 `ssserver` 远端出站控制。NG2 生成 local ACL 时应只生成 `[proxy_all]`/`[bypass_all]` 与 `[bypass_list]`/`[proxy_list]`，避免复用有双重语义的 section 名。

来源：

- 上游 README 的 ACL 章节：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L1112-L1132>
- 上游 ACL 源码的 section、mode 和 rule 注释：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L286-L337>

### 1.2 单条规则

解析顺序和语义如下：

| 写法 | 语义 |
| --- | --- |
| `10.0.0.0/8`、`127.0.0.1`、`::1` | IP/CIDR 规则 |
| `|example.com` | 精确域名匹配 |
| `||example.com` | `example.com` 及其子域匹配 |
| `(^|\\.)example\\.com$` | 正则域名匹配 |
| `# comment` | 注释；源码只把行首就是 `#` 的行当作注释 |

规则行必须是 ASCII；非 ASCII 行会记录 warning 后跳过。以 `|` 或 `||` 开头的规则先按精确/域名树处理；其他非 section 行先尝试 CIDR/IP，再作为正则保存。因此配置生成器不能把任意 Adblock 语法原样当作 ACL 语法。

来源：

- 规则形式的上游注释：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L328-L337>
- 读取、ASCII 过滤、`||`/`|`、IP/CIDR 与正则分流：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L351-L465>

### 1.3 命中优先级与 DNS

对域名目标，`check_target_bypassed` 先检查域名规则：`proxy_list` 命中返回 proxy，`bypass_list` 命中返回直连。未命中且 ACL 中存在 IP 规则时，sslocal 会调用其 `Context` 的 DNS resolver，把解析到的 IP 再与对应 IP 规则比较；解析失败或没有 IP 命中时回到默认模式。

对已经是 IP 的目标，不需要 DNS。源码中 IP 检查先看 `bypass_list`，再看 `proxy_list`，最后使用默认模式；因此“同一 IP 同时出现在两边”不是应该依赖的可移植配置，生成器应在生成前拒绝冲突。

这意味着 ACL 的 DNS 行为不是“所有 DNS 都通过远端 Shadowsocks server”：它是为了决定某个目标是否 bypass 而可能进行本地 resolver 查询。另有独立的 `local-dns` 入站协议，它才是按照 ACL 在 local DNS 与 remote DNS 之间选择的 DNS relay。

来源：

- host/IP 命中与默认模式：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L475-L548>
- 域名目标的 DNS fallback 与直连/代理结果：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L555-L589>
- `local-dns` 的官方说明：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L41-L55>

### 1.4 “直连 / proxy”在 sslocal 中如何落地

TCP 路径调用 ACL 后，命中 bypass 就直接连接目标，未 bypass 才经 configured Shadowsocks server；UDP association 也在发送数据时调用同一个 `check_target_bypassed`。ACL 的结果不是返回给 macOS 的 `DIRECT`/`SOCKS` 字符串，而是由 sslocal 自己选择 outbound socket 路径。

来源：

- TCP auto-proxy：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/net/tcp/auto_proxy_stream.rs#L145-L161>
- UDP association：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/net/udp/association.rs#L515-L522>

## 2. sslocal 的加载、应用、重载与失败行为

### 2.1 配置入口和作用域

v1.25.0 有三种相关入口：

- CLI `--acl PATH`：加载一个全局 ACL。
- 配置顶层 `acl`：同样形成全局 local context 的 ACL。
- `locals[]` 内的 `acl`：为单个 SOCKS/HTTP/DNS 等 local 实例指定 ACL；它会覆盖从全局 context clone 来的 ACL。

上游 `SSConfig` 与 `SSLocalExtConfig` 都声明了 `acl: Option<String>`；`locals[]` 例子也明确展示了 instance-specific ACL。`ServiceContext` 内保存的是 `Option<Arc<AccessControl>>`，local server 创建时把解析好的 ACL 放进 context；因此运行期使用的是已加载的对象，不是每次请求重新读文件。

来源：

- 顶层与 `locals[]` schema：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L400-L428>、<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L419-L525>
- 官方多 local 配置示例：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L620-L705>
- ACL 加载失败被转成配置错误：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2078-L2096>
- context 保存 ACL 以及 local-specific override：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/context.rs#L22-L39>、<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/mod.rs#L163-L180>、<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/mod.rs#L272-L285>

### 2.2 初始加载失败行为

可以确认的失败行为：

- ACL 文件打不开、权限不足或路径不存在：`File::open` 返回错误，配置加载失败。
- 正则无法编译：最终 `into_rules()?` 返回错误，配置加载失败。
- 单条规则含非 ASCII：不是全局失败；记录 warning 并跳过该行。
- 域名用于 IP 规则 fallback 时 DNS 解析失败：不把请求判为错误，而是回到该 ACL 的默认 proxy/bypass 策略。
- 未知 section 不会被当作一个严格 schema 错误；解析器的默认分支会把它继续当作 IP/域名/正则规则处理。这是配置生成器应自行校验的风险，而不是可以依赖的容错协议。

`--acl` CLI 入口同样直接调用 `AccessControl::load_from_file`，失败会变成 `LoadAclFailure`。因此 NG2 若生成 ACL，应先原子写完并自检，再把新路径交给 sslocal；不能把一个半写入或不可读文件交给正在重启的 child。

来源：

- ACL parser 的错误/警告路径：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L351-L465>
- CLI `--acl` 的失败映射：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L888-L899>

### 2.3 是否支持 ACL 热加载

结论：**v1.25.0 的 sslocal 不提供 ACL 文件热加载。**

上游的 reload task 只有 `config_path` 和 `balancer`。收到 Unix `SIGUSR1` 后，它重新读取配置文件，但只把 `source_config.server` 交给 `balancer.reset_servers(...)`；已运行的 `Server`/local context 不会因为 ACL 文件改变而重建。配置文件本身被重新解析时，如果新 ACL 已损坏，reload task 会记录加载失败并保留旧运行实例；如果新 ACL 有效，也只刷新服务器列表，旧 ACL 仍继续用于现有 local context。

这与 NG2 当前 wrapper 的协议正好形成风险：`ShadowsocksX-NG2/Agent/main.swift:13-15` 把“仅 servers 变化”转成向 sslocal 转发 `SIGUSR1`，`main.swift:164-192` 也只在监听结构变化时重启。引入 ACL 后，ACL 内容/path/hash 必须成为 restart fingerprint；不能沿用“只 forward SIGUSR1”的分支。

来源：

- sslocal 建立一次 `Server`，再单独启动 reload task：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1001-L1018>
- reload task 只 reset servers：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1068-L1111>
- `SIGUSR1` 监听：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1117-L1129>

## 3. ACL 与 PAC 的能力边界

这里的 PAC 对比以本仓库当前 NG2 实现为准，而不是把一个未实现的 PAC 规则子集算进产品能力。

系统边界也不同：Apple 的 CFNetwork 文档把 PAC URL/JavaScript 自动配置和 SOCKS 作为不同的 proxy 类型；自动配置脚本由系统执行来决定某个 URL 使用什么 proxy，而 SOCKS 是一个固定的 proxy endpoint。Apple 的 `CFNetworkCopyProxiesForURL` 也明确以 URL 查询代理列表。因此，ACL 接入的系统形状应是“系统 SOCKS endpoint + sslocal 内部路由”，不是把 ACL 文件交给 macOS 当 PAC。

当前 PAC 生成的返回链还包含 `SOCKS5`、`SOCKS` 和 `DIRECT`：当 PAC 客户端无法使用前两个代理时，客户端可能继续尝试 DIRECT。ACL 则是在 sslocal 内部选定 bypass 或 proxy outbound；它不会从 ACL 规则中自动产生同一个按请求的 PAC fallback。因此“可达性/失败时是否允许直连”必须作为迁移决策单独定义。

来源：<https://developer.apple.com/documentation/cfnetwork/proxy-types>、<https://developer.apple.com/documentation/cfnetwork/global-proxy-settings-constants>。

| 维度 | 当前 NG2 PAC | sslocal ACL |
| --- | --- | --- |
| macOS 系统入口 | PAC 模式把 PAC URL 交给系统代理；`ProxyMode.pac` 生成 PAC target | ACL 不写 macOS SystemConfiguration；需要把系统代理设为 `127.0.0.1:<SOCKS>`，即 NG2 已有的 global SOCKS 投影 |
| 决策位置 | 应用请求 PAC 时按 URL 调用 `FindProxyForURL` | 请求进入 sslocal SOCKS/HTTP 后，按 target address 决定 outbound |
| 当前默认策略 | NG2 的用户规则实现只提取 `@@` 例外为 DIRECT，其余规则维持 SOCKS 优先 | `[proxy_all]` 默认 proxy，或 `[bypass_all]` 默认直连 |
| 域名 | 当前最小实现只保留可规范化的例外 host/suffix | 精确 `|`、子域 `||`、正则；域名未命中时还可能 DNS 后检查 IP |
| IP/CIDR | 当前 PAC 用户规则适配器没有把普通规则编译成 IP ACL | 原生支持 IPv4/IPv6 地址与 CIDR |
| 直连 | PAC 返回 DIRECT，应用自己直连；当前链还包含 proxy 失败后的 DIRECT fallback | sslocal 自己建立直连 outbound socket；没有同一个 PAC-style fallback |
| 代理 | PAC 返回 SOCKS endpoint | sslocal 选择 configured Shadowsocks server/balancer |
| 阻断 | 当前 NG2 PAC 生成器没有 BLOCK 分支 | local ACL 没有 block 动作； remote `[outbound_block_*]` 是 ssserver 语义 |
| URL 路径/query/HTTP 方法 | PAC 输入是 URL，理论上可按这些信息编写 JS；当前 NG2 规则适配器没有实现这些规则 | ACL 只处理 target host/IP，不能表达 URL path、query、HTTP method |
| 端口 | 当前 PAC 生成器没有端口策略 | ACL parser 的规则类型没有端口字段；不要把 `host:port` 当作已支持的 ACL 语法 |
| 进程/应用 | PAC 也不会天然知道进程；由应用是否遵守 PAC 决定 | ACL 也没有进程维度；未使用 SOCKS 的应用不会经过它 |
| UDP | PAC 本身是应用代理选择；NG2 当前 PAC/系统代理验证重点是 TCP | sslocal SOCKS UDP 在 `tcp_and_udp` 时也调用 ACL，但需真实测试 DNS/UDP 应用行为 |
| DNS | PAC 与应用/系统 resolver 的交互由客户端实现决定 | ACL 为 IP 规则判断可能调用 sslocal resolver；`local-dns` 是另外的 DNS relay 功能 |

本仓库证据：`PACRuleSet` 明确说只有 `@@` 例外变成 DIRECT，`ProxyMode` 只有 `.pac` 和 `.global`，其中 global 目标是本地 SOCKS；runtime document 当前也只把 PAC 放在 wrapper 自有的 `x_shadowsocksx_ng_pac` 区域。见 `ShadowsocksX-NG2/Domain/PACUserRules.swift:3-37`、`ShadowsocksX-NG2/Domain/ProxyMode.swift:3-80`、`ShadowsocksX-NG2/Domain/SslocalRuntimeDocument.swift:37-78`。

当前 `gfwListURL` 已被设置模型持久化和校验，但 active source 中没有对应的下载/编译调用；当前运行时实际消费的是 `pacUserRules` 的最小 `@@` 例外适配。迁移研究不能把 GFW List 当成现成的 PAC 或 ACL 规则输入。见 [`ProxySettings.swift`](../../ShadowsocksX-NG2/Domain/ProxySettings.swift#L6-L19)、[`PACUserRules.swift`](../../ShadowsocksX-NG2/Domain/PACUserRules.swift#L3-L17)、[`SslocalRuntimeDocument.swift`](../../ShadowsocksX-NG2/Domain/SslocalRuntimeDocument.swift#L112-L127)。

还要处理 SystemConfiguration 的 `ExceptionsList`：当前 controller 把 `settings.proxyExceptionList` 传给 PAC 和 global 两种模式；切到 global SOCKS 后，这些目标会在 macOS 层直接绕过 sslocal，ACL 不会看到它们。迁移时应明确例外项由系统代理还是 ACL 作为唯一事实来源，不要让两套规则悄悄产生不同结果。见 [`ProxyRuntimeController.swift`](../../ShadowsocksX-NG2/App/ProxyRuntimeController.swift#L771-L780)、[`ProxyMode.swift`](../../ShadowsocksX-NG2/Domain/ProxyMode.swift#L63-L80)、[`SystemProxyPropertyList.swift`](../../ShadowsocksX-NG2/Domain/SystemProxyPropertyList.swift#L18-L41)。

上游 local ACL 的直连/代理实现见：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/net/tcp/auto_proxy_stream.rs#L155-L161>。远端 outbound block 的区别见：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/acl/mod.rs#L607-L625>。

## 4. 版本、协议与 macOS 集成接口

### 4.1 版本基线与 feature

本仓库当前 vendor manifest 已固定：

`ShadowsocksX-NG2/Vendor/sslocal/manifest.json:2-11`：官方 `shadowsocks-rust` v1.25.0、`aarch64-apple-darwin`、官方 release asset、SHA-256、bundle 内 `Helpers/sslocal`。

上游 v1.25.0 的 Cargo facts：

- package version `1.25.0`，Rust MSRV `1.91`；`sslocal` binary 需要 `local` feature。
- `local-http` 才提供 HTTP local；`local-dns` 才提供 DNS relay；`local-tun` 是 TUN 相关功能。
- 默认 `full` feature 包含 local、local-http、local-dns、local-tun 等；如果未来改为自编译精简 binary，必须显式保留实际使用的 feature。
- ACL 只影响本地路由，不改变 Shadowsocks wire protocol；服务器端仍必须支持配置的 method、密码与插件组合。

来源：<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/Cargo.toml#L1-L22>、<https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/Cargo.toml#L57-L97>、<https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.25.0>。

### 4.2 建议的配置形状

如果使用全局 ACL，最小形状可以是：

```json
{
  "acl": "/absolute/path/to/sslocal.acl",
  "servers": [
    {
      "server": "example.invalid",
      "server_port": 8388,
      "password": "...",
      "method": "aes-256-gcm"
    }
  ],
  "locals": [
    {
      "protocol": "socks",
      "local_address": "127.0.0.1",
      "local_port": 11086,
      "mode": "tcp_and_udp"
    }
  ]
}
```

若 SOCKS 与 HTTP local 的规则需要独立，则应给每个 `locals[]` 项设置同一个或不同的 `acl`；`locals[].acl` 会覆盖 global ACL。NG2 当前 `SslocalLocalDocument` 没有 `acl` 字段，因此接入前必须扩展 runtime contract 和生成/校验边界；这不是现有 PAC 扩展字段可以隐式解决的事情。

### 4.3 进程接口与重启策略

上游没有用于变更 ACL 的 JSON-RPC 或 control socket。对 NG2 可用的接口仍是：

- wrapper 以绝对路径启动 `sslocal -c <config>`；
- SIGTERM 做 graceful stop；
- SIGUSR1 仅用于上游实现的 server-list refresh；
- ACL 变更应由 wrapper 完整重启 sslocal，再等待 SOCKS/HTTP listener 健康后让 macOS system proxy 指向新实例。

当前 NG2 已有可复用的生命周期边界：`ShadowsocksX-NG2/Agent/main.swift:3-17` 说明 wrapper 管理 PAC endpoint 与 sslocal 生命周期，`main.swift:221-249` 负责停止 child；`ShadowsocksX-NG2/Tests/RealSslocalSmokeTests.swift:5-8,143-160` 已验证 bundled v1.25.0 的 local listener 与 SOCKS5 handshake。需要补充的是 ACL 真实 e2e，而不是把现有 handshake smoke 当成 ACL 证据。

## 5. 对 NG2 替代当前 PAC 的可行性判断

### 5.1 可行的目标定义

可行目标是：

> 将 macOS 系统代理设置为 NG2 的 local SOCKS；对所有确实把连接交给该 SOCKS 的 TCP/UDP 流量，由 sslocal ACL 决定直连或通过 Shadowsocks server。

这与当前 global 投影相符：`ShadowsocksX-NG2/Domain/ProxyMode.swift:63-80` 把 global 映射到 `127.0.0.1:<socksPort>`。因此实现上可以保留 wrapper/LaunchAgent/health supervision，新增 ACL 文件生成、runtime schema 字段、ACL 变化检测和 restart classification。

这里的“按配置”若是指“按域名规则选择直连或当前激活配置的 Shadowsocks server”，ACL 可以覆盖；若是指“不同规则选择 `servers[]` 中不同的服务器/目录配置”，ACL 不能覆盖。上游 ACL 只决定 bypass 或进入当前 balancer，NG2 当前则把活动目标展开成一个 `servers[]` 列表；规则到服务器的映射需要多实例、额外 dispatcher，或继续使用 PAC/其他路由层。见 [`ActivationStateMachine.swift`](../../ShadowsocksX-NG2/Domain/ActivationStateMachine.swift#L129-L138)、上游 [`AutoProxyClientStream`](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/net/tcp/auto_proxy_stream.rs#L130-L161)。

### 5.2 不可直接承诺的目标

以下说法不能从 v1.25.0 ACL 得出，也不应在 UI/文档中暗示：

- “完全等价于 PAC”：不等价；决策输入从 URL 变成 target address。
- “所有应用都按配置代理”：不成立；应用必须使用系统 SOCKS，或显式连接 NG2 的 local。
- “ACL 可以阻断本机请求”：local ACL 没有这个动作；需要应用侧拒绝、网络过滤器或远端 `ssserver` outbound ACL。
- “修改规则立即生效”：不成立；v1.25.0 需要重启 sslocal 才能可靠换掉 context 中的 ACL。
- “把现有 GFW/Adblock 规则直接写入 ACL”：不安全；当前 NG2 只实现了极小的 `@@` 例外抽取，其他语法必须经过明确转换和校验。
- “按规则选择不同的 Shadowsocks server”：不成立；ACL 只选择 bypass 或当前 `servers[]` balancer，不提供规则到 server 的映射。

### 5.3 主要风险

1. **规则语义漂移**：现有 PAC 规则和 ACL 的 exact/suffix/regex/默认模式不同；尤其是 `@@` 例外、普通 Adblock pattern、IP 规则、尾点/IDNA、冲突规则。
2. **DNS 泄漏与决策不一致**：ACL 为 IP 规则可能进行 resolver 查询；应用把 hostname 交给 SOCKS、应用先自行解析、`local-dns` relay 和 fake DNS 又是不同路径。
3. **重启窗口**：ACL 更新期间若先切换 system proxy 或删除旧 ACL，可能出现 SOCKS 不可用、旧规则继续生效或 launchd 反复拉起。
4. **UDP/应用覆盖率**：`tcp_and_udp` 的源码路径存在，但系统 SOCKS、应用 UDP 使用方式和 DNS 行为仍需在真实 macOS 上验证。
5. **安全默认值**：`[proxy_all]` 与 `[bypass_all]` 的选错会产生全量直连或全量代理；ACL 文件路径和生成过程还涉及权限、原子替换及崩溃恢复。
6. **多 local 一致性**：如果 SOCKS 与 HTTP local 使用不同 ACL，用户看到的“按配置代理”会随入口而改变；如果使用全局 ACL，则应测试 local-specific override 不会被意外写入。

### 5.4 必须先验证的未知点

建议把下列项目列为实现前的验收矩阵：

1. `proxy_all` + `bypass_list`、`bypass_all` + `proxy_list` 的域名 exact/suffix/regex 命中和同名冲突。
2. IPv4/IPv6/CIDR、hostname 解析到多个 A/AAAA、解析失败、尾点域名与 IDNA。
3. hostname 目标与已解析 IP 目标是否得到产品预期的相同结果；分别记录 resolver 来源。
4. SOCKS TCP、SOCKS UDP、HTTP local 三条入口是否都使用预期 ACL；`local-dns` 是否按预期选择 local/remote DNS。
5. 修改 ACL 后不重启只发 SIGUSR1 的结果，确认旧 ACL 保持；再做 wrapper 原子替换 + 完整重启，确认新 ACL 生效且 system proxy 无错误窗口。
6. 真实 macOS SystemConfiguration 写入与恢复，以及 Safari、URLSession、浏览器、命令行、忽略系统代理的应用矩阵。现有 fake/unit 代理测试不能替代这项证据。
7. 仍使用官方 v1.25.0 arm64 binary 时的签名、bundle、Gatekeeper 和 release packaging；若升级上游版本，应重新核对 ACL 源码、配置 schema、reload 行为和 release notes。

## 6. 建议决策

短期不建议删除当前 PAC 方案。建议先做一个隔离的 ACL 运行时实验：

1. 仅在现有 `.global` system SOCKS 投影下接入生成的 ACL；
2. 将 ACL 路径、内容 hash、生成器版本写入 runtime snapshot，ACL 变化触发完整 sslocal restart；
3. 先支持一个受控的 `proxy_all`/`bypass_list` 子集，拒绝未知 Adblock 语法、非 ASCII、冲突 IP/域名规则；
4. 通过真实 SOCKS/HTTP/UDP/DNS 和 macOS 应用矩阵后，再决定是否把它作为产品级“按配置代理”模式；
5. PAC 与 ACL 若都保留，应明确其语义：PAC 适合需要系统 PAC 选择的场景，ACL 全局 SOCKS 适合把目标路由集中到 sslocal 的场景。

在当前证据边界内，最终判断是：**可实现，但应作为“ACL 驱动的全局 SOCKS 路由”重新定义和验证，不能作为当前 PAC 的无损替换。**
