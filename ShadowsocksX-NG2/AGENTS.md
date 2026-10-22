# ShadowsocksX-NG2

新实现（2.0）所在目录。仓库级约定见根目录 [`AGENTS.md`](../AGENTS.md)；工程结构、外部二进制供应链、签名基线、构建测试命令、代码风格工具安装与基线版本见 [`README.md`](README.md)，本文件不重复。

## Unit tests（hostless）

单测不以 app 为宿主（ADR-0021）。两条约定：

- 测试需要 app 产物（嵌入二进制、打包面 Info.plist 断言）时，一律经 `Tests/AppArtifact.swift` 定位。
- 生产代码读取 app bundle 内打包资源（规则快照、LaunchDaemon 清单等）时，走注入缝——控制器的 `appBundle` 参数（生产默认 `Bundle.main`），测试夹具注入 `AppArtifact.bundle`。

背景与三处资源缝的由来见 [ADR-0021](../docs/adr/0021-hostless-unit-tests.md)。

## Test framework

- 新增测试默认用 Swift Testing（`import Testing`）；UI 测试与性能测试依赖 XCTest 专属 API（`XCUIApplication`、`measure` 计时），继续用 XCTest；存量 XCTest 用例不回迁。
- 单测多 runner 并行执行：新夹具只占用进程私有资源——运行时分配端口、临时目录、UUID 后缀命名空间，不写共享路径与固定名。

## Test fixtures and execution cost

- 输入规模由断言目标决定。启停、保存、部署、回滚、状态投影等行为集成测试使用小型确定性输入，保留真实的被测工作流与编译路径；规则行为夹具优先复用 `ProxyRuntimeFixture.controlFlowRuleSnapshot`。
- 验证打包资源、完整规则语义、大数据边界或性能的专用用例，显式注入完整数据。行为测试通过规则数据注入缝缩小输入；仍需清单等打包资源时保留 `AppArtifact.bundle`。
- 小夹具保留场景依赖：覆盖、遮蔽、禁用、孤立记录等关系按用例构造；公共夹具中无关的域名避开用例自身的规则，避免意外吸收或重复使预期部署变成无操作。替身实现被测流程依赖的注册、退出、回执等生命周期语义。
- 异步穿插优先用 expectation、gate 或可控时钟观测阶段；与断言无关的生产延迟通过注入缩短。保留用例刻意验证的超时、健康窗、进程监督等待与数据边界。
- 存量 XCTest 按行为拆为可独立调度的具体测试类；共享夹具基类只放状态和工厂，不含 `test*` 方法，避免子类重复执行继承用例。拆类或调整夹具后核对用例清单，确认无遗漏、重复或新增跳过。
- 优化耗时先记录同一配置下的全量墙钟、最慢类和用例，再分段测量定位计算与等待。优先消除测试目标之外的重复计算，再评估拆类并行或独立的生产性能优化；用例耗时合计除以墙钟表示执行重叠，不能当作 CPU 使用率。
