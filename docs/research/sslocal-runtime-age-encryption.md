# sslocal 运行时配置的 age 加密方案评估（2026-10-18）

> 状态：研究与候选设计，不表示已采纳或实现。代码快照为 HEAD `b1b00d7`；后续实施前须重新核对代码、依赖版本和上游接口。

## 结论

**age v1 + X25519 适合作为运行时配置文件的候选加密格式。** Rust `age` crate 有内存与流式 API，可嵌入上游 `sslocal`；AgeKit 暴露 X25519 身份生成、公钥序列化和 age 文件加解密 API。两边按经典 X25519 recipient 互通在技术上可行，但本次没有找到跨实现测试证据，因此目前只能确认“候选匹配”，不能宣称已经互通。[age 文件格式规范](https://github.com/C2SP/C2SP/blob/main/age.md)、[Rust `age` crate](https://docs.rs/age/latest/age/)、[AgeKit](https://github.com/jamesog/AgeKit)

建议的职责边界：

1. Agent 首次运行时生成 X25519 identity；私钥只保存在 Agent 自己的 Keychain 项中，公钥 recipient 以带版本和 key ID 的文件发布给主程序。公钥不是秘密，但主程序必须能信任它确实属于当前 Agent。
2. 主程序从已解锁的服务器库构造运行时 JSON，在内存中使用 AgeKit 加密，再原子写入密文文件。不要创建明文临时运行配置。
3. Agent 从自己的 Keychain 取得私钥，通过专用继承文件描述符/管道交给 `sslocal`；不放进命令行参数、环境变量、日志或普通临时文件。修改后的 Rust `sslocal` 独自解密并解析运行配置。
4. Agent 另读一个最小的非秘密监管清单，继续执行监听探测、ACL 路径检查、重启分类和部署回执。它不需要解密服务器配置。

Agent 的运行时私钥是可重建的派生密钥。若 Agent 因签名身份变化无法继续访问旧私钥，可轮换 Agent 密钥并由主程序从持久服务器库重新生成运行时密文；只有主程序读取服务器库主密钥失败时，才需要按既定服务器库恢复流程重新授权。这个边界与已接受的服务器库 Keychain/恢复设计一致。[ADR-0035](../adr/0035-encrypt-persistent-server-library.md)

## age 与两种实现的适配性

age v1 采用带 recipient stanza 的二进制文件格式，并对文件头和加密内容提供完整性保护。X25519 recipient 使用临时 X25519 密钥和 HKDF-SHA256 包装随机文件密钥，再以 ChaCha20-Poly1305 加密数据。密文完整性可检测篡改和截断，但 age 公钥加密不认证发送方：任何持有公开 recipient 的进程都能产生该 recipient 可解密的有效密文。[C2SP age 规范](https://github.com/C2SP/C2SP/blob/main/age.md)

为匹配当前 Swift 实现，首版应明确限定为 age v1 + 经典 X25519 recipient（`age1…`），不启用 age 插件 recipient、SSH recipient 或 PQ recipient。若以后要把发送方身份纳入保证，需要单独增加签名/授权机制；不能把 age 密文认证描述成“由主程序写入”。本项目现行凭据威胁边界不包含同一用户进程被攻破；目录 0700、文件 0600 继续用于隔离其他用户账户。[GLOSSARY.md](../../GLOSSARY.md#凭据与诊断)

Rust crate 当前文档为 `age` 0.12.1，并明确所有 1.0 前版本仍是 beta/testing 发布。它提供 X25519 `Identity::generate()`、`to_public()`，以及小型数据的 `age::encrypt` / `age::decrypt` 和流式 `Encryptor` / `Decryptor`。运行 JSON 较小时可先评估内存 API；若用流式 API，解密必须读取到 EOF 才完成末块认证，写入端必须调用 `finish()`，然后才能原子替换活动配置。应固定确切 crate 版本与 features，不把 age 文件格式自行拆包或手工解析。[crate 文档](https://docs.rs/age/latest/age/)、[Encryptor](https://docs.rs/age/latest/age/struct.Encryptor.html)、[Decryptor](https://docs.rs/age/latest/age/struct.Decryptor.html)、[X25519 Identity](https://docs.rs/age/latest/age/x25519/struct.Identity.html)

AgeKit 的当前 README 描述了 X25519 key/recipient 与 age 加解密路径，最低为 macOS 11，满足本项目当前 macOS 15 部署目标。它也记录 scrypt 互通限制和不支持 SSH；这些不影响仅使用 X25519 的方案。风险在于该 Swift 实现尚无可见的正式 release，README 指向 `main` 分支，Package.swift 还依赖 `swift-asn1` 的移动 `main` 分支，且现有测试主要是库内往返测试，未见 Rust/age CLI 跨实现夹具。`parseIdentities` 对导入的私钥文本还要求换行结尾。落地前应固定并审查 AgeKit 与全部传递依赖的具体提交；如果不能固定或审查，考虑 fork/vendor 后维护所需的 X25519 子集。[AgeKit README](https://github.com/jamesog/AgeKit/blob/main/README.md)、[Package.swift](https://github.com/jamesog/AgeKit/blob/main/Package.swift)、[identity parser](https://github.com/jamesog/AgeKit/blob/main/Sources/AgeKit/Parse.swift)、[AgeKit commits](https://github.com/jamesog/AgeKit/commits/main)、[releases](https://github.com/jamesog/AgeKit/releases)

## 当前 Agent 是否读取 `sslocal-active.json`

**当前实现中 Agent 和 sslocal 都读取它。** Agent 的 [loadContract()](../../ShadowsocksX-NG2/Agent/AgentContract.swift#L11) 读取整个文件并解码完整 `SslocalRuntimeDocument`；该结构含 `servers[].password`、插件选项和监听数据。[文档模型](../../ShadowsocksX-NG2/Domain/Runtime/SslocalRuntimeDocument.swift#L87) 明确将其定义为完整运行契约；Agent 随后用 `-c <路径>` 启动 sslocal，且上游通过 SIGUSR1 重读同一文件。[运行路径](../../ShadowsocksX-NG2/Domain/Runtime/RuntimePaths.swift#L13)

Agent 解析该文档有现行用途，不只是重复检查：

- 启动/重载时验证 schema 与监听配置，并比较 `listenFingerprint`，决定重启子进程还是转发 SIGUSR1；[重载逻辑](../../ShadowsocksX-NG2/Agent/main.swift#L234)
- 检查 ACL 活动链接是否落在运行目录内；[AgentContract.swift](../../ShadowsocksX-NG2/Agent/AgentContract.swift#L14)
- 按 `locals` 探测监听端点，并在 ACL 模式下检查子进程是否拥有 TCP listener；[AgentListening.swift](../../ShadowsocksX-NG2/Agent/AgentListening.swift#L41)
- 从 `listen.authentication` 读取 LAN 用户名/密码并写入认证 sidecar；[认证 sidecar](../../ShadowsocksX-NG2/Agent/AgentContract.swift#L45)、[凭据结构](../../ShadowsocksX-NG2/Domain/Runtime/RuntimeListenerAuthentication.swift#L3)
- 根据已解析文档计算部署回执摘要；[回执写入](../../ShadowsocksX-NG2/Agent/AgentContract.swift#L27)

所以，**目标不是让 Agent 对所有运行文件都盲目**，而是把当前完整 JSON 拆成“只有 sslocal 读取的密文配置”和“Agent 可读的非秘密控制面”。只把现有 JSON 加密并让 Agent 继续 `loadContract()` 会失效；让 Agent 不读任何旁路数据也会丢失上述监管职责。

## 建议拆分的控制面

`sslocal-active.age` 保存上游 sslocal 所需的完整配置以及只有 sslocal/GUI 需要的扩展；Agent 只读取例如 `agent-runtime.json` 的精简监管清单。清单至少应表达：格式版本、活动 key ID/部署 generation、需要探测的监听协议与地址、一个不泄露 LAN 密码的监听配置 generation、ACL 是否启用及固定运行路径，以及 Agent 发布回执所需的部署标识。清单不得包含服务器密码、完整插件参数、LAN 用户名或密码。

避免直接把 `listenFingerprint` 原样搬到清单：当前 fingerprint 包含 authentication 字段，含用户名/密码。应由 GUI 产生不暴露凭据的 opaque generation/token，或拆出只含非秘密监听字段的结构。也不要用低熵凭据的无盐散列代替秘密字段。

LAN auth sidecar 是职责迁移的主要接缝：当前 Agent 从明文运行文档写出 sidecar。可由 GUI 在写密文时生成这些现有 0600 派生文件，或由修改后的 sslocal 根据解密配置生成；不要把 LAN 凭据复制进监管清单。两种方案都要保证旧进程仍使用的内容寻址 sidecar 不被覆盖。[RuntimeListenerAuthentication.swift](../../ShadowsocksX-NG2/Domain/Runtime/RuntimeListenerAuthentication.swift#L21)

当前 Agent 在重载后会直接写入基于 JSON digest 的部署回执。改成密文加旁路清单后，回执不能只代表 Agent 成功读到了 manifest；最好由 sslocal 在成功解密、校验并应用指定 generation 后确认，Agent 再结合监听 ready 状态发布回执。否则 GUI 可能把“文件已写入”误判成“新配置已生效”。新旧 generation 与 ACL 变体/活动链接/运行契约的原子发布顺序也需重新定义，并保留现有的事务与代次防护。[RuntimeFileStore.swift](../../ShadowsocksX-NG2/Domain/Runtime/RuntimeFileStore.swift)

## 失败语义与恢复

加密文件认证失败、密钥不可用、文件格式未知或密文损坏时，应保留原密文并报告具体可恢复状态，不删除文件、不写空配置。当前 Agent 的无效 JSON 路径会删除 `sslocal-active.json`；加密后不能沿用这一语义。[启动失败路径](../../ShadowsocksX-NG2/Agent/main.swift#L85)、[重载失败路径](../../ShadowsocksX-NG2/Agent/main.swift#L242)

运行中重载时，sslocal 应先完整解密并验证新 generation，再原子切换内存配置；失败则保留旧的有效配置。首次启动解密失败时不得启动空配置。加密文件应在同目录临时写出后原子替换，临时文件也只能是密文。Agent 的崩溃恢复仍需保留“意外退出后由 launchd 重放最近有效快照”的既有语义，且要避免永久解密错误造成无休止的重启循环。[LaunchAgentService.swift](../../ShadowsocksX-NG2/App/Application/Services/LaunchAgentService.swift)

私钥从 Agent 到 sslocal 的传递仍然是秘密跨进程传递。age 只保护静态文件，不解决这段运行时密钥交接；使用独立管道/继承 FD 或受保护的本地 IPC，并核实 Swift `Process`/实际 spawn 路径不会意外把 FD 传给其他子进程。不要将私钥写入 argv、环境变量、日志或与密文并列的 0600 普通文件。若 Agent 私钥因签名变化不可用，优先按“重建派生密钥、从持久服务器库重生成运行文件”恢复；不要为保持派生文件而降低存储保护级别。

## 实施前的互通与生命周期门槛

尚未运行实现或测试。进入实现前至少需完成：

1. AgeKit 加密 → Rust `age` 解密、Rust `age` 加密 → AgeKit 解密；并与参考 `age`/`rage` 做双向固定夹具验证。
2. 错误 recipient、错误私钥、篡改头/内容、截断、未知格式、空配置与超大输入的失败验证；确保不会把认证失败当作空配置或删除原文件。
3. 首次启动的公钥文件竞争、key rotation、Agent Keychain 项被拒绝/重建、主程序在 Agent 之前启动、GUI 重写密文与 Agent 同时重载等时序验证。
4. 检查进程参数、环境、日志、临时文件和 Agent 控制清单不含私钥、服务器密码、插件秘密或 LAN 密码；检查密文与 sidecar 的 0600 权限和 0700 父目录。
5. 验证 Agent 的 receipt 只在 sslocal 已应用相应 generation 且监听就绪后发布，并覆盖启动、SIGUSR1 重载、结构变化重启、子进程崩溃恢复与持久解密错误路径。

## 一手资料

- [C2SP age file encryption format](https://github.com/C2SP/C2SP/blob/main/age.md)
- [Rust `age` crate API](https://docs.rs/age/latest/age/)
- [AgeKit README](https://github.com/jamesog/AgeKit/blob/main/README.md)、[Package.swift](https://github.com/jamesog/AgeKit/blob/main/Package.swift)、[源码](https://github.com/jamesog/AgeKit/tree/main/Sources/AgeKit)、[测试](https://github.com/jamesog/AgeKit/tree/main/Tests/AgeKitTests)
- [项目术语表中的凭据暴露边界](../../GLOSSARY.md#凭据与诊断)、[ADR-0035](../adr/0035-encrypt-persistent-server-library.md)
