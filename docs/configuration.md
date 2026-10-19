# 订阅、插件与监听配置

[返回工程首页](../ShadowsocksX-NG2/README.md)

## 订阅资料

订阅可在 SIP-008 JSON 根级提供 `bytes_used`、`bytes_remaining`（非负整数，最大为 UInt64），以及自定义的 `expires_at`（服务到期时间）、`traffic_reset_at`（流量重置时间）。日期值使用 RFC 3339 字符串，省略或 `null` 表示未提供；无效资料仅忽略该项，不影响有效服务器或分组资料。

成功刷新完整替换白名单订阅资料，省略或无效的字段清除旧值；失败或取消保留最后成功资料与独立成功时间。资料和目录记录同文档原子保存，不另存原始响应或含密码的服务器明文快照；密码和插件参数沿用 Keychain 存储。旧目录文件缺少成功时间时不猜测。

订阅卡片显示返回的有效资料；仅在两项流量都有效且总量大于零时显示消耗进度。日期按用户当前语言与时区显示，到期和重置资料不改变代理启停或激活行为。

## 用户插件目录

`PluginCatalog` 合成当前托管清单与本机 `plugins.json` 用户记录，名称精确区分大小写。用户映射优先，失效 override 不退回托管程序；删除 override 恢复当前 app 默认值。文件读取错误保留阻断事实，不按空映射处理。用户路径、本地启动参数与插件传输模式不进入服务器资料、订阅或分享文件。用户路径也不进入诊断报告。

设置页底部的“插件”区域统一展示内置与用户插件，按记录展示全部名称，支持新增、编辑名称集合与路径、逐名称覆盖内置、删除记录与恢复同名内置。用户与内置记录可以设置插件传输模式 `tcp_only` 或 `tcp_and_udp`；默认 `tcp_only`，生成 sslocal 配置时省略 `plugin_mode`。应用不探测插件的 SIP003u 支持。内置编辑器中的“清空参数”只清空草稿启动参数并保留模式，保存后生效。名称与启动参数使用列表编辑，启动参数保留顺序和完整字符串；路径支持手动输入与文件选择。读取失败时隐藏条目并提供只读重试，管理 UI 不提供整体重置。映射提交与显式修复 interface 在组合根统一接入表单、激活与诊断。保存成功后刷新激活候选并异步收敛，运行失败不撤销保存。没有文件替换监控。`plugins.json` v1 每项独立迁移为带持久身份的用户记录，下一次保存写入 v2，不按相同路径合并。现有内置程序同时提供 `v2ray-plugin` 和 `v2ray-plugin-v1`。详见 [ADR-0033](adr/0033-plugin-records-own-aliases-and-local-arguments.md)。

`MacOSPluginInspection` 只读取下载隔离、签名与系统评估事实，不启动用户插件、不修改系统策略。检查失败或不适用为未知；策略评估拒绝不等于实际执行禁令，也不阻止映射保存或激活。真实 macOS 拦截提示不由 hostless 替身测试证明。

## Cloak 托管插件

随应用提供官方 [Cloak v2.12.0](https://github.com/cbeuw/Cloak/releases/tag/v2.12.0) 的 darwin-arm64 `ck-client`，服务器引用名称为 `cloak` 或 `cloak-v2`，两者共享一条内置记录。`ck-client` 是打包文件名，不是可引用名称。同名用户插件仍优先；失效覆盖不会自动回退到内置程序。

服务器插件选项原样传给上游，不进行 Cloak 字段语义校验。可以使用分号分隔的 `Key=value` 参数，或使用外部 JSON 配置文件的绝对路径。外部文件由用户维护，应用不复制文件、不管理文件凭据或生命周期；分享路径不包含文件内容，接收方需要自行提供对应文件。本地启动参数仍独立保存，不随服务器资料分享。

[固定版本配置解析](https://github.com/cbeuw/Cloak/blob/v2.12.0/internal/client/state.go)存在以下限制：只有同时含 `;` 和 `=` 的字符串才被识别为参数列表，单个 `Key=value` 会被当作文件路径；转义分号仍会被切分，引号和反斜杠也不能按通用 SIP003 转义方式可靠传递；空段会终止后续解析。需要复杂值时可自行维护 JSON 文件。提供 `UID`、`PublicKey`、`ServerName`、`EncryptionMethod`，并按需显式设置 `NumConn=4`，不能依赖 README 所述的默认 4；省略时固定版本实现关闭连接复用。显式端点字段会覆盖 SIP003 环境变量，因此通常应省略 `LocalHost`、`LocalPort`、`RemoteHost`、`RemotePort`。

默认插件传输模式为 `tcp_only`。上游 `UDP=true` 切换为 UDP 监听，不代表同时承载 TCP 与 UDP 的 SIP003u 支持；应用仍允许用户设置现有传输模式，本次只验收 TCP 配置接入。托管程序的 GPL-3.0 许可证、来源与第三方声明随应用装入 `Contents/Resources/ThirdParty/Cloak/`，源码与构建入口见其中 NOTICE。

## 本地与局域网监听

后台代理客户端运行时，本地 SOCKS/HTTP 始终监听 `127.0.0.1`，默认端口为 `11086`/`11087`；本地 SOCKS 固定开启 UDP 中继。局域网入口默认关闭，使用独立端口 `11088`/`11089`，支持 IPv4、双栈和仅 IPv6 三种方式。四端口必须在 `1025...65535` 内且全部不同。

局域网 SOCKS 的 UDP 中继和 SOCKS/HTTP 共用的身份验证独立设置。用户名与密码随监听配置整体加密保存，Keychain 仅保存监听专用主密钥；运行时派生当前用户专用的认证文件；上游认证失败日志中的密码会隐藏。设置只检查 TCP 占用，不设置独立 UDP 端口。首页命令按选择地址使用本地或局域网端口，局域网身份验证开启时加入编码后的凭据；tooltip 显示完整命令。

监听配置单独加密保存在 `proxy-listening.enc`，只包含本地与局域网监听相关值。代理模式、规则默认动作、代理服务开关、系统代理开关和附加系统代理例外以 `proxyControl.` 前缀的独立键保存在 UserDefaults；运行计算的内存快照不代表统一持久化文档。监听仍采用联合校验与原子文件保存；UserDefaults 偏好不提供同步落盘失败的报错与回滚。

不迁移旧 `settings.json`：新监听文件与新增偏好缺值时使用默认值，需要重新设置现有开发配置；旧文件不读取、不删除，遗留 Keychain 条目不访问、不清理。已有语言、静默启动、测试 URL 等独立偏好及服务器资料保持原状。监听读取失败会阻断正常启动，包括静默启动，并显示只含“重置监听配置”的说明性 alert。用户确认后创建新监听主密钥并原子保存默认配置，默认关闭局域网监听。重置成功前保留原文件及已有后台代理和系统代理；成功后按默认配置与原有开关意图收敛。不迁移旧 `proxy-listening.json`，不读取或清理旧逐项 Keychain 凭据；发现旧文件时同样提示确认重置。设计见 [ADR-0034](adr/0034-separate-local-and-lan-listeners.md)、[ADR-0040](adr/0040-keep-settings-recovery-simple.md) 、[ADR-0041](adr/0041-separate-preferences-from-proxy-listening-configuration.md) 和 [ADR-0042](adr/0042-encrypt-proxy-listening-configuration.md)。
