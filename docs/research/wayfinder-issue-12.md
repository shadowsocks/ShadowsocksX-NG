# Wayfinder issue 12：PAC 本地 HTTP 服务实现方案（替代 GCDWebServer）

- 票据：[研究：PAC 本地 HTTP 服务实现方案（替代 GCDWebServer）](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/12)
- 父地图：[Wayfinder: ShadowsocksX-NG 2.0 现代化重实现](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/1)
- 研究日期：2026-09-20
- 适用范围：macOS 15+、仅 arm64、ShadowsocksX-NG 2.0；该服务只负责向系统客户端交付版本化 PAC 文件，HTTP 代理入站由外部 `sslocal` 直接提供，不经过此服务。
- 监听范围约束（2026-09-20 确认）：监听范围是用户可配置的两态切换——回环（默认）或主机地址（如 `0.0.0.0` 通配绑定）。用户会把 PAC URL 复制给局域网其他机器使用，因此选定方案必须支持绑定到非回环地址。这与 Legacy 的 `PacServer.BindToLocalhost` 开关（ProxyConfHelper.m:246）相对应，是对 #11 “只监听 127.0.0.1” 默认值的显式放宽。
- 证据规则：依赖候选以 GitHub API/仓库内容与 Swift Package Index 抓取结果为准（均标注查询日期）；API/系统能力以本机 SDK 为证据；未实测的行为不写成事实。

## 决策摘要

1. **推荐 2.0 用 Network.framework 自研一个最小本地 HTTP/1.1 服务来交付 PAC。** 该服务的全部职责是：绑定监听地址（默认 127.0.0.1，用户可切换为主机地址通配绑定）、响应一个版本化静态路径的 GET、返回固定 MIME 与 no-store。当前 SDK 已直接提供监听与绑定原语（`NWListener`、`NWParameters.requiredLocalEndpoint`，可绑定任意地址包括 `0.0.0.0` 与指定接口），而它并不提供任何公共 HTTP 服务器栈（见第 2 节 SDK 证据），缺的只是一层可以严格限定的最小 HTTP/1.1 解析。为这一个端点引入完整第三方服务器框架（或已归档的 GCDWebServer 系）会放大依赖面、线程模型与供应链风险，超出收益。
2. **明确排除 GCDWebServer 本体：上游已归档、无 SwiftPM、只能经 CocoaPods 引入。** swisspol/GCDWebServer 仓库 `archived: true`，最后推送 2022-10-05，最后 tag 3.5.4，仓库内没有 `Package.swift`；Legacy 恰是通过 CocoaPods `pod "GCDWebServer", "~> 3.0"`（锁定 3.5.4）引入它的。沿用本体等于把 2.0 唯一遗留的 CocoaPods 时代依赖重新带回，并与 #6 的 SwiftPM 决策直接冲突。
3. **明确排除 GCDWebServer 的 SwiftPM fork。** 提供 `Package.swift` 的活跃 fork（yene、readium、CaperWhite）都是单一维护者、低 star 的归档项目衍生分支，修复面集中在本仓库无关的平台杂项上，Swift 6 严格并发兼容未经验证。为单一静态端点把供应链押在一个 fork 上，是所有候选中风险/收益比最差的选择。
4. **Swifter 排除：维护实质停滞。** 最后一个 release 1.5.0 发布于 2020-09-26，仓库最后推送 2024-03-17；基于 POSIX socket 的线程模型也不利于嵌入 per-user runtime。
5. **Telegraph 是唯一保留的第三方备选，但不是默认。** MIT、纯 Swift、SwiftPM 原生、无外部依赖，功能面正好覆盖“嵌入式 TCP/HTTP 服务器”；但其最后发布 0.40.0 停在 2024-04-01，此后约两年半无发布。若实现阶段证明自研解析不可控，Telegraph 是回退首选。
6. **swift-nio 是指定的升级路径，不是起点。** Apple 维护、Apache-2.0、活跃（最后推送 2026-09-17，最新 release 2.103.0）、SwiftPM 原生；但为“一个 GET 端点”引入整个 NIO 依赖树和 channel/pipeline 并发模型过度供给。若未来 PAC 服务需要真实 HTTP 语义（按请求鉴权、动态内容、可观测性），按本报告升级到 swift-nio，而不是中途换其他框架。
7. **本票据不决定 PAC 服务的宿主进程归属与默认端口。** PAC 服务与 per-user LaunchAgent（#3）、GUI 的生命周期关系，以及默认端口与端口冲突策略，留给后续规格/实现票据；本票据只约束实现形态（见第 5 节）。

