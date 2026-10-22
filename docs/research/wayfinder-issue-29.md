# Wayfinder issue 29：系统代理写入、四种模式与健康门禁

## 实现结论

2.0 现在把 PAC、全局、手动、外部 PAC 建模为互斥的 `ProxyMode`。控制器先确认本地 SOCKS 端口和本地 PAC endpoint 健康，再执行系统代理动作；外部 PAC 还必须通过同一 PAC 内容/响应检查。任一检查失败都不会调用 SystemConfiguration 写入。

- PAC：写入当前监听范围派生出的 PAC URL。
- 全局：只启用本机 `127.0.0.1:<SOCKS 端口>` 的 SOCKS 代理；HTTP 入站仍是独立运行时能力，不复活 Legacy Privoxy 或 `FollowGlobal` 语义。
- 手动：恢复 2.0 最近一次接管前的完整 Proxies 字典，不再改写系统代理。
- 外部 PAC：接受无凭据的 HTTP/HTTPS URL；启用前验证 URL、HTTP 响应 MIME 与 `FindProxyForURL` 内容。`file:` 暂不进入支持矩阵，因为本机目标系统未建立跨客户端契约。

生产适配器以当前 network set 的 network service ID 为粒度读取和写入 `Proxies` entity。第一次写入保存完整原字典，切换模式只改变 2.0 控制的 enable/endpoint 字段；恢复前若发现当前字典已被用户或 MDM 改动，则报告所有权冲突并不覆盖。记录文件使用 v2 目录的 0700/0600 原子写入基线。

正式模式菜单属于 #31，本票只提供控制器控制面和可验证的模式/写入 seam；外部 PAC 保留在核心模式模型中，待 #31 接线时按下述实测范围决定菜单暴露。

## 本机实测

环境：macOS 27.0（Build 26A428），arm64，2026-09-20。

### 已通过

- 本地 HTTP PAC endpoint 可由 `SystemPACHealthProbe` 获取并验证：HTTP 200、`application/x-ns-proxy-autoconfig`、内容包含 `FindProxyForURL`。对应测试使用真实 loopback socket，不写系统代理。
- PAC URL 的 loopback/主机地址派生和 SOCKS 全局目标均由纯映射测试覆盖；四种模式不会同时启用 PAC、HTTP/HTTPS、SOCKS。

### 未执行的破坏性操作与边界

- 未对当前用户的 network service 做真实写入/恢复。`scutil --proxy` 显示当前机器已有其他本地代理（HTTP/HTTPS/SOCKS 均为 `127.0.0.1:64649`，PAC 关闭），不能在日常配置上覆盖它。
- `networksetup` 的授权检查返回 `AuthorizationCreate() failed: -60008`；因此本轮没有伪造“真实 SystemConfiguration 写入已通过”的结论。生产路径仍使用 `SCPreferencesCreateWithAuthorization`，失败会呈现明确的系统代理授权错误。
- 本机没有为 `file:` PAC 建立目标系统所有客户端的实测证据，所以外部 PAC 校验只允许 HTTP/HTTPS；正式菜单尚未在 #31 中接线。

验证重点由单测覆盖：健康门禁前不写入、外部 PAC 不健康不写入、全局/手动切换立即生效、停止恢复系统代理、所有权冲突不覆盖用户改动，以及所有权记录的原子权限。
