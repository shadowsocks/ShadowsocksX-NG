# Wayfinder issue 18：macOS arm64 SIP003 插件的分发与验证边界

- 票据：[研究：macOS arm64 SIP003 插件的分发与验证边界](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/18)
- 父地图：[Wayfinder: ShadowsocksX-NG 2.0 现代化重实现](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/1)
- 研究日期：2026-09-20（本节所有 GitHub/官方文档链接均于当日访问）
- 适用范围：macOS 15+、仅 arm64、ShadowsocksX-NG 2.0；SIP003 客户端侧插件（由外部 `sslocal` 拉起的外部子进程，#2）
- 证据规则：生态与版本事实以官方仓库 Release/源码与 shadowsocks.org 官方文档一手资料为准；签名/架构/哈希以本机下载静态实测为准（只做不启动代码的观测）；Gatekeeper quarantine 行为以 Apple 一手文档 + 一次用户目视 HITL 观察为准（第 6.1 节，该测试方法已停用，不复现）；版本偏移（本机 macOS 27.0 Build 26A428 vs 目标 macOS 15+）不作外推，列入第 10 节。

## 决策摘要

1. **原生 SIP003 且有官方 darwin arm64 资产的候选只有 5 个**：v2ray-plugin v1.3.2（2022-09）、xray-plugin v1.8.24（2026-02）、shadow-tls v0.2.25（2023-12）、Cloak v2.12.0（2025-07）、qtun v0.3.0（2024-12）。simple-obfs、kcptun、GoQuiet、simple-tls 无任何官方 darwin arm64 资产，只能归「暂不支持」（第 4.6 节）。
2. **全部实测资产签名态与 `sslocal` 完全同一模式**：`Signature=adhoc`（`flags=0x20002(adhoc,linker-signed)`）、`TeamIdentifier=not set`、`spctl --assess` rejected。#16 对 sslocal 的结论（回环零交互、DevID 重签静默）逐条适用于插件；#6 的「官方哈希固定 → DevID 内向外重签 → 随 app 公证」流程无需修改即可扩展到插件。
3. **上游校验和几乎不存在**：5 个候选中只有 qtun 发布了官方 SHA-256（zip 内 `.sha256`，本地比对一致）；其余全部无上游公布哈希。信任根只能是「进入清单时记录的本地复验哈希」，升级时以新 release 的本地复验值为准，无独立审计通道。
4. **建议 2.0 第一版只走「受产品打包管理」路径**（第 7 节）：内嵌插件与 `sslocal` 同流程（固定版本+SHA-256 清单+DevID 重签+随 app 公证）；首版候选建议从 v2ray-plugin（shadowsocks 官方组织、MIT、生态事实标准）开始评估。「用户自行指定」因来源不可验证、quarantine 首启拦截无内联旁路（HITL 观察）而建议第一版不做。
5. **kcptun 的上游已消失**：`xtaci/kcptun` 返回 404（仓库已删除，账号 xtaci 仍在且 kcp-go 库活跃）；官方 SIP003 文档指向的 `shadowsocks/kcptun` 是 fork，最新 release 停在 2017，且其源码不含任何 SIP003 环境变量读取（代码搜索 0 命中）——不构成可维护的依赖对象。
6. **插件失败是 sslocal 侧可观测信号，不是 GUI 猜测**：sslocal 最多等 3 秒检查监听、插件退出写 error 日志、全部插件退出会触发插件监控 task panic（#2，引上游源码）；GUI 呈现应基于这些事实（第 8 节）。

## 2. 候选清单对比表

