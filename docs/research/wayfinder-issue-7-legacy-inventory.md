# Wayfinder Issue 7：Legacy 配置迁移与旧版功能边界 — 事实盘点

- 票据：决策：Legacy 配置迁移与旧版功能边界
- 研究日期：2026-09-20
- 范围：只读审计冻结的 `Legacy/` 源码、XIB、脚本和 README；不执行旧程序、不读取任何用户实际偏好文件，也不作产品或迁移决策。
- 证据限界：以下是 Legacy 的历史实现事实，不是新实现的需求或技术规范。

## 1. 应用拥有的 UserDefaults

`applicationDidFinishLaunching` 中唯一的 `register(defaults:)` 调用注册了下列 21 个默认值。[AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L91-L114)

| Key | 注册默认值 |
| --- | --- |
| `ShadowsocksOn` | `true` |
| `ShadowsocksRunningMode` | `"auto"` |
| `LocalSocks5.ListenPort` | `NSNumber(UInt16(1086))` |
| `LocalSocks5.ListenAddress` | `"127.0.0.1"` |
| `PacServer.BindToLocalhost` | `NSNumber(Bool(true))` |
| `PacServer.ListenPort` | `NSNumber(UInt16(1089))` |
| `LocalSocks5.Timeout` | `NSNumber(UInt(60))` |
| `LocalSocks5.EnableUDPRelay` | `NSNumber(Bool(false))` |
| `LocalSocks5.EnableVerboseMode` | `NSNumber(Bool(false))` |
| `GFWListURL` | `"https://cdn.jsdelivr.net/gh/gfwlist/gfwlist/gfwlist.txt"` |
| `AutoConfigureNetworkServices` | `NSNumber(Bool(true))` |
| `LocalHTTP.ListenAddress` | `"127.0.0.1"` |
| `LocalHTTP.ListenPort` | `NSNumber(UInt16(1087))` |
| `LocalHTTPOn` | `true` |
| `LocalHTTP.FollowGlobal` | `false` |
| `ProxyExceptions` | `"127.0.0.1, localhost, 192.168.0.0/16, 10.0.0.0/8, FE80::/64, ::1, FD00::/8"` |
| `ExternalPACURL` | `""` |
| `EnableSwitchMode.PAC` | `true` |
| `EnableSwitchMode.Global` | `true` |
| `EnableSwitchMode.Manual` | `false` |
| `EnableSwitchMode.ExternalPAC` | `false` |

下列 key 被读写，但没有出现在这份注册默认值中：

