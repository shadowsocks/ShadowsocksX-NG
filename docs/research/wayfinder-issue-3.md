# Wayfinder 研究：macOS 15 arm64 外部服务与应用生命周期

> 研究日期：2026-09-20  
> 范围：ShadowsocksX-NG 2.0；SwiftUI 菜单栏 GUI；随 `.app` 分发的 arm64 `shadowsocks-rust` 外部进程。  
> 约束：本报告只修改研究文档，不修改 `Legacy/` 或生产代码。

## 结论先行

推荐使用 **`SMAppService.agent(plistName:)` 注册一个随应用签名、位于应用包内的 LaunchAgent**；运行时仍由 `launchd` 管理，`SMAppService` 是现代的注册、授权和注销入口，不是另一个进程监督器。不要在 macOS 15 目标上把手写 `~/Library/LaunchAgents` plist 作为生产安装路径，也不要把不需要 root、开机前运行或跨用户服务的本地代理做成 LaunchDaemon。

建议的边界是：

1. `SMAppService.Status` 表示“服务是否已注册、是否获准运行”，不表示代理进程当前健康。
2. LaunchAgent plist 使用 `BundleProgram` 指向应用包内的 `shadowsocks-rust`，使用 launchd 的 `KeepAlive` 策略恢复崩溃；GUI 通过本地健康检查和明确的生命周期协议判断代理是否真的可用。
3. 用户主动停止或退出应用时，先执行代理的可选优雅停止协议，再注销服务；注销要使用 completion-handler 版本并等待完成，避免立即重新注册造成竞态。
4. 应用退出策略必须明确：默认 Quit 应停止代理，或提供清晰的“退出但保留代理运行”选项。若允许代理留在后台，菜单栏/登录项设置中必须仍有可见的停止控制。

这是一个**架构建议**，不是 Apple 对本项目的唯一规定。Apple 明确规定了 API 的注册、授权状态和 launchd plist 语义；“如何把代理健康度、连接开关和 GUI 状态组合起来”属于本项目设计选择。

## Apple 文档确认的事实

### 1. LaunchAgent 与 LaunchDaemon 的边界