锚点：shadowsocks.org 官方 SIP003 文档「Known good SIP003 plugins」列出 GoQuiet、Cloak、Kcptun（指向 `shadowsocks/kcptun` fork）、v2ray-plugin（[SIP003 文档](https://shadowsocks.org/doc/sip003.html)）。在此基础上按票据补入生态主流的 simple-obfs、shadow-tls、xray-plugin、qtun、simple-tls。

| 项目 | 语言 | 许可证 | 最新 release（日期） | 官方 darwin arm64 资产 | 上游校验和 | 原生 SIP003 | 维护状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin) | Go | MIT | v1.3.2（2022-09-08） | `v2ray-plugin-darwin-arm64-v1.3.2.tar.gz` | 无 | 是（`args.go` 读 `SS_*`） | 源码活跃（pushed 2026-07-09）但 4 年未发版 |
| [xray-plugin](https://github.com/teddysun/xray-plugin) | Go | MIT | v1.8.24（2026-02-22） | `xray-plugin-darwin-arm64-v1.8.24.tar.gz` | 无 | 是（`args.go` 读 `SS_*`） | 活跃（pushed 2026-04-01）；个人维护者 |
| [shadow-tls](https://github.com/ihciah/shadow-tls) | Rust | MIT | v0.2.25（2023-12-13） | `shadow-tls-aarch64-apple-darwin`（裸二进制） | 无 | 是（`main.rs` 读 `SS_*`） | release 停滞约 2.8 年（pushed 2025-04-25） |
| [Cloak](https://github.com/cbeuw/Cloak) | Go | GPL-3.0 | v2.12.0（2025-07-23） | `ck-client-darwin-arm64-v2.12.0`（裸二进制） | 无 | 是（`ck-client.go` 读 `SS_*`） | 活跃（pushed 2026-05-29） |
| [qtun](https://github.com/shadowsocks/qtun) | Rust | MIT（Cargo.toml 声明；GitHub 许可证 API 未检测到 LICENSE 文件） | v0.3.0（2024-12-31） | `qtun-aarch64-apple-darwin-v0.3.0.zip`（内含 tar.xz + `.sha256`） | **有** | 是（官方 SIP003 插件） | shadowsocks 官方组织，低频（pushed 2026-08-19） |
| [simple-obfs](https://github.com/shadowsocks/simple-obfs) | C/C++ | GPL-3.0 | v0.0.5（2017-11-16） | **无**（唯一资产 `obfs-local.zip` 实测为 Windows PE32+ x86-64） | 无 | 是 | 仓库自述 Deprecated（pushed 2022-11-05） |
| kcptun | Go | MIT（fork） | fork 最新 v20170718（2017-07-18） | **无**（仅 darwin 386/amd64） | 无 | **否**（`SS_*` 代码搜索 0 命中，需第三方 wrapper） | 上游 `xtaci/kcptun` 已 404；[官方文档所指 fork](https://github.com/shadowsocks/kcptun) pushed 2023-02-18 |
| [GoQuiet](https://github.com/cbeuw/GoQuiet) | Go | GPL-3.0 | v1.2.2（2018-10-05） | **无**（仅 darwin 386/amd64） | 无 | 是 | 停更（pushed 2022-03-04） |
| [simple-tls](https://github.com/IrineSistiana/simple-tls) | Go | GPL-3.0 | v0.8.0（2022-10-20） | **无**（v0.8.0 无 darwin 资产；v0.7.0 仅 darwin-amd64） | 无 | 是 | 停更（pushed 2022-10-20） |

## 3. 逐项目证据

### 3.1 v2ray-plugin（shadowsocks 官方组织）

- [Release v1.3.2](https://github.com/shadowsocks/v2ray-plugin/releases/tag/v1.3.2)（2022-09-08）提供 12 个平台资产，含 [`v2ray-plugin-darwin-arm64-v1.3.2.tar.gz`](https://github.com/shadowsocks/v2ray-plugin/releases/download/v1.3.2/v2ray-plugin-darwin-arm64-v1.3.2.tar.gz)。无校验和资产。
- 许可证 MIT（仓库元数据）。构建体系 `go build`（[README](https://github.com/shadowsocks/v2ray-plugin/blob/master/README.md)），符合「只接受官方构建产物」政策（官方已有构建产物，无需本仓库编 Go）。
- SIP003 原生：`args.go` 读取 `SS_REMOTE_HOST` 等环境变量（GitHub 代码搜索确认）。
- 风险：release 停滞 4 年而 master 持续演进（pushed 2026-07-09），发布物与源码漂移。

### 3.2 xray-plugin（teddysun）

- [Release v1.8.24](https://github.com/teddysun/xray-plugin/releases/tag/v1.8.24)（2026-02-22），含 [`xray-plugin-darwin-arm64-v1.8.24.tar.gz`](https://github.com/teddysun/xray-plugin/releases/download/v1.8.24/xray-plugin-darwin-arm64-v1.8.24.tar.gz)，16 个平台资产，无校验和。
- MIT；个人维护者（teddysun，非 shadowsocks 组织）；内嵌完整 Xray-core，实测二进制 19 MB（本节尺寸来自第 4 节下载实测）。

### 3.3 shadow-tls（ihciah）

- [Release v0.2.25](https://github.com/ihciah/shadow-tls/releases/tag/v0.2.25)（2023-12-13），含 [`shadow-tls-aarch64-apple-darwin`](https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-aarch64-apple-darwin) 裸二进制（非归档），无校验和。
- MIT，Rust。SIP003 原生：[`main.rs`](https://github.com/ihciah/shadow-tls/blob/master/src/main.rs) 读取 `SS_REMOTE_HOST/PORT`、`SS_LOCAL_HOST/PORT`、`SS_PLUGIN_OPTIONS`；其 README 与 v3 协议文档均无 SIP003hf 表述，shadowsocks-rust v1.25.0 插件模块亦仅标注 SIP003（[`plugin/mod.rs`](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/mod.rs) 头注释），两者代码搜索 `sip003hf` 均 0 命中。
- 风险：约 2.8 年未发版；协议 v3 为其主要演进方向，与 SIP003 客户端侧的长期兼容性不明。

### 3.4 Cloak（cbeuw）

- [Release v2.12.0](https://github.com/cbeuw/Cloak/releases/tag/v2.12.0)（2025-07-23），含 [`ck-client-darwin-arm64-v2.12.0`](https://github.com/cbeuw/Cloak/releases/download/v2.12.0/ck-client-darwin-arm64-v2.12.0) 裸二进制，18 个平台资产，无校验和。官方 [SIP003 文档](https://shadowsocks.org/doc/sip003.html)列为 Known good。
- **GPL-3.0**：随产品分发该二进制会触发许可证义务（对应源码提供等），与 MIT 候选相比增加分发合规成本；此为事实陈述，法律评估留给后续决策票据。

### 3.5 qtun（shadowsocks 官方组织）

- [Release v0.3.0](https://github.com/shadowsocks/qtun/releases/tag/v0.3.0)（2024-12-31），资产 [`qtun-aarch64-apple-darwin-v0.3.0.zip`](https://github.com/shadowsocks/qtun/releases/download/v0.3.0/qtun-aarch64-apple-darwin-v0.3.0.zip)，**zip 内含 `qtun-v0.3.0.aarch64-apple-darwin.tar.xz` 与官方 `.sha256`**——5 个候选中唯一提供上游公布哈希的项目（v0.2.0 曾以 companion asset 形式提供，v0.3.0 改为 zip 内嵌）。
- 许可证 MIT（[Cargo.toml](https://github.com/shadowsocks/qtun/blob/v0.3.0/Cargo.toml) `license = "MIT"`；GitHub license API 未能自动检测 LICENSE 文件，如实记录）。
- 低频维护（v0.2.0 → v0.3.0 间隔 3 年），生态占用小。

### 3.6 无 darwin arm64 资产的候选（暂不支持的事实依据）

- **simple-obfs**：仓库描述自带 "(Deprecated)"；[v0.0.5](https://github.com/shadowsocks/simple-obfs/releases/tag/v0.0.5)（2017-11-16）唯一资产 [`obfs-local.zip`](https://github.com/shadowsocks/simple-obfs/releases/download/v0.0.5/obfs-local.zip) 实测为 **Windows PE32+ x86-64**（`obfs-local.exe` + `libwinpthread-1.dll`），从未有 macOS 官方构建。C/C++ autotools 构建，纳入本仓库从源码构建违反项目政策。
- **kcptun**：上游 `xtaci/kcptun` 已 404（浏览器级访问复核；账号 [xtaci](https://github.com/xtaci) 仍在、其 kcp-go 库活跃，故为仓库删除而非账号消失）；官方 [SIP003 文档](https://shadowsocks.org/doc/sip003.html)指向的 [shadowsocks/kcptun](https://github.com/shadowsocks/kcptun) 是 fork，最新 release [v20170718](https://github.com/shadowsocks/kcptun/releases/tag/v20170718) 仅 darwin 386/amd64，且源码无任何 `SS_*` 环境变量读取（代码搜索 0 命中）——原生不支持 SIP003，社区靠 [wrapper 脚本](https://github.com/zhanhb/kcptun-sip003-wrapper)拼装，不构成可审计依赖。
- **GoQuiet**：最新 [v1.2.2](https://github.com/cbeuw/GoQuiet/releases)（2018-10-05）仅 darwin 386/amd64，停更约 8 年。
- **simple-tls**：[v0.8.0](https://github.com/IrineSistiana/simple-tls/releases/tag/v0.8.0)（2022-10-20）无任何 darwin 资产（v0.7.0 仅 darwin-amd64），停更。

## 4. 本机静态实测（全部为不启动代码的观测）

方法：`curl -L` 下载官方 release 资产到 `mktemp -d` 临时目录，解包（`tar xzf` / `unzip`）后仅执行 `file`、`lipo -archs`、`codesign -dv --verbose=4`、`spctl --assess`、`xattr -l`、`shasum -a 256`；测毕删除临时目录。**未运行任何下载的二进制，未执行 `--version` 类命令。**

### 4.1 实测结果汇总（arm64 二进制）

| 资产（版本） | file / lipo | codesign | spctl | quarantine | SHA-256（本地复验值） |
| --- | --- | --- | --- | --- | --- |
| v2ray-plugin_darwin_arm64（v1.3.2） | Mach-O arm64 | `Signature=adhoc`，`flags=0x20002(adhoc,linker-signed)`，TeamIdentifier=not set，Identifier=`a.out` | rejected | 无 | `ec19068e4fa0b29c575012b836f4ee3703d286912620966300ee6f5df12fb107` |
| shadow-tls（v0.2.25） | Mach-O arm64 | 同上，Identifier=`shadow_tls-be5b45739694c2a8` | rejected | 无 | `a7c39d70cfc5868f654b19766b768518413ac4ffd9532ea8534a36a1d447b5b1` |
| ck-client（v2.12.0） | Mach-O arm64 | 同上，Identifier=`a.out` | rejected | 无 | `dbef5cd5dd1b551a046c422e07854eb4736fc958e684c6532eb7e809b593ad5c` |
| xray-plugin_darwin_arm64（v1.8.24） | Mach-O arm64 | 同上，Identifier=`a.out` | rejected | 无 | `43e4c7f00a10c05c83ee4e0259e1eafe5b742426e87e249f771d48f011c4cfbb` |
| qtun-client（v0.3.0） | Mach-O arm64 | 同上，Identifier=`qtun_client-7a4e4912c147b3a5` | rejected | 无 | `633ed28505e83d850d5e56a6b735fd59c27e3118920ab0d3e2f523e0c3de5ae9` |
| qtun-server（v0.3.0） | Mach-O arm64 | 同上，Identifier=`qtun_server-514287e0951295bd` | rejected | 无 | `bc0fc629622c99ccff9f3c0cc628fe10d55886613fe4b4a506c0ef95ee33d05f` |

附带：simple-obfs `obfs-local.exe`（v0.0.5）实测为 `PE32+ executable (console) x86-64, for MS Windows`，SHA-256 `e84f8b2b084ff565ebaa5b502b32f8542f29f476903f8a4e8c9e7910bfc860b5`。qtun 内嵌归档官方校验和 `65000f74fd3cbefe1b837d5b8e67e342a3bf8c3a8c2d798cdb8476bfc0dd388d  qtun-v0.3.0.aarch64-apple-darwin.tar.xz` 与本地 `shasum -a 256` 一致。

### 4.2 观察

- 六个二进制（含 sslocal，#16 §7）签名模式完全一致：上游链接器 adhoc 签名、无 CA 身份。**没有任何候选提供可验证上游身份的签名**，供应链验证只能靠「固定版本 + 哈希清单」，与 #6 的机制相同。
- `xattr -l` 各资产仅见 `com.apple.provenance`（系统追加的来源追踪属性），无 `com.apple.quarantine`——`curl` 下载本就不设 quarantine；本节照实记录，不据此推断最终用户经浏览器下载后的属性状态（那属于第 6 节 quarantine 语义，引 Apple 文档）。
- 裸可执行文件的 `spctl --assess` 一律 rejected，照实记录；该命令对非 bundle 裸二进制的评估本就受限，不作为额外证据。
- 与 #16 防火墙结论交叉：客户端插件按 SIP003 在 `SS_LOCAL_HOST:SS_LOCAL_PORT` 监听、由 sslocal 连入（#2），2.0 生成的配置可将该面固定为回环（#12 回环默认）；插件的对外连接是出站流量。按 #16 实测（回环监听零交互、出站不经应用防火墙执法面），**打包插件在默认形态下不引入防火墙弹窗**，无需重复实测。

### 4.3 本次下载过的资产 URL 清单（红线要求的留痕）

```text
https://github.com/shadowsocks/v2ray-plugin/releases/download/v1.3.2/v2ray-plugin-darwin-arm64-v1.3.2.tar.gz
https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-aarch64-apple-darwin
https://github.com/cbeuw/Cloak/releases/download/v2.12.0/ck-client-darwin-arm64-v2.12.0
https://github.com/teddysun/xray-plugin/releases/download/v1.8.24/xray-plugin-darwin-arm64-v1.8.24.tar.gz
https://github.com/shadowsocks/qtun/releases/download/v0.3.0/qtun-aarch64-apple-darwin-v0.3.0.zip
https://github.com/shadowsocks/simple-obfs/releases/download/v0.0.5/obfs-local.zip
```

## 5. 与既有签名/公证/宿主决策的兼容性

- **Developer ID 重签**：插件与 `sslocal` 一样无上游 CA 签名，#6 流程（先校验官方归档/二进制哈希 → `codesign --force --sign <DevID> --timestamp --options runtime --identifier …` → 外层 app 签名）逐字适用；重签使插件获得与 app 同源的 Team ID。
- **公证对嵌套代码的要求**：Apple 公证常见问题文档要求签名校验覆盖嵌套代码（`codesign --verify --strict`「确保检查嵌套代码内容」、其严格度与公证要求一致，[Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)），且公证必须启用 Hardened Runtime（[Hardened Runtime 文档](https://developer.apple.com/documentation/security/hardened-runtime)：「To upload a macOS app to be notarized, you must enable the Hardened Runtime capability.」）；嵌套代码先内后外的签名顺序见 #6 已引的 [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS10003709-CH1-SUBSECTION13)。打包插件因此必须与 sslocal 一样进入「先重签、后公证」链，随 app 公证后整体通过 Gatekeeper。
- **Hardened Runtime 与子进程签名链**：Hardened Runtime 的保护与 entitlements 挂在被签可执行文件自身；文档原文「You add entitlements only to executables. Shared libraries, frameworks, and in-process plug-ins inherit the entitlements of their host executable.」——SIP003 插件是**独立子进程而非 in-process plug-in**，不继承宿主 entitlements；同时 #16 L3 实测已旁证 DevID(+runtime) 父进程可正常拉起 ad-hoc 子进程并令其监听。综合判断「DevID+Hardened 的 sslocal 拉起 adhoc 插件子进程不会被 Hardened Runtime 拦截」，但**无 Apple 一手文档逐字支撑**，列入第 10 节（打包插件经我们重签后该问题基本消失）。
- **plugin_opts 的敏感性**：`plugin_opts` 经 `SS_PLUGIN_OPTIONS` 以明文环境变量传给插件进程（#2），属于 CONTEXT.md 定义的 **Sensitive information**（"plugin options that contain credentials"）；其生命周期按 #10 的凭据规则处理，不得进入日志与诊断转储。

## 6. 三种分发路径

### 6.1 用户自行指定（配置里填插件可执行路径）

- **Gatekeeper 语义（Apple 一手文档）**：Gatekeeper「requests user approval before opening downloaded software for the first time」（[Platform Security: Gatekeeper and runtime protection](https://support.apple.com/guide/security/sec5599b66df/web)）；macOS 15 Sequoia 起「users will no longer be able to Control-click to override Gatekeeper … They'll need to visit System Settings > Privacy & Security」，见 [Apple Developer 新闻：Updates to runtime protection in macOS Sequoia](https://developer.apple.com/news/?id=saqachfa)（2024-08-06）；放行走系统设置 → 隐私与安全性 → Open Anyway（[Safely open apps on your Mac](https://support.apple.com/en-us/102445)）。
- **HITL 观察（用户目视，macOS 27.0，该测试方法已停用）**：先前会话对带 `com.apple.quarantine` 的 shadow-tls 测试副本尝试启动，弹出系统模态「未打开 "shadow-tls-q"」/「Apple无法验证 …」，按钮仅「完成」与「移到废纸篓」，**无内联"打开"旁路**，启动在代码执行前被拦截——与上述 Sequoia 起的 Apple 官方描述一致（macOS 15 上的具体弹窗形态未测，第 10 节）。
- **安全与供应链**：自定路径等于让产品为任意来源二进制背书执行；adhoc/未签名的插件无法验证作者、无法防替换、无更新安全通道。
- **可维护性**：GUI 能做的只有第 8 节的静态事实校验（存在性/可执行位/架构/codesign/quarantine/SHA-256），无法提升信任级别。
- **sslocal 子进程模型兼容性**：见第 5 节——大概率可运行（#16 L3 旁证），但属未验证判断。
- **结论**：技术上可实现最小校验，但信任与体验俱差；**建议 2.0 第一版不做**，仅保留数据模型空间（`plugin` 字段本就是字符串，#2）。

### 6.2 受产品打包管理（插件随 app 进 Contents/Helpers 等）

- **机制**：与 #6 完全同构——对每个插件固定 release tag、资产 URL、SHA-256 清单 → 构建时校验 → DevID 重签 → 装入 bundle → 随 app 公证。对 6.1 的全部短板（不可验证、quarantine 拦截、防火墙不确定性）一次性消除：app 整体公证后 Gatekeeper 放行，回环监听零防火墙交互（第 4.2 节）。
- **供应链责任**：我们替用户背书第三方插件的特定版本；在无上游校验和的 4 个候选上，信任根是本仓库清单中的本地复验哈希（第 3、4 节），升级须人工复验——这与 #2/#6 对 sslocal 的既有立场一致，并非新增负担。
- **更新耦合**：插件升级必须随 app 发版；候选中 v2ray-plugin（4 年未发版）与 shadow-tls（2.8 年未发版）的实际风险是「长期无更新」而非「频繁被迫跟随」。
- **许可证**：MIT 候选无额外义务；GPL-3.0（Cloak）分发须履行源码提供等义务（事实陈述，后续票据评估）。
- **结论**：**唯一建议路径**。首版是否内嵌具体插件是独立决策；若内嵌，建议从 v2ray-plugin（官方组织、MIT、生态事实标准、SIP003 原生）开始评估，xray-plugin（活跃、MIT，但个人维护者）与 qtun（官方组织、MIT、唯一有上游校验和，但低频低占用）列为次选，shadow-tls/Cloak 暂缓（发版停滞 / GPL）。

### 6.3 暂不支持

- **事实归类**：simple-obfs（弃用 + 唯一资产是 Windows exe）、kcptun（上游 404 + 无原生 SIP003 + 官方 fork 停在 2017）、GoQuiet（2018 年后无 arm64）、simple-tls（无 darwin arm64 资产）——四者无官方 arm64 资产或无原生 SIP003，在「只接受官方构建产物」政策下不可纳入。
- **UI 表达**：不支持就是不提供对应预设；若保留 `plugin` 自由输入（面向自备插件的未来路径），须在输入处明示「本版本不校验、不背书第三方插件」并阻断激活或明确警告，**不许诺、不静默失败**。

## 7. 无法验证/无可执行文件时的呈现事实（给 #5 的输入）

GUI 可静态采集的事实清单（全部无特权、不执行目标代码）：

1. 路径存在性、可执行位（POSIX mode）；
2. 架构是否 arm64（Mach-O header 可编程读取，等价于本报告 `file`/`lipo -archs`）；
3. codesign 状态：unsigned / adhoc / Developer ID（含 TeamIdentifier 与 CDHash，等价于 `codesign -dv`）；
4. `com.apple.quarantine` 有无（URL resource values 可读）；
5. SHA-256；
6. 与产品清单（打包插件）比对是否一致；上游是否公布校验和（仅 qtun 有）；
7. sslocal 侧运行时失败信号（#2）：3 秒内未建立 TCP 监听 → 错误；插件进程退出 → error 日志；全部插件退出 → 插件监控 task panic；Unix 下销毁先 SIGTERM、10 ms 后 kill。日志经 LaunchAgent stdout/stderr 捕获（#13）。

不能承诺的边界（UI 不得暗示）：adhoc/未签名插件无法验证作者与完整性；无自动更新的安全通道；`plugin_opts` 可能含凭据、以明文环境变量进入插件进程（敏感信息，#10/CONTEXT.md）；对被 quarantine 拦截的用户自备插件，产品无法代为放行（须用户自行走系统设置 Open Anyway，macOS 15+ 无右键旁路）。

UI 文案要点：打包插件展示「来源项目、许可证、固定版本、由 ShadowsocksX-NG 开发者签名重签」；不支持项展示「无官方 arm64 构建 / 上游已停止维护」类事实原因；插件失败展示「插件未能在 3 秒内建立本地监听」或「插件进程已退出」并指向日志路径。

## 8. 对后续决策的输入

- **#2（配置契约）**：`servers[].plugin`/`plugin_opts` 直通 sslocal；2.0 的校验对象是插件**可执行文件**而非 opts 字符串；打包插件的 `plugin` 值应指向 bundle 内固定绝对路径。
- **#5（UI）**：按第 7 节呈现事实与限制；插件选择器只列打包插件；「暂不支持」给事实原因。
- **#6（打包）**：清单 schema 需支持多二进制（`Vendor/<plugin>/manifest` 同构扩展）；签名脚本按插件逐个重签，`--identifier` 建议沿用 `<bundle-id>.<plugin>` 形式。
- **#10（敏感信息）**：`plugin_opts` 全量按敏感信息处理（含凭据引用化、日志脱敏、迁移不带走生成缓存）。
- **#13（宿主）**：插件是 sslocal 的子进程（launchd 不感知），wrapper 生命周期管理只需管好 sslocal；插件随 sslocal 终止而终止（SIGTERM→kill 链，#2）。
- **#16（防火墙）**：打包插件回环监听零交互，无需进入防火墙诊断面；若未来出现非回环插件场景须重开研究。

## 9. 建议汇总（给后续 grilling 决策票，非最终裁决）

1. 分发路径：只做「受产品打包管理」；「用户自行指定」第一版不做；「暂不支持」作为明确产品状态而非静默缺失。
2. 首版候选评估顺序：v2ray-plugin → qtun → xray-plugin；shadow-tls、Cloak 暂缓；simple-obfs、kcptun、GoQuiet、simple-tls 不支持（事实原因见第 3.6 节）。
3. 无论选谁：清单固定 tag/URL/SHA-256 + DevID 重签 + 随 app 公证；无上游校验和这一残余风险显式记入决策记录。

## 10. 未验证项

1. **macOS 15 实机**的 quarantine/Gatekeeper 弹窗形态与 Open Anyway 流程（HITL 观察来自 macOS 27.0；Apple 文档描述 Sequoia 起的行为，15 上的具体表现未测）。
2. **Hardened Runtime 子进程签名链**：DevID+Hardened 的 sslocal → adhoc 插件子进程在 macOS 15 上的完整运行验证（#16 L3 提供旁证，未覆盖 sslocal→plugin 两级子进程链）。
3. **真实公证流程**对重签后嵌套插件的接受度（本机无 notarytool 凭据，同 #16 遗留）。
4. **功能级兼容性**（各插件协议行为、性能、与真实服务器配合）完全未测——本票据只覆盖分发与验证边界。
5. **候选项目未来 release 行为**（资产命名、校验和引入与否）不受本报告约束；升级任何插件前须重做第 4 节静态清单。
6. Cloak 等 GPL 项目的**分发合规评估**未做（本报告仅陈述许可证类型与义务存在）。

本报告只新增研究文档；未修改 `Legacy/`、未实现 2.0 功能、未触碰工作树中其他会话的未提交文件。
