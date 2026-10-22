# Wayfinder issue 17：Legacy 运行时交接的识别、卸载与恢复路径

- 票据：[研究：Legacy 运行时交接（停止/卸载/端口释放/登录项/系统代理）](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/17)
- 父地图：[Wayfinder: ShadowsocksX-NG 2.0 现代化重实现](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/1)
- 研究日期：2026-09-20
- 适用范围：macOS 15+、仅 arm64、ShadowsocksX-NG 2.0；落实 [#7 决议「Legacy 运行时交接」](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/7)：仅停止/卸载经正向识别的 `com.qiuyuzhou.shadowsocksX-NG.local` 与 `com.qiuyuzhou.shadowsocksX-NG.http`，不泛匹配、不自动删除 Legacy 数据。
- 证据规则：系统契约以本机 man 页与 SDK 头文件为权威（Apple 网页为 JS 渲染，本次未取到正文，按票据规则以 man/头文件为准）；Legacy 侧事实来自冻结源码与全量 git 历史；本机实测标注环境。**本机验证在 macOS 27.0（Build 26A428, arm64）完成；macOS 15 行为以文档为准，差异进入「遗留验证」。**

## 决策摘要

1. **识别完全可行且无需泛匹配。** Legacy 的两个 job label、plist 文件名、登录项 helper bundle ID 全部是源码硬编码字符串，全量 619 提交历史中从未变更；识别 = 精确 label 的 `launchctl print gui/<uid>/<label>`（未加载返回退出码 113，本机实测）+ `~/Library/LaunchAgents/<plist>` 文件检查 + `launchctl print-disabled` 残留记录。本机还实测到第三条痕迹：print-disabled 中保留着两个 label 的 override 记录，即使 plist 与 job 都已不存在——它是「这台机器装过 Legacy」的正向信号。
2. **停止与卸载用 `launchctl bootout gui/<uid>/<label>`（按 service target，不按路径）。** `load/unload` 在现行 man 页列为 LEGACY 子命令并明示推荐替代为 `bootstrap/bootout/enable/disable`；`bootout` 按 service identifier 定位不需要 plist 文件存在，恰好覆盖「job 已加载但 plist 缺失」的错位。bootout 的信号序列 man 页未文档化，需显式终止时的有文档后备是 `launchctl kill SIGTERM gui/<uid>/<label>`。
3. **SMAppService 不能注销其他应用的 agent——这是 SDK 头文件的明文约束**：`agentServiceWithPlistName:` 要求 plist 位于「调用方 app 自己的 Contents/Library/LaunchAgents」。因此对 Legacy 这类第三方 per-user agent，launchctl 是唯一可用接口；`SMAppService.statusForLegacyURL:` 只提供只读状态查询，且未文档化是否可用于第三方 plist（遗留验证）。
4. **残留 plist 不是无害的，必须看内容。** 2017-05-11（提交 `0f050f6`）之前的 Legacy plist 生成代码带 `KeepAlive: true`——该时代的残留 plist 会在每次登录时自动拉起 ss-local 并在退出后重启，即使 Legacy app 早已删除。残留处置必须先读 plist 内容判断活跃性，而不是假设它休眠。现行 Legacy plist 无 KeepAlive/RunAtLoad，登录时仅注册不启动。
5. **端口释放确认有一个必须绕开的坑：Legacy ss-local 以 `--reuse-port` 运行。** 端口探测不得设置 `SO_REUSEPORT`，否则在 Legacy 仍持端口时 bind 也能成功、产生假「已释放」。推荐组合：对配置的具体端口做 lsof 监听者诊断（同用户进程无需 sudo，本机实测）+ 无 SO_REUSEPORT 的 bind 探测。另外 **PAC 端口 1089 的持有者是 Legacy GUI 进程内的 GCDWebServer，不是任何 launchd job**——bootout 两个 job 不会释放 1089，交接流程必须把「退出 Legacy app」纳入前置条件。
6. **旧 SMLoginItem 登录项没有可靠的 2.0 侧编程停用路径。** `SMLoginItemSetEnabled` 自 macOS 13.0 起弃用（SDK 头文件明文）；`SMAppService.loginItem(identifier:)` 要求 identifier 对应「调用方 app 自己的 Contents/Library/LoginItems」中的 bundle。主路径是人工指引（系统设置 → 登录项，或经 Legacy app 自身开关）；`sfltool dumpbtm` 本机实测触发了管理员授权弹窗，不能作为 2.0 的无提示检测手段（详见 §7）。
7. **系统代理确认无所有者标记**（`scutil --proxy` 本机实测输出只有代理键值），所以「切换到 2.0」的确认文案必须显式告知系统代理将被关闭/改写（#7 决议要求），失败路径按 #11 的 ownership record + #14 的健康门禁纪律执行。

## 1. Legacy 运行时产物的精确清单（正向识别的基底）

两个 launchd job 的全部标识字符串在冻结源码中硬编码，[LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L11-L16)：

| 产物 | 精确值 | 源码位置 |
| --- | --- | --- |
| ss-local job label | `com.qiuyuzhou.shadowsocksX-NG.local` | [LaunchAgentUtils.swift L66](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L66) |
| ss-local plist 路径 | `~/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.local.plist` | [LaunchAgentUtils.swift L14/L34-36](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L14) |
| Privoxy job label | `com.qiuyuzhou.shadowsocksX-NG.http` | [LaunchAgentUtils.swift L303](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L303) |
| Privoxy plist 路径 | `~/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.http.plist` | [LaunchAgentUtils.swift L15/L287-289](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L15) |
| 登录项 helper bundle ID | `com.qiuyuzhou.ShadowsocksX-NG.LaunchHelper`（注意大小写与 job label 不同） | [LaunchAtLoginController.m L69](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAtLoginController.m#L67-L81) |
| 登录项 helper 安装位置 | `<Legacy app>/Contents/Library/LoginItems/LaunchHelper.app` | [project.pbxproj L131](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG.xcodeproj/project.pbxproj#L131)（`dstPath = Contents/Library/LoginItems`） |

**跨版本稳定性（git 全历史查证）**：对全部 619 个提交做 `git grep` 扫描，出现过的 label 字符串只有 `.local`、`.http`、`.kcptun` 三种，无任何改名、变体或大小写漂移。2.0 可以安全地把这些字符串当作常量。

**历史第三 job（识别面要覆盖、处置面要区分）**：`com.qiuyuzhou.shadowsocksX-NG.kcptun` job 连同 `generateKcptunLauchAgentPlist()` 存活到 2018-09-16（提交 `db81543` "Remove feature over kcptune."）。用过 2018 年前 Legacy 版本的用户机器上可能残留该 plist 甚至已加载 job。#7 决议只授权停止/卸载 `.local` 与 `.http` 两个 job；kcptun 残留应走「检测 + 提示用户处理」路线（识别序列仍按精确 label 检查它），其处置是否扩入停止名单需要一个小裁决（遗留裁决项，见 §9）。

**两个 job 的 plist 关键形态**（现行冻结版）：只有 `Label`、`WorkingDirectory`、`StandardOutPath/StandardErrorPath`、`ProgramArguments`、`EnvironmentVariables`（ss-local），无 `RunAtLoad`、无 `KeepAlive`、无 Socket 定义——即登录时 launchd 只注册 job 不启动实例；ss-local 由 Legacy app 经脚本 `launchctl load -wF` + `launchctl start` 显式拉起（[start_ss_local.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ss-local/start_ss_local.sh)、[stop_ss_local.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ss-local/stop_ss_local.sh)，用旧式 `load/unload`）。ss-local 的 `ProgramArguments` 含 `--reuse-port`（[LaunchAgentUtils.swift L57](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L50-L58)），这对端口释放探测有直接约束（§2.3）。

**端口归属映射（交接检查的对象清单）**：

| 端口（默认） | 持有者 | 归属证据 | 释放条件 |
| --- | --- | --- | --- |
| 1086 SOCKS5 | ss-local job（`.local`） | plist `ProgramArguments` | bootout `.local` |
| 1087 HTTP | Privoxy job（`.http`） | plist `ProgramArguments` | bootout `.http` |
| 1089 PAC | **Legacy GUI 进程内 GCDWebServer**，非 launchd job | [ProxyConfHelper.m L16/L223-236](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L223-L236)（进程内全局对象） | **Legacy app 退出**；bootout 两个 job 不影响它 |

注意 Legacy 的 LaunchAgent plist 内**没有端口字段**：端口写在 `~/Library/Application Support/ShadowsocksX-NG/ss-local-config.json`（`local_port`/`local_address`）与 `privoxy.config` 中，源头是 Legacy defaults `LocalSocks5.ListenPort`/`LocalHTTP.ListenPort`/`PacServer.ListenPort`（inventory §1）。因此端口释放检查不能从 LaunchAgent plist 读端口，而应：从 defaults 域 `com.qiuyuzhou.ShadowsocksX-NG` 与上述生成文件读取配置端口，再对每个具体端口探测。

## 2. 识别：job、plist、端口

### 2.1 已加载 job：`launchctl print gui/<uid>/<label>`

- man launchctl：`print domain-target | service-target`「Prints information about the specified service or domain… Service output includes various properties of the service, including information about its origin on-disk, its current state, execution context, and last exit status」。
- **本机实测（macOS 27.0）**：对未加载的精确 label 查询

  ```text
  $ launchctl print gui/501/com.qiuyuzhou.shadowsocksX-NG.local
  Bad request.
  Could not find service "com.qiuyuzhou.shadowsocksX-NG.local" in domain for user gui: 501
  （退出码 113）
  $ launchctl error 113
  113: Could not find specified service
  ```

  即「job 是否已加载」的可靠判据是**退出码**（0 = 已加载；113 = 不存在），不是输出文本。
- **诚实边界（man 明文）**：`print` 的输出「is NOT API in any sense at all. Do NOT rely on the structure or information emitted for ANY reason. It may change from release to release without warning」（man launchctl, CAVEATS/IMPROTANT 注记）。2.0 应把 `launchctl` 当作命令行工具用退出码驱动状态机，**不得解析 print 的输出结构**；需要属性明细（如 PID）时只用于诊断展示，不作为逻辑分支依据。
- `launchctl print-disabled gui/<uid>`「Prints the list of disabled services in the specified domain」——列出该域 Disabled override 状态。本机实测两条 Legacy 记录仍在：

  ```text
  "com.qiuyuzhou.shadowsocksX-NG.http" => enabled
  "com.qiuyuzhou.shadowsocksX-NG.local" => enabled
  ```

  按 man launchctl 对 `load -w` 的说明，Disabled 覆盖状态「stored elsewhere on-disk in a location that may not be directly manipulated by any process other than launchd」——所以即使 plist 与 job 都已消失，记录仍保留（本机正是此形态）。它的用途是「曾经注册过 Legacy」的正向信号，不是运行状态。

### 2.2 磁盘残留 plist 与官方只读状态 API

- 文件检查：`~/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.local.plist`、`.http.plist`（及历史的 `.kcptun.plist`）的 `FileManager.fileExists`。这是纯粹的正向识别——文件名即产品固定常量。
- **`SMAppService.statusForLegacyURL:`（macOS 13+）**，SDK 头文件注释（SMAppService.h，本机 SDK 实读）：「Valid URLs have the prefix /Library/LaunchDaemons /Library/LaunchAgents or /Users/$USER/Library/LaunchAgents」「intended for apps that are unable to adopt the new daemon and agent packaging guidelines but still want to know when a user disables its legacy daemons or agents」。它返回 `SMAppServiceStatus`（notRegistered/enabled/requiresApproval/notFound），是对 `~/Library/LaunchAgents` 下 legacy plist 的官方只读状态查询。文档没有写明是否允许查询**第三方** plist；2.0 可以把「自家 plist 路径查询」作为快路径，把第三方 plist 的可用性列为遗留验证（§9），不能作为唯一判据。
- 残留 plist 的**活跃性检查（必须做）**：读 plist 内容判断是否含 `KeepAlive`（历史版本曾生成，见 §1）与 `RunAtLoad`。含 KeepAlive 的残留会在每次登录自动拉起 ss-local 并在其退出后重启（launchd.plist(5)：KeepAlive=true 让 launchd 持续保持 job 运行，隐含 RunAtLoad）；无这两个 key 的残留（现行 Legacy 形态）登录时仅注册、不启动。两者都属「检测到残留时提示用户处理」（#7 决议），但前者要在提示中说明它在实际运行。

### 2.3 监听端口：来源与探测

- 端口值来源（按优先级）：① Legacy defaults 域 `com.qiuyuzhou.ShadowsocksX-NG` 的 `LocalSocks5.ListenPort`/`LocalHTTP.ListenPort`/`PacServer.ListenPort`（用户自定义值在这里，默认 1086/1087/1089，inventory §1）；② `~/Library/Application Support/ShadowsocksX-NG/ss-local-config.json` 的 `local_port` 与 `privoxy.config` 的 listen 地址（Legacy 实际生效值）。两者只读读取，均属 Legacy 数据——只读，不删改（#7 约束）。
- 运行时确认用两层探测：
  1. **lsof 监听者诊断**：`lsof -nP -iTCP:<port> -sTCP:LISTEN`。同用户进程无需 sudo（Legacy 两个 job 均为 per-user，本机实测三个默认端口均无监听、退出码 1、无输出）。它同时给出持有 PID，可反查是否为 `.local`/`.http` job 的实例（launchd job 的 PID 可由 `launchctl print` 输出对照，仅诊断用）。注意 lsof 对其他用户的进程不可见——Legacy job 与 2.0 同用户，此盲区不影响本场景；PAC 1089 的持有者是 Legacy GUI 进程，同为同用户，可见。
  2. **bind 探测**：对具体端口做一次 `bind()` 后立即关闭。**探测 socket 不得设置 `SO_REUSEPORT`**：Legacy ss-local 带 `--reuse-port` 运行，BSD 语义下同端口多绑定要求所有 socket 都设了 `SO_REUSEPORT`；设置了它的探测会在 Legacy 仍持端口时假成功。普通 `SO_REUSEADDR` 不受影响、探得的 `EADDRINUSE` 是真占用。（这也是 2.0 自身运行时的约束：sslocal 不得启用 reuse-port 类选项，否则与「端口冲突一律显式失败」的 #14 决议冲突。）
- `launchctl print` 的输出里没有端口信息（plist 无端口字段），所以「从 plist 字段读端口」不成立，必须走上述 defaults/生成文件 + 探测组合。

## 3. 停止与卸载

### 3.1 子命令选择与弃用状态

- man launchctl 把 `load | unload` 放在 **LEGACY SUBCOMMANDS** 节，并明示「Recommended alternative subcommands: bootstrap | bootout | enable | disable」。未从系统移除（Legacy 自己仍在用），但 2.0 的生产代码不应继承旧式接口。
- `bootout domain-target [service-path ...] | service-target`：「removes their definitions into the domain. Services may be specified as a series of paths or a **service identifier**」。**按 service target（`gui/<uid>/<label>`）bootout 不需要 plist 文件存在**，这正是「job 已加载但 plist 已缺失」错位情形的正确处置入口；按路径 bootout 则要求路径可解析。
- **bootout 的信号序列 man 页未文档化**（只承诺移除定义）。通行行为是 SIGTERM、超时后 SIGKILL，但按证据规则不把它当文档事实。需要显式、有文档的终止时，man 有 `kill signal-name | signal-number service-target`（「Sends the specified signal to the specified service if it is running」）。推荐顺序见 §8。
- `enable | disable`：「Once a service is disabled, it cannot be loaded in the specified domain until it is once again enabled. This state persists across boots」——仅用于显式需要「阻止再加载」的场景；#7 决议不要求，默认不做（多写一次 launchd 状态反而多一分与用户意图冲突的面）。
- KeepAlive job 被 bootout 的行为：job 定义被移出 domain 后，launchd 不再持有重启依据（KeepAlive 是 plist 键，launchd.plist(5)，随定义一起被移除）。Legacy 现行 plist 无 KeepAlive，此问不存在于主线；仅 2017 前残留 plist（§2.2）需要它——对这类残留同样适用 bootout。
- **SMAppService 注销不了第三方 agent（launchctl 是唯一接口的论证）**：SDK 头文件 SMAppService.h 明文——`agentServiceWithPlistName:`「The plistName must correspond to a plist in the **calling app's** Contents/Library/LaunchAgents directory」；`loginItemServiceWithIdentifier:`「must correspond to… the **calling app's** Contents/Library/LoginItems directory」。`unregister()` 是这些实例上的方法。即 SMAppService 的注册/注销面封闭在调用方 app 自己的 bundle 内，无法指向 `com.qiuyuzhou.shadowsocksX-NG.*` 这种手写在用户 LaunchAgents 目录的第三方 plist。（#3 研究已确立 2.0 自身走 SMAppService——那条结论不外推到 Legacy 卸载。）

### 3.2 两种错位情形的正确动作

| 情形 | 检测形态 | 2.0 的正确动作 |
| --- | --- | --- |
| job 已加载，plist 文件缺失 | `launchctl print gui/<uid>/<label>` 退出码 0；文件检查不存在 | `launchctl bootout gui/<uid>/<label>`（按 service target，无需路径）；随后按 §8 验证。**不**因文件缺失而跳过卸载——运行中的 job 正是占端口的那一个 |
| plist 残留，job 未加载 | 文件存在；print 退出码 113 | **不做任何 launchctl 操作、不删 plist**（#7：不自动删除）。先读内容判活跃性（§2.2）：无 KeepAlive/RunAtLoad 的残留是休眠的（登录仅注册不启动），不阻塞 2.0 启动，记入残留提示；含 KeepAlive 的残留会实际运行/占端口，若其端口与 2.0 冲突则按 #14 显式失败 + 残留提示（提示用户可手动 `launchctl bootout` 并删除该 plist，或交由后续票据裁决是否提供一次性经确认的清理动作） |

第三种组合（job 已加载且 plist 在）是主线：bootout 后 plist 留在磁盘，进入残留提示清单。

## 4. 旧 SMLoginItem helper（登录项）

### 4.1 现状与 API 边界（一手出处）

- `SMLoginItemSetEnabled` 在 SDK 头文件（SMLoginItem.h，本机实读）标注 `__OSX_DEPRECATED(10.6, 13.0, "Please use SMAppService instead")`，注释「Enable a helper application located in the main application bundle's Contents/Library/LoginItems directory… If false, the helper application will no longer be kept running」。Apple 文档页（JS 渲染未取到正文）同口径：macOS 13.0 弃用。
- `SMAppService.loginItem(identifier:)` 的 identifier「must correspond to the bundle identifier for a LoginItem that lives in the **calling app's** Contents/Library/LoginItems directory」（SMAppService.h）。**即 2.0 无法用现行 API 正向管理 Legacy helper（`com.qiuyuzhou.ShadowsocksX-NG.LaunchHelper`）的登录项**——它登记在 Legacy app 的 LoginItems 目录语境下。
- 登记入口仍是系统设置：`SMAppService.openSystemSettingsLoginItems`（macOS 13+）「Opens System Settings to the Login Items panel」——这是 2.0 可以合法调用的人工指引直达入口。

### 4.2 识别途径与诚实边界

- 可正向识别的静态事实：Legacy app bundle 是否存在于常见安装位置（`/Applications/ShadowsocksX-NG.app` 等，LaunchHelper 的启动逻辑本身也按这些位置找主 app，[AppDelegate.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/LaunchHelper/LaunchHelper/AppDelegate.m)）；bundle 内 `Contents/Library/LoginItems/LaunchHelper.app` 是否存在；defaults 域 `com.qiuyuzhou.ShadowsocksX-NG` 的 `LaunchAtLogin` 布尔（[LaunchAtLoginController.m L76](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAtLoginController.m#L75-L77) 在 SMLoginItemSetEnabled 成功后写入，可作意图信号，但不是系统登记的真值）。
- BTM 数据库（macOS 13+ 登录项统一存储）：`sfltool dumpbtm` 可列出记录（记录含 `Identifier`、`URL`、`Type`、`Disposition` 字段，第三方登录项按 bundle ID 可辨）。但本机实测该命令**触发了面向用户的系统管理员授权弹窗**（协调者确认），且 `man sfltool` 只把它描述为「tool for testing and debugging SharedFileList」，`dumpbtm` 子命令本身未文档化。**结论：sfltool 不能作为 2.0 应用内的无提示检测手段**——它需要管理员授权、输出格式无 API 承诺、子命令未文档化。
- 因此 2.0 对旧登录项的编程能力边界是：只能做**静态正向识别**（Legacy bundle/helper 文件存在性 + defaults 意图信号），无法可靠地以编程方式读取或改变系统登记状态。停用动作走人工路径：
  1. **首选（状态真值在系统设置）**：指引文案指向 系统设置 → 通用 → 登录项与扩展，在「登录时打开」/「允许在后台」中找到 ShadowsocksX-NG（或其 helper）条目并移除；可用 `openSystemSettingsLoginItems` 直达。
  2. **替代（若 Legacy app 仍在）**：启动 Legacy app 并在其偏好中关闭「登录时启动」——它会以弃用 API 把自己登记为 false（[LaunchAtLoginController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAtLoginController.m#L67-L82)）。语义上这是让「旧代码撤销旧登记」，最不容易误伤。
- 不采用：从 2.0 调用 `SMLoginItemSetEnabled(helperID, false)` 的跨 app 摸底——弃用 API 对「非本 app LoginItems 目录中的 identifier」的行为未文档化，且无法在本机构造已登记环境验证（Legacy 已不在本机登记，见 §7）。若未来要试，必须先在装有 Legacy 且已开登录项的机器上验证（§9）。

## 5. 系统代理：确认、改写与失败路径

### 5.1 没有所有者标记（本机实测）

`scutil --proxy` 的输出只有 `HTTPEnable/HTTPPort/HTTPProxy/HTTPSEnable/…/SOCKSEnable/ProxyAutoConfigEnable/ExceptionsList` 等配置键值，没有任何「由哪个应用写入」的标记：

```text
HTTPEnable : 1
HTTPPort : 64649
HTTPProxy : 127.0.0.1
ProxyAutoConfigEnable : 0
SOCKSEnable : 1
SOCKSPort : 64649
...
```

（本机当前指向 64649——是本机另一个代理软件的值，仅用于证明「系统代理可能是别的所有者写的」。）SystemConfiguration 公开 schema（SCSchemaDefinitions.h，#11 已引用）同样没有 ownership 键。**推论：2.0 无法从系统状态判断现有代理是不是 Legacy 写的**，所以「切换到 2.0」改写前必须：(a) 向用户明说将关闭/改写系统代理（#7 决议的告知义务）；(b) 按 #11 §4.3 的 ownership record 纪律——写入前保存原 Proxies 字典，只有当现有值与 Legacy 特征值匹配（如 PAC URL 恰为 `http://localhost:1089/proxy.pac` 或 SOCKS 指向 1086）时才按「Legacy 拥有」处理，不匹配则按「未知所有者」呈现冲突、请用户决定，而不是盲目覆盖。

### 5.2 「切换到 2.0」确认文案要点（非定稿）

- 说明系统代理的三个去向：关闭 Legacy 写入的代理（PAC/SOCKS/HTTP 键恢复为空或用户原值）；随后由 2.0 在代理健康时写入自己的配置（#11 的授权 SC 写入路径，需用户授权）。
- 说明顺序：先停 Legacy（job 卸载 + 提示退出 Legacy app），系统代理短暂处于「无代理/直连」态，之后 2.0 启动成功才改写；启动失败则系统代理停在「已清理」态而非指向死端口。
- 提示需要授权：改写系统代理会请求管理员授权（#11 的最小 helper 授权边界）。
- 提示退出 Legacy app：PAC 端口 1089 由 Legacy app 进程持有（§1），不退出会继续占用且其 PAC server 仍在。

### 5.3 失败路径（交叉引用 #11/#14）

- **Legacy 已停但系统代理仍指向旧端口**：若交接流程先停 job 后清理代理时中途失败（如授权被拒），系统代理指向已死的 1089/1086——表现为全网「打不开网页」。检测：2.0 下一次启动/每次代理停止时，按 ownership record 与 Legacy 特征值（1089 PAC URL、1086 SOCKS）识别「指向已知死端口的代理配置」，在诊断页呈现「系统代理指向已停止的 Legacy 端口」并给一键清理（走 #11 授权写入）。这是正交于 #14 健康门禁的一条**Legacy 特征恢复规则**，特征值是固定的（§1 的常量），识别是正向的。
- **2.0 自身异常退出后代理指向死端口**：#11 §4.2/§4.3 已定「崩溃恢复通过保存的 ownership URL/token 判断是否需要清理，不盲目覆盖」；#14 已定「绑定失败不写系统代理、健康门禁在 GUI」。2.0 重启时的门禁顺序：先健康检查端点，再决定改写系统代理——发现系统代理指向自己的旧 ownership 记录而端点不健康时，呈现「代理未运行，系统代理仍指向本应用（将无法上网）」并提供「关闭系统代理」或「启动代理」两键。
- 残留 plist（含 KeepAlive 变体）在交接后复发占端口：属 #14 的「端口冲突显式失败 + 指名端点」正常路径，错误信息附残留提示（§3.2）。

## 6. 显式排除的反模式（给理由）

| 反模式 | 排除理由 |
| --- | --- |
| 按进程名匹配 / `pkill` | #7 决议明文禁止。技术上也不必要：两个 job 有精确 label，`launchctl bootout gui/<uid>/<label>` 即可定位并终止；名字匹配会误伤同名的用户自有进程（`ss-local`、`privoxy` 都是第三方生态常见名），且绕过 launchd 的停止语义、留下「job 仍注册但实例被外杀」的脏状态 |
| 自动删除 Legacy 配置、二进制、日志、规则文件 | #7 决议明文（保留回退来源，CONTEXT.md「Legacy handoff…retaining Legacy data for rollback」）。且删除不可逆：`~/Library/Application Support/ShadowsocksX-NG/`、`~/.ShadowsocksX-NG/` 中含用户服务器凭据与规则，误删无法恢复。残留只提示、由用户处置 |
| 自动删除残留 LaunchAgent plist | plist 是 launchd 配置文件，删除动作落在用户文件系统；#7 决议将其列入「不自动删除」清单。2.0 的动作上限是：bootout 已加载 job（决议授权的两个）+ 提示用户手动删除 |
| 解析 `launchctl print` 输出结构作为 API | man launchctl 明文「This output is NOT API in any sense at all…may change from release to release without warning」。逻辑分支只允许依赖退出码（有 EXIT STATUS 文档承诺） |
| 用带 `SO_REUSEPORT` 的探测判端口空闲 | 会在 Legacy `--reuse-port` 监听存续时假成功（§2.3），直接破坏「确认旧监听端口释放后才能启动 2.0」的门禁 |
| `sfltool dumpbtm` 作为应用内检测 | 需管理员授权弹窗（本机实测）、子命令未文档化、输出无 API 承诺（§4.2） |

## 7. 本机验证（macOS 27.0 Build 26A428，arm64；macOS 15 行为以文档为准）

全部为只读操作；未 bootout/bootstrap/remove/kill 任何 job，未改系统状态。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 系统版本 | `sw_vers` | macOS 27.0 (26A428)；`launchctl managername` = Aqua；uid 501 |
| 两个 job 加载态 | `launchctl print gui/501/com.qiuyuzhou.shadowsocksX-NG.local` 与 `.http` | 均未加载：stderr `Could not find service "…" in domain for user gui: 501`，**退出码 113** |
| 错误码语义 | `launchctl error 113` | `113: Could not find specified service` |
| Disabled 覆盖残留 | `launchctl print-disabled gui/501` | 含 `"com.qiuyuzhou.shadowsocksX-NG.http" => enabled` 与 `"com.qiuyuzhou.shadowsocksX-NG.local" => enabled`——plist 已不存在但记录仍在，证实 override 库独立于 plist 存续 |
| LaunchAgents 目录 | `ls ~/Library/LaunchAgents/` | 无 `com.qiuyuzhou.shadowsocksX-NG*.plist`（本机无 plist 残留） |
| 系统代理形态 | `scutil --proxy` | 仅配置键值（HTTP/HTTPS/SOCKS → 127.0.0.1:64649，PAC off），无所有者信息（§5.1） |
| 端口监听诊断 | `lsof -nP -iTCP:1086/-iTCP:1087/-iTCP:1089 -sTCP:LISTEN` | 三者均无输出、退出码 1（无监听）；同用户诊断无需 sudo |
| man 页 | `man launchctl` / `man launchd.plist` | LEGACY SUBCOMMANDS（load/unload 推荐替代 bootstrap/bootout/enable/disable）、print 非 API 注记、enable/disable 持久化、FILES 列出 `~/Library/LaunchAgents`（§2/§3 引用） |
| SDK 头文件 | `xcrun --show-sdk-path` 下 ServiceManagement.framework/Headers | SMLoginItem.h：`SMLoginItemSetEnabled` `__OSX_DEPRECATED(10.6, 13.0, "Please use SMAppService instead")`；SMAppService.h：loginItem/agent 的「calling app's」限定、`statusForLegacyURL:` 合法前缀（§3.1/§4.1 引用） |
| BTM 数据库 | `sfltool dumpbtm` | **触发系统管理员授权弹窗（用户侧目视确认）**；本会话内命令最终返回成功（1133 行），其中无任何 `shadowsocks`/`qiuyuzhou` 记录（与本机「Legacy 已卸载干净」一致），记录含 `Identifier`/`URL`/`Type`/`Disposition` 字段可辨第三方登录项。结论按 §6：不作为 2.0 检测手段 |

与 macOS 15 的差异风险集中在：print-disabled/BTM 的呈现细节、sfltool 的授权模型、系统设置登录项面板结构——都只影响诊断展示层，不影响「退出码 + 精确 label + 文件存在性」的识别主干；列 §9 复核。

## 8. 明确建议（可交后续实现）

### 8.1 识别序列（用户选择「切换到 2.0」前展示状态用）

对每个 label（`…-NG.local`、`…-NG.http`；`…-NG.kcptun` 仅检测展示）：

1. `launchctl print gui/<uid>/<label>` → 退出码 0（已加载）/113（未加载），不解析输出文本。
2. `FileManager.fileExists` 检查 `~/Library/LaunchAgents/com.qiuyuzhou.shadowsocksX-NG.{local,http,kcptun}.plist`；存在则读内容，标记 `KeepAlive`/`RunAtLoad` 活跃性。
3. `launchctl print-disabled gui/<uid>` 查字符串包含（正向信号：曾注册过；仅提示用）。
4. Legacy app 存在性：`/Applications/ShadowsocksX-NG.app` 与其 `Contents/Library/LoginItems/LaunchHelper.app`；defaults `com.qiuyuzhou.ShadowsocksX-NG` 读 `LaunchAtLogin` 意图信号。
5. 端口来源：defaults 读 `LocalSocks5.ListenPort`/`LocalHTTP.ListenPort`/`PacServer.ListenPort`（缺省 1086/1087/1089）；再对每个具体端口跑 `lsof -nP -iTCP:<p> -sTCP:LISTEN`（展示持有 PID）。

### 8.2 停止/卸载序列（用户确认后执行；只针对两个决议授权的 job）

对每个 label（先 `.http` 后 `.local`，或逐个）：

1. `launchctl bootout gui/<uid>/<label>`（按 service target；plist 缺失时同样有效）。
2. 验证 job 卸载：`launchctl print gui/<uid>/<label>` 退出码 113。非 0 非 113 的失败原样呈现给用户（附 launchctl stderr）。
3. 若 print 仍为 0（未按预期移除，如系统版本行为差异）：用有文档的显式终止 `launchctl kill SIGTERM gui/<uid>/<label>` 后重复第 2 步；仍失败则停止流程并呈现错误，不升级为任何名字匹配。
4. bootout 的未文档化信号等待期内（§3.1）短暂轮询端口释放（下一步骤已覆盖，无需额外 sleep 逻辑上写死）。

### 8.3 端口释放确认（两个 job 各自端口 + PAC 端口）

1. 对 1086/1087（或 defaults 实际值）：`lsof -nP -iTCP:<p> -sTCP:LISTEN` 无输出，且无 `SO_REUSEPORT` 的 bind 探测成功后立即关闭（§2.3 语义约束）。
2. 对 PAC 端口 1089：**前置条件是用户已退出 Legacy app**（确认文案 §5.2 明示）；检测同上。Legacy app 仍在运行时不满足启动 2.0 的门禁，呈现等待状态。
3. 全部端口释放确认通过后，才允许 2.0 proxy runtime 绑定（衔接 #14 门禁：GUI 健康检查通过才写系统代理）。
4. 中途失败：保持「已卸载的 job 不回滚、端口未释放则不启动 2.0」的显式失败呈现（#14 语义），不自动重试 bootout。

### 8.4 旧登录项指引文案要点

- 主动识别成功（Legacy bundle 存在）时提示：「旧版 ShadowsocksX-NG 的开机自启动需手动关闭：打开 系统设置 → 通用 → 登录项与扩展，在列表中移除 ShadowsocksX-NG（或其 LaunchHelper）条目。」可附「打开系统设置」按钮（`openSystemSettingsLoginItems`）。
- 若 Legacy app 仍在：附替代路径「或打开旧版 ShadowsocksX-NG，在偏好设置中关闭『登录时启动』」。
- 2.0 不声明已自动关闭旧登录项；未识别到 Legacy bundle 时也说明「若曾使用旧版的开机自启动，请按上述步骤检查」。

### 8.5 系统代理确认/失败文案要点

- 确认（切换前，§5.2）：告知将关闭/改写系统代理、期间短暂直连、需要管理员授权、需退出旧版 app（PAC 端口占用者）。
- 失败（§5.3）：「系统代理指向已停止的旧版端口（127.0.0.1:1086/1089），可能导致无法上网」+ 一键清理（按 ownership/特征值识别后经授权写入清理）；2.0 自身异常退出后的恢复走 #11 ownership record + #14 健康门禁，不盲目覆盖未知所有者的代理配置。
- 遇到与 Legacy 特征值不匹配的现有代理（未知所有者）：呈现冲突并请求用户决定，不静默改写。

## 9. 遗留验证（实现前或首次接触真实 Legacy 环境时完成）

1. **macOS 15 复核**：`launchctl print` 未加载 job 的退出码是否仍为 113；print-disabled 输出形态；系统设置登录项面板结构；`statusForLegacyURL:` 对第三方 plist 的返回语义（官方未文档化，须实测后才可进入实现）。本报告实测均在 macOS 27.0。
2. **bootout 实弹验证**：在受控测试用户上安装 Legacy 并开启代理后执行 §8.2 序列，确认退出码序列、bootout 后进程退出、端口释放时序（本机无 Legacy job，无法演练）。
3. **`SMLoginItemSetEnabled(helperID, false)` 跨 app 探针**：仅在装有 Legacy 且已登记登录项的机器上验证弃用 API 能否撤销他 app 登记（预期不可靠，见 §4.2；验证通过也不进主路径，只作人工指引之外的尽力而为）。
4. **KeepAlive 时代残留 plist 实样**：构造一份带 `KeepAlive: true` 的 `.local.plist` 残留，验证 §2.2 的登录自动拉起行为与 §3.2 处置流程。
5. **kcptun 残留处置裁决**：是否把 `com.qiuyuzhou.shadowsocksX-NG.kcptun` 扩入可停用名单（当前按决议只提示不停止），需一个小决议。
6. **sfltool 授权行为**：macOS 15 上 `dumpbtm` 的授权要求是否与本机一致（本机已确认需要授权弹窗；该工具不进实现，仅记录）。

## 10. 对后续票据的明确约束

- 「决策：Legacy handoff 实现」（后续实现票据）：识别/停止/卸载/端口释放严格按 §8 序列；`launchctl` 只用退出码，不解析输出；探测 socket 禁用 `SO_REUSEPORT`；PAC 端口 1089 的释放以「用户退出 Legacy app」为前置。
- #5（UI）：切换确认文案按 §5.2/§8.5 要点起草；残留提示含 plist 活跃性与登录项指引（§8.4）。
- #11/#14 的所有权与门禁纪律不因交接而放宽：未知所有者的系统代理不覆盖；端口未释放不启动、不写系统代理。

本报告只新增研究文档；未修改 `Legacy/`、2.0 生产代码或仓库其他文件，未执行任何变更系统状态的操作。
