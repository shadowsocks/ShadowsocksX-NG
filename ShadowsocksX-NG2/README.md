# ShadowsocksX-NG2

ShadowsocksX-NG 的现代化重写版本。新工程的全部源码与构建配置放在本目录下。

依赖的二进制工具（sslocal、v2ray-plugin 等）不再以子模块方式在仓库内构建，而是直接复制外部项目发布好的可执行文件。HTTP 入站由 shadowsocks-rust 直接提供，2.0 不再携带 Legacy Privoxy。

旧版工程源码已从本仓库移除，归档在 [shadowsocks/ShadowsocksX-NG](https://github.com/shadowsocks/ShadowsocksX-NG) 的 [`legacy-v1`](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1) 分支下，仅供参考，不保证可构建。

## 工程结构

- `project.yml` — XcodeGen 工程定义，唯一事实来源。`.xcodeproj` 与 `App/Resources/Info.plist`、`*.entitlements`、`Tests/Info.plist` 都是生成物（已 gitignore），改工程结构一律改 `project.yml` 后重新生成。
- `App/` — app target 源码（SwiftUI 菜单栏 app，LSUIElement）。目录即分层，层内按功能分组：
  - `Composition/` — 组合根与进程生命周期：`@main`、依赖装配、应用形态与窗口激活策略。
  - `Application/` — 应用层（无 SwiftUI 视图）：`*Workflow/` 工作流 module（UI-facing interface 与实现协作者）、`ProxyRuntime/` 运行时控制器家族与事实投影、`Services/` LaunchAgent/登录项/helper/防火墙。
  - `Presentation/` — 跨功能表现层：错误呈现、被多个界面面共用的状态模型。
  - `UI/` — 视图层，按子视图分目录（`Workspace/`、`Home/`、`Servers/`、`Subscriptions/`、`Rules/`、`Settings/`、`Diagnostics/`、`StatusMenu/`，`Servers/Plugin/` 为插件管理子视图）。
  - `PlatformEffects/` — 平台效应 seam（协议 + InMemory 替身 + AppKit adapter），系统框架访问集中于此。
  - `Resources/` — `Info.plist`、`entitlements`（生成物）与 `Assets.xcassets`、`*.xcstrings`（入库）。

  分层边界由 `Tests/SkeletonTests.swift` 的正向圈定守卫断言：只扫描 `App/UI/`，视图层不得引用运行时控制器、工作流实现协作者或原始目录/凭据存储类型；新增运行时适配器放进 `Application/` 即自动落在扫描范围外，无需登记豁免。注意 `App/` 下任何非源码文件都会被 XcodeGen 收进 Resources 阶段并封进签名后的 bundle，因此文档不放 `App/`（`project.yml` 已排除 `**/*.md`）。分层与主题的组织方式、守卫为何取正面圈定、以及 XcodeGen 的上述约束见 [ADR-0029](../docs/adr/0029-source-layout-declares-layer-and-theme.md)。
- `Agent/` — 代理运行时 wrapper（独立可执行文件，装入 `Contents/MacOS/`，由 LaunchAgent 常驻）：读 `sslocal-active.json` 契约，以绝对路径启动和监管 sslocal（SIGTERM 链式停止、SIGUSR1 热重载/结构重启、崩溃时非零退出交 KeepAlive 重放，spec #21 D2/D5/D7）。PAC HTTP endpoint 已随 issue #67 移除。
- `LaunchAgent/` — `SMAppService.agent(plistName:)` 的注册清单，装入 `Contents/Library/LaunchAgents/`；`ProgramArguments` 用 bundle 相对路径，由 launchd 按注册 app 的 bundle 位置解析。
- `Domain/` — 领域核心（配置目录树、凭据引用与持久化，spec #21 D3/D5），与 UI 无关。目录即主题，根下不留平铺文件，子目录口径取自 `GLOSSARY.md` 的章节划分：
  - `Catalog/` — 配置目录树、结构不变量错误、目录文件存储、节点与凭据身份，以及 `ss://` 编解码 `SsUri`。
  - `Subscription/` — 订阅文档解析、抓取、订阅记录与刷新失败。
  - `Rules/` — 代理模式、规则身份与匹配、内置规则快照、规则集合/浏览/分析、离线规则测试；`Rules/Custom/` 为用户自定义规则的编辑草稿、校验与存储。
  - `Runtime/` — 代理运行服务：运行时文档与监听设置、ACL 与部署收据、路径、原子写入、文件存储、日志与事件、端点/端口/socket 探针。
  - `Activation/` — 激活候选校验、激活状态机与 `RuntimeConfiguration`。
  - `Settings/` — 用户设置的持久化：代理设置、监听设置、静默启动。
  - `SystemProxy/` — 系统代理 typed 配置、property list 映射、计划器与特权 helper 的 XPC 契约/请求引擎。
  - `Plugin/` — 托管插件、用户插件映射与插件安全校验。
  - `Credentials/`、`LegacyImport/`、`Diagnostics/` — 凭据存储与写入日志、旧版导入、诊断报告。

  跨进程契约按**文件**编入其它 target：`Runtime/` 的 9 个文件同时编入 wrapper（`RuntimePaths`、`SslocalRuntimeDocument`、`RuntimeLog` 等），`SystemProxy/` 全部 6 个文件编入特权 helper。`project.yml` 里这 15 条是显式路径，在 `Domain/` 内移动文件必须同步，漏改会让 `xcodegen generate` 以缺文件直接失败。布局守卫（`Tests/Architecture/SkeletonTests.swift` 的 `DomainLayoutTests`）断言根下无平铺 `.swift`、树下只有 `.swift`（非源码文件会被 XcodeGen 收进 Resources 阶段并封进签名后的 bundle）。
- `Tests/` — 单元测试 target，随 `ShadowsocksX-NG2` scheme 运行。目录即主题，根下不留平铺测试文件：
  - `Architecture/` — 跨切面工程约束守卫（分层与布局、平台效应 seam、开窗落点、清单完整性），扫源码或构建产物而不驱动行为。
  - `Support/` — 夹具、替身与 helper，不含用例（`CatalogFixtures`、`ProxyRuntimeFixture`、`SystemProxyFakes`、`AppArtifact`、`TestSourceTree` 等）。
  - `Agent/`、`Activation/`、`Catalog/`（工作流用例在 `Catalog/Workflow/`）、`Subscription/`、`Rules/`（自定义规则在 `Rules/Custom/`）、`ProxyRuntime/`、`ProxyControl/`、`Runtime/`、`Settings/`、`SystemProxy/`、`Plugin/`、`Diagnostics/`、`Credentials/`、`Workspace/`、`Servers/` — 按功能领域的用例，与生产代码的领域主题和 `*Workflow` 同名同界。
  - `Smoke/` — 真实进程冒烟，独立 target 与 scheme（`task test:smoke`）。
  - `Fixtures/RuleSnapshots/` — 生成的内置规则快照夹具，作为 folder resource 随测试 bundle 发布（`GeneratedRuleSnapshotTests` 按 `subdirectory:` 读）。

  断言需要读源码树（`Vendor/` 清单、`App/`、`Domain/`）时一律经 `Support/TestSourceTree.swift` 从 `#filePath` 沿父目录上溯定位 `ShadowsocksX-NG2/`，不写死父目录层数——测试文件处于不同深度，写死层数会在文件移动后静默指错。布局守卫 `TestsLayoutTests` 只断言根层无平铺 `.swift`（比 `Domain/` 那条弱一档：根层的 `Info.plist` 与 `Fixtures/` 下的 JSON 都必须在）。`Tests/Support/AppArtifact.swift` 同时编入 Smoke target，是 `project.yml` 里的显式文件路径，移动需同步。
- `Vendor/<name>/manifest.json` — 外部二进制的固定供应链清单（tag + 资产 URL + 资产 SHA-256 + bundle 内位置 + 签名 identifier）；二进制本体与 `.fetched.sha256` 戳是构建缓存，不入库。
- `Vendor/rules/geolocation-cn/` — 内置中国域名规则快照（issue #63）：`snapshot.json`（规范化规则 + 元数据 + 损失报告）、`manifest.json`（上游版本与快照 SHA-256）、`NOTICE`（许可证与归属）。普通构建只读本地快照，绝不抓取或转换。
- `Vendor/rules/china-ipv4/` — 内置中国 IPv4 CIDR 直连候选快照（issue #64）：同上三件套，来源为 [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) `china.txt` 固定 commit。规则模式的 `proxy_all` ACL 同时编入中国域名与 IPv4 CIDR 直连候选。
- `Vendor/rules/gfwlist/` — 内置 GFWList 代理候选快照（issue #65）：同上三件套，来源为 [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) 官方 Base64 AutoProxy `gfwlist.txt` 固定 commit。域名锚点转换为后缀匹配，满足条件的空路径或根路径 URL 前缀转换为精确域名匹配；「未匹配时直连」的 `bypass_all` ACL 编入这些代理候选。
- `Scripts/` — 供应链脚本（见下节）与打包门槛断言；另有 `update-geolocation-cn.sh` / `update-china-ipv4.sh` / `update-gfwlist.sh`（显式维护动作，抓取固定版上游并转换）与 `verify-rule-snapshots.sh`（构建前离线校验快照完整性）。

## 外部二进制供应链

外部二进制只用上游官方构建产物：`sslocal`（shadowsocks-rust v1.25.0，装于 `Contents/Helpers/`）、`v2ray-plugin`（v1.3.2）与 Cloak `ck-client`（v2.12.0，两个插件均装于 `Contents/Helpers/Plugins/`）。信任根是提交在库里的清单哈希；构建链如下（spec #21 D6/D10）：

1. **fetch** — `Scripts/fetch-external-binaries.sh` 下载清单固定 URL 的资产、逐字节校验 `archiveSHA256`，按 `assetFormat` 处理 tar 归档（默认，提取 `archiveMember`）或直接二进制（`binary`），并确认 arm64，落盘 `Vendor/<name>/` 并记录戳。资产哈希不符 → 立即失败；本地缓存漂移或清单变更 → 自动重新下载复验。
2. **generate** — `xcodegen generate` 把清单对应二进制作为 Copy Files 项装入 `Contents/Helpers[/Plugins]`。注意顺序：**先 fetch 再 generate**，文件在生成时必须已存在，否则 Copy Files 阶段会被静默丢弃（generate 也会直接报缺文件）。
3. **verify on every build** — 预构建脚本阶段重跑 fetch 脚本（缓存命中时只对本地戳快速复验），哈希或清单漂移使构建即失败。
4. **sign** — `Scripts/sign-embedded-helpers.sh`（post-build 阶段）对每个二进制 Developer ID 重签：`--options runtime --timestamp --identifier <清单 signIdentifier>`（插件形如 `<bundle-id>.plugin.<name>`）；随后 Xcode 完成 app 外层签名，封存重签后的嵌套代码。
5. **gate** — 构建产物必须过 `Scripts/packaging-gate.sh <App.app>`：嵌套代码签名严格校验、主应用 DevID + Hardened Runtime 且无 App Sandbox entitlement、逐二进制清单覆盖（Helpers 下每个 Mach-O 都在清单内且 DevID 重签通过）。篡改任一二进制会因签名失效被断言发现。

## 签名与运行形态基线

- bundle id `com.qiuyuzhou.ShadowsocksX-NG2`，与 Legacy（`com.qiuyuzhou.ShadowsocksX-NG`）区分；运行时数据落 `~/Library/Application Support/ShadowsocksX-NG2/`。macOS 15+ / arm64。
- Hardened Runtime（DevID 发布路径；免证书的 ad-hoc Debug 例外，见下）；不启用 App Sandbox，entitlements 为空 dict；签名样式固定 `Manual`。
- **证书与 Team 都不入库**（开源仓库）：`project.yml` 不含 `CODE_SIGN_IDENTITY` / `DEVELOPMENT_TEAM`，两个键由 project xcconfig 按 config 在构建期注入：
  - `Configs/Signing-Debug.xcconfig`（入库）基线是 **ad-hoc（`-`）**：新 clone 与 CI 不需要任何证书就能 `task build` / `task test`。arm64 要求代码至少有 ad-hoc 签名才会被加载，所以「免证书」不是「不签名」。ad-hoc 产物不带 Hardened Runtime（Xcode 对 ad-hoc 签名不传 `-o runtime`，实测；`Scripts/sign-embedded-helpers.sh` 的 ad-hoc 分支同样不加），Hardened Runtime 由 DevID 发布路径与打包门槛断言。
  - `Configs/Signing-Release.xcconfig`（入库）基线是 **Developer ID Application**：发布产物必须真签名，这里不给免证书路径。
  - 两者都可选包含 `Configs/Signing.local.xcconfig`（gitignore）。有证书的人（含维护者）用它升级本机身份，例如让 Debug 也走 Developer ID：

    ```bash
    cat > Configs/Signing.local.xcconfig <<'EOF'
    DEVELOPMENT_TEAM = YOUR_TEAM_ID
    CODE_SIGN_IDENTITY = Developer ID Application
    EOF
    ```

  - 该文件缺失时 Debug 构建为 ad-hoc（可跑单测），Release 构建以 Xcode 的「Signing for … requires selecting either a development team or a provisioning profile」明确失败，不静默降级。
  - 测试 target（单测与冒烟）身份随同一基线：去宿主化（ADR-0021）后 xctest 包不再注入宿主 app，ad-hoc 也能加载执行（实测），因此测试无需证书。
  - 注意 `project.yml` 一旦重新设置这两个键，pbxproj 构建设置会盖掉 xcconfig（`Tests/Architecture/SigningConfigurationTests.swift` 守卫该约束）。
- Release 配置关闭 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`，保证发布产物 entitlements 只来自项目文件。

## 开发、构建与测试

在本目录内，日常格式化、静态检查、工程生成、构建和测试优先使用 `Taskfile.dist.yml` 定义的任务：

```bash
task format
task lint
task lint:fix  # 需要自动修复 SwiftLint 违规时使用；执行后再运行 task lint
task gen:prj   # 生成 Xcode 工程
task build     # 构建 Debug 版本 app
task test      # 运行单元测试（不含真实进程冒烟）
task test:smoke  # 运行真实进程冒烟测试（拉起真实 sslocal，见下节发布门槛）
```

`task format` 会格式化 `App/`、`Tests/`、`Domain/` 和 `Agent/` 下的 Swift 文件；`task lint:fix` 会修改源文件，执行后检查并复核 diff。

新 clone 或清单变更后，在本目录内先取外部二进制，再生成工程（顺序不可颠倒）：

```bash
Scripts/fetch-external-binaries.sh
task gen:prj
```

无证书也能构建与跑单测：Debug 基线是 ad-hoc，不需要 `Configs/Signing.local.xcconfig`。只有要做 Developer ID 签名（发布，或让本机 Debug 产物过打包门槛）时才写该文件，内容见上节「签名与运行形态基线」。

`Tests/Smoke/` 是真实进程冒烟（经 wrapper 拉起真实 sslocal 验证启动、握手、
ACL 路由与插件监管），不在默认 `task test` 内，由独立 scheme 按需运行。

发布前运行发布门槛检查：

```bash
# 发布门槛（必须全绿）：真实进程冒烟 + 打包门槛
task test:smoke
Scripts/packaging-gate.sh \
  .build/derivedData/Build/Products/Debug/ShadowsocksX-NG2.app
```

打包门槛只接受 Developer ID 签名的产物：Team 期望值取自 `Configs/Signing.local.xcconfig`（可用 `EXPECTED_TEAM_ID=<Team ID>` 显式覆盖），两者都没有时该断言直接失败，不静默跳过。无证书的 ad-hoc Debug 产物会在此明确失败（`gate: hint` 会说明原因），这是预期行为。

## 代码风格工具

- `swift format` 随 Xcode/Swift 工具链提供，无需单独安装（基线：Apple Swift 6.4）；SwiftLint 需 `brew install swiftlint`（基线 0.65.0）。工具缺失时，含本目录 Swift 文件的提交会被 pre-commit 钩子拒绝而不是放行。
- 配置文件：`.swift-format` 是 Swift 6.4 工具链默认规则的快照（固定成文件，工具链升级不漂移）；`.swiftlint.yml` 默认规则起步，只声明排除项与个别和 format 基线冲突的关闭项（文件内有触发案例注释）。
- 仓库级 `pre-commit` 钩子的启用方式和检查范围见根目录 [`README.md`](../README.md)。
- 调整规则只针对实际痛点：修改 `.swift-format` / `.swiftlint.yml` 的 PR 须给出触发案例，并同步更新本节中的基线版本。

## 订阅资料

订阅可在 SIP-008 JSON 根级提供 `bytes_used`、`bytes_remaining`（非负整数，最大为 UInt64），以及自定义的 `expires_at`（服务到期时间）、`traffic_reset_at`（流量重置时间）。日期值使用 RFC 3339 字符串，省略或 `null` 表示未提供；无效资料仅忽略该项，不影响有效服务器或分组资料。

成功刷新完整替换白名单订阅资料，省略或无效的字段清除旧值；失败或取消保留最后成功资料与独立成功时间。资料和目录记录同文档原子保存，不另存原始响应或含密码的服务器明文快照；密码和插件参数沿用 Keychain 存储。旧目录文件缺少成功时间时不猜测。

订阅卡片显示返回的有效资料；仅在两项流量都有效且总量大于零时显示消耗进度。日期按用户当前语言与时区显示，到期和重置资料不改变代理启停或激活行为。

## 内置规则快照

规则模式使用的内置快照是显式维护产物：

- **geolocation-cn**（issue #63）：人工复验上游后运行 `Scripts/update-geolocation-cn.sh`，从固定版 [Loyalsoldier/domain-list-custom](https://github.com/Loyalsoldier/domain-list-custom) `geosite.dat` 解析 typed 条目并生成 `Vendor/rules/geolocation-cn/snapshot.json`。
- **china-ipv4**（issue #64）：运行 `Scripts/update-china-ipv4.sh`，从固定版 [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) `china.txt` 规范化并去重 IPv4 CIDR，生成 `Vendor/rules/china-ipv4/snapshot.json`。
- **gfwlist**（issue #65）：运行 `Scripts/update-gfwlist.sh`，从固定版 [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) `gfwlist.txt` 解码官方 Base64 AutoProxy 列表并生成 `Vendor/rules/gfwlist/snapshot.json`。`||host` / `||host^` 转换为域名后缀匹配；`|scheme://host`（可含合法端口）在路径为空或仅为 `/`，无查询、fragment 或用户信息，且 host 为无通配符的合法域名时，提取 host 转换为精确域名匹配，忽略协议和端口。仅含根路径 `/` 可转换，包含具体路径的规则继续跳过。`@@` 保留直连动作。其他 URL 前缀、路径、通配符、正则、单标签前缀与 IP 字面量规则逐类计入损失报告。被代理规则完全覆盖的 `@@` 例外不写入无效 ACL 项（sslocal 域名匹配 proxy_list 优先于 bypass_list），保留代理规则，遮蔽数只计入 `absorbedCount`；逐条取证输出到维护脚本 stdout。

快照使用 schema 2 / converter 2.0.0 的紧凑 JSON：每条规则只有 `action` 和 `match`，来源只在 `metadata.source`，转换报告只保留计数。被吸收的 `.cn` 条目与被遮蔽的 GFWList 例外不随快照分发，禁用宽规则后不再恢复；详见 [ADR-0024](../docs/adr/0024-snapshot-drops-absorbed-and-forensics.md)。旧版本快照拒载。

Python 是唯一的上游转换实现；Swift 只加载、校验并消费快照，不另行解析上游输入。转换脚本的离线回归检查：`PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test-rule-snapshot-converters.py`。默认 `task test` 也会运行两组 Python 检查；可单独运行 `task test:rules`。另运行 `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test-rule-conversion-behavior.py`，验证转换行为和单测 bundle 使用的固定快照夹具。审查转换变化后，可通过同一命令加 `--write-fixtures` 重建夹具。夹具时间固定，正常测试逐字节检查生成结果。快照完整性检查：`Scripts/verify-rule-snapshots.sh`。

更新失败保留上一份有效快照。geolocation-cn 转换会因未知语法/损坏输入失败；china-ipv4 转换还会因异常格式（拒绝率过高）、全部失效或相对上一份快照的异常规模变化失败；gfwlist 转换因未知语法、损坏 Base64、异常规模或相对上一份快照的异常规模变化失败。普通构建由 `Scripts/verify-rule-snapshots.sh` 离线校验快照存在、摘要匹配且 schema/转换器版本一致，缺失或损坏即构建失败。分发物必须携带各自的 `NOTICE`（许可证与归属）。

规则模式「未匹配时代理」生成的 `proxy_all` ACL 同时包含中国域名与中国 IPv4 CIDR 直连候选，固定本地绕过优先。规则模式「未匹配时直连」生成的 `bypass_all` ACL 只编入 GFWList 可生效代理候选；两种默认动作不把全部内置来源无条件并集。未匹配目标与无可用规则命中的 IP 字面目标直连。**CIDR 判定可能触发本地 DNS 查询**：sslocal 为未命中域名做 IP 匹配时可能发起本地 DNS 查询，产品不承诺 DNS 查询均经远端 Shadowsocks 服务器。

## 依赖升级

升级任一外部二进制是显式供应链动作：人工复验新 release（下载归档、静态观测哈希/架构/签名，不执行），随后在一次 PR 中同时改 `Vendor/<name>/manifest.json` 的 release/asset/url/archiveSHA256 与对应测试锚点。不接受 `latest`，不在仓库内构建，不做应用内更新通道（升级仅随 app 发版）。

### 用户插件目录

`PluginCatalog` 合成当前托管清单与本机 `plugins.json` 用户记录，名称精确区分大小写。用户映射优先，失效 override 不退回托管程序；删除 override 恢复当前 app 默认值。文件读取错误保留阻断事实，不按空映射处理。用户路径、本地启动参数与插件传输模式不进入服务器资料、订阅或分享文件。用户路径也不进入诊断报告。

设置页底部的“插件”区域统一展示内置与用户插件，按记录展示全部名称，支持新增、编辑名称集合与路径、逐名称覆盖内置、删除记录与恢复同名内置。用户与内置记录可以设置插件传输模式 `tcp_only` 或 `tcp_and_udp`；默认 `tcp_only`，生成 sslocal 配置时省略 `plugin_mode`。应用不探测插件的 SIP003u 支持。内置编辑器中的“清空参数”只清空草稿启动参数并保留模式，保存后生效。名称与启动参数使用列表编辑，启动参数保留顺序和完整字符串；路径支持手动输入与文件选择。读取失败时隐藏条目并提供只读重试，管理 UI 不提供整体重置。映射提交与显式修复 interface 在组合根统一接入表单、激活与诊断。保存成功后刷新激活候选并异步收敛，运行失败不撤销保存。没有文件替换监控。`plugins.json` v1 每项独立迁移为带持久身份的用户记录，下一次保存写入 v2，不按相同路径合并。现有内置程序同时提供 `v2ray-plugin` 和 `v2ray-plugin-v1`。详见 [ADR-0033](../docs/adr/0033-plugin-records-own-aliases-and-local-arguments.md)。

`MacOSPluginInspection` 只读取下载隔离、签名与系统评估事实，不启动用户插件、不修改系统策略。检查失败或不适用为未知；策略评估拒绝不等于实际执行禁令，也不阻止映射保存或激活。真实 macOS 拦截提示不由 hostless 替身测试证明。

## Cloak 托管插件

随应用提供官方 [Cloak v2.12.0](https://github.com/cbeuw/Cloak/releases/tag/v2.12.0) 的 darwin-arm64 `ck-client`，服务器引用名称为 `cloak` 或 `cloak-v2`，两者共享一条内置记录。`ck-client` 是打包文件名，不是可引用名称。同名用户插件仍优先；失效覆盖不会自动回退到内置程序。

服务器插件选项原样传给上游，不进行 Cloak 字段语义校验。可以使用分号分隔的 `Key=value` 参数，或使用外部 JSON 配置文件的绝对路径。外部文件由用户维护，应用不复制文件、不管理文件凭据或生命周期；分享路径不包含文件内容，接收方需要自行提供对应文件。本地启动参数仍独立保存，不随服务器资料分享。

[固定版本配置解析](https://github.com/cbeuw/Cloak/blob/v2.12.0/internal/client/state.go)存在以下限制：只有同时含 `;` 和 `=` 的字符串才被识别为参数列表，单个 `Key=value` 会被当作文件路径；转义分号仍会被切分，引号和反斜杠也不能按通用 SIP003 转义方式可靠传递；空段会终止后续解析。需要复杂值时可自行维护 JSON 文件。提供 `UID`、`PublicKey`、`ServerName`、`EncryptionMethod`，并按需显式设置 `NumConn=4`，不能依赖 README 所述的默认 4；省略时固定版本实现关闭连接复用。显式端点字段会覆盖 SIP003 环境变量，因此通常应省略 `LocalHost`、`LocalPort`、`RemoteHost`、`RemotePort`。

默认插件传输模式为 `tcp_only`。上游 `UDP=true` 切换为 UDP 监听，不代表同时承载 TCP 与 UDP 的 SIP003u 支持；应用仍允许用户设置现有传输模式，本次只验收 TCP 配置接入。托管程序的 GPL-3.0 许可证、来源与第三方声明随应用装入 `Contents/Resources/ThirdParty/Cloak/`，源码与构建入口见其中 NOTICE。