## 1. Legacy 里 GCDWebServer 的真实用途

Legacy 对 GCDWebServer 的使用确实只有一件事：在本地回环上交付 `/proxy.pac`。

- 依赖来自 CocoaPods：`pod "GCDWebServer", "~> 3.0"`，Podfile.lock 锁定 3.5.4（GCDWebServer/Core）。[Podfile](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/Podfile#L11) [Podfile.lock](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/Podfile.lock#L4-L6)
- 本地 PAC URL 固定拼为 `http://localhost:<port>/proxy.pac`，端口来自 `PacServer.ListenPort`，short 窄化。[ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L206-L215)
- 启动服务时把 PAC 文件一次性读入内存 `originalPACData`，只注册 `GET /proxy.pac` 一个 handler，返回 `application/x-ns-proxy-autoconfig`；再以 `GCDWebServerOption_BindToLocalhost` + `GCDWebServerOption_Port` 启动——`PacServer.BindToLocalhost` 是 Legacy 已有的回环/主机两态开关，即“把 PAC URL 给局域网其他机器用”的场景在 Legacy 就被支持。[ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L223-L253)
- 停止服务只是 `stop`，无错误传播；启动失败的 `error:nil` 也被丢弃——这正是 #11 已判定要重写的生命周期与失败语义。[ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L255-L260)

结论：2.0 对这个组件的需求与 Legacy 完全同构（loopback + 单端点 + 固定 MIME），但生命周期、失败传播和版本化缓存（#11 §4.2）要求整体重写。GCDWebServer 在 Legacy 中的使用没有隐藏功能，替换它没有迁移负债。

## 2. 2.0 对该 HTTP 服务的真实需求面

把 #11 的结论落成选型需求，这个服务的完整契约是：

- 绑定两态：默认绑定 127.0.0.1；用户显式切换“主机地址”时绑定通配地址（`0.0.0.0`）或指定接口地址。方案必须支持任意绑定地址；非回环暴露是显式 opt-in，不是默认态。
- 只响应一个路由族 `GET /v1/pac/<generation>`；其余路径 404、非 GET 405。
- 响应体是不可变快照的完整 JavaScript；`Content-Type: application/x-ns-proxy-autoconfig`；显式 `no-store`；generation 变化是缓存失效主机制。
- 无 TLS、无路由、无动态内容、无上传、无 Cookie/session；请求频率极低（系统客户端在 PAC URL 变化或重启后拉取）。
- 启动失败/端口冲突/健康检查失败必须阻止把 URL 写入系统代理（#11 §4.2）；服务属于 per-user runtime 生命周期，可显式启停。
- 客户端与暴露面：回环态面向 macOS 系统代理栈（CFNetwork/Safari/URLSession），暴露对象限于本机同用户进程；主机地址态面向局域网客户端，暴露对象扩大到同一网段的任意主机。PAC 内容本身只是路由规则与本地代理地址，不含凭据（#10 的敏感信息边界不受影响），但非回环态下请求解析的健壮性约束（限长、限速、畸形输入断开）从“防御同用户进程”升级为“防御局域网可达的端口”。
- 与 #11 §4.2 的差异说明：#11 把“只监听 127.0.0.1”写成默认推荐，其顾虑是“不要把可配置的 localhost 解析结果或用户输入地址作为绑定地址”。两态切换恰好消除自由文本绑定地址：用户只能在“回环”与“主机地址”之间选择，2.0 不提供任意地址输入框。该差异应在地图 #1 的 PAC 决策行上可见。

由此，选型衡量的不是“谁功能强”，而是“谁在只做这一件事时依赖面最小、生命周期最可控”。

## 3. 候选方案调研

以下仓库状态均为 2026-09-20 通过 GitHub API 查询的结果；Swift Package Index（SPI）为同日抓取的页面信息。

### 3.1 GCDWebServer 本体（swisspol/GCDWebServer）

| 维度 | 事实 |
| --- | --- |
| 维护状态 | `archived: true`；最后推送 2022-10-05；最后 tag 3.5.4；SPM 请求 issue [#515](https://github.com/swisspol/GCDWebServer/issues/515) 自 2020 年开放未实现 |
| SwiftPM | 无 `Package.swift`（contents API 404）；只能 CocoaPods/Carthage |
| 许可证 | LICENSE 为 BSD-3 风格（"Copyright (c) 2012-2014, Pierre-Olivier Latour"），GitHub 归类 NOASSERTION |
| 绑定能力 | `GCDWebServerOption_BindToLocalhost` 两态开关（回环/通配），满足两态监听需求——Legacy 正是用它实现的 |
| 场景复杂度 | 功能匹配（legacy 已验证），但 ObjC/GCD 异步模型与 Swift 6 严格并发磨合无上游投入 |
| 与 #11/#6 契合 | 与 #6 "SwiftPM 只管理必要依赖"冲突；需重新引入 CocoaPods |

来源：[仓库](https://github.com/swisspol/GCDWebServer)、[tags API](https://api.github.com/repos/swisspol/GCDWebServer/tags)、[SPM 请求 issue](https://github.com/swisspol/GCDWebServer/issues/515)、[SPI 页面](https://swiftpackageindex.com/swisspol/GCDWebServer)。

决定：排除。上游归档是硬事实；3.5.4 之后没有任何修复，包括对现代 Xcode 工具链的适配。

### 3.2 GCDWebServer 的 SwiftPM fork

GitHub 搜索stars 最高的携带 `Package.swift` 的 fork（2026-09-20 查询）：

| Fork | 最后推送 | 附加内容 | star |
| --- | --- | --- | --- |
| [yene/GCDWebServer](https://github.com/yene/GCDWebServer) | 2025-02-04 | Package.swift、tvOS 支持、Privacy manifests、补 LICENSE | 51 |
| [readium/GCDWebServer](https://github.com/readium/GCDWebServer) | 2024-12-11 | Package.swift（readium 项目自用） | 13 |
| [CaperWhite/GCDWebServer](https://github.com/CaperWhite/GCDWebServer) | 2021-08-12 | Package.swift | 15 |

共同问题：都从已归档上游分叉；单一维护者；提交内容是各自下游需求（隐私清单、tvOS），不是对 HTTP 栈的持续维护；Swift 6 严格并发适配无任何承诺；license 归类 NOASSERTION 需自行核对 BSD 条款。绑定能力继承上游的两态开关，满足监听需求，但不改变上述风险。

决定：排除。选 fork 等于把上游归档的风险换一种记账方式，还叠加了 fork 存续风险。

### 3.3 Swifter（httpswift/swifter）

| 维度 | 事实 |
| --- | --- |
| 维护状态 | 未归档；最后推送 2024-03-17；最新 release 1.5.0 发布于 2020-09-26 |
| SwiftPM | 有 `Package.swift`；默认分支 `stable` |
| 许可证 | BSD-3-Clause |
| 绑定能力 | 满足：`tcpSocketForListen(_:forceIPv4:maxPendingConnection:listenAddress:)` 接受任意 IPv4/IPv6 地址字符串，回环与通配均可（[Socket+Server.swift](https://github.com/httpswift/swifter/blob/stable/Xcode/Sources/Socket+Server.swift)） |
| 场景复杂度 | API 简单，但基于 POSIX socket 的线程/阻塞模型；路由框架远超单一端点需要 |
| 与 #11/#6 契合 | 依赖面小，但近六年只有一个 release，长期无 Swift 工具链验证承诺 |

来源：[仓库](https://github.com/httpswift/swifter)、[releases API](https://api.github.com/repos/httpswift/swifter/releases/latest)、[SPI 页面](https://swiftpackageindex.com/httpswift/swifter)（SPI 列出 6.1–6.4 工具链兼容条目；本研究未逐项核验构建通过状态）。

决定：排除。 stagnation 程度与 GCDWebServer 本体相当，且没有“已经在用”的存量理由。

### 3.4 Telegraph（Building42/Telegraph）

| 维度 | 事实 |
| --- | --- |
| 维护状态 | 未归档；最后推送 2024-06-08；main 最新提交 2024-04-01（"Release 0.40.0"）；最新 tag 0.40.0 |
| SwiftPM | 有 `Package.swift`；零外部依赖的纯 Swift 服务器（TCP/TLS/HTTP/WebSocket） |
| 许可证 | MIT |
| 绑定能力 | 满足：`start(port:interface:)` 的 `interface: String?` 支持绑定指定地址/接口，回环与通配均可（Server.swift `start(port:interface:)`） |
| 场景复杂度 | 正是“嵌入 app 的轻量 HTTP 服务器”定位；绑定、路由、响应控制齐全；对我们用不到 TLS/WebSocket 部分 |
| 与 #11/#6 契合 | SwiftPM 原生，契合 #6；功能契合 #11；短板是 2024-04 后无发布，维护节奏由单一团队决定 |

来源：[仓库](https://github.com/Building42/Telegraph)、[branches/tags API](https://api.github.com/repos/Building42/Telegraph/tags)、[SPI 页面](https://swiftpackageindex.com/Building42/Telegraph)（SPI 显示 0.40.0/main 有 6.1–6.4 工具链兼容条目）。

决定：保留为**备选**。若实现阶段发现自研解析的边界情况处理成本超出预期（例如需要长连接 keep-alive 语义），Telegraph 是功能面最贴近、依赖面最干净的库方案；引入前须复核其 Swift 6 并发与 macOS 15+ 实测。

### 3.5 swift-nio（apple/swift-nio，NIOHTTP1）

| 维度 | 事实 |
| --- | --- |
| 维护状态 | 活跃；最后推送 2026-09-17；最新 release 2.103.0；Apple 官方维护 |
| SwiftPM | 原生；core + NIOHTTP1 等模块 |
| 许可证 | Apache-2.0 |
| 绑定能力 | 满足：`bind(to:)` 原生接受任意 `SocketAddress`（回环、通配、接口地址） |
| 场景复杂度 | 需要自组 pipeline（decoder/encoder/pipeline handler）；为单一端点引入整个事件循环依赖树 |
| 与 #11/#6 契合 | 供应链最稳；依赖重量与 #6 “最小依赖面”精神相悖（对本场景） |

来源：[仓库](https://github.com/apple/swift-nio)、[releases API](https://api.github.com/repos/apple/swift-nio/releases/latest)。

决定：作为**升级路径**保留。若 PAC 服务需求演进到按请求鉴权、动态 generation 内容或更高并发语义，迁移到 swift-nio；不作为 2.0 首选。

### 3.6 其他考虑过并排除的方案

- **Hummingbird**（hummingbird-project/hummingbird）：Apache-2.0、非常活跃（2026-09-19 推送，2.26.0），绑定任意地址自然支持，但是完整服务器框架（swift-nio + swift-log/service-lifecycle 生态），比裸 swift-nio 更超出本场景。排除。
- **Vapor**：同上且更重。排除。
- **在 `sslocal` 前面挂现成 HTTP 文件服务（如独立进程 caddy/nginx）**：引入一个非 Swift 的第三方二进制违背 #6 的 helper 面收敛，且生命周期与签名发布复杂度完全不对称。排除。

### 3.7 Network.framework 自研最小 HTTP/1.1 服务

本机 SDK（macOS 27.0 SDK，Xcode 自带）证据：

```text
Network.framework/Versions/Current/Modules/Network.swiftmodule/arm64e-apple-macos.swiftinterface
  line 616: final public class NWListener
  line 653: final public var newConnectionHandler: (@Sendable (NWConnection) -> Void)?
  line 710: final public func start(queue: DispatchQueue)
  line 2543: final public var requiredLocalEndpoint: NWEndpoint?   (NWParameters)
```

- 同一 swiftinterface 中不存在任何公共 HTTP 协议/服务器类型（grep `NWProtocolHTTP` 无结果；Headers 目录亦无 `http_options.h`）。即 Network.framework 提供监听/连接/绑定原语，HTTP/1.1 解析必须自己写——这是本方案的唯一工作增量。
- `requiredLocalEndpoint` 接受任意 `NWEndpoint.hostPort(host:port:)`：回环态绑 `127.0.0.1`，主机地址态绑 `0.0.0.0` 通配或指定接口地址；省略 `requiredLocalEndpoint` 时的默认行为即通配绑定。两态监听范围都是 SDK 原生表达，无需额外依赖。
- handler 标注 `@Sendable`，与 Swift 6 严格并发天然兼容；无第三方线程模型。
- 依赖面为零：无 SwiftPM 依赖、无 CocoaPods、无第三方许可证义务；与 #6 的供应链收敛一致。
- 若将来 app 采用 App Sandbox，监听入站连接需要 `com.apple.security.network.server` entitlement（Xcode App Sandbox > Network > Incoming Connections）；通配绑定时该 entitlement 同样适用。这是任何监听方案共同的约束，应记入 #6 的打包清单。该 entitlement 属于 App Sandbox 体系，本研究未实测其行为。

决定：**推荐**。

## 4. 候选对比

关于两态监听约束：**所有候选都满足“支持绑定非回环地址”**（见各节绑定能力行），因此该约束不构成区分项；真正的区分项仍是维护状态、依赖面与场景契合度。

| 方案 | SwiftPM/依赖面 | 维护/许可证 | 绑定能力 | 单端点场景复杂度 | 与 #11/#6 契合 | 决定 |
| --- | --- | --- | --- | --- | --- | --- |
| GCDWebServer 本体 | 无 SPM，需 CocoaPods | 已归档（2022），BSD-3 风格 | 两态开关，满足 | 低（legacy 同构） | 冲突：重新引入 CocoaPods | 排除 |
| GCDWebServer SPM fork | SPM（fork 提供） | 单维护者低星 fork | 继承上游，满足 | 低 | fork 存续风险叠加归档上游 | 排除 |
| Swifter | SPM | 停滞（最后 release 2020），BSD-3 | 任意地址，满足 | 低-中（socket 线程模型） | 维护风险高 | 排除 |
| Telegraph | SPM，零外部依赖 | 2024-04 后无发布，MIT | `interface:` 参数，满足 | 低（库承担解析/路由） | 契合；维护节奏存疑 | 备选 |
| swift-nio | SPM，重量级依赖树 | Apple 活跃，Apache-2.0 | `bind(to:)`，满足 | 中（自组 pipeline） | 供应链稳但过度供给 | 升级路径 |
| Network.framework 自研 | 零第三方依赖 | 随系统 SDK | `requiredLocalEndpoint`，满足 | 中（自写有界 HTTP/1.1 解析） | 完全契合 | **推荐** |

## 5. 推荐方案的实现约束

以下约束把 #11 §4.2 的 endpoint 要求翻译成自研服务的实现边界；实现票据应逐条验收。

- **绑定（两态监听范围）**：`NWParameters.tcp` + `requiredLocalEndpoint`。回环态（默认）固定为 IPv4 `127.0.0.1` + 端口；用户显式选择“主机地址”态时绑定 `0.0.0.0` 通配（或指定接口地址）。监听范围是二选一开关，**不提供自由文本绑定地址输入**——这保留 #11 对“用户输入地址作为绑定地址”的顾虑，同时满足局域网共享 PAC URL 的需求。用户可配置项只有监听范围开关与端口。
- **非回环态的安全语义**：PAC 内容是路由规则与本地代理地址，不含凭据，局域网暴露本身可接受；但非回环态下请求解析的健壮性约束（限长、畸形输入断开、慢速连接防护）面向的是局域网可达端口而非仅本机进程，实现不得因“回环默认”而省略这些边界。generation URL 路径仍是主要访问控制：非持有者只能拿到 PAC 内容本身。
- **请求解析**：读取请求直到 CRLFCRLF，设硬性头部上限（如 16 KiB），超限即断开；只接受 GET；request-target 同时容忍 origin-form 与 absolute-form；路径不匹配 404，非 GET 405；解析失败一律断开连接，不回显输入。
- **响应**：200 + 完整 JavaScript 快照；`Content-Type: application/x-ns-proxy-autoconfig`；`Cache-Control: no-store`；精确 `Content-Length`；每个响应后主动 `Connection: close`，把状态机压缩到“单请求单响应”。PAC 拉取频率极低，放弃 keep-alive 是合理交换；若实测发现某系统客户端依赖 keep-alive，再作为受控增强引入。
- **失败语义**：listener 创建/启动失败、端口冲突必须以错误状态上抛；在失败未解除前不得发布/保留该 URL 的系统代理写入（#11 §4.2 的门禁由上层执行，服务必须可靠地报告失败而不是吞掉）。
- **生命周期**：与 per-user runtime 同生命周期，支持显式 start/stop 与 generation 热切换（切换只是替换内存快照与当前 generation 值，不重启监听）。
- **安全边界**：暴露面随监听范围两态变化（回环态限于本机进程，主机地址态扩展到局域网，见前两条）；不实现 TLS、不回显 query、日志脱敏（对齐 #10 的脱敏要求）。
- **宿主进程、默认端口与端口冲突恢复策略**：不在本票据决定；实现票据必须先决定宿主（LaunchAgent 或 GUI 进程）再落地。
- **测试**：解析器做成纯函数单元测试（畸形请求、超长头部、多请求管道、absolute-form、大小写头部）；再以真实 loopback socket 做集成测试；最终接入 #11 验证计划的 endpoint 项（MIME、no-store、generation 切换、系统客户端行为）。

## 6. 验证计划

进入实现前必须完成，不把本报告的推断当成已验证：

1. 在 macOS 15 与本机（macOS 27.0 Build 26A428）各跑一个最小 `NWListener` + 手写解析原型，确认 `requiredLocalEndpoint` 分别绑定 `127.0.0.1` 与 `0.0.0.0` 的行为、端口占用时的错误类型与可恢复性。
2. 非回环态实测：通配绑定后从同一局域网的另一台机器用浏览器/curl 拉取 PAC URL，确认可达性、响应头与 generation 切换；记录 macOS 应用防火墙（socketfilterfw）对入站监听的提示/放行行为——该行为未实测前不得写成事实。
3. 用 Safari 与 `CFNetworkCopyProxiesForURL` 验证系统代理栈对 `Connection: close`、no-store、generation URL 切换的实际行为；记录是否存在需要 keep-alive 的客户端。
4. 对解析器跑畸形输入矩阵（超长头部、空请求、二进制、慢速发送、并发连接），确认有界且不崩溃；矩阵在回环与非回环态下各跑一遍。
5. 压测 generation 热切换：切换期间进行中的请求返回旧快照或失败但绝不返回混合内容。
6. 若 2.0 决定启用 App Sandbox，实测 `com.apple.security.network.server` entitlement 下监听回环与通配的行为，并记入 #6 打包清单。

## 7. 对后续票据的明确约束

- 「SwiftUI 菜单栏与配置管理界面信息架构」：监听范围（回环/主机地址两态）与 PAC 服务的失败状态（端口冲突、监听失败）是用户可见状态的一部分；两态切换必须明确提示“主机地址会把 PAC 端点暴露给局域网”。界面契约按 #11 的呈现要求执行。
- 「决策：Legacy 配置迁移与旧版功能边界」：`PacServer.BindToLocalhost` 开关按语义迁移为 2.0 的监听范围两态（回环默认）；迁移用户配置的 `PacServer.ListenPort` 端口值时，short 窄化表示必须换成完整端口范围校验。
- 实现票据：先决定宿主进程与端口策略，再按第 5 节约束实现；若中途放弃自研，回退顺序是 Telegraph，然后 swift-nio，不得回到 GCDWebServer 系。

本报告只新增研究文档；未修改 Legacy/ 或 2.0 生产代码。
