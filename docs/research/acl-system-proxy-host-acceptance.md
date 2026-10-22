# ACL 系统代理路径宿主验收证据（issue #67）

- 记录日期：2026-09-26
- 记录人：Qiu Yuzhou（agent 辅助执行）
- 环境：macOS 26（Darwin 27.0.0）arm64；Xcode DerivedData Debug 构建；随包 sslocal v1.25.0（`aarch64-apple-darwin`，Vendor 清单固定版本，构建期哈希复验 + Developer ID 重签）。
- 证据规则：以下每一条都对应可重复执行的自动化测试或本记录中的命令输出摘要；未实测的系统行为不写成事实，统一列在「未验证边界」。

## 自动化回归覆盖（fake / 回环，不写真实 SystemConfiguration）

以下类别由 `ShadowsocksX-NG2/Tests/` 中的确定性 fake 与回环测试覆盖，不启动真实 LaunchAgent、不写用户真实系统代理字典：

| 类别 | 覆盖位置 | 要点 |
| --- | --- | --- |
| 模式切换与持久化 | `ProxyRuntimeControllerTests+Mode`、`ProxyControlWorkflowIntegrationTests` | 规则/全局/直连三模式切换、子选项切换、偏好持久化、GUI 重启后恢复 |
| 出口待配置 | `ProxyRuntimeControllerTests+AgentAndSystemProxy`、`+Mode` | 无活动目标时 agent 仍监听；规则/全局不写系统代理；直连可用 |
| ownership | `ProxyRuntimeControllerTests+AgentAndSystemProxy`、`SystemProxyTests` | ownership 冲突报告而不强制覆盖；恢复顺序（先恢复系统代理再注销 agent） |
| 失败回滚 | `ProxyRuntimeControllerTests+Mode`、`+GlobalMode` | 模式切换失败恢复旧模式、旧 ACL、旧系统代理应用状态 |
| GUI 重同步 | `ProxyRuntimeControllerTests+ResyncAndSettings`、`+AgentAndSystemProxy` | `resyncOnLaunch` 注册态重校验、目标失效后 agent 保持监听但系统代理撤回 |
| ACL 路由（真实 sslocal 回环） | `RealSslocalSmokeTests+ACLRouting`、`+GFWListACL`、`+CustomRules` | `proxy_all`/`bypass_all`、域名与 IP 优先级、SOCKS/HTTP 共用 ACL、无服务器直连 |
| 规则快照与许可证 | `BuiltinRuleCatalogTests`、`Scripts/verify-rule-snapshots.sh`（构建期门） | 快照来源/许可证/归因随分发物；缺失或损坏使构建失败 |

## 已在真实宿主观察到的行为

1. **构建产物签名与打包门**：`Scripts/packaging-gate.sh` 在构建后对 `ShadowsocksX-NG2.app` 做嵌套代码签名严格校验、DevID + Hardened Runtime 断言、逐二进制清单覆盖。本机 Debug 构建通过该门（`task build` 成功）。
2. **规则快照许可证/归因随分发**：`Vendor/rules/{gfwlist,geolocation-cn,china-ipv4}/` 各含 `NOTICE`（许可证、上游 URL/commit、归因声明）与 `manifest.json`（输入摘要、转换器版本）；`verify-rule-snapshots.sh` 在构建期断言二者齐备。
3. **真实 sslocal ACL 路由（回环）**：`RealSslocalSmokeTests` 以随包 sslocal 做有界回环验证——`proxy_all`/`bypass_all` 骨架、中国域名/CIDR 直连候选、GFWList 代理候选、自定义规则合并、SOCKS 与 HTTP 入站共用同一 ACL、空服务器列表仍绑定本地监听。

## 未验证边界（不写成事实）

以下项目需要在真实 macOS 宿主上单独验收，本记录不作声称：

1. **真实 SystemConfiguration 写入**：`SystemConfigurationProxyController` 对 SCPreferences 的授权、写入、提交、ownership 冲突检测在自动化测试中全部走 fake。真实 `SCPreferencesCommitChanges` 行为、多网络位置切换、授权对话框流程未在本机做端到端实测。
2. **系统 SOCKS 设置的跨应用遵守程度**：产品只承诺「已遵守系统 SOCKS 设置或明确连接本地入口的流量被规则处理」。哪些应用真正遵守 macOS 系统 SOCKS 代理、哪些绕过，未做跨应用矩阵实测。
3. **IPv6 系统例外匹配**：CONTEXT.md 已记录「IPv6 CIDR 字符串写入系统例外不构成已验证的绕过保证」。只读 CFNetwork 验证仅证明本机观察：IPv4 CIDR 与 `*.local` 匹配，IPv6 CIDR 的裸写/尖括号/方括号写法未按预期匹配，精确 IPv6 地址可匹配。跨 macOS 版本行为未验证。
4. **DNS 覆盖**：CIDR 判定可能触发 sslocal 本地 DNS 查询；产品不承诺 DNS 查询均经远端。真实 DNS 泄漏边界未做抓包验证。
5. **UDP 流量覆盖**：SOCKS5 UDP ASSOCIATE 是本地入口能力，不等于系统级 UDP 代理。全应用 UDP 流量是否被拦截未验证。
6. **签名/公证分发**：Developer ID 公证（notarytool）、 stapling、Gatekeeper 首次打开流程未在本记录环境完成（Debug 构建不走公证）。
7. **GFWList 例外遮蔽**：被更宽代理规则遮蔽的 `@@` 例外不写入 ACL，已列入转换报告与已知问题；真实网络下这些目标的实际路由表现未做端到端确认。
