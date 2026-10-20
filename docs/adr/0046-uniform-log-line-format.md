# 统一日志行格式与日志视图 intake

**状态**：已接受（2026-10-20）。

「一行日志是什么」收口到 `LogLine`（时间戳 + 级别 + 来源 + 正文），渲染与解析各一处，agent.log 文件与诊断日志视图共用同一格式：`yyyy-MM-dd HH:mm:ss.SSS [error|warning|info] [gui|wrapper|sslocal] 正文`，时间戳固定 POSIX locale，报障对照不随用户区域漂移。采用写侧富化：wrapper 事件行与 sslocal 行在写入时带上时间戳与级别（sslocal 级别沿 ADR-0045 的空白 token 探测），旧 `ssxng:` 事件标记吸收为来源列。旧格式行（升级前落盘）解析失败时降级保留原文、级别尽力探测、时间未知，raw capture 不改写。

诊断日志查看器由一个 intake（`DiagnosticLogIntake`）提供行：tail 窗口逻辑（有限字节、起始半行丢弃）收在 intake，GUI 事件缓冲与 agent.log 尾部行按时间戳归并为一个列表（旧格式行排最前并保持文件内顺序），提供级别（全部 / 警告+错误 / 仅错误）与来源（全部 / GUI / wrapper / sslocal）双维过滤，复制跟随可见行。级别用经典三级 error / warning / info——里程碑事件归 info、上游 WARN/WARNING 归 warning；统一日志的五级投影（ADR-0045）是另一个口径，两者的映射规则在 `LogLine` 同一处。

边界不变：诊断报告的白名单投影零改动，日志行仍只经显式查看/复制呈现、永不进入诊断报告（ADR-0006）；统一日志继续只做 Console 面。agent.log 的保留策略（启动时超 1 MiB 截断）仍留在文件去向一侧。

考虑过但拒绝的选项：从 OSLogStore 回读喂查看器（统一日志是跨进程共同事实源，但 private 字段回读为 `<private>`，恰好毁掉查看器展示正文的职责；测试回读须真写系统日志，与测试静默缝相撞）——该路径留给特权 helper 事件（唯一没有文件面、且枚举文本公开）；读侧推导元数据（agent.log 行无时间戳，归并排序与过滤残缺）；保留双 tab 只统一行格式（GUI 与 wrapper 时间线仍无法对照）。
