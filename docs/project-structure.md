# 工程结构与源码搜索

[返回工程首页](../ShadowsocksX-NG2/README.md)

除特别说明外，命令从 `ShadowsocksX-NG2/` 执行，文中工程路径也相对于该目录。

## 工程结构

- `project.yml` — XcodeGen 工程定义，唯一事实来源。`.xcodeproj` 与 `App/Resources/Info.plist`、`*.entitlements`、`Tests/Info.plist` 都是生成物（已 gitignore），改工程结构一律改 `project.yml` 后重新生成。
- `App/` — app target 源码（SwiftUI 菜单栏 app，LSUIElement）。目录即分层，层内按功能分组：
  - `Composition/` — 组合根与进程生命周期：`@main`、依赖装配、应用形态与窗口激活策略。
  - `Application/` — 应用层（无 SwiftUI 视图）：`*Workflow/` 工作流 module（UI-facing interface 与实现协作者）、`ProxyRuntime/` 运行时控制器家族与事实投影、`Services/` LaunchAgent/登录项/helper/防火墙。
  - `Presentation/` — 跨功能表现层：错误呈现、被多个界面共用的状态模型。
  - `UI/` — 视图层，按子视图分目录（`Workspace/`、`Home/`、`Servers/`、`Subscriptions/`、`Rules/`、`Settings/`、`Diagnostics/`、`StatusMenu/`，`Servers/Plugin/` 为插件管理子视图）。
  - `PlatformEffects/` — 平台效应 seam（协议 + InMemory 替身 + AppKit adapter），系统框架访问集中于此。
  - `Resources/` — `Info.plist`、`entitlements`（生成物）与 `Assets.xcassets`、`*.xcstrings`（入库）。

  分层边界由 `Tests/Architecture/SkeletonTests.swift` 的正向圈定守卫断言：只扫描 `App/UI/`，视图层不得引用运行时控制器、工作流实现协作者或原始目录/凭据存储类型；新增运行时适配器放进 `Application/` 即自动落在扫描范围外，无需登记豁免。注意 `App/` 下任何非源码文件都会被 XcodeGen 收进 Resources 阶段并封进签名后的 bundle，因此文档不放 `App/`（`project.yml` 已排除 `**/*.md`）。分层与主题的组织方式、守卫为何取正面圈定、以及 XcodeGen 的上述约束见 [ADR-0029](adr/0029-source-layout-declares-layer-and-theme.md)。
- `Agent/` — 独立的后台监管可执行文件，装入 `Contents/MacOS/`，由 LaunchAgent 常驻。只读取非秘密 `agent-supervision.json`，切换稳定配置与 ACL 链接，启动和监管 sslocal；不解析 sslocal 配置或 LAN 凭据。发布与失败处理见 ADR-0037、ADR-0038，GUI 单向配置输出见 ADR-0043。
- `LaunchAgent/` — `SMAppService.agent(plistName:)` 的注册清单，装入 `Contents/Library/LaunchAgents/`；`ProgramArguments` 用 bundle 相对路径，由 launchd 按注册 app 的 bundle 位置解析。
- `Domain/` — 领域核心（配置目录树、凭据引用与持久化，spec #21 D3/D5），与 UI 无关。目录即主题，根下不留平铺文件，子目录口径取自 [术语表](../GLOSSARY.md) 的章节划分：
  - `Catalog/` — 配置目录树、结构不变量错误、目录文件存储、节点与凭据身份，以及 `ss://` 编解码 `SsUri`。
  - `Subscription/` — 订阅文档解析、抓取、订阅记录与刷新失败。
  - `Rules/` — 代理模式、规则身份与匹配、内置规则快照、规则集合/浏览/分析、离线规则测试；`Rules/Custom/` 为用户自定义规则的编辑草稿、校验与存储。
  - `Runtime/` — 代理运行服务：运行时文档与监听设置、ACL 与部署收据、路径、原子写入、文件存储、日志与事件（统一日志发射单元 `SystemLog`、统一日志行 `LogLine`、sslocal 输出 intake）、端点/端口/socket 探针。
  - `Activation/` — 激活候选校验、激活状态机与 `RuntimeConfiguration`。
  - `Settings/` — 代理监听配置文件、独立代理控制偏好、运行计算的内存快照与静默启动偏好。
  - `SystemProxy/` — 系统代理 typed 配置、property list 映射、计划器、特权 helper 的 XPC 契约/请求引擎与 helper 侧日志事件。
  - `Plugin/` — 托管插件、用户插件映射与插件安全校验。
  - `Credentials/`、`LegacyImport/`、`Diagnostics/` — 主密钥存储与加密文件提交、旧版导入、诊断报告。

  跨进程契约按**文件**编入其它 target：`Runtime/` 的 9 个文件和 `Settings/ApplicationSupportPaths.swift` 同时编入 wrapper（`RuntimePaths`、`RuntimeSupervision`、`RuntimeLog`、`SystemLog`、`LogLine`、`SslocalOutputIntake` 等），`SystemProxy/` 全部 7 个文件连同 `Runtime/SystemLog.swift` 编入特权 helper（helper 侧日志只进统一日志，ADR-0047）。`project.yml` 里这 18 条是显式路径，在 `Domain/` 内移动文件必须同步，漏改会让 `xcodegen generate` 以缺文件直接失败。布局守卫（`Tests/Architecture/SkeletonTests.swift` 的 `DomainLayoutTests`）断言根下无平铺 `.swift`、树下只有 `.swift`（非源码文件会被 XcodeGen 收进 Resources 阶段并封进签名后的 bundle）。
