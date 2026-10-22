# 开发、构建与测试

[English](development.md) | [返回工程首页](../ShadowsocksX-NG2/README.zh-CN.md)

除特别说明外，命令从 `ShadowsocksX-NG2/` 执行，文中工程路径也相对于该目录。

## 统一验证

统一验证入口（从仓库根目录调用）：

```bash
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate
# 按指定顺序只运行所需关卡：
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate -- lint test
```

在工程目录内可用 `task --exit-code validate`。从任意目录可用 `task --exit-code --taskfile /path/to/ShadowsocksX-NG/ShadowsocksX-NG2/Taskfile.dist.yml validate`。入口按 Taskfile 所在位置定位工程目录，内部调用发行 Taskfile 中的单项任务。

默认按 `lint → test → test:smoke → build` 执行，也可按指定顺序选择子集，每关最多一次；任一关失败立即停止，后续关标记 `not_run`，进程返回非零。`--exit-code` 让 Task 透传关卡退出码；省略时 Task 仍返回非零，但可能使用自己的错误码。入口不自动重试，不修改测试并行设置，也不执行会修改源码的格式化。

### 验证产物与证据

每次运行创建独立的 `.build/validation/<UTC时间>-<随机后缀>/`，开始与结束均输出结果绝对路径。`summary.txt` 保存各关状态、退出码与证据状态；每个已执行关卡在同名子目录下保留合并 stdout/stderr 的 `raw.log` 和 `status.txt`（`test:smoke` 对应 `test-smoke/`），Xcode 关卡显式保存 `result.xcresult`。控制台只显示进度和摘要，需要完整错误时直接读取对应日志。所有产物均在现有忽略目录内；`task clean` 会删除它们，需要长期留存时先复制出去。

测试关通过本机 `xcrun xcresulttool get test-results summary` 和系统 `plutil` 尽力读取计数，无需新增脚本或工具依赖。`test-summary.json` 保存原始摘要，`test-summary.stderr.log` 保存 xcresulttool 错误，`count-reader.log` 保存计数读取错误。汇总展示通过、失败、跳过、预期失败及总数（Xcode 汇总口径，参数化测试的实际执行次数可能不同）。关卡与总体退出码由原命令决定，命令失败始终保留失败。结果包缺失或摘要不可读时显著标注 `evidence incomplete`（证据不完整）、计数未知，不改变命令结果，也不把缺失计数写成零。构建关不读取测试计数；未执行的关卡不等同于测试跳过。

统一入口成功表示所选关卡的命令通过，仍需核对证据是否完整；hostless、真实进程 smoke、原生 UI 和真实系统代理的验收边界仍分别成立，发布打包门槛见[签名与分发](distribution.zh-CN.md#发布门槛)。

`task test` 与 `task test:smoke` 显式启用 Xcode 单测试超时：默认 120 秒，上限 300 秒。这是 runner 兜底，不保证测试任务正常清理，也不是性能门槛。规则阶段等待失败会抛错退出测试体；受保护的测试任务先释放夹具，再取消并等待结束。规则延迟 gate 和同步阻塞夹具的默认等待上限为 10 秒，超时必须报告失败。共享 `AsyncGate` 保留由用例控制的取消语义。Swift Testing 的 detached worker 超时报告保留创建用例名称和源码位置；应同时核对命令退出码与测试计数，不能仅凭单例通过数判断成功。

## 常用任务

在工程目录内，日常格式化、静态检查、工程生成、构建和测试优先使用 `Taskfile.dist.yml` 定义的任务：

```bash
task format
task lint
task lint:fix  # 需要自动修复 SwiftLint 违规时使用；执行后再运行 task lint
task gen:prj   # 生成 Xcode 工程
task build     # 构建 Debug 版本 app
task test      # 运行单元测试（不含真实进程冒烟）
task test:smoke  # 运行真实进程冒烟测试（拉起真实 sslocal，见签名与分发文档的发布门槛）
```

`task format` 会格式化 `App/`、`Tests/`、`Domain/` 和 `Agent/` 下的 Swift 文件；`task lint:fix` 会修改源文件，执行后检查并复核 diff。

## 首次准备与测试范围

新 clone 或清单变更后，在工程目录内先取外部二进制，再生成工程（顺序不可颠倒）：

```bash
Scripts/fetch-external-binaries.sh
task gen:prj
```

Swift Package Manager 从 `project.yml` 固定的正式版本解析 AgeSwift，并校验其发布 XCFramework。首次解析需要网络，消费者无需安装 Rust。`Vendor/AgeSwift/LICENSE-MIT` 来自固定版本，随应用打包到 `Resources/ThirdParty/AgeSwift/`。加密存储互操作测试还需要 `brew install age` 和可访问的登录钥匙串；测试使用 UUID 隔离的 service 并清理，不修改真实应用配置。命令行调试方法见[加密格式文档](server-library-encryption-format.zh-CN.md)。

无证书也能构建与跑单测：Debug 基线是 ad-hoc，不需要 `Configs/Signing.local.xcconfig`。只有要做 Developer ID 签名（发布，或让本机 Debug 产物过打包门槛）时才写该文件，内容见[签名与运行形态基线](distribution.zh-CN.md#签名与运行形态基线)。

`Tests/Smoke/` 是真实进程冒烟（经 wrapper 拉起真实 sslocal 验证启动、握手、
ACL 路由与插件监管），不在默认 `task test` 内，由独立 scheme 按需运行。

## 代码风格工具

- `swift format` 随 Xcode/Swift 工具链提供，无需单独安装（基线：Apple Swift 6.4）；SwiftLint 需 `brew install swiftlint`（基线 0.65.0）。工具缺失时，含工程目录 Swift 文件的提交会被 pre-commit 钩子拒绝而不是放行。
- 配置文件：`.swift-format` 是 Swift 6.4 工具链默认规则的快照（固定成文件，工具链升级不漂移）；`.swiftlint.yml` 默认规则起步，只声明排除项与个别和 format 基线冲突的关闭项（文件内有触发案例注释）。
- 仓库级 `pre-commit` 钩子的启用方式和检查范围见下节「开发钩子」。
- 调整规则只针对实际痛点：修改 `.swift-format` / `.swiftlint.yml` 的 PR 须给出触发案例，并同步更新本节中的基线版本。

## 开发钩子

新 clone 后，在仓库根目录启用 Git hooks：

```bash
git config core.hooksPath .githooks
```

启用后，`pre-commit` 只检查暂存区中 `ShadowsocksX-NG2/` 下的 `.swift` 文件：`swift format` 的结果写回暂存区、不修改工作区；SwiftLint 的 error 级违规拒绝提交，warning 仅提示。其他文件跳过；没有 NG2 Swift 文件时直接放行。含有 NG2 Swift 文件但缺少工具时，提交检查失败。两关都把「工具没能执行」与「查出问题」分开报告：看到「执行失败」应查工具与配置环境，而不是去改代码。工具安装与版本见上节「代码风格工具」。

## 领域文档语言

本项目的 [术语表](../GLOSSARY.md) 和新建 [架构决策记录（ADR）](adr/) 使用简体中文，代码标识符与必要的英文术语保留原文；已有 ADR 保留原文，不作语言迁移。

AI 生成大量文档后，人与机器之间的沟通成为协作瓶颈：人的阅读、理解和审阅速度决定了文档能否有效推动开发。使用简体中文可以降低维护者的认知负荷，提高沟通与审阅效率。
