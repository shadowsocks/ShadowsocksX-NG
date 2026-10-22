# Wayfinder issue 11：macOS 15+ PAC 代理模式的重实现方案

- 票据：[研究：macOS 15+ PAC 代理模式的重实现方案](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/11)
- 父地图：[Wayfinder: ShadowsocksX-NG 2.0 现代化重实现](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/1)
- 研究日期：2026-09-20
- 适用范围：macOS 15+、仅 arm64、ShadowsocksX-NG 2.0；Legacy 只读参考；不把产品扩大为 VPN、TUN 或 Network Extension 代理产品。
- 证据规则：Legacy 源码和本机 SDK/工具是本项目证据；系统契约使用 Apple 官方文档、SDK 头文件和 Apple 官方设备管理 schema；所有实测结果都标注环境，未实测的系统行为不写成事实。

## 决策摘要

1. **2.0 应保留内置 PAC 作为代理模式，但替换 Legacy 的文件监视和状态切换设计。** 目前没有 Apple 提供的“把域名规则直接变成系统分流”的更高层 API。Apple 的公共边界仍是 PAC URL、PAC JavaScript 和 System Configuration 的 Proxies 配置。更好的方案是把规则编译、PAC 交付、系统配置和恢复分成独立的可验证组件，而不是把整个 PAC 生命周期绑在 GCDWebServer 快照和 setuid helper 上。
2. **推荐的默认交付是受控的 loopback HTTP PAC endpoint。** PAC 服务只绑定 127.0.0.1，提供只读、固定 MIME、单一版本化路径的内存快照；每次成功编译产生新 generation URL，避免依赖缓存刷新。PAC 服务可以作为 per-user runtime service 的一部分，不需要 root；系统代理配置仍通过一个最小化、明确授权的 SystemConfiguration seam 写入。
3. **继续使用 SystemConfiguration 的原生 Proxies 配置，不把 networksetup 当作 2.0 的核心 API。** Apple 的 SCPreferences/SCNetworkConfiguration API 明确提供代理配置、提交和应用操作；增强权限需要授权。networksetup 仍可用于诊断或手工恢复，但通过 shell 解析它会增加本地化、错误传播和权限处理风险。
4. **内联 PAC JavaScript 是值得做的短期原型，不应在没有目标系统实测前替代 URL。** Apple SDK 和文档公开了 ProxyAutoConfigJavaScript key，以及 CFNetwork 对内存 PAC 脚本的执行 API；但公开资料没有承诺把该 key 写入每个 network service 后，macOS 27/15 上所有系统客户端都按系统 PAC 模式使用它。因此它是可验证的候选优化，不是本票据可以直接锁定的默认实现。
5. **file URL 不作为默认方案。** Legacy 接受 file/http/https URL，但 Apple 的当前公开用户文档只保证“Automatic proxy configuration + PAC URL”这一配置边界，没有为本产品承诺 file URL 在 macOS 15+ 的所有系统客户端中可用。迁移时保留原值并做能力校验；未经目标版本实测，不应把 file PAC 宣传为支持能力。
6. **Network Extension App Proxy、Transparent Proxy、Packet Tunnel 都不属于 PAC 替代方案。** Apple 将这些能力定义为 VPN/流量代理并要求 Network Extension entitlement；它们会扩大本地图的目标，不应作为 PAC 研究的默认逃生路线。

## 1. Legacy 的真实 PAC 契约

Legacy 的 PAC 是“规则编译 + 本机 HTTP 托管 + 特权系统代理写入”的组合，不是一个可以直接复制到 2.0 的静态文件。