- `Tests/` — 单元测试 target，随 `ShadowsocksX-NG2` scheme 运行。目录即主题，根下不留平铺测试文件：
  - `Architecture/` — 跨切面工程约束守卫（分层与布局、平台效应 seam、开窗落点、清单完整性），扫源码或构建产物而不驱动行为。
  - `TestSupport/` — 测试等待与清理 helper 的故障回归用例。
  - `Support/` — 夹具、替身与 helper，不含用例（`CatalogFixtures`、`ProxyRuntimeFixture`、`SystemProxyFakes`、`AppArtifact`、`TestSourceTree` 等）。
  - `Agent/`、`Activation/`、`Catalog/`（工作流用例在 `Catalog/Workflow/`）、`Subscription/`、`Rules/`（自定义规则在 `Rules/Custom/`）、`ProxyRuntime/`、`ProxyControl/`、`Runtime/`、`Settings/`、`SystemProxy/`、`Plugin/`、`Diagnostics/`、`Credentials/`、`Workspace/`、`Servers/` — 按功能领域的用例，与生产代码的领域主题和 `*Workflow` 同名同界。
  - `Smoke/` — 真实进程冒烟，独立 target 与 scheme（`task test:smoke`）。
  - `Fixtures/RuleSnapshots/` — 生成的内置规则快照夹具，作为 folder resource 随测试 bundle 发布（`GeneratedRuleSnapshotTests` 按 `subdirectory:` 读）。

  断言需要读源码树（`Vendor/` 清单、`App/`、`Domain/`）时一律经 `Support/TestSourceTree.swift` 从 `#filePath` 沿父目录上溯定位 `ShadowsocksX-NG2/`，不写死父目录层数——测试文件处于不同深度，写死层数会在文件移动后静默指错。布局守卫 `TestsLayoutTests` 只断言根层无平铺 `.swift`（比 `Domain/` 那条弱一档：根层的 `Info.plist` 与 `Fixtures/` 下的 JSON 都必须在）。`Tests/Support/AppArtifact.swift` 同时编入 Smoke target，是 `project.yml` 里的显式文件路径，移动需同步。
- `Vendor/<name>/manifest.json` — 外部二进制的固定供应链清单（tag + 资产 URL + 资产 SHA-256 + bundle 内位置 + 签名 identifier）；二进制本体与 `.fetched.sha256` 戳是构建缓存，不入库。
- `Vendor/rules/geolocation-cn/` — 内置中国域名规则快照（issue #63）：`snapshot.json`（规范化规则 + 元数据 + 损失报告）、`manifest.json`（上游版本与快照 SHA-256）、`NOTICE`（许可证与归属）。普通构建只读本地快照，绝不抓取或转换。
- `Vendor/rules/china-ipv4/` — 内置中国 IPv4 CIDR 直连候选快照（issue #64）：同上三件套，来源为 [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) `china.txt` 固定 commit。规则模式的 `proxy_all` ACL 同时编入中国域名与 IPv4 CIDR 直连候选。
- `Vendor/rules/gfwlist/` — 内置 GFWList 代理候选快照（issue #65）：同上三件套，来源为 [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) 官方 Base64 AutoProxy `gfwlist.txt` 固定 commit。域名锚点转换为后缀匹配，满足条件的空路径或根路径 URL 前缀转换为精确域名匹配；「未匹配时直连」的 `bypass_all` ACL 编入这些代理候选。
- `Scripts/` — 供应链脚本（见[外部二进制供应链](distribution.md#外部二进制供应链)）与打包门槛断言；另有 `update-geolocation-cn.sh` / `update-china-ipv4.sh` / `update-gfwlist.sh`（显式维护动作，抓取固定版上游并转换）与 `verify-rule-snapshots.sh`（构建前离线校验快照完整性）。

### 源码搜索

先按上面的目录分层用 `rg --files` 定位，再限定目录或文件类型搜索内容；未找到时逐步扩大范围。以下命令从 `ShadowsocksX-NG2/` 执行：

```sh
# 查外部二进制版本与来源，先定位对应清单
rg --files Vendor/sslocal -g 'manifest.json'
# 查运行职责，限定相关 Swift 源码
rg -n -g '*.swift' 'sslocal|reload' Agent Domain/Runtime App/Application/ProxyRuntime
# 查规则内容时先只列出命中文件
rg -l '关键词' Vendor/rules Tests/Fixtures/RuleSnapshots
# 需要显示匹配行时，省略超长行并保留命中提示
rg -n -M 300 '关键词' Vendor/rules
```

`Vendor/rules/*/snapshot.json` 与 `Tests/Fixtures/RuleSnapshots/*.json` 是生成的单行 JSON。`-M 300` 按字节限制长行显示，不限制总输出量；`-m` 和 `head -n` 只限制行数，不能防止单条长行撑大输出。需要完整规则时，定位具体快照后按 JSON 字段读取。清单与 `NOTICE` 也保留在各自的 Vendor 目录中，可按需单独搜索。
