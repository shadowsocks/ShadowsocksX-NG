# Legacy bootout 实弹验证记录（issue #37 / Further Notes #5 闭环）

- 验证日期：2026-09-21
- 环境：macOS 27.0（Build 26A428，arm64），uid 501（Aqua gui 域）。研究报告 `wayfinder-issue-17-legacy-handoff.md` §9.2 要求的「受控环境 bootout 演练」在本机以假替身 job 完成：plist 使用与 Legacy 完全相同的 label 与结构（无 RunAtLoad/KeepAlive 的现行形态 + KeepAlive=true 的 2017 前残留形态），可执行体为 `/usr/bin/nc -l 1086`（模拟 ss-local 持有 SOCKS 端口）。Legacy 实际 ss-local/Privoxy 本体未参与（本机无 Legacy 安装）；label、plist 键、启动方式（`launchctl start`）与真实残留一致，launchd 侧行为不受可执行体影响。
- 基线（验证前）：三个 label `launchctl print gui/501/…` 均退出码 113（未加载）；1086 无监听；`~/Library/LaunchAgents/` 无相关 plist；print-disabled 中已有 `.local`/`.http` 的历史 `=> enabled` 记录（研究报告 §2.1 所述残留）。

## 结果摘要

| # | 场景 | 命令 | 退出码 | 观测 |
| --- | --- | --- | --- | --- |
| 1a | 现行形态：job 已加载 + 进程持端口 | bootstrap（exit 0）→ `launchctl start`（exit 0）→ print=0，lsof 见 `nc *:1086 LISTEN`（pid 79755） | — | 无 RunAtLoad 的 plist 注册后不自动启动，须显式 start——与 Legacy 脚本行为一致 |
| 1b | **bootout 运行中的 job** | `launchctl bootout gui/501/com.qiuyuzhou.shadowsocksX-NG.local` | **0**（wall ≈20ms） | +100ms 内：print→**113**、lsof 无监听、nc 进程消失。SIGTERM→等退出的等待期短到不可观测 |
| 2a | KeepAlive 残留形态被外部杀死 | plist 带 `KeepAlive: true`，bootstrap 后 `kill -9` 持有进程 | — | ≤2s 内 launchd 重启新进程（pid 80094→80108），端口继续被持有——证实活跃残留会自我复活 |
| 2b | **bootout KeepAlive job** | 同 1b | **0** | 进程退出、端口释放、print→113，连续 5s 无重启（KeepAlive 重启依据随 job 定义一并移除） |
| 3a | **bootout 未加载的 label** | 同 1b | **3**（stderr `Boot-out failed: 3: No such process`） | **不是 print 的 113**——退出码语义按子命令而异，产品代码把 0/3 都按「已移除」处理 |
| 3b | job 已加载但 plist 文件已删（错位形态） | bootstrap+start 后 `rm plist` 再 bootout | **0** | 按 service target bootout 不需要 plist 存在；print→113、端口释放 |
| 3d | `launchctl kill 15` 后备 | `launchctl kill 15 gui/501/<label>` | **0** | 旧进程收到 SIGTERM 退出，但 **job 定义仍在（print=0）**，KeepAlive 形态下进程立即被重启——kill 只是终止不是移除，验证后仍须 bootout |
| 3e | disable / enable 语义 | `launchctl disable gui/501/<dummy>` | **0**（幂等） | print-disabled 立即出现 `<dummy> => disabled`；disabled 状态下 bootstrap 该 label 失败（`5: Input/output error`）——disable 确实阻止加载且跨启动持久；`enable` 后记录变为 `=> enabled`（记录保留，状态翻转） |

## 对产品实现的直接修正

1. `LegacyHandoffService.removeJob` 把 bootout 退出码 **0 与 3** 都视为「已移除」（3 = print 与 bootout 之间自行退出的竞态，或检测后未再加载）。测试假实现同步改为 3。
2. kill 后备的验证判据维持 print 退出码（kill 不改变注册态，print=0 ⇒ kill 未达成移除，继续升级为失败呈现）。

## 清理与残留声明

- 验证后：三个 label print 均 113；1086 空闲；`~/Library/LaunchAgents/` 无相关 plist；`/tmp` 临时 plist 已删。
- print-disabled 中 `.local`/`.http` 的历史 `=> enabled` 记录与验证前一致（bootstrap/bootout 不写 override 记录）。
- 唯一新痕迹：dummy label `com.qiuyuzhou.shadowsocksx-ng2.live-test-dummy` 在 print-disabled 留下一条 `=> enabled` 记录（enabled 即默认态，无行为影响；launchctl 无删除单条记录的接口）。

## 遗留验证余项（不阻塞本票）

- macOS 15 与 27 的 print-disabled 呈现细节、`statusForLegacyURL:` 对第三方 plist 的返回语义（研究报告 §9.1）。
- 真实 Legacy ss-local（`--reuse-port`）的端口释放时序：本验证用 nc（无复用选项）替身；bind 探测「无 SO_REUSEPORT ⇒ 真占用」的语义已由研究报告 §2.3 论证，产品探测不设置任何复用选项。