Apple 将 LaunchAgent 定义为代表当前登录用户运行的进程；LaunchDaemon 是可由 `launchd` 管理、以 root 身份运行、甚至在用户登录前运行的独立后台进程。[Service Management 总览](https://developer.apple.com/documentation/servicemanagement) 也将二者明确区分。对一个只服务当前用户、无需修改系统配置的本地 Shadowsocks 代理，LaunchAgent 的权限和生命周期边界更贴合需求；选择 LaunchDaemon 会引入系统级服务和管理员批准流程，这是设计推导，不是“代理必然不需要其他网络/防火墙权限”的保证。

传统 launchd 配置由 plist 描述。Apple 的 Launchd 编程指南说明，LaunchAgent 可以放在用户的 `Library/LaunchAgents`，而 LaunchDaemon 放在系统级目录；`Label` 和 `ProgramArguments` 是基本配置，`KeepAlive` 控制是否持续保持运行。[Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

当前 Darwin 的 Apple 开源 man page 进一步说明，LaunchAgent 应运行在用户 session；`Program` 要求绝对路径，而仅由 `SMAppService` 安装的 plist 可以使用相对应用包的 `BundleProgram`。[Apple `launchd.plist(5)`](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5) 这使得服务可以随 `.app` 携带，而不必把安装后的绝对路径写死。

### 2. `SMAppService` 是 macOS 15 应用应使用的注册层

Apple 的 `SMAppService` 文档明确说：在 macOS 13 及更高版本，用它注册和控制 LoginItem、LaunchAgent、LaunchDaemon；对 LaunchAgent，它替代把 plist 手工安装到 `~/Library/LaunchAgents` 或 `/Library/LaunchAgents`。[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

LaunchAgent plist 必须位于主应用包的 `Contents/Library/LaunchAgents`。Apple 的迁移文档建议把 helper 放进应用包，并把 plist 中的 `Program` 替换为相对应用包的 `BundleProgram`；这样应用移动位置时仍可定位 helper。[Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)

注册时，`SMAppService.agent(plistName:)` 对应的 LaunchAgent 会立即 bootstrap，并在后续用户登录时再次 bootstrap；API 必须在目标用户正在运行应用时调用，不能从用户上下文之外替另一个用户注册。[register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)

Apple 还明确要求使用 `SMAppService` 的应用经过代码签名；如果 LaunchAgent 的 plist 或可执行文件更新，需要重新注册，否则可能不会启动，Apple 建议可执行文件变化时先注销再注册。[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

因此，生产包建议类似以下结构（名称仅为设计示例）：

```text
ShadowsocksX-NG.app/
└── Contents/
    ├── Library/LaunchAgents/com.shadowsocksxng.proxy.plist
    └── Resources/shadowsocks-rust       # arm64，随应用签名
```

plist 仍然是 launchd 配置；`SMAppService` 负责让它进入系统的 Service Management 生命周期。两者不是互斥方案。

### 3. 授权和用户可见性

`SMAppService.Status` 有四个有明确含义的状态：`notRegistered`、`enabled`、`requiresApproval`、`notFound`。[SMAppService.Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum) 其中 `requiresApproval` 表示服务已注册，但用户需要在 System Settings 中采取行动，或用户已撤销允许运行的同意。[requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)

Apple 对 LaunchDaemon 明确要求管理员在 System Settings 中批准；对 LaunchAgent，文档描述的是当前用户上下文注册和登录时 bootstrap，而不是系统级管理员授权。[register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29) 因此本项目应避免 LaunchDaemon，不应为了启动普通用户代理而设计提权流程。仍需在实际分发包上验证签名、Gatekeeper、用户关闭后台项后的行为，以及代理自身涉及的网络/防火墙权限；这些不是 `SMAppService` 文档可以替项目保证的事项。

Apple 建议依赖 helper 的应用检查授权状态，并在用户同意后打开 Login Items 设置；可通过 `SMAppService.openSystemSettingsLoginItems()` 引导用户。[Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)

### 4. 崩溃恢复不是 `SMAppService.Status` 的职责

对 LaunchAgent，`register()` 文档只承诺立即 bootstrap 和后续登录 bootstrap；它没有承诺“LaunchAgent 崩溃后自动重启”。重启策略来自 launchd plist。Apple 的 `launchd.plist(5)` 说明：

- `KeepAlive=true` 会让 launchd 持续保持 job 运行，并隐含 `RunAtLoad`；快速、频繁退出的 job 会被 throttle。
- `KeepAlive` 字典可以用 `Crashed` 只针对由典型 crash signal 退出的情况决定是否重启。
- LaunchAgent 应处理 `SIGTERM`，快速结束未完成工作后退出。

来源：[Apple `launchd.plist(5)`](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5)。

对 `shadowsocks-rust`，建议第一版采用下面的策略（**设计选择**）：

- 如果“代理服务已启用”代表应持续运行，使用 `KeepAlive` 的 `Crashed=true`，让信号崩溃自动恢复，但不要把配置错误导致的普通非零退出变成无限重启循环。
- 用户主动停止前先改变本项目的 desired state，再注销服务；否则 `KeepAlive` 可能把一次主动退出解释成需要再次启动。
- 代理必须能响应 `SIGTERM`，或者由一个很薄的、能优雅处理信号的 wrapper 负责管理它；不要在 launchd 进程中自行 daemonize/fork。launchd man page 对这两点都有明确约束。[Apple `launchd.plist(5)`](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5)

不要把 LoginItem helper 的行为误套到 LaunchAgent 上：Apple 对 LoginItem 单独说明了 crash 或非零退出会被重新拉起；LaunchAgent 的恢复行为应由 plist 的 launchd 策略决定。[register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)

### 5. 应用退出、重启与干净停止

Apple 的后台进程指南要求：应用退出时，要终止自己启动的后台工作，或者给用户提供停止它的能力；如果长时间后台服务确实必要，应考虑用 `SMAppService` 注册 LaunchAgent，让用户能在 System Settings 中管理它。[Managing ongoing background processes in your Mac](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)

这意味着“GUI 退出但代理无提示地继续运行”不是默认可忽略的实现细节。推荐把行为定义为：

| 用户动作 | 推荐契约 |
| --- | --- |
| Stop Proxy | 发送代理自己的 graceful-stop 请求；随后注销 LaunchAgent；确认完成后展示 stopped。 |
| Quit | 默认执行 Stop Proxy，再退出 GUI；若产品要支持保留代理，提供明确的“Keep proxy running”路径和之后可用的停止入口。 |
| Relaunch | 读取 `SMAppService.status`，再做端口/IPC 健康检查；已有代理则复用，不重复注册或启动第二个实例。 |
| App 更新 | 若 plist 或代理二进制变化，注销并重新注册；等待异步注销完成后再注册。 |

`SMAppService.unregister()` 的文档保证服务不再由系统启动；异步 completion-handler 版本把完成结果交给调用方，适合把“停止完成”作为退出前的明确阶段。[unregister(completionHandler:)](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28completionhandler%3A%29) GUI 若需要延迟退出，可使用 AppKit 的 `applicationShouldTerminate(_:)` 返回延迟结果，完成服务停止后再 `reply(toApplicationShouldTerminate:)`。[applicationShouldTerminate(_:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate%28_%3A%29)

Apple 同时提醒，直接用 `posix_spawn()`、`fork()` 或 `system()` 启动的长期进程需要由应用自己保证退出；若进程要在 GUI 退出后继续运行，应该考虑用 SMAppService 管理的 LaunchAgent。[Managing ongoing background processes in your Mac](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac) 这正是本项目不应把生产生命周期建立在 GUI 直接 spawn 上的主要理由。

### 6. 日志和诊断

Launchd plist 可以把 helper 的 stdout/stderr 定向到文件，使用 `StandardOutPath` 和 `StandardErrorPath`；Apple 的 Launchd 编程指南给出了这种调试配置示例。[Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

SwiftUI GUI 及 Swift helper 的生命周期、注册错误、状态变化应使用 Apple Unified Logging。Apple 说明统一日志由 `Logger`/OSLog 写入，可用 Console、`log` 工具、Xcode 或 OSLog API 查看；它不是普通可读文本文件。[Logging](https://developer.apple.com/documentation/os/logging)；[Viewing Log Messages](https://developer.apple.com/documentation/os/viewing-log-messages)

因此要区分两类证据（**设计选择**）：

- `shadowsocks-rust` 的 stdout/stderr：落到应用专属的用户日志文件，GUI 可展示最近一段并保留路径。
- GUI/生命周期管理器：写 Unified Log，带稳定 subsystem/category，便于 Console 和 `log show` 查询。

服务状态的诊断入口可以使用 `launchctl print gui/$UID/<label>`。Apple 当前 `launchctl(1)` 说明 `print` 会显示服务的来源、当前状态、执行上下文和最后退出状态；`bootstrap`/`bootout` 管理服务定义，`kickstart` 可立即运行服务。[Apple `launchctl(1)`](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchctl.1)

但 GUI 不应把 `launchctl` 的人类可读输出当作稳定应用 API。运行时真值建议是：

```text
registration = SMAppService.status
process      = launchd 负责的实例是否可观察
health       = 本地 IPC/端口握手是否成功
```

后两项是本项目的健康模型；Apple 的 `SMAppService.status` 只表达注册/授权状态，并不等价于进程已运行或代理已可用。[status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property)

## 原始 per-user plist 与 `SMAppService` 对比

| 维度 | 手写 `~/Library/LaunchAgents` + `launchctl` | `SMAppService.agent(plistName:)` |
| --- | --- | --- |
| 运行时监督 | 仍由 launchd；plist 直接表达 `KeepAlive` 等策略。[`launchd.plist(5)`](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5) | 同样由 launchd；SMAppService 是注册/注销入口。[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) |
| 安装/更新 | 要自行写入、bootstrap、卸载、处理 owner/权限和残留 | plist 与 helper 随签名 `.app`，注册状态由 API 管理；更新后按 Apple 要求重新注册。[迁移文档](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos) |
| 用户授权/可见性 | 手工路径本身不提供现代 API 的 status 模型 | `status` 暴露 enabled / requiresApproval 等状态，并接入 Login Items 设置。[Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum) |
| 应用移动 | 绝对 `Program` 路径容易失效 | `BundleProgram` 支持应用包相对路径。[迁移文档](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos) |
| 适合本项目吗 | 适合开发期诊断、迁移兼容和底层排障 | **推荐生产方案**；目标 macOS 15 已满足 API 可用范围 |

结论不是“不要用 plist”，而是“不要把 plist 的安装/注册/授权生命周期自行实现一遍”。推荐的生产方案仍然需要一个最小 plist，但由 `SMAppService` 管理它。

## 建议的可验证生命周期模型

```text
NotRegistered
    │ register()
    ▼
RequiresApproval ──用户在 Login Items 中允许──▶ Enabled
    │                                      │
    │                                      ├─ launchd 启动 / 崩溃恢复
    │                                      └─ IPC/端口健康检查
    │
    └─ 用户拒绝/关闭 ───────────────▶ RequiresApproval

Enabled + unregister(completionHandler:)
    └─ 停止服务、等待完成 ───────────▶ NotRegistered
```

实现验收至少应覆盖：注册后服务是否立即 bootstrap；注销后是否不会在下次登录自动启动；用户在 Login Items 中关闭后是否得到 `requiresApproval`；代理 SIGTERM 是否干净退出；崩溃后是否按 `KeepAlive` 策略恢复；GUI 重启时是否能区分“已授权但进程未健康”和“未授权”。前五项分别由 Apple API/launchd 语义和本项目测试共同验证，最后一项是本项目设计的状态组合。

## GitHub #3 说明（只读核验）

任务说明中的“numeric #3 是 closed historical PR”对 **upstream** 仓库成立：[`shadowsocks/ShadowsocksX-NG#3`](https://github.com/shadowsocks/ShadowsocksX-NG/pull/3) 是 2016 年关闭的 `Project skeleton optimization` PR。

当前工作副本的 `origin` 是 `qiuyuzhou/ShadowsocksX-NG`，该仓库的 [`#3`](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/3) 当前则是 open 的 Wayfinder 研究 issue，标题为“研究：macOS 15 arm64 外部服务与应用生命周期”。本次只读核验没有执行任何 GitHub issue/PR 写操作。

## Wayfinder resolution comment（简版）

基于 Apple 的 Service Management、`SMAppService`、`launchd.plist(5)` 和 `launchctl(1)` 文档，2.0 应采用随签名 `.app` 分发的 per-user LaunchAgent，并通过 `SMAppService.agent(plistName:)` 注册/注销；不要生产环境手写 `~/Library/LaunchAgents` 安装流程，也不需要把普通用户代理升级为 LaunchDaemon。LaunchAgent 仍由 launchd 负责启动和崩溃恢复，`SMAppService.status` 只代表注册/授权，不代表代理健康。使用 `BundleProgram` 指向包内 arm64 `shadowsocks-rust`，用 `KeepAlive` 的明确策略处理 crash，GUI 用 IPC/端口健康检查补充状态；Quit/Stop 必须执行可验证的停止流程并让用户知道后台代理是否仍在运行。上游仓库的 numeric #3 是已关闭历史 PR；本次不修改 GitHub。

## Apple 一手来源索引

- [Service Management](https://developer.apple.com/documentation/servicemanagement)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [SMAppService.register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)
- [SMAppService.Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum)
- [SMAppService.unregister(completionHandler:)](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28completionhandler%3A%29)
- [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Managing ongoing background processes in your Mac](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)
- [Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [Apple `launchd.plist(5)` source](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5)
- [Apple `launchctl(1)` source](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchctl.1)
- [Logging](https://developer.apple.com/documentation/os/logging)
- [Viewing Log Messages](https://developer.apple.com/documentation/os/viewing-log-messages)
- [`applicationShouldTerminate(_:)`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate%28_%3A%29)
