# 特权 helper 事件只进统一日志

**状态**：已接受（2026-10-20）。

特权系统代理 helper（root LaunchDaemon）此前是日志黑洞：launchd 丢弃其 stdout/stderr，进程内零输出，helper 侧失败上下文只剩随 XPC 应答回传的 typed 错误、由 GUI 进程转述成 `.systemProxyWriteFailed`。GUI 视角不完整的场景完全没有痕迹：GUI 超时后 helper 实际做了什么、连接中途失效、helper 被 launchd 杀死或拉起失败、签名校验拒绝的连接（谁在敲门）。

helper 复用统一日志的最小发射单元 `SystemLog`（`Domain/Runtime/SystemLog.swift`），与 GUI、wrapper 共用 subsystem `com.qiuyuzhou.ShadowsocksX-NG2`，category 沿用 `system-proxy`——root 侧事件与 GUI 侧 XPC detail 在 Console.app 同一过滤下按时间相邻对照。特权进程的编译面只增加两个文件：发射单元 `SystemLog` 与 helper 侧事件枚举 `SystemProxyHelperLogEvent`。

helper 事件是专属封闭枚举 `SystemProxyHelperLogEvent`，不扩 `RuntimeLogEvent`：GUI 事件枚举（含连通性测量内容）不进特权进程。事件面是生命周期最小集：拉起就绪、连接接受/拒绝（含对端 pid，本机事实字段）、每个 apply/clear 请求的 typed 结果（written/unchanged/cleared 或失败 case + detail）；不记 payload 内容（例外列表等不入日志）。privacy 口径沿 ADR-0045：typed 枚举文本标 public，自由 detail 段（服务标识、SC/XPC 错误文本）标 private。

事件没有文件面：不写 stderr、不进 agent.log、诊断日志视图与诊断报告（ADR-0006 不新增披露面），root 侧细节的查看路径就是 Console.app。诊断日志视图里系统代理的行仍是 GUI 侧转述。发射缝可注入（engine 与 listener 的构造参数，生产默认 `SystemProxyHelperLog.emit`），测试注入替身断言发射内容；`SSXNG_SYSTEM_LOG=0` 测试静默缝照旧。

考虑过但拒绝的选项：扩 `RuntimeLogEvent` 并让 helper 编译 `RuntimeLog.swift`（特权进程背上 GUI 全事件面，编译面扩大）；helper 直写 `os.Logger`（privacy 拆分与测试缝两处重复）；OSLogStore 回读并入诊断日志视图（helper 事件文本公开、回读可读全，但引入读系统日志的测试面与真实 store 写入，与测试静默缝相互作用，复杂度不值当前失败面）；GUI 在失败应答时把 root 事件转记进视图（只覆盖应答成功的场景，超时与断连仍缺，恰是本决策要补的面）。

helper 与 GUI 的 XPC 契约不变，不加请求关联 id：helper 请求串行执行，同一 subsystem 下的时间戳与串行顺序足以对照两侧事件。
