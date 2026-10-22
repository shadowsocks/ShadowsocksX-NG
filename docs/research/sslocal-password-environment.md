# sslocal 通过环境变量传递 `password` 的安全边界研究

> 研究日期：2026-09-25（Asia/Shanghai）  
> 上游基线：官方 `shadowsocks-rust` v1.25.0，tag commit `ab388c7466d21f979430e33cc9ef10e22fb05955`；本仓库 vendor 清单也固定为该版本和 `aarch64-apple-darwin`。见 [`ShadowsocksX-NG2/Vendor/sslocal/manifest.json`](../../ShadowsocksX-NG2/Vendor/sslocal/manifest.json#L1-L11)。  
> 证据范围：`shadowsocks-rust` 官方文档/源码、Rust/POSIX/Apple 一手文档、本仓库源码，以及本机对仓库内官方 v1.25.0 二进制的最小验证。没有使用博客、论坛或第三方教程。

## 结论先行

1. **可以，但限定于实现和版本。** 官方 `shadowsocks-rust` 的 `sslocal` 从 v1.12.3 起支持在配置文件的 `password` 字段使用完整形式 `${VAR}`；v1.12.2 尚不包含该配置文件能力。当前 v1.25.0 仍支持，官方 README 的示例就是 `"password": "${PASSWORD_FROM_ENV}"`。[README 示例](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L795-L805)、[v1.25.0 配置加载源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2137-L2179)。这不是所有名为 `sslocal` 的实现都必然支持的通用 JSON 语法。
2. **它不是 shell 展开，也不是 JSON/Serde 的通用变量替换。** 只有整个字段恰好以 `${` 开头、以 `}` 结尾时，`shadowsocks-rust` 才取中间字符串作为环境变量名；嵌入式文本不会展开，且当前源码明确只对 `password` 使用该函数。[源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L3446-L3466)
3. **密码值不进入 `sslocal` 的 argv，但会进入其进程环境和内存。** `sslocal` 的 JSON 配置路径仍在 argv 中，环境变量值由 `std::env::var` 读入，再用于创建内存中的 `ServerConfig` 和派生密钥；配置文件本身不会被 `sslocal` 回写。Rust/POSIX/Apple 文档都把 argv 与 environment 作为不同的进程启动输入。[sslocal 启动调用链](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L624-L638)、[ServerConfig 的 password 字段](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/config.rs#L403-L410)、[POSIX exec 环境说明](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html)、[Apple Process.arguments](https://developer.apple.com/documentation/foundation/process/arguments?changes=_9)、[Apple Process.environment](https://developer.apple.com/documentation/foundation/process/environment?changes=_2)
4. **安全性是“减少 argv/配置文件持久暴露”，不是秘密管理或不可观察。** 同一用户权限下的进程检查、调试/崩溃采集、父进程/启动器日志、以及 sslocal 启动的插件都可能接触环境或内存中的值。官方 SIP003 plugin 启动代码没有清空环境，因此 plugin 子进程默认继承包括该变量在内的父环境。[官方 plugin 启动源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/ss_plugin.rs#L7-L29)、[Rust Command 的默认继承规则](https://doc.rust-lang.org/std/process/struct.Command.html#method.new)
5. **对当前 ShadowsocksX-NG2 不直接适用。** NG2 当前不生成 `${VAR}` 占位符，也不把 Keychain 密码注入 agent 环境；它在激活时从凭据存储解析密码，写入 `sslocal-active.json` 的明文 `password` 字段，再由 wrapper 以 `sslocal -c <path>` 启动。wrapper 会把自身环境整体传给 sslocal，但这并不等于它提供了某个服务器密码变量。[NG2 激活解析](../../ShadowsocksX-NG2/Domain/ActivationStateMachine.swift#L164-L223)、[NG2 runtime 文档](../../ShadowsocksX-NG2/Domain/SslocalRuntimeDocument.swift#L149-L210)、[NG2 wrapper spawn](../../ShadowsocksX-NG2/Agent/main.swift#L395-L406)

## 1. `${VAR}` 是否由 sslocal 解析，在哪个版本/实现中

### 1.1 当前实现的实际语义

`shadowsocks-rust` v1.25.0 的配置加载器在两条 JSON 路径都调用 `read_variable_field_value`：

- 标准单服务器配置的顶层 `password`：加载 `server/server_port/password/method` 后调用该函数，再创建 `ServerConfig`。[源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2137-L2179)
- 扩展配置的 `servers[]` 条目：同样先解析 `svr.password`，再调用该函数。[源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2247-L2287)

`sslocal` 以 `ConfigType::Local` 调用同一个配置加载器；命令行 `--password/-k` 也调用同一函数，因此命令行若传入字面量 `'${VAR}'` 也会解析，但命令行 shell 是否已先展开是另一层问题。[sslocal 源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L624-L638)

解析函数的边界很窄：

- `${PASSWORD_FROM_ENV}`：读取环境变量 `PASSWORD_FROM_ENV`。
- `prefix${VAR}`、`${VAR}suffix`、`$VAR`、`{VAR}`：不替换，原样作为密码字符串。
- 变量不存在，或环境变量不是有效 UTF-8：记录 warning，并返回原始 `${VAR}` 字符串；**不会自动变成空字符串，也不会把它当成硬错误**。因此部署器应在启动前验证变量存在，否则程序可能以错误的字面量密码继续初始化。[源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L3446-L3466)

### 1.2 版本边界

官方历史提交给出了可审计的版本边界：

- 提交 `74e8a4f8f58ce60545d778f2f083caab72478eea`（2021-11-25）首次把配置文件 `password` 的 `${VAR_NAME}` 读取接入 `shadowsocks-service`，并同时加入 README 示例；提交说明明确写的是“Servers in configuration file `password` field support `${VAR_NAME}`”。[提交 diff](https://github.com/shadowsocks/shadowsocks-rust/commit/74e8a4f8f58ce60545d778f2f083caab72478eea)
- v1.12.2 于 2021-11-16 发布，早于该提交；v1.12.3 于 2021-11-26 发布，并包含该代码。[v1.12.2 release](https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.12.2) 与 [v1.12.3 release](https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.12.3) 可固定版本；对比 [v1.12.2 `config.rs`](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.12.2/crates/shadowsocks-service/src/config.rs) 与 [v1.12.3 `config.rs`](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.12.3/crates/shadowsocks-service/src/config.rs) 可见，前者没有 `read_variable_field_value`，后者已在标准配置和 `servers[]` 两处调用它。
- 提交 `7aec233271670cfc4053bc6cfa0e477baf722790`（2021-11-25）随后把同一语法扩展到命令行 `--password`，并修正变量不存在时保留原文而不是变成空字符串。[提交 diff](https://github.com/shadowsocks/shadowsocks-rust/commit/7aec233271670cfc4053bc6cfa0e477baf722790)

所以本报告的“可用”结论适用于官方 `shadowsocks-rust` v1.12.3 及之后的该配置实现，且已在本仓库固定的 v1.25.0 上复核；不能外推到 `shadowsocks-libev`、其他语言实现或旧版 fork。

## 2. 环境变量值如何进入进程，以及会出现在哪里

### 2.1 进程入口

环境变量必须在启动 `sslocal` 的父进程或服务管理器环境中存在。`std::env::var` 在 `sslocal` 已经启动后读取该进程的环境；它不会从配置文件、Keychain 或某个远程服务自动获取变量。

对 macOS `Process`/`NSTask`，Apple 将 `arguments` 定义为传给 executable 的 `argv[]`，将 `environment` 定义为独立的环境字典；若不另设环境，子进程继承启动它的进程环境。[Apple arguments](https://developer.apple.com/documentation/foundation/process/arguments?changes=_9)、[Apple environment](https://developer.apple.com/documentation/foundation/process/environment?changes=_2)。POSIX `execve` 也明确把 `argv[]` 和 `envp[]` 作为分离的参数数组。[POSIX exec](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html)

因此典型配置：

```sh
export PASSWORD_FROM_ENV='secret'
sslocal -c /path/to/config.json
```

其中 argv 只含 executable、`-c` 和配置文件路径；密码在 `envp` 中。若写成 `sslocal -k "$PASSWORD_FROM_ENV"`，shell 会先把密码替换进命令行，密码就会重新进入 argv；这不是 `${VAR}` 配置文件方案的安全形状。命令行值也可能进入 shell 历史或启动器审计记录，具体取决于启动方式。

### 2.2 配置文件和内存

`Config::load_from_file` 只读入文件文本，再交给 JSON/JSON5 解析和配置转换；环境替换发生在内存中。随后 `ServerConfig` 保存一个 `password: String`，并用它派生 `enc_key`。[读取文件](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2809-L2828)、[ServerConfig 字段](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/config.rs#L403-L414)、[密钥派生](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/config.rs#L447-L475)

这意味着：

- 原始配置文件可以只保存 `${PASSWORD_FROM_ENV}`，`sslocal` 不会把解析出的值回写到该文件；这是相对明文 JSON 的主要收益。
- 解析后的密码仍会在 sslocal 的用户态内存中存在，至少存在于配置对象/密码字符串和派生过程相关数据中；环境变量没有让密码变成“只存在于内核”的秘密。
- 文件权限、备份、APFS 快照、诊断收集等风险只在文件确实没有明文密码时减少；如果外层程序先把环境值写回 JSON，收益就消失。

### 2.3 日志

v1.25.0 的环境替换函数在失败时只记录变量名和错误，不把环境变量的值拼进 warning。[源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L3454-L3465)

在当前 `sslocal` 启动路径中，显式 `trace!("{:?}", service_config)` 位于加载服务层配置之后、加载 Shadowsocks 配置对象之前；被 trace 的对象是外层 runtime/log 配置，不是已解析的 `ServerConfig` 列表。[源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L605-L627)

但这不应被解释成“日志永远安全”：官方依赖中的 `ServerConfig` 是 `#[derive(Debug)]` 且包含 `password: String`，任何集成层、未来版本或调试代码如果直接打印该对象，都可能把密码写入日志。[依赖源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/config.rs#L403-L410) 因此建议把 `RUST_LOG=trace`、崩溃转储和第三方 wrapper/plugin 日志视为需要单独审计的面。

### 2.4 子进程/plugin 环境

SIP003 plugin 是重要例外。官方 v1.25.0 用 Tokio `Command::new(&plugin.plugin)` 启动 plugin，设置 `SS_REMOTE_*`、`SS_LOCAL_*`、可选 `SS_PLUGIN_OPTIONS`，但没有调用 `env_clear` 或移除未知变量；Rust `Command` 的默认行为是继承父进程环境。[官方 plugin 源码](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/ss_plugin.rs#L7-L29)、[Rust Command 文档](https://doc.rust-lang.org/std/process/struct.Command.html#method.new)

所以若 `PASSWORD_FROM_ENV` 在 sslocal 环境中，官方启动的 plugin 默认也能读取它；plugin 若继续创建子进程，通常还会把它继续传递。受信任、受签名约束的 plugin 可以把这个面纳入产品边界；不受信任 plugin、插件参数中调用的脚本或诊断工具不能被视为隔离的秘密存储。

## 3. 最小可复现验证（2026-09-25）

使用本仓库已固定的 `ShadowsocksX-NG2/Vendor/sslocal/sslocal`，其二进制输出为 `shadowsocks 1.25.0`，架构为 arm64。临时配置的核心内容是：

```jsonc
{
  "servers": [{
    "server": "127.0.0.1",
    "server_port": 1,
    "method": "aes-256-gcm",
    "password": "${SSXNG_RESEARCH_PASSWORD}"
  }],
  "locals": [{
    "protocol": "socks",
    "local_address": "127.0.0.1",
    "local_port": 11986,
    "mode": "tcp_only"
  }]
}
```

以 `SSXNG_RESEARCH_PASSWORD=ENV-ONLY-RESEARCH-MARKER` 启动，观察到：

- sslocal 输出 v1.25.0，并成功监听 `127.0.0.1:11986`；这证明配置文件路径、`servers[].password` 的环境替换和后续配置初始化都通过。远端设置为本机端口 1，未发起真实服务器连接。
- `ps -ww` 的命令行只有 `sslocal -c .sslocal-env-verification.jsonc`，没有 marker。
- 同用户 `ps eww` 能看到该 marker 所在的环境变量；报告不复述其完整值。这是本机实证的环境暴露面，不把它夸大为跨用户/跨权限读取能力。
- `agent`/sslocal 日志没有出现 marker；原始 JSON 在启动后仍只包含 `${SSXNG_RESEARCH_PASSWORD}`。
- 首次在受限沙箱中运行时，系统配置读取/监听被 sandbox 拒绝；在获得一次受控执行许可后重复运行得到以上结果。该验证没有修改源代码，临时配置已删除，仓库仅保留本报告。

验证命令的关键观察面是：

```sh
ps -ww -o pid=,command= -p <sslocal-pid>
ps eww -p <sslocal-pid>
```

这项 CLI 验证只证明本仓库所固定的 v1.25.0 二进制实际接受该配置并启动，不证明任何特定系统服务管理器会安全提供环境变量，也不证明 plugin 会主动隐藏它。

## 4. 安全边界和与其他方式的比较

| 方式 | argv | 配置文件 | 进程环境 / 内存 | 主要结论 |
| --- | --- | --- | --- | --- |
| 配置文件 `"password": "${VAR}"` | 不含实际密码；只含 `-c path` | 只含变量名/占位符 | sslocal 必然读取并在内存中保存；plugin 默认继承环境 | 比 argv 和明文 JSON 少一个常见泄露面，但仍是可观察的运行期秘密 |
| `sslocal -k 'secret'` | 实际密码在 argv；本机验证同类 `ps` 可见 | 不需要密码文件 | sslocal 仍会在内存中保存 | 不建议用于长期服务/GUI 启动；变量语法只有在 argv 中传的是字面量 `${VAR}` 时才避免实际密码进 argv |
| 明文 JSON `"password": "secret"` | argv 只含配置路径 | 实际密码落盘，可能进入备份/快照/权限错误副本 | sslocal 仍会在内存中保存 | 运维简单，但持久化暴露面最大 |
| Keychain/专用 secret store → 运行时配置 | 取决于交接方式 | 可不落盘；若生成运行时 JSON 则运行时文件仍可能是明文 | 读取方和子进程仍会看到运行期值 | 需要围绕交接文件权限、进程环境、plugin 和日志做完整设计；不是自动安全 |

结论是：`${VAR}` **适合作为“避免把实际密码放进 argv 或静态配置文件”的部署接口**，但不应被描述为“安全传递密码”“无泄露风险”或“替代 Keychain”。最低限度的安全约束应是：

- 变量由受控的同用户启动器提供，不把 secret 写进 shell 命令历史、LaunchAgent plist、CI 日志或调试输出；
- 对启动器环境做白名单，避免无意把所有环境变量传给不需要它们的 plugin；官方 plugin 默认继承环境，因此这是实现责任，不是 sslocal 自动提供的隔离；
- 启动前检查变量存在且非空；因为 sslocal 缺变量时保留 `${VAR}` 字面量并继续走后续配置构造，而不是明确失败；
- 日志默认不打开会打印配置对象的 trace/debug；审计 wrapper、plugin、崩溃采集和诊断导出；
- 配置文件、runtime 临时文件、备份和快照按“可能含秘密”处理，使用最小权限并接受普通删除不等于安全擦除。

## 5. 对 ShadowsocksX-NG2 的适用性

### 5.1 当前实现的事实

NG2 的当前链路与官方环境变量示例不同：

1. `ActivationStateMachine` 通过 `CredentialStoring` 解析 `passwordRef`，得到明文 password。[源码](../../ShadowsocksX-NG2/Domain/ActivationStateMachine.swift#L164-L223)
2. `SslocalServerDocument` 的 `password` 是必填 `String`，`jsonData()` 将完整 runtime document 编码为 JSON。[源码](../../ShadowsocksX-NG2/Domain/SslocalRuntimeDocument.swift#L149-L210)
3. `RuntimeFileStore` 通过 `AtomicFileWriter` 写 `sslocal-active.json`；目录基线是 0700，文件是 0600，但文件内容本身包含运行所需的明文密码。[源码](../../ShadowsocksX-NG2/Domain/RuntimeFileStore.swift#L25-L42)、[原子写入权限](../../ShadowsocksX-NG2/Domain/AtomicFileWriter.swift#L11-L42)
4. wrapper 使用 `child.arguments = ["-c", contractURL.path]`，并把 agent 启动时的整个 `environment` 复制给 sslocal；它没有按 server 把 Keychain 值写入某个 `${VAR}` 名称。[源码](../../ShadowsocksX-NG2/Agent/main.swift#L22-L34)、[spawn](../../ShadowsocksX-NG2/Agent/main.swift#L395-L406)
5. 当前 LaunchAgent plist 只声明 `ProgramArguments`，没有声明密码环境变量；因此在 NG2 现状下，`${VAR}` 只会是一个未提供变量的字面量，除非外部部署环境另行注入同名变量。[plist](../../ShadowsocksX-NG2/LaunchAgent/com.qiuyuzhou.ShadowsocksX-NG2.agent.plist#L10-L18)

仓库上下文也明确区分“配置树只存 credential reference”和“runtime configuration file 是给外部 tunnel service 的派生文件”，并把 password/plugin options 定义为敏感信息。[`CONTEXT.md`](../../CONTEXT.md#L25-L29)。因此不能因为上游 `sslocal` 支持 `${VAR}`，就把 NG2 当前的 Keychain→runtime contract 交接自动改写成环境变量方案。

### 5.2 适用性结论

**本次不建议把环境变量方式直接接入 NG2，也不应把它写成当前产品能力。** 若未来专门设计该方案，至少要先决定并验证：

- 谁在 GUI、LaunchAgent、wrapper、sslocal 之间拥有变量，如何避免变量进入 plist、日志和 crash report；
- 多 server/group 激活时变量命名、生命周期和原子更新如何定义；
- plugin 是否允许继承 password 环境，还是必须在 wrapper/sslocal/plugin 边界清理环境；
- 缺失/空变量是否必须变成 NG2 的显式 activation failure，而不能接受上游“保留 `${VAR}` 并继续”的默认行为；
- runtime 文件是否仍落盘明文，以及诊断/备份/崩溃路径怎样处理；
- 环境变量变化是否要成为 wrapper 的 restart fingerprint，不能被当前“仅 servers 变化就转发 SIGUSR1”的重载协议静默吞掉。[NG2 wrapper 重载逻辑](../../ShadowsocksX-NG2/Agent/main.swift#L13-L17)、[重载分支](../../ShadowsocksX-NG2/Agent/main.swift#L164-L192)

在这些边界没有被单独设计和验证前，针对 NG2 的准确说法是：**上游 sslocal 支持该机制；NG2 当前没有使用它，当前产品的凭据交接路径仍是 Keychain 解析后写入受权限保护的 runtime contract。**

## 6. 来源索引

### 官方 shadowsocks-rust

- [v1.25.0 README 配置示例](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/README.md#L795-L805)
- [v1.25.0 `shadowsocks-service` 配置解析](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2137-L2179)、[扩展 `servers[]` 路径](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L2247-L2287)、[变量函数](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks-service/src/config.rs#L3446-L3466)
- [v1.25.0 sslocal 入口](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/src/service/local.rs#L605-L638)
- [v1.25.0 `ServerConfig`](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/config.rs#L403-L475)
- [v1.25.0 SIP003 plugin 启动](https://github.com/shadowsocks/shadowsocks-rust/blob/v1.25.0/crates/shadowsocks/src/plugin/ss_plugin.rs#L7-L29)
- [首次引入配置文件 `${VAR}` 的提交](https://github.com/shadowsocks/shadowsocks-rust/commit/74e8a4f8f58ce60545d778f2f083caab72478eea)
- [扩展到命令行 `--password` 的提交](https://github.com/shadowsocks/shadowsocks-rust/commit/7aec233271670cfc4053bc6cfa0e477baf722790)
- [v1.12.2](https://github.com/shadowsocks/shadowsocks-rust/tree/v1.12.2)、[v1.12.3](https://github.com/shadowsocks/shadowsocks-rust/tree/v1.12.3)

### 依赖/规范/平台一手来源

- [Rust `std::process::Command` 环境继承](https://doc.rust-lang.org/std/process/struct.Command.html#method.new)
- [POSIX `execve` 的 argv/envp 说明](https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html)
- [Apple `Process.arguments`](https://developer.apple.com/documentation/foundation/process/arguments?changes=_9)
- [Apple `Process.environment`](https://developer.apple.com/documentation/foundation/process/environment?changes=_2)

> 以上结论和验证均截至 2026-09-25；上游未来版本可能改变缺失变量、日志、plugin 环境或重载行为，升级 vendor 版本时应重新核对相同源码边界。
