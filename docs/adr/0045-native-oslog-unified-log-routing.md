# 统一日志路由：原生 os.Logger 与封闭枚举 dispatch

**状态**：已接受（2026-10-20）。

日志去向收进发射缝统一路由到 macOS 统一日志，Console.app 按稳定 subsystem `com.qiuyuzhou.ShadowsocksX-NG2` 与 category 过滤查看；stderr 行式输出与事件缓冲降为另外两个去向，`RuntimeLog.emit(_:)` 仍是唯一发射 interface。实现用平台原生 `os.Logger`，不引第三方日志库：swift-log 及其 backend、CocoaLumberjack 会把 privacy 标注拍平成普通字符串，swift-log-oslog 自身也建议直接使用 os_log；本仓库保持零 SPM 依赖。不恢复用户日志级别设置（延续 ADR-0014），级别、category 与 privacy 全部由事件派生。

`RuntimeLogEvent` 保持封闭枚举，脱敏由构造保证（延续 ADR-0006）。系统日志路由是枚举上的穷举 switch：level 三分（失败类 `.error`、里程碑 `.default`、冗长测量 `.info`），category 五分（runtime / supervision / system-proxy / connectivity / diagnostics），公开文本与 private detail 按 `text` + `privateDetail` == `description` 从 `description` 裁切派生，不手抄前缀。新增事件漏路由直接编译失败，privacy 决策必须显式作出。规则：枚举构造的文本标 public，自由形式的错误 detail 与连通性测量内容（含探测目标 IP）标 private；服务器地址与备注默认不进普通日志的基线不变。

sslocal 的上游自由文本是进入统一日志的第二条流，不进 `RuntimeLogEvent`：`SslocalOutputIntake` 拥有 chunk-safe 分帧、密码脱敏与超长行丢弃，把脱敏后的行送两个去向——agent.log 文件（行格式见 ADR-0046，行正文为脱敏后的原始文本，供 ADR-0006 的本地查看面）与统一日志 category `sslocal`。上游行整行标 private（上游默认日志可能含服务器地址），级别按空白 token 探测 ERROR/WARN/WARNING，忽略大小写并支持 token 外的一对方括号，其余落 `.info`；统一日志只有五级、没有 warning，WARN/WARNING 落持久的 `.default`，级别名仍留在行文本里。上游改格式时优雅退化为全 `.info`，不丢行。agent.log 的保留策略（启动时超 1 MiB 截断）留在共写该文件的文件去向一侧，不并入 intake。

考虑过但拒绝的选项：把上游自由文本塞进封闭枚举（破坏脱敏由构造保证的基线）；密码脱敏后把上游行标 public（服务器地址进持久 store）；再加一层地址形态正则脱敏后标 public（会漂移的正则防线）；让 intake 拥有 agent.log 截断策略（该策略属于 wrapper 事件行与 sslocal 行共写的文件去向）。`.info`/`.debug` 只在 stream 可见、不落盘，统一日志的持久面只收探测到的警告与错误，agent.log 才是完整持久面；private 字段对普通 Console 用户显示 `<private>`，正文阅读继续走 app 内诊断查看面。诊断报告的白名单投影独立于本路由，新增事件仍须显式决策（ADR-0006）。

测试运行关闭统一日志写入：测试缝 `SSXNG_SYSTEM_LOG=0` 由 scheme 的测试动作注入、测试拉起的子进程在夹具显式设置，stderr 行与事件缓冲不受影响——测试不把日志灌进系统日志 store。这不是用户日志级别设置（ADR-0014 的口径不变）。

**2026-10-20 补充**：统一日志的写入单元随后抽为 `SystemLog`（`Domain/Runtime/SystemLog.swift`），GUI/wrapper 的 `RuntimeLog.emit` 与特权系统代理 helper 共用它；helper 侧事件的边界（专属封闭枚举、无文件面）见 ADR-0047。