- `ServerProfiles` 是 Profile 字典数组，`ActiveServerProfileId` 是选中 Profile 的字符串 ID。[ServerProfileManager.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfileManager.swift#L18-L44)
- `LocalSocks5.ListenAddress.Old` 和 `LocalSocks5.ListenPort.Old` 是 PAC 重生成的上次监听地址/端口缓存。[PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L20-L36)
- `Proxy4NetworkServices` 是手选 System Configuration 网络服务 ID 的数组；未保存时 UI 使用空集合。[ProxyInterfacesViewCtrl.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyInterfacesViewCtrl.swift#L21-L32) [ProxyInterfacesViewCtrl.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyInterfacesViewCtrl.swift#L60-L74)
- `LaunchAtLogin` 在 `SMLoginItemSetEnabled` 成功后写入；源中没有注册默认值。[LaunchAtLoginController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAtLoginController.m#L43-L81)
- `ToggleRunning` 与 `SwitchProxyMode` 是 `MASShortcutView` 的关联 defaults key，并由 MASShortcut 绑定；本应用源码未注册快捷键默认组合。[PreferencesWinController.xib](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Base.lproj/PreferencesWinController.xib#L36-L63) [ShortcutsController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShortcutsController.m#L16-L28)

不确定性：这是一份应用源码层的 key 盘点；未实测某个用户的偏好域，也未审计 CocoaPods 内部可能持有的 framework 私有 key 或 MASShortcut 的序列化形状。

## 2. ServerProfile 模型、UUID 与选中行为

- 新建 `ServerProfile` 立即生成 `UUID().uuidString`；初始字段为 `serverHost = ""`、`serverPort = 8379`、`method = "aes-128-gcm"`，以及空的 `password`、`remark`、`plugin`、`pluginOptions`。空 `plugin` 表示禁用插件。[ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L12-L32)
- 持久化字典字段精确为 `Id`、`ServerHost`、`ServerPort`、`Method`、`Password`、`Remark`、`Plugin`、`PluginOptions`。读取时前四个服务器字段和密码使用强制转换；缺少 `Id` 时会生成新 UUID。[ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L159-L198)
- `ServerProfiles` 只写入 `isValid()` 的 Profile；有效性要求主机是 IPv4、IPv6 或匹配的域名，且密码非空。[ServerProfileManager.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfileManager.swift#L35-L49) [ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L233-L269)
- `ActiveServerProfileId` 与 Profile 的 `uuid` 做精确字符串匹配；找不到匹配项时 `getActiveProfile()` 返回 `nil`。`setActiveProfiledId` 同时更新内存和 defaults。[ServerProfileManager.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfileManager.swift#L29-L33) [ServerProfileManager.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfileManager.swift#L64-L75)
- `save()` 找不到活动 Profile 时只将内存 `activeProfileId` 置为 `nil`，该方法内没有移除或重写 `ActiveServerProfileId` 的 defaults 值。收到 `NOTIFY_SERVER_PROFILES_CHANGED` 后，应用仅在内存 ID 为 `nil` 且首个 Profile 有效时选择第一个 Profile 并写回 ID。[ServerProfileManager.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfileManager.swift#L35-L49) [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L132-L145)
- URL 导入由 `ServerProfile(url:)` 先调用默认构造器，再填充 URL 字段；`ss://` URL 输出也不包含 `Id`。因此该导入路径本身不携带原有 UUID。[ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L34-L144) [ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L295-L324)

## 3. 迁移相关文件索引

| 范围 | 主要历史证据 |
| --- | --- |
| 启动、默认值、运行模式、菜单动作 | [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L76-L251)、[MainMenu.xib](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Base.lproj/MainMenu.xib#L32-L160) |
| Profile schema、导入/导出、选中 ID | [ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L12-L324)、[ServerProfileManager.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfileManager.swift#L11-L104) |
| PAC 规则文件、编译和 GFW List 下载 | [PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L12-L198)、[UserRulesController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/UserRulesController.swift#L15-L52)、[abp.js](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/abp.js#L1-L22) |
| 系统代理与本地 PAC 托管 | [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L103-L294)、[proxy_conf_helper/main.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/proxy_conf_helper/main.m#L45-L223) |
| `ss-local`、Privoxy、插件安装和 launchd | [LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L11-L202)、[LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L281-L452)、各 `install_*.sh` 脚本 |
| QR、文本/剪贴板导入与 Profile 分享 | [ImportWindowController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ImportWindowController.swift#L11-L56)、[ShareServerProfilesWindowController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShareServerProfilesWindowController.swift#L47-L189)、[Utils.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Utils.m#L13-L199) |
| 快捷键、登录启动、诊断 | [ShortcutsController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShortcutsController.m#L16-L28)、[LaunchAtLoginController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAtLoginController.m#L43-L87)、[Diagnose.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Diagnose.swift#L28-L96) |

## 4. 用户可见能力面（事实，不是保留范围）

| 能力面 | Legacy 行为 | 证据 |
| --- | --- | --- |
| 内置 PAC 与 GFW List | 规则目录为 `~/.ShadowsocksX-NG/`，输入为 `gfwlist.txt` 和 `user-rule.txt`，输出为 `gfwlist.js`；首次可从 `~/.ShadowsocksX-NE/` 移动目录。编译时 Base64 解码 GFW List、将用户规则置前并去重、替换 JavaScript 模板的 SOCKS 地址/端口；更新动作通过 `GFWListURL` 下载并重编译。 | [PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L12-L17) [PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L51-L150) [PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L162-L198) |
| PAC 用户规则 | 菜单有 “Edit User Rules For PAC...”；窗口读取/原子写入 `user-rule.txt`，随后调用 `GeneratePACFile()` 并发出成功或失败通知。 | [MainMenu.xib](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Base.lproj/MainMenu.xib#L111-L121) [UserRulesController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/UserRulesController.swift#L15-L52) |
| 自动 PAC 模式 | `ShadowsocksRunningMode == "auto"` 时启动本机 PAC server，并以 helper 的 `auto` 模式把 `http://localhost:<PacServer.ListenPort>/proxy.pac` 写入系统代理。server 只提供 `GET /proxy.pac`，MIME 为 `application/x-ns-proxy-autoconfig`，端口和是否绑定 localhost 来自 defaults。 | [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L231-L250) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L136-L153) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L206-L253) |
| 全局与手动模式 | `global` 调 helper 设置 SOCKS；启用 `LocalHTTPOn && LocalHTTP.FollowGlobal` 时一并传入 Privoxy 的 HTTP/HTTPS 地址和端口。`manual` 调 `disableProxy()`；README 描述它为不配置系统代理、由用户自行给应用配置 SOCKS5 的模式。 | [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L155-L193) [proxy_conf_helper/main.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/proxy_conf_helper/main.m#L154-L210) [README.md](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/README.md#L46-L49) |
| 外部 PAC | `externalPAC` 将 `ExternalPACURL` 直接传给同一 helper 的 `auto` 模式；菜单仅在该值非空时启用。输入 formatter 允许空值或 `file`、`http`、`https` scheme。 | [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L477-L503) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L195-L221) [PACURLFormatter.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACURLFormatter.swift#L26-L52) |
| 网络服务与例外项 | `AutoConfigureNetworkServices == false` 时，helper 接收 `Proxy4NetworkServices` 中的服务 ID；`ProxyExceptions` 按逗号、顿号、空白分割为多个 `-x` 参数。未手选服务时 helper 按 Wi-Fi/AirPort/Ethernet 判断。 | [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L103-L134) [ProxyInterfacesViewCtrl.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyInterfacesViewCtrl.swift#L21-L74) [proxy_conf_helper/main.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/proxy_conf_helper/main.m#L133-L170) |
| 本地 HTTP/Privoxy | 安装/生成 `com.qiuyuzhou.shadowsocksX-NG.http` LaunchAgent；模板将 `{http}` 监听地址/端口和 `{socks5}` 替换后写入 `privoxy.config`，追加 `~/.ShadowsocksX-NG/user-privoxy.config`。仅在有活动 Profile 且 `LocalHTTPOn` 为真时启动。菜单可复制 `http_proxy` 和 `https_proxy` export 命令。 | [LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L284-L317) [LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L343-L452) [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L411-L425) |
| SIP003 插件 | Profile 含 `plugin` 与 `pluginOptions`；非空插件在 `ss-local` JSON 中写成 `plugins/<plugin>` 和 `plugin_opts`。安装脚本安装/链接 `simple-obfs`、`kcptun` adapter 和 `v2ray-plugin` 到应用支持目录的 `plugins/`。 | [ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L22-L24) [ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L201-L219) [install_simple_obfs.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/simple-obfs/install_simple_obfs.sh#L7-L19) [install_kcptun.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/kcptun/install_kcptun.sh#L9-L23) [install_v2ray_plugin.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/v2ray-plugin/install_v2ray_plugin.sh#L17-L23) |
| QR、URL 导入和分享 | 分享窗可复制单个 URL、二维码、全部 URL，保存二维码 GIF 或全部 URL 文本；二维码由 Profile 的 `ss://` URL 生成。导入窗口从剪贴板/文本行中接受 scheme 为 `ss` 的 URL。屏幕扫描先检查/请求屏幕录制权限，再扫描所有活动显示器的 QR，并只收集以 `ss://` 开头的消息。 | [ShareServerProfilesWindowController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShareServerProfilesWindowController.swift#L47-L132) [ShareServerProfilesWindowController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShareServerProfilesWindowController.swift#L171-L189) [ImportWindowController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ImportWindowController.swift#L19-L55) [Utils.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Utils.m#L13-L47) [Utils.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Utils.m#L95-L159) [Info.plist](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Info.plist#L52-L53) |
| 快捷键 | 两个 MASShortcut defaults key：`ToggleRunning` 发布运行开关通知，`SwitchProxyMode` 发布模式切换通知。模式切换按启用的 `EnableSwitchMode.*` 顺序循环，外部 PAC 还要求菜单当前可用。状态菜单另有运行开关和三种模式的 key equivalents，前十个动态 Profile 菜单项使用 `1` 至 `0`。 | [ShortcutsController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShortcutsController.m#L16-L28) [MainMenu.xib](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Base.lproj/MainMenu.xib#L37-L66) [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L147-L199) [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L591-L610) |
| 登录时启动 | `LaunchAtLogin` 绑定到 `SMLoginItemSetEnabled`，helper bundle ID 为 `com.qiuyuzhou.ShadowsocksX-NG.LaunchHelper`；LaunchHelper 尝试在 `/Applications`、按名称、再按相对 bundle 路径启动主 app 后退出。 | [LaunchAtLoginController.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAtLoginController.m#L67-L87) [LaunchHelper AppDelegate.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/LaunchHelper/LaunchHelper/AppDelegate.m#L18-L35) |
| 诊断和日志 | 菜单可打开 `~/Library/Logs/ss-local.log` 或将 `diagnose()` 输出写入用户选择的文本文件。诊断包含 Info.plist、列出的偏好、活动 Profile 的 `debugString()`、若干目录列表、监听端口、网卡和 launchctl 输出。 | [AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L428-L465) [Diagnose.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Diagnose.swift#L28-L96) |

README 也列出 SIP003 插件、GFW List PAC 更新、二维码/URL 分享、剪贴板导入、屏幕 QR 扫描、PAC 自定义规则和 Privoxy HTTP proxy；它同时说明 `ss-local` 通过 launchd 运行，退出 app 后仍可能继续运行。[README.md](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/README.md#L35-L49)

## 5. 敏感字段与暴露位置

| 字段/数据 | 源码中的位置和流向 | 明确边界 |
| --- | --- | --- |
| `Password`、服务器主机/端口、加密方法 | `ServerProfiles` 字典包含这些字段；活动 Profile 被 JSON 序列化为 `~/Library/Application Support/ShadowsocksX-NG/ss-local-config.json`。 | 源码显示直接 dictionary/JSON 序列化；本审计未对 macOS 实际文件权限或 UserDefaults 底层存储格式作实测。 |
| Profile 分享 URL 与二维码 | `URL()` 对 `"<method>:<password>"` 进行 Base64 编码并组成 `ss://` URL；分享窗口把 URL 写入剪贴板/文本文件，或把它编码到 QR/GIF。 | URL 和二维码因包含该编码后的 user info 而属于凭据载体。 |
| 屏幕扫描结果 | 每个发现的 QR `messageString` 会被 `NSLog`，并且以 `ss://` 开头的 URL 会进入导入通知。 | 日志是否被导出、保留多久或谁可访问，源码未说明。 |
| `PluginOptions`、`ExternalPACURL`、`GFWListURL` | Plugin options 被写入 `ss-local` JSON；外部 PAC URL 传给 helper；GFW List URL 用于下载。 | 这些字段不一定含凭据，但其值可能含连接、路径或查询信息；是否敏感取决于具体值。 |

对应一手证据：[ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L188-L219) [ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L295-L324) [LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L133-L160) [ShareServerProfilesWindowController.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ShareServerProfilesWindowController.swift#L47-L132) [Utils.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Utils.m#L109-L118) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L195-L221) [PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L172-L198)

诊断对活动 Profile 的 `ServerHost` 与 `Password` 以同长度星号输出，但仍输出端口、method、plugin 和 `PluginOptions`；诊断偏好列表包含 `GFWListURL` 和代理例外项。[ServerProfile.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ServerProfile.swift#L222-L230) [Diagnose.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/Diagnose.swift#L38-L70)

## 6. 仅在 Legacy 中观察到的依赖/机制

| Legacy 依赖或机制 | 已见用途 |
| --- | --- |
| CocoaPods：Alamofire、GCDWebServer、MASShortcut、RxSwift、RxCocoa、BRLOptionParser | 分别用于 GFW List 请求、本地 PAC server、全局快捷键、通知绑定，以及特权 helper 的命令行解析。 |
| 打包二进制和安装脚本：`ss-local`、`privoxy`、`simple-obfs`、`kcptun`、`v2ray-plugin` | 脚本复制/链接到 `~/Library/Application Support/ShadowsocksX-NG/`，前两者使用 per-user LaunchAgent。README 标记 `ss-local` 为 shadowsocks-libev 3.2.5。 |
| 特权 `proxy_conf_helper` | 安装到 `/Library/Application Support/ShadowsocksX-NG/`，脚本设置 `root:admin`、可执行和 setuid；helper 使用 Authorization 与 SystemConfiguration 写代理偏好。 |
| `SMLoginItem` + `LaunchHelper.app` | 登录时启动依赖辅助 app 和 `SMLoginItemSetEnabled`。 |

对应证据：[Podfile](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/Podfile#L3-L27) [LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L31-L83) [LaunchAgentUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/LaunchAgentUtils.swift#L284-L378) [install_helper.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/install_helper.sh#L10-L14) [proxy_conf_helper/main.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/proxy_conf_helper/main.m#L105-L218) [README.md](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/README.md#L35-L49)

“仅在 Legacy 中观察到”只描述本次审计范围内的实现构成；本报告没有审计或断言新实现是否使用、替换或保留其中任一依赖。

## 7. 未由静态资料确定的事项

- 没有运行 Legacy，因此没有证据证明上述旧二进制、脚本、权限请求、launchd job 或系统代理修改在当前 macOS 上仍可成功执行。
- 没有实际偏好域样本，因此无法从源码外确认历史用户是否存在遗漏字段、错误类型、重复 UUID 或已失效的 `ActiveServerProfileId`。
- 没有对外部 PAC、GFW List 或插件二进制进行联网或内容验证；本报告仅记录代码如何引用它们。
- 源码没有定义新实现的配置映射、兼容承诺、弃用策略或安全存储方案；这些均不在本次事实盘点的结论内。
