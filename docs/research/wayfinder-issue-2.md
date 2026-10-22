# Wayfinder issue 2：shadowsocks-rust arm64 发布物与 `sslocal` 配置契约

- 票据：[研究：shadowsocks-rust arm64 发布物与 sslocal 配置契约](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/2)
- 父地图：[Wayfinder: ShadowsocksX-NG 2.0 现代化重实现](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/1)
- 研究日期：2026-09-20
- 适用范围：macOS 15+、仅 arm64、ShadowsocksX-NG 2.0；只使用 `shadowsocks-rust` 官方仓库/源码/Release 和 Shadowsocks 官方 SIP 文档。

## 决策摘要

1. **2.0 首个上游依赖固定为 `shadowsocks-rust v1.25.0`。** 研究日观察到的最新 Release 是 `v1.25.0`，对应提交 [`ab388c7466d21f979430e33cc9ef10e22fb05955`](https://github.com/shadowsocks/shadowsocks-rust/commit/ab388c7466d21f979430e33cc9ef10e22fb05955)。使用官方 `aarch64-apple-darwin` 归档，不使用 `latest`、`master` 或本仓库自行编译。[官方 Release](https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.25.0) [官方发布工作流](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/.github/workflows/build-release.yml#L142-L185)
2. **固定归档 SHA-256，并在构建时验证。** 目标资产为 [`shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz`](https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz)，期望值为 `58e0caf0cc9266c4ea226f38aa20fb28c1be12efc87a73cf5903197867555208`；同时保存并报告官方 [`.sha256` companion asset](https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz.sha256)。上游构建脚本明确用 `shasum -a 256` 生成该文件。[构建脚本](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/build/build-host-release#L21-L25)[构建脚本](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/build/build-host-release#L86-L105)
3. **GUI 启动显式配置文件：** `sslocal -c <absolute-config-path>`。不要依赖上游默认搜索路径，也不要把密码放进命令行参数；上游读取配置文件中的 `password`，并支持 `${VAR_NAME}` 环境变量占位符，但这不是一个独立的安全存储协议。[CLI 入口](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/bin/sslocal.rs#L7-L20)[默认路径与配置读取](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/config.rs#L14-L81)[密码读取](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2137-L2176)[环境变量占位符](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L3446-L3466)
4. **激活分组时把该分组的有效服务器展开到 `servers`，交给上游自动选择。** `sslocal` 对 TCP/UDP 分别维护最佳服务器，按主动探测得到的延迟、失败率、波动和用户权重评分；GUI 不应自行实现第二套选路算法。空分组应由 GUI 拒绝激活，因为上游 balancer 的 `best_*_server` 在无服务器时会断言失败。[多服务器配置](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L315-L355)[选路实现](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L63-L188)[空 balancer 行为](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L217-L231)
5. **订阅分组由 ShadowsocksX-NG 自己解析和持久化。** 上游 SIP-008 loader 只把响应解析成扁平 `servers`，然后替换 `ServerSource::OnlineConfig`；其配置结构没有嵌套分组模型。因此 2.0 应保留完整订阅文档/扩展树，再把当前激活分组翻译成 `sslocal` 配置，而不是把嵌套扩展交给 `sslocal --online-config-url`。[上游在线配置服务](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/online_config/mod.rs#L193-L243)[扁平服务器结构](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L535-L604)[SIP-008 自定义字段与服务器 UUID](https://shadowsocks.org/doc/sip008.html#json-document-format)

## 1. 官方 arm64 发布物与升级策略

### 1.1 当前发布物

上游 README 将 GitHub Releases 作为发布构建下载位置，并明确列出 `aarch64-apple-darwin`；macOS Release job 使用 `macos-latest`、stable Rust 和 `aarch64-apple-darwin` target。[README：Download release](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L130-L136)[发布工作流](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/.github/workflows/build-release.yml#L142-L185)

发布脚本从 `Cargo.toml` 读取版本，打包 `sslocal`、`ssserver`、`ssurl`、`ssmanager`、`ssservice`，再生成 `.tar.xz` 和 `.sha256`；因此 2.0 只需提取 `sslocal`，不应把其余可执行文件当作应用能力承诺。[Cargo target 定义](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/Cargo.toml#L17-L45)[macOS 打包脚本](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/build/build-host-release#L45-L105)

本次对官方归档做了本地验证：归档包含 `sslocal` 等五个上游可执行文件；提取出的 `sslocal` 是 Mach-O arm64，`sslocal --version` 输出 `shadowsocks 1.25.0`；本地 `shasum -a 256` 与官方 `.sha256` 均得到上述 `58e0caf0...55208`。验证对象是未重新签名的官方归档；嵌入 app 后的 helper 会被本项目重新签名，不能再用归档哈希校验签名后的文件。[官方归档](https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz)[官方 SHA-256](https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz.sha256)

### 1.2 2.0 的更新门槛

- 在项目清单中同时固定 `release tag`、上游 commit、target triple、资产 URL、归档 SHA-256 和提取文件名；升级必须是显式变更，重新执行归档、架构、版本和启动检查。[版本来源](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/Cargo.toml#L1-L12)[Release tag](https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.25.0)
- 构建时以清单中的哈希为信任根，再用官方 `.sha256` 文件作独立审计；不要只下载 `releases/latest` 或远端 checksum 后信任同一次可变请求。[官方构建脚本](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/build/build-host-release#L94-L105)
- 2.0 不需要上游 Rust toolchain 或源代码作为构建依赖；官方 Release 已提供目标架构归档，符合“外部开源可执行文件使用源项目构建产物”的项目约束。[官方 README](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L130-L136)

## 2. `sslocal` CLI 与配置文件契约

### 2.1 启动命令

`sslocal` 是独立 binary，`-c/--config` 接收配置文件路径，`-b/--local-addr` 可直接指定本地监听地址；`--protocol` 默认 SOCKS5，完整官方构建还暴露 HTTP、tunnel、redir、DNS、TUN 等按 feature 编译的模式。[binary 定义](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/Cargo.toml#L17-L20)[CLI 参数](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L85-L216)[协议参数](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L713-L728)

上游默认会依次搜索当前目录的 `local.json`/`config.json`、macOS `~/Library/Application Support/org.shadowsocks.shadowsocks-rust/config.json` 等位置；GUI 应始终传绝对路径，避免当前工作目录、旧配置和 launchd 工作目录造成歧义。[默认搜索实现](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/config.rs#L14-L81)

本地配置通过 JSON5 解析，因此严格 JSON 是安全子集；SIP-008 在线响应路径则使用严格 JSON 解析。2.0 生成严格 JSON，避免把 JSON5 注释或尾逗号带入订阅/迁移边界。[本地 JSON5 解析](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2809-L2834)[在线 JSON 解析](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/online_config/mod.rs#L187-L202)

### 2.2 推荐生成的最小配置

```json
{
  "servers": [
    {
      "id": "stable-server-id",
      "remarks": "Example",
      "server": "example.com",
      "server_port": 443,
      "password": "redacted-at-documentation-time",
      "method": "chacha20-ietf-poly1305",
      "mode": "tcp_only"
    }
  ],
  "local_address": "127.0.0.1",
  "local_port": 1080,
  "protocol": "socks",
  "mode": "tcp_only"
}
```

`servers[]` 的 `server`、`server_port`、`method` 和加密方法所需的 `password` 形成核心契约；`disabled: true` 的条目会被跳过，`remarks`/`id` 可用于显示和稳定身份，插件字段及 TCP/UDP 权重也由上游读取。[服务器字段](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L535-L604)[标准字段校验](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2137-L2237)[扩展服务器读取](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2239-L2245)

上游会把 `password` 直接读入 `ServerConfig`；`${VAR_NAME}` 只是在解析阶段从进程环境取值。由于 2.0 仍必须让 `sslocal` 取得真实密码，Keychain 不能单独解决配置文件、进程环境、日志和崩溃驻留问题；本阶段不把 Keychain 作为必选安全边界，生成文件应限制权限、使用短生命周期/原子替换，并避免把秘密放入 argv 或日志。[密码装载](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2161-L2176)[环境变量实现](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L3446-L3466)[文件读取](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2821-L2834)

### 2.3 配置更新与订阅边界

带 `-c` 的 `sslocal` 会记录配置路径；Unix 上收到 `SIGUSR1` 时，上游会重新读取文件并只替换 `ServerSource::Configuration` 服务器。修改服务器列表可以采用“写临时文件—原子替换—发 `SIGUSR1`”的路径；监听地址、协议和本地端口变化仍应重启服务。[配置路径记录](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2821-L2834)[SIGUSR1 reload](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1001-L1014)[reload 实现](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1068-L1135)

上游 `--online-config-url` 默认每 3600 秒更新，启动时先执行一次，要求响应状态 200、读取 JSON 并将在线来源服务器替换进 balancer；允许插件列表是字符串白名单。它不会保留 ShadowsocksX-NG 的嵌套分组树，因此订阅抓取、扩展解析、固定订阅分组和刷新合并必须属于 GUI 层。[在线配置参数](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L557-L581)[在线服务生命周期](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/online_config/mod.rs#L27-L80)[刷新与插件白名单](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/online_config/mod.rs#L104-L243)[SIP-008 HTTPS 与 JSON 契约](https://shadowsocks.org/doc/sip008.html#transport-and-delivery)

## 3. 多服务器自动选择

- `servers` 按配置顺序进入 `PingBalancer`；`disabled` 条目不进入，上游按 `mode` 和 `tcp_weight`/`udp_weight > 0` 分别判定 TCP/UDP 是否可用。[服务器过滤](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2240-L2245)[可用性判定](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L343-L369)
- 多服务器时主动探测 TCP 和 UDP；默认单次探测超时 5 秒、探测间隔 10 秒。TCP 与 UDP 各自保存最佳索引，不保证两者选择同一台服务器。[默认探测参数](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/server_stat.rs#L8-L11)[独立 TCP/UDP 选择](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L205-L231)
- 评分降低延迟中位数、失败率和 MAD 的影响，并除以用户权重；分数越低越好，探测失败计为错误。[评分公式](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/server_stat.rs#L87-L116)[探测失败处理](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L811-L842)
- 初始构建会先探测并选择最佳服务器；只有一个可用服务器时 checker task 不持续探测。GUI 的“激活分组”应保留稳定顺序和服务器 ID，但不把“当前最佳服务器”写回用户配置。[初始化](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L304-L341)[单服务器 checker 行为](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L351-L383)

## 4. 插件进程

SIP-003 规定插件是 Shadowsocks 的子进程，通过 `SS_REMOTE_HOST`、`SS_REMOTE_PORT`、`SS_LOCAL_HOST`、`SS_LOCAL_PORT` 和可选的 `SS_PLUGIN_OPTIONS` 传参；标准描述的通用插件转发目前是 TCP，插件本身不随 `shadowsocks-rust` Release 一起提供。[SIP-003 生命周期与环境变量](https://shadowsocks.org/doc/sip003.html#life-cycle-of-a-plugin)[SIP-003 限制](https://shadowsocks.org/doc/sip003.html#restrictions)[Rust 插件启动](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/ss_plugin.rs#L7-L29)

Rust 实现为每个带插件的服务器启动外部 executable，最多等待 3 秒检查 TCP 监听；插件退出会写 error 日志，所有插件都退出时插件监控 task 会 panic。Unix 下销毁插件时先发 SIGTERM，最多等待 10ms，仍未退出则强制 kill。[插件启动与等待](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/mod.rs#L68-L165)[插件退出监控](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/local/loadbalancing/ping_balancer.rs#L243-L301)[插件终止](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/mod.rs#L167-L244)

因此 2.0 应把插件 executable 作为另一个有版本、有来源、有架构和签名要求的外部依赖；配置编辑器应校验路径/名称并明确插件是外部进程，不应假设仅凭 `plugin_opts` 就能安装插件。第一版不应向用户承诺所有插件的 UDP 兼容性；上游 CLI 虽接受 `tcp_only`、`udp_only`、`tcp_and_udp`，SIP-003 的标准兼容边界仍是 TCP。[Rust plugin_mode 解析](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2192-L2217)[SIP-003 限制](https://shadowsocks.org/doc/sip003.html#restrictions)

## 5. 日志、信号与退出

- 默认日志 writer 是 console；`-v` 逐级提高日志等级，`RUST_LOG` 环境变量优先于默认过滤器；`--log-config` 已隐藏并标记为 deprecated。新 GUI 应优先捕获 LaunchAgent 的 stdout/stderr，或写入应用支持目录中的滚动日志，不要依赖 deprecated `log4rs` 文件配置。[日志配置](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/config.rs#L159-L180)[日志过滤](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/logging/tracing.rs#L23-L152)[CLI 日志参数](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L246-L271)
- Unix 收到 SIGTERM 或 SIGINT 时，monitor 返回正常完成，`sslocal` 以成功退出；服务 future 意外结束或 listener 错误则返回错误。[信号 monitor](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/monitor/unix.rs#L1-L21)[主循环](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1001-L1053)
- 错误退出类别为：服务异常/中止 `EX_SOFTWARE`，配置或 ACL 失败 `EX_CONFIG`，参数不足 `EX_USAGE`；GUI 应把“用户主动停止”和“崩溃/配置失败”分开呈现。[退出码映射](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/error.rs#L6-L40)[主入口](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L1056-L1065)
- 上游提供的 macOS launchd plist 以 `-c` 启动 `sslocal`，并把 stdout/stderr 重定向到文件；2.0 应改成随应用签名分发的 per-user LaunchAgent/`SMAppService` 路径和应用支持目录日志，不能直接复制其中的 `/usr/local`、`/tmp` 全局路径。[官方 macOS plist](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/configs/org.shadowsocks.shadowsocks-rust.plist#L8-L40)

## 6. 对 2.0 实现的最终边界

1. XcodeGen/发布脚本负责固定并校验官方 arm64 Release、提取 `sslocal`、再按项目签名流程嵌入；不编译 `shadowsocks-rust` 源码。[官方 Release 资产](https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.25.0)[官方打包脚本](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/build/build-host-release#L86-L105)
2. GUI 负责分组树、订阅扩展、迁移和敏感配置生命周期；运行时只生成一个当前激活目标的严格 JSON 配置，显式传给 `sslocal -c`。
3. 单服务器激活生成单元素 `servers`；分组激活递归展开有效后代服务器；上游负责健康探测和 TCP/UDP 自动选择。
4. 服务健康判定至少组合 launchd/`SMAppService` 状态、进程退出码、日志诊断和本地 SOCKS 监听检查；不能把进程存在误认为代理可用。

本报告只新增研究文档，未修改 `Legacy/` 或生产代码。
