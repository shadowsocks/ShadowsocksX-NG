# 受管插件功能级兼容实测记录（spec #21 Further Notes #6，issue #38）

- 实测日期：2026-09-21
- 实测人：Qiu Yuzhou（agent 辅助执行）
- 环境：macOS 26（Darwin 27.0.0）arm64；Xcode DerivedData Debug 构建；sslocal v1.25.0（`aarch64-apple-darwin`，归档 SHA-256 `58e0caf0…`）；v2ray-plugin v1.3.2（`darwin-arm64`，归档 SHA-256 `35747669…`），均为 Vendor 清单固定版本，构建期哈希复验 + Developer ID 重签（插件 identifier `com.qiuyuzhou.ShadowsocksX-NG.plugin.v2ray-plugin`，hardened runtime）。
- 证据规则：以下每一条都对应可重复执行的测试或本记录中的命令输出摘要；未实测的系统行为不写成事实。

## 已实测闭环

### 1. 配置生成 → sslocal 拉起 → 插件进程建立（端到端边界）

生产组合根已接线：`CatalogViewModel` / `ProxyRuntimeController` 的默认受管插件提供均为 `BundleManagedPluginProvider`（宿主 app bundle），激活派生、编辑器提供事实与诊断清单读同一事实源；`BundleManagedPluginProviderTests.testHostAppBundleProvidesManagedPlugin` 固化「bundle 内插件在位」防打包回归。

`Tests/RealSslocalSmokeTests.testRealSslocalLaunchesManagedV2rayPluginProcess`：

- 契约 `servers[0]` 携带 bundle 内插件绝对路径（`Contents/Helpers/Plugins/v2ray-plugin`）与 `plugin_opts: "mode=websocket"`；
- wrapper 以真实 sslocal 拉起，SIP003 插件进程建立（`pgrep -f` 按完整路径确认，进程存活）；
- 本地 SOCKS 端口完成监听绑定；
- SIGTERM 停止链：wrapper 干净退出（0），插件进程随 sslocal 一并结束。

无插件基线 `testRealSslocalBindsSOCKSAndHTTPPortsAndCompletesHandshake` 在同一套件中保持通过（SOCKS5 完整握手）。

实测观察（补充两条对后续票有用的行为事实）：

- **sslocal 在插件进程就绪前不绑定本地监听**。插件冷启动（首次 exec 触发签名校验）时，从 sslocal spawn 到端口可用可能明显超过 3 秒（本机 xcodebuild 冷环境实测出现过 6 秒级）。D10 的「3 秒未建立监听 → error 日志」在此场景是真实告警而非误报，GUI 健康门（15 秒）不受影响。
- shadowsocks-rust 按 SIP003 以 `SS_LOCAL_HOST/SS_LOCAL_PORT` 环境变量让插件监听管道口；插件进程先于本地端口出现。

### 2. 选择器全语义与保存语义

`Tests/CatalogViewModelPluginTests`（9 例）与 `Tests/BundleManagedPluginProviderTests`（6 例）：

- 「无 / 受管 / 集外」三态呈现；受管选中显示供应链事实（来源项目、许可证 MIT、固定版本 v1.3.2、重签标识）且只有受管选中出现参数输入；
- 受管选择落盘：程序名入目录、参数入钥匙串（引用形态）；空参数删除引用与秘密；「无」整体清除；
- 集外引用（如 Legacy/订阅带入的 `obfs-local`）显式渲染「本版本未提供」、原样保留引用与参数秘密，连接字段照常可编辑；
- 受管集外程序名一律 `executablePath == nil`（含路径形态引用，绝不拼接用户输入），经状态机以 `pluginNotProvided` 原子拒绝；文件缺失/降级同语义。

### 3. 激活失效路径接 #26 语义

`Tests/ActivationStateMachineTests`（存量）+ `BundleManagedPluginProviderTests`（新增，以真实文件存在性驱动 provider）：

- 组内一叶引用未提供插件 → 整组原子拒绝并点名；
- 活动目标插件变为不可用（`catalogDidCommit` / `resyncOnLaunch`）→ 清除目标、停止代理、点名原因（`ProxyRuntimeControllerTests` 存量覆盖）。

### 4. ss URI 往返

`Tests/SsUriTests`（存量，逐字节同构语料）+ `CatalogViewModelPluginTests.testSharedSsUriRoundTripsThroughEditorEdit`（经编辑面保存 → 分享 → 再导入，`plugin=name;opts` 同构，与 #32 编解码一致）。

### 5. 诊断页/导出

`Tests/DiagnosticReportTests`（新增 2 例）：导出含「受管插件」清单（程序名 + 版本 + 提供/缺失），投毒夹具确认插件参数不进导出。

### 6. wrapper 监听判定

`Tests/AgentLifecycleTests.testListenNotEstablishedWithinDeadlineIsLoggedAndSupervisionContinues`：stub sslocal 不监听 → 拉起 3 秒后 `agent.log` 出现 `listen not established within deadline: <端点>`，监管循环继续，后续 SIGTERM 停止链不受影响（D10「运行期失败以 sslocal 信号为准，GUI 不猜测」）。插件进程退出不经 wrapper 直接观测——插件死亡连带 sslocal 退出（实测行为），由既有的 `sslocalExitedUnexpectedly` error 日志承接，与「以 sslocal 信号为准」一致。

## 仍属发布门槛人工项（不能在本机自动化闭环）

1. **真实服务器功能验证**：经 v2ray-plugin websocket 隧道访问真实远端的协议行为与性能（无真实服务器夹具；本记录只闭环到「插件进程建立 + 本地监听」边界）。
2. **真实公证对嵌套重签插件的接受度**（Further Notes #3，需 notarytool 凭据，#39）。
3. **Gatekeeper 首启/quarantine 实机弹窗形态**（Further Notes #1）与 Hardened Runtime 下两级子进程签名链在陌生机器上的表现（Further Notes #2 的实机部分）。

## 结论

#38 验收标准中「stub 边界验证或真实夹具」档位的功能级兼容实测已闭环并固化为本仓库测试；真实服务器配合、公证与陌生机器 Gatekeeper 行为按规格保留为发版前人工检查项。