- PAC 状态目录是 ~/.ShadowsocksX-NG/；输出为 gfwlist.js，输入为 gfwlist.txt 和 user-rule.txt。首次运行从 bundle 复制规则资源，同时迁移旧的 ~/.ShadowsocksX-NE/ 目录。[PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L12-L17) [PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L51-L73)
- GeneratePACFile() 对 Base64 GFWList 解码，把用户规则置前并去重，过滤空行/注释，再把规则和 SOCKS 地址/端口替换进 abp.js；结果用临时文件加 rename 原子替换 gfwlist.js。[PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L79-L150)
- abp.js 的 FindProxyForURL 命中规则时返回 SOCKS5/SOCKS/DIRECT，否则返回 DIRECT。[abp.js](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/abp.js#L1-L6) [abp.js](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/abp.js#L768-L777)
- 本地 PAC URL 固定为 http://localhost:<port>/proxy.pac；GCDWebServer 在启动时把文件读入 originalPACData，只注册 GET /proxy.pac，并返回 application/x-ns-proxy-autoconfig。[ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L136-L153) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L206-L253)
- 默认监听 localhost:1089，端口和绑定范围来自 UserDefaults；PAC 文件变更由 vnode 监视器触发 disableProxy 后 enablePACProxy。[AppDelegate.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/AppDelegate.swift#L91-L115) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L262-L294)
- 系统代理由 /Library/Application Support/ShadowsocksX-NG/proxy_conf_helper 写入。安装脚本把 helper 设为 root:admin、a+rx 并加 setuid；helper 使用 AuthorizationCreate 和 SCPreferencesCreateWithAuthorization，处理 auto/global/off 以及网络服务、例外项。[install_helper.sh](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/install_helper.sh#L10-L14) [proxy_conf_helper/main.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/proxy_conf_helper/main.m#L105-L216)
- 外部 PAC 直接把 ExternalPACURL 传给相同的 helper；PACURLFormatter 接受 file/http/https，但没有看到内容、可达性或来源完整性校验。[PACURLFormatter.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACURLFormatter.swift#L26-L52) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L195-L221)

源码盘点发现的具体风险边界：

- PAC 服务失败的布尔结果未向上层传播，之后仍可能把不可用 URL 写入系统代理；用户端口允许 128–65535，但 URL/监听路径有 short 窄化，32768–65535 存在表示范围不一致。[ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L206-L215) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L244-L252)
- 原子替换会产生 vnode DELETE；监视器在 DELETE 事件中取消自身，而源码没有持续重装路径。后续规则更新并不保证仍会被观察到。[PACUtils.swift](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/PACUtils.swift#L146-L150) [ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L273-L293)
- helper 的 auto/global 路径从部分 key 新建 Proxies 字典，关闭时只在 PAC URL 或 SOCKS 值恰好匹配调用方参数时清除；它没有保存并恢复用户原有的完整代理字典。[proxy_conf_helper/main.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/proxy_conf_helper/main.m#L126-L216)
- 外部 PAC 启用时传入外部 URL，但 disableProxy 始终传本地 getHttpPACUrl；外部 PAC 进入 manual/off 或退出的清理路径因此存在状态不对称。[ProxyConfHelper.m](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/ProxyConfHelper.m#L178-L203)
- PAC 模板头部标注由 gfwlist2pac 生成并带 GPLv3 声明。2.0 若继续重用该模板，要把许可和生成器来源作为独立发布检查项；本票据不假定其上游维护状态。[abp.js](https://github.com/shadowsocks/ShadowsocksX-NG/blob/legacy-v1/ShadowsocksX-NG/abp.js#L1-L22)

## 2. Apple 当前的 PAC 和系统代理边界

### 2.1 用户可见契约

Apple 当前的 macOS 用户指南把 Automatic proxy configuration 定义为“使用 PAC 文件，并在 URL 字段输入 PAC 文件地址”，同时把 Auto proxy discovery、HTTP、HTTPS、SOCKS 和 bypass hosts/domains 列为不同选项。[Apple Support：Enter proxy server settings on Mac](https://support.apple.com/en-nz/guide/mac-help/mchlp25912/mac)

这支持 2.0 继续把 PAC 视为一个独立 Proxy mode；它不支持把 PAC 误说成自动 TUN、VPN 或覆盖所有网络路径的系统替代品。

### 2.2 SystemConfiguration 是写入系统配置的原生边界

Apple 的 SystemConfiguration 文档公开了：

- kSCPropNetProxiesProxyAutoConfigEnable：Proxies 字典中的 0/1 开关。[文档](https://developer.apple.com/documentation/systemconfiguration/kscpropnetproxiesproxyautoconfigenable-swift.var)
- kSCPropNetProxiesProxyAutoConfigURLString：Proxies 字典中的 PAC URL 字符串。[文档](https://developer.apple.com/documentation/systemconfiguration/kscpropnetproxiesproxyautoconfigurlstring-swift.var)
- SCNetworkServiceCopyAll、SCNetworkServiceCopyProtocol 和 SCNetworkProtocolSetConfiguration：读取 network services 并保存指定协议配置；SCNetworkConfiguration 总览要求通过 SCPreferencesCommitChanges 持久化。[SCNetworkConfiguration](https://developer.apple.com/documentation/systemconfiguration/scnetworkconfiguration) [SCNetworkProtocolSetConfiguration](https://developer.apple.com/documentation/systemconfiguration/scnetworkprotocolsetconfiguration%28_%3A_%3A%29)
- SCPreferencesCreateWithAuthorization：访问需要增强权限的 per-system preferences session；SCPreferencesCommitChanges 持久化，SCPreferencesApplyChanges 请求应用到 active configuration。[创建授权 session](https://developer.apple.com/documentation/systemconfiguration/scpreferencescreatewithauthorization%28_%3A_%3A_%3A_%3A%29) [提交](https://developer.apple.com/documentation/systemconfiguration/scpreferencescommitchanges%28_%3A%29) [应用](https://developer.apple.com/documentation/systemconfiguration/scpreferencesapplychanges%28_%3A%29)

这意味着“换成 Apple API”不能理解为“免权限”：2.0 可以把 Legacy 的 setuid root 全局 helper 收窄为只负责代理配置的授权边界，但仍必须明确授权、提交、应用、失败传播和原配置恢复。

### 2.3 CFNetwork 能执行 PAC，但不是系统配置写入 API

Apple CFNetwork 文档同时公开 CFNetworkCopySystemProxySettings、CFNetworkCopyProxiesForURL、CFNetworkCopyProxiesForAutoConfigurationScript 和 CFNetworkExecuteProxyAutoConfigurationURL；它们分别读取系统代理、计算某 URL 的代理、执行内存脚本或下载并执行 PAC URL。[CFNetwork](https://developer.apple.com/documentation/CFNetwork)

Apple 还公开了两个相关 key：

- kCFNetworkProxiesProxyAutoConfigURLString 的值是 PAC 文件 URL。[文档](https://developer.apple.com/documentation/cfnetwork/kcfnetworkproxiesproxyautoconfigurlstring)
- kCFNetworkProxiesProxyAutoConfigJavaScript 的值是完整 PAC JavaScript；kCFProxyTypeAutoConfigurationJavaScript 表示由提供的脚本决定代理。[JavaScript key](https://developer.apple.com/documentation/cfnetwork/kcfnetworkproxiesproxyautoconfigjavascript) [Proxy type](https://developer.apple.com/documentation/cfnetwork/kcfproxytypeautoconfigurationjavascript)

这确认“内存 PAC 脚本”是 CFNetwork 的真实能力，但这些页面没有承诺把 JavaScript key 写入每一个 network service 后，macOS 15+ 的所有系统客户端都像用户在 Network > Proxies 中启用 PAC URL 一样使用它。它必须先在目标版本的 disposable network service 上实测，不能仅凭 key 名称选型。

### 2.4 Network Extension 是不同产品边界

Apple 把 NEAppProxyProvider 描述为 app extension 中的透明网络代理；App Proxy provider 文档明确把它放在 flow-oriented custom VPN client 语境中，并要求 com.apple.developer.networking.networkextension entitlement。[NEAppProxyProvider](https://developer.apple.com/documentation/networkextension/neappproxyprovider) [App proxy provider](https://developer.apple.com/documentation/networkextension/app-proxy-provider) [Network Extensions entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.networking.networkextension)

因此 App Proxy、Transparent Proxy、Packet Tunnel 不能作为本票据的 PAC 替代。选择它们会重画地图目的地，带来 entitlement、extension lifecycle、用户批准和 VPN/流量覆盖问题。

## 3. 候选方案比较

| 方案 | Apple 证据 | 兼容/迁移判断 | 决定 |
| --- | --- | --- | --- |
| Legacy 本机 HTTP + 文件快照 | macOS 用户契约明确接受 PAC URL；Legacy 已有可工作的交付路径 | 兼容性最高，但旧实现有端口、缓存、watcher、恢复和 setuid 风险 | 保留 PAC URL 形态，重写生命周期和安全边界 |
| 受控 loopback HTTP + versioned endpoint | 同上；PAC URL 是公开系统边界 | 继续覆盖 Safari/CFNetwork 等使用系统 PAC 的客户端；服务可与 per-user runtime 同生命周期 | **2.0 默认推荐** |
| file URL | Legacy formatter 接受 file；Apple 当前公开指南只说明 PAC URL，不保证 scheme/客户端覆盖 | 容易绕过 HTTP server，但目标系统兼容和缓存语义未证实 | 迁移保留，能力校验通过前不承诺 |
| 内联 ProxyAutoConfigJavaScript | Apple SDK/API 明确有 key 和 CFNetwork 脚本执行能力 | 可能消除本地 server 和 URL cache，但没有公开的 system-wide client 契约；需要目标系统实验 | 做小型 prototype；不作为默认 |
| networksetup shell | 本机 networksetup 1.8.4 提供 -setautoproxyurl/-getautoproxyurl/-setautoproxystate；help 明确改变网络设置至少需要 admin | 可作为诊断/恢复工具；shell、权限和输出格式不应成为核心状态机 | 不作为核心 API |
| Network Extension App/Transparent/Packet Tunnel | Apple 官方支持，但定义为 VPN/流量代理并需要 entitlement | 超出 PAC 和当前地图目的地 | 明确排除 |

### 本机观察（不是跨版本契约）

研究机器的环境是 macOS 27.0（Build 26A428）、arm64，networksetup Version 1.8.4。2026-09-20 执行 networksetup -help 观察到：

- 存在 -setautoproxyurl <networkservice> <url>、-getautoproxyurl 和 -setautoproxystate。
- help 末尾说明 networksetup 改动 network settings 至少需要 admin privileges；执行 help 自身还打印 AuthorizationCreate() failed: -60008。
- 当前 scutil --proxy 只有 HTTP/HTTPS/SOCKS 指向 127.0.0.1:64649，ProxyAutoConfigEnable 为 0；这只是本机当前状态，不是产品行为或最低系统保证。

当前 SDK 的官方头文件也直接记录了 PAC schema：

~~~text
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SystemConfiguration.framework/Headers/SCSchemaDefinitions.h
  kSCPropNetProxiesProxyAutoConfigEnable             "ProxyAutoConfigEnable"        CFNumber (0 or 1)
  kSCPropNetProxiesProxyAutoConfigJavaScript         "ProxyAutoConfigJavaScript"    CFString
  kSCPropNetProxiesProxyAutoConfigURLString          "ProxyAutoConfigURLString"     CFString
~~~

头文件是编译期 API/schema 证据，不等于 JavaScript key 已在所有网络客户端上通过系统配置路径验证。

## 4. 2.0 推荐的 PAC 设计约束

### 4.1 规则编译器

- 把 GFWList、用户规则和激活目标转成一个纯的 PAC snapshot；输入校验、规则去重、SOCKS host/IPv6 格式化和 JavaScript 字符串转义必须在编译阶段完成。
- 编译失败时保留最后一个有效 snapshot，并把错误呈现为 stale/error 状态；不得把半成品或空 PAC 替换到系统配置。
- 生成器不得依赖文件 vnode 事件来触发服务重启。成功编译产生不可变 generation；服务收到显式 publish 命令后切换快照。
- 是否继续复用 gfwlist2pac 的 abp.js，必须另做 GPLv3/上游维护审查；本票据只决定交付和生命周期，不把第三方规则源写死成产品承诺。

### 4.2 PAC endpoint

- 只监听 127.0.0.1；不要把可配置的 “localhost” 解析结果或用户输入地址作为绑定地址。
- 只允许 GET 一个固定路由族，例如 /v1/pac/<generation>；不提供任意文件路径、不回显 query 中的敏感信息。
- 返回完整 JavaScript、application/x-ns-proxy-autoconfig，并显式返回 no-store；generation URL 变化是缓存失效的主机制，Cache-Control 只是额外防线。
- server 启动失败、端口冲突、健康检查失败必须阻止把 URL 写入系统代理；已有有效 PAC 应继续使用或进入明确停止状态。
- PAC endpoint 属于 per-user runtime 生命周期。显式停止时先清理自己拥有的系统配置再停 server；异常崩溃恢复时通过保存的 ownership URL/token 判断是否需要清理，不能按“当前是 PAC”盲目覆盖用户配置。

### 4.3 系统代理事务

- 为每个目标 network service 读取完整 Proxies 字典，只改 ProxyAutoConfigEnable、ProxyAutoConfigURLString（或经过实测的 JavaScript key）以及产品明确拥有的例外项。
- 提交前保存原字典和 ownership record；SCPreferencesCommitChanges 成功后调用 SCPreferencesApplyChanges，并检查两个返回值。
- 停止/切换到 global/manual/off 时，只有当前 URL 或 generation 仍匹配本产品 ownership 才恢复原字典；如果用户已经手动改过，报告冲突并保留用户最新状态。
- 系统配置 helper 只负责授权的 network service/proxy 操作，不承载 PAC 编译、不读取服务器密码、不运行任意 URL；不要继续使用长期 setuid root 作为默认安全边界。
- 用 service ID 而不是显示名称保存选择，并在网络服务增删/切换后重新解析当前 set。Apple 的 SCNetworkServiceCopyAll/SCNetworkSetCopyCurrent 是该查询边界。

### 4.4 外部 PAC

- External PAC 仍可作为独立 Proxy mode，但保存 URL 时至少做 scheme、长度和明显凭证泄漏校验；启用前做 URL 可达性/响应类型检查，失败不切系统代理。
- 迁移 file/http/https 字符串时不静默改写。对于 file URL，显示“需要在当前 macOS 版本验证”的状态；若能力测试失败，提供迁移错误和人工修复入口。
- 外部 PAC 的停用必须传入并匹配实际 external URL，修复 Legacy disableProxy 总是使用本地 URL 的不对称。

## 5. 验证计划

以下是进入实现前必须完成的 macOS 15+ arm64 验证，不把本报告中的推断当成已通过测试：

1. 在 macOS 15 的干净测试账户和 macOS 27.0 Build 26A428 的测试账户各建立一个可回滚的网络 service；记录原始 Proxies 字典，不在日常网络配置上直接试验。
2. 用最小 PAC 脚本分别验证 URL endpoint 和 ProxyAutoConfigJavaScript：GET 状态码、MIME、loopback 绑定、CFNetworkCopyProxiesForURL/CFNetworkCopyProxiesForAutoConfigurationScript 结果，以及 Safari/URLSession 的实际系统代理行为。
3. 编译一个 generation，访问多个 URL，再发布第二个 generation；确认不重启 app 时系统客户端不会继续使用旧快照。分别测试 URL path 变化、ETag/no-store、服务重启和端口变化。
4. 规则输入覆盖空列表、注释、重复项、Unicode、IPv4/IPv6 SOCKS 地址、引号/换行/反斜杠和超大规则集；对非法输入确认旧 snapshot 保留且错误可见。
5. 测试 PAC server 启动失败、端口冲突、sslocal 崩溃、app/LaunchAgent 重启、网络服务增删和用户在外部手动改代理后的恢复/冲突语义。
6. 对 PAC/global/manual/external PAC 循环切换，确认每个模式清理的是本产品拥有的 key，原 HTTP/HTTPS/SOCKS、例外项和其他 MDM 设置不被覆盖。
7. 对外部 http、https、file PAC 分别记录“可用/不可用、适用客户端、缓存行为”；未在 macOS 15 和 27 都通过的 scheme 不进入稳定支持矩阵。
8. 用 codesign/notarized 2.0 构建和实际 per-user runtime 运行一次；确认 PAC 服务无 root 权限也能工作，而只有系统代理写入需要用户授权的最小 helper。

## 6. 对后续票据的明确约束

- 「决策：Legacy 配置迁移与旧版功能边界」：迁移 PAC、外部 PAC URL、GFWList URL、用户规则和网络服务选择，但不迁移旧的 vnode watcher、固定 1089 端口、setuid helper 设计或不对称的 external PAC 清理逻辑；file URL 需要能力校验后再决定保留/报错。
- 「决策：SwiftUI 菜单栏与配置管理界面信息架构」：PAC、global、manual、external PAC 仍是互斥的 Proxy mode；界面必须能呈现 PAC snapshot stale/error、系统代理授权失败、端口/服务冲突和外部 PAC 不可用，不把 PAC 描述为 VPN/TUN。
- 「研究：macOS 15 arm64 外部服务与应用生命周期」的 per-user launchd 结论可用于 PAC runtime 的监督，但不自动授予修改系统网络配置的权限；两条生命周期仍需分开显示健康状态。

本报告只新增研究文档；未修改 Legacy/ 或 2.0 生产代码。
