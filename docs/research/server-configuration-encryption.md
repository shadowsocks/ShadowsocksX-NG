# 服务器配置文件整体加密方案研究（2026-10-18）

> 研究日期：2026-10-18。本文记录调研时点的一手资料与代码快照，并提出候选方案；不表示项目已采纳或实现。后续实现应再次核实代码、签名条件及支持的 macOS 版本。

## 结论与推荐

推荐以 **CryptoKit AES-256-GCM 对完整服务器库序列化结果加密，随机 256 位主密钥存于 Keychain**。服务器名称、地址、端口、加密方法、密码、插件参数、分组、订阅 URL 和相关元数据进入同一认证加密 payload；Keychain 不再按服务器拆分保存这些秘密。AES.GCM 同时提供加密和认证，并支持认证附加数据（AAD）；CryptoKit 是 Apple 推荐优先使用的高层密码学接口。[AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)、[CryptoKit](https://developer.apple.com/documentation/cryptokit)

对当前单个 JSON 文档，不建议增加数据库、SQLCipher、通用密钥管理系统或 KEK/DEK 双层封装。一个文档主密钥足够；用版本化文件头为后续格式迁移留边界。ChaCha20-Poly1305 同样合适，但当前没有互操作或性能证据要求选择它；AES-GCM 作为首选是本报告的工程判断，并非宣称另一算法不安全。[Apple ChaChaPoly](https://developer.apple.com/documentation/cryptokit/chachapoly)、[RFC 8439](https://datatracker.ietf.org/doc/html/rfc8439)

本次任务范围已明确：

- **本次范围：持久服务器库整体加密。** 密码、插件参数、订阅 URL 与服务器库其他资料一起进入密文；服务器库专用 Keychain 项只保存主密钥。监听认证、连通性检测 URL 等其他用途的凭据不自动纳入迁移。
- **另案处理：运行时文件加密。** 用户已明确 `sslocal-active.json` 的加密需要改造上游 sslocal，本次不研究或实施该改造，也不将运行契约及派生认证文件无明文作为本次验收条件。

考虑到开源项目可能更换签名 Team、用户也会自行编译，**本项目优先推荐经典登录钥匙串 + 严格 ACL + 显式加密导出/恢复**；换 Team 后可能需要前台重新授权，不能承诺静默访问。Apple 默认推荐的 data protection keychain 仍是候选，但其访问组身份与签名授权关联，不能仅凭相同 bundle ID 或用户弹窗读取旧 Team 的钥匙。详见第 4.3 节；算法和密文格式不因此改变。[TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)、[Keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)

## 1. 调研时点代码快照

以下以 HEAD `5fc5ddf` 为调研快照，仅用于说明改造接缝，不作为持续维护的现状文档。[GLOSSARY.md](../../GLOSSARY.md) 已将用户管理文档与运行配置区分，且已有威胁模型不承诺抵御同用户进程被控制、root 或历史快照；本报告不自动扩张这些保证。

| 面 | 2026-10-18 核实结果（HEAD `5fc5ddf`） | 对加密的影响 |
| --- | --- | --- |
| 服务器库 | [CatalogFileStore.swift](../../ShadowsocksX-NG2/Domain/Catalog/CatalogFileStore.swift) 写 schema v6，读取兼容 v1–v6；JSON 包含整树 entries、rootChildren、subscriptions、favoriteIDs | 应加密整个文档，而非只加密 ServerFields 中部分字段 |
| 服务器字段 | [CatalogModels.swift](../../ShadowsocksX-NG2/Domain/Catalog/CatalogModels.swift) 定义服务器数据；秘密通过 credential reference 关联 | 最终需新增包含真实秘密的持久 payload，不能只把原有引用 JSON 加密后声称秘密已整合 |
| 现有 Keychain | [CredentialStore.swift](../../ShadowsocksX-NG2/Domain/Credentials/CredentialStore.swift) 使用 Generic Password，service 为 `com.qiuyuzhou.ShadowsocksX-NG2.credentials`，值为 UTF-8 String；订阅 URL 也已存 Keychain | 用户描述中的“仅密码和插件参数”需补上订阅 URL；新主密钥应使用二进制 Data 接口，避免沿用 String 秘密语义 |
| Keychain 属性 | 同文件设置 AfterFirstUnlock，没有设置 `kSecUseDataProtectionKeychain` | 不能根据属性名或注释推断真实 macOS 锁定语义，详见第 4 节 |
| 原子写 | [AtomicFileWriter.swift](../../ShadowsocksX-NG2/Domain/Runtime/AtomicFileWriter.swift) 使用 0700 目录、0600 同目录临时文件与替换；未实现 fsync | 可复用权限与替换路径，但必须先在内存加密，再写临时文件；不能宣称已有断电持久性保证 |
| 加载失败 | [CatalogCommitCoordinator.swift](../../ShadowsocksX-NG2/App/Application/CatalogWorkflow/CatalogCommitCoordinator.swift) 存在 `(try? fileStore.load()) ?? CatalogDocument()` | 加密后不能把密钥不可用、认证失败或损坏当作空库，否则后续提交可能覆盖可恢复数据 |
| 激活 | [LeafPreparation.swift](../../ShadowsocksX-NG2/Domain/Activation/LeafPreparation.swift) 读取凭据准备运行文档 | 秘密整合后需调整数据来源与凭据事务模型 |
| 运行时 | [RuntimePaths.swift](../../ShadowsocksX-NG2/Domain/Runtime/RuntimePaths.swift) 区分 GUI 私有 `catalog.json` 与运行契约 `sslocal-active.json`；[SslocalRuntimeDocument.swift](../../ShadowsocksX-NG2/Domain/Runtime/SslocalRuntimeDocument.swift) 可编码真实 password/pluginOpts | 库文件加密不会自动覆盖运行契约 |
| Agent | [AgentContract.swift](../../ShadowsocksX-NG2/Agent/AgentContract.swift) 读取明文 Data，向 sslocal 传 `-c <path>`，并写监听认证派生文件 | 运行时契约加密与上游 sslocal 改造另案处理 |
| 签名 | [project.yml](../../ShadowsocksX-NG2/project.yml) 目标 macOS 15、arm64，Release 使用 Developer ID/hardened runtime；[entitlements](../../ShadowsocksX-NG2/App/Resources/ShadowsocksX-NG2.entitlements) 当前为空字典 | data protection keychain 及跨进程共享不能假定已经配置 |
| 凭据事务 | [CredentialWriteJournal.swift](../../ShadowsocksX-NG2/Domain/Credentials/CredentialWriteJournal.swift) 处理逐项凭据回滚 | 单密文模型需重看事务边界，不能只替换 JSON encoder |

## 2. 加密目标和边界

本方案主要防止：服务器库被直接打开、误传、单独复制到其他机器或仅文件备份泄漏时暴露服务器地址、分组、订阅和秘密；同时检测文件内容被修改、截断、拼接等导致的认证失败。这一目标来自 AEAD 的保密与完整性能力；AAD 可认证不需要隐藏的文件头。[RFC 5116 §2](https://datatracker.ietf.org/doc/html/rfc5116#section-2)

它不保证以下情况的安全，后续产品描述应保持这个边界：

- 应用获准解密后，配置与密钥仍会进入进程内存；进程被控制、调试转储或应用主动泄漏不由磁盘加密解决。CryptoKit 的敏感内存处理有帮助，但业务层 Data、String、日志副本不因此自动消失。[CryptoKit](https://developer.apple.com/documentation/cryptokit)
- 文件名、大小、修改时间、写入频率仍可见；整文件加密并不隐藏这些文件系统元数据。这是建议格式的直接推论。
- 攻击者把整份合法旧密文替换回来时，普通 AEAD 仍会认证成功；防回滚需要额外可信状态，不能靠文件中的 revision 自证最新。[RFC 5116 §3](https://datatracker.ietf.org/doc/html/rfc5116#section-3)
- 已有运行契约、日志、导出、剪贴板、分享二维码、旧备份及 APFS 快照不因新库文件加密而被追溯擦除。运行契约是否明文以第 1 节代码为依据；其余是后续需单独审计的输出路径。
- 仅本机存钥降低单独拿到库文件的风险；它不是阻止所有同用户进程、管理员或已授权代码访问的绝对边界。安全性还取决于 Keychain ACL/access group、签名和运行环境。[TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)

## 3. 候选加密方案比较

| 方案 | 适配性与代价 | 判断 |
| --- | --- | --- |
| CryptoKit AES-256-GCM | 高层 AEAD；加密并验证 AAD；可直接覆盖序列化 Data；无需第三方依赖 | 推荐 |
| CryptoKit ChaCha20-Poly1305 | 同样为 AEAD；256 位密钥、96 位 nonce；适合有对应协议互操作要求的情况 | 可接受备选，无需同时实现两套 |
| AES-CBC + 自行 HMAC/填充/组合 | 要自行确定认证顺序、密钥分离及错误处理；本任务已有高层 AEAD 可用 | 不选 |
| SQLCipher/数据库加密 | 需要改变存储模型、引入数据库及其维护；当前需求为单文档整体保护 | 目前不选，不否定其数据库场景价值 |
| FileVault/文件权限 | 对应整卷静态保护与权限控制，不能取代应用所需“文件副本离开机器后仍为密文”的封装 | 作为互补措施 |
| Secure Enclave 非对称钥匙 + 包装主密钥 | 增加硬件、访问控制、密钥封装与恢复设计；不是把 AES SymmetricKey 直接放进 Secure Enclave | 首版不选 |

上述算法能力依据 [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)、[RFC 8439 §2.8](https://datatracker.ietf.org/doc/html/rfc8439#section-2.8)；优先高层接口依据 [CryptoKit](https://developer.apple.com/documentation/cryptokit)。CBC、数据库和分层密钥的取舍是针对本项目单文档规模的工程判断。FileVault 的作用范围见 [Apple FileVault](https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web)。

### 推荐参数与文件封装

建议固定一套 v1 格式：

| 部分 | 建议 |
| --- | --- |
| 主密钥 | `SymmetricKey(size: .bits256)` 生成；Keychain 存原始 32 字节，不使用用户密码、设备 ID 或硬编码字符串派生 |
| 加密 | `AES.GCM.seal(payload, using: key, authenticating: headerBytes)`；每次保存新生成 nonce |
| nonce/tag | 默认 12 字节随机 nonce、16 字节 tag；存储 `SealedBox.combined` |
| 明文文件头 | magic、envelopeVersion、固定算法标识、随机 keyID；不放服务器名、URL、密码或主密钥 |
| 认证文件头 | 对确切 header 字节做 AAD；不要依赖未定义顺序的 JSON 重新编码得出同一 AAD |
| payload | 完整服务器库 DTO 的 JSON/其他现有序列化 Data；其 schemaVersion 与 envelopeVersion 分离 |
| 写入 | 内存序列化 → 内存加密 → 0600 临时密文 → 替换；临时文件、恢复副本也只能写密文 |

随机主密钥生成 API 见 [SymmetricKey.init(size:)](https://developer.apple.com/documentation/cryptokit/symmetrickey/init(size:))。Apple 文档确认 `combined` 在默认 nonce 下按 nonce、ciphertext、tag 排列；默认 nonce 为 12 字节随机数，且不可重复使用。AES-GCM 的 tag 长度依据 RFC 5116。本任务不应设计持久递增 nonce 计数器，以免文件回滚或并发保存导致重用；库大小及写入频率预计远低于大流量协议，但实施时仍应设定合理文件大小和生命周期上限。[combined](https://developer.apple.com/documentation/cryptokit/aes/gcm/sealedbox/combined)、[Nonce.init](https://developer.apple.com/documentation/cryptokit/aes/gcm/nonce/init())、[Nonce](https://developer.apple.com/documentation/cryptokit/aes/gcm/nonce)、[RFC 5116 §5.1–5.2](https://datatracker.ietf.org/doc/html/rfc5116#section-5.1)

文件头属于本报告提出的应用封装，不是 CryptoKit 自带格式。v1 解码器只接受固定算法和支持的版本，不做失败后换算法或按明文重试；先限制头长度、文件大小并校验结构，再定位 keyID、验证认证，最后解析 payload。随机 keyID 只是主密钥查找标识，不能误当密钥材料。

## 4. Keychain 选型与后台读取

### 4.1 主密钥的存法

Apple 的 CryptoKit Keychain 示例把 SymmetricKey 等不能直接作为 SecKey 表达的密钥存为 Generic Password 的二进制值。因此“主密钥存 Generic Password”是官方示范路径；无须为了名字里出现 password 而改用不匹配的 SecKey 包装。[Storing CryptoKit Keys in the Keychain](https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain)

建议服务器库主密钥使用独立 service 命名空间，account 为 keyID；明确 `kSecAttrSynchronizable: false`。文件头可公开 keyID。不要把主密钥加入导出配置、UserDefaults、日志、崩溃诊断或普通备份清单。同步密钥也不等于同步文件，且 ThisDeviceOnly 与可同步属性不兼容。[kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable)

### 4.2 两种 macOS Keychain 不可混为一谈

| 选择 | 官方机制 | 本项目需要验证 |
| --- | --- | --- |
| 经典 file-based / login keychain | ACL（SecAccess）控制；默认 keychain 与 search list 决定落点 | 正式签名升级后授权是否保留、用户手动锁定登录钥匙串、首次访问提示、安装位置变化 |
| data protection keychain | 使用 `kSecUseDataProtectionKeychain: true` 显式选择；用户登录上下文；access groups 与签名 entitlement 相关 | App 在发布签名下增删读、权限配置与换 Team 迁移；本次无需 Agent 共享主密钥 |

Apple 推荐默认选择 data protection keychain；无用户上下文的 launchd daemon 必须使用 file-based keychain。命令行程序即使通过 app-like bundle 承载 entitlement，也仍必须处在用户上下文。用户级 Agent 与系统 daemon 不能因都由 launchd 启动而视为相同环境。[TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)、[kSecUseDataProtectionKeychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)

特别注意：Apple 对 `kSecAttrAccessible` 明确要求 macOS 同时选择 data protection keychain 或 synchronizable。因此当前代码仅设置 AfterFirstUnlock，不能证明经典登录钥匙串执行了该保护类；应先确认实际后端，不能照搬 iOS 示例或代码注释。[kSecAttrAccessible](https://developer.apple.com/documentation/security/ksecattraccessible)

对明确采用 data protection keychain 的方案，可在 `WhenUnlocked` 与 `AfterFirstUnlock` 之间按产品需求选择。Apple 把 `AfterFirstUnlockThisDeviceOnly` 描述为适合后台访问、首次解锁后直到重启可用、不可迁移新设备；但本报告不把该通用说明等同于所有 macOS 硬件/版本上的锁屏数据保护保证。Apple 平台安全文档明确指出 macOS 不直接以 Data Protection 实施这些保证；必须用目标 macOS 的真实登录/锁屏/重启情境验证。[AfterFirstUnlockThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)、[Keychain data protection](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web)

结合第 4.3 节的开源签名约束，建议本次验证 **App 单进程使用经典登录钥匙串** 的严格 ACL、升级授权与恢复；data protection keychain 作为签名团队稳定且迁移路径明确时的备选。本次 catalog 为 GUI 私有，无需向 Agent 扩大主密钥访问权限。

### 4.3 开源分发、换 Team 与自编译

**签名 Team 可能改变，会影响选型；两种 Keychain 都不能承诺换签名后静默读取旧钥。** 对本项目这种 Developer ID 开源分发，建议优先采用经典登录钥匙串、保留严格 ACL，并提供显式加密导出/恢复路径。这是考虑维护者变更和用户自编译后的工程取舍；Apple 的平台默认建议仍是 data protection keychain。

DP keychain 的默认组与应用标识有关，通常包含 Team ID / App ID prefix；显式共享组同样受 entitlement 和 provisioning 授权约束。保持 bundle ID、service、account 不变，不能让新 Team 获得旧组的读取权；用户同意弹窗也不是跨组授权机制。这一点由组成员必须匹配的访问规则推导，不能套用经典钥匙串的“Always Allow”。旧版仍能读主密钥时，应先导出完整配置，或实施经验证的桥接迁移，再切换签名；不要等唯一旧读取路径消失后再处理。[Sharing access to keychain items](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)、[kSecAttrAccessGroup](https://developer.apple.com/documentation/security/ksecattraccessgroup)

经典 file-based keychain 使用 ACL，并以代码签名 requirement 跟踪应用身份。常规 Developer ID designated requirement（DR）包含 Team 条件，因此换 Team 也可能不再匹配旧授权。区别是用户可显式批准新应用访问；Apple 的 Keychain Access 指南提供逐个添加应用和 Always Allow 的操作。项目可设计“前台请求重新授权 → 用户确认 → 重试读取”及 Keychain Access 修复指引，但不能保证每种 macOS、ACL 状态和签名变化都会自动弹窗或成功；后台拒绝交互时应停在可恢复错误状态。[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)、[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[Digital signing and encryption](https://support.apple.com/en-ie/guide/security/secd0da50a09/web)、[Allow apps to access your keychain](https://support.apple.com/en-gb/guide/mac-help/kychn002/26/mac/26)

| 签名变化 | 预期与限制 |
| --- | --- |
| 同 Team 证书续期/换证书 | 与换 Team 不同。若 entitlement、应用标识和 DR 保持兼容，常规 DR 不绑定某张证书的指纹；不能因证书文件换了就认定必须丢钥。自定义 ACL 若钉住具体证书则另论 |
| 换 Team、改签名身份 | DP 可能失去旧组访问；经典 ACL 可能失配。应准备旧版导出/迁移、前台重新授权与独立恢复路径，不能承诺静默升级 |
| 用户用自己的 Team 自编译 | 属于不同身份；相同源码/仓库名不产生旧主密钥访问权。应按显式导入或重新授权处理 |
| 无付费 Team / 自签名构建 | 不假定具备正式发行版的受限 entitlement。经典钥匙串可结合稳定自签名身份使用，但须独立验证；这不等于通过 Developer ID/Gatekeeper 分发检查 |
| ad-hoc（Sign to Run Locally） | DR 绑定该次代码，重新构建可能再次触发授权；不能作为跨版本稳定身份。此处的 ad-hoc 指 macOS 本地签名，不是 iOS Ad Hoc 分发 |

表中同 Team 续期属于依据标准 Developer ID DR 条件的推论，仍需比较实际构建签名；自签名支持依据 TN2206，ad-hoc 限制依据 TN3127。[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)

安全 ACL 应继续限制到获准应用的完整签名身份。**不要为了跨 Team 兼容把 requirement 简化为仅 bundle ID，也不要设为任意应用可读。** 合法的新身份由用户显式授权或迁移，不应通过放宽所有调用方访问解决。主密钥一旦成为整库唯一解密入口，独立恢复导出的价值也高于当前可逐项重新输入密码的模型。

### 4.4 无交互读取与失败语义

自动启动、后台重连不应依赖 Touch ID/userPresence 等每次交互授权。禁交互只能让需要认证的操作失败，不会绕过保护。Apple 已弃用 `kSecUseAuthenticationUIFail`，建议在适用路径使用 `kSecUseAuthenticationContext` 搭配 `LAContext.interactionNotAllowed`；经典 file-based 后端须另外核实其行为，不能由 LAContext 文档推断通用兼容。[kSecUseAuthenticationUIFail](https://developer.apple.com/documentation/security/ksecuseauthenticationuifail)、[LAContext.interactionNotAllowed](https://developer.apple.com/documentation/localauthentication/lacontext/interactionnotallowed)

实现应区分：不存在、被锁定/需要交互、缺 entitlement/无权访问、用户取消、文件认证失败、格式版本不支持。保留原密文、阻止自动写入，提示可恢复的状态；不要把所有错误归为“还没有配置”。

### 4.5 Secure Enclave 为什么不作为首选

Secure Enclave 的 P-256 接口处理签名/密钥协商，不能把现有任意 AES 对称主密钥导入后要求硬件直接完成文件 AES-GCM。Apple 对 P-256 路径说明须在 Enclave 内生成私钥且不可迁出；间接保护文档需要额外的密钥协商/封装方案，并增加设备绑定与恢复限制。这并不能消除业务明文进入 App 内存的事实。[Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)、[SecureEnclave.P256](https://developer.apple.com/documentation/cryptokit/secureenclave/p256)

若未来产品明确要求硬件绑定、限制私钥可导出或交互解锁，可再研究 envelope/key wrapping；对当前目标，Keychain 保存随机对称主密钥更直接。

## 5. 密钥与文件生命周期建议

本节是由 AEAD/Keychain 能力推导的应用事务建议，不是 Apple 提供的跨 Keychain/文件原子事务。

### 初始化与并发

- 只有确认没有已有库文件，才允许生成新库与新主密钥。已有密文但查不到 keyID 时必须进入恢复状态，禁止生成新钥后覆盖。
- 单进程串行化保存；若可能多进程初始化，用稳定 bootstrap 定位方式和独占协调防止双库。`SecItemAdd` 返回 duplicate 时重读已有项，不能继续用自己尚未获持久保存的候选密钥；duplicate 的复合主键规则见 [kSecClassGenericPassword](https://developer.apple.com/documentation/security/ksecclassgenericpassword)。
- Keychain 写入成功并重新读取校验后，才提交用该密钥加密的首份文件。文件提交失败可留下孤立密钥，后续辨认/清理；宁可留多余钥匙，也不能生成无钥可开的唯一密文。

### 旧数据迁移

1. 按原版本读取 catalog，解析全部密码、插件参数、订阅 URL。任意旧凭据缺失/被锁定就停止迁移，不能静默变空。
2. 在内存构建完整新 payload；通过旧库与新 payload 的语义比对确认没有漏字段、排序、订阅状态或秘密。
3. 创建并验证主密钥，在内存加密 payload，原子提交新格式，再重新打开并验证；迁移中断后能够根据磁盘与密钥状态重试。
4. 只有新库可读且恢复策略落实后，才清理已迁入的逐项凭据；范围外的 Keychain 项保留。
5. 是否临时保留旧明文备份须明确选择：默认建议不新增持久明文备份，安全提交前以旧文件作为唯一来源；安全提交后清理旧路径。若为了回退另存明文，会延长敏感元数据泄漏窗口，必须定义期限与说明。

已存在的旧备份/快照无法靠删除当前路径保证消失；不承诺迁移后的“安全擦除”。旧版本程序对新密文应明确拒绝打开，不能再创建或覆盖同路径空库。

### 损坏、轮换与恢复

文件加载至少区分 missing、keyUnavailable、authenticationFailed、unsupportedVersion、malformedPayload；仅 missing 可进入新建流程。认证失败不尝试解码未经认证的明文，也不自动恢复空库。[AES.GCM.open](https://developer.apple.com/documentation/cryptokit/aes/gcm)

轮换时先创建新 keyID/密钥，以新密钥生成并验证新文件，然后替换；旧钥保留到旧密文备份不再需要。不能先删除旧钥。若要保留多个历史密文，必须同时定义其 keyID/密钥保留期限；“轮换”不会让持有旧密钥和旧备份的攻击者失去旧数据。

恢复政策必须在实施前明确：

| 政策 | 收益 | 必须说明的后果 |
| --- | --- | --- |
| 本机绑定 / ThisDeviceOnly | 限制主密钥迁移 | 仅有密文备份、换机或钥匙串丢失时无法恢复；应提供受控导出/重新订阅路径 |
| 可迁移但不同步的 Keychain 项 | 可配合系统迁移/备份场景 | 必须实测所支持的迁移/恢复方式，不能承诺复制 catalog 即可用 |
| 显式密码加密导出 | 便于跨机器恢复，与本机主密钥解耦 | 需要独立 KDF、口令策略与导出格式研究，不应直接复用弱口令作为 AES key |
| iCloud 同步主密钥 | 可能支持多机共享钥匙 | 文件并不同步；扩大恢复和同步状态空间，首版不推荐 |

Apple 对 ThisDeviceOnly 明确规定不迁移到其他设备；对 synchronizable 明确规定其同步语义。经典 keychain 的文件级备份也不能作为未经验证的恢复承诺；产品应验证系统支持的迁移与恢复流程，避免依赖内部存储布局。[AfterFirstUnlockThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)、[kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable)、[TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)

## 6. 已明确的任务边界

本次只覆盖持久服务器库整体加密。`sslocal-active.json` 的加密及所需上游 sslocal 改造另案处理，不作为本次设计、实现或验收的前置条件。运行契约与派生认证文件沿用现有机制，本次不要求 Agent 读取服务器库主密钥。

当前 wrapper 向 sslocal 传递 JSON 文件路径，服务器库与运行契约是两个独立存储边界；本次成果应表述为“服务器库整体加密”。保留该事实用于准确描述保护范围，不在本文继续展开运行时加密候选方案。[AgentContract.swift](../../ShadowsocksX-NG2/Agent/AgentContract.swift)、[RuntimePaths.swift](../../ShadowsocksX-NG2/Domain/Runtime/RuntimePaths.swift)

## 7. 实施前验证与待决定事项

本文仅完成源码与一手资料调研，未实现加密、未对真实 Keychain 写入或进行签名发布验证。

建议后续采用以下有区分的证据：

| 验证层 | 验收重点 |
| --- | --- |
| 纯函数/文件测试 | 完整 payload 往返、空库/大库、错误钥匙、篡改 nonce/tag/header、截断、未知版本；相同 payload 多次保存产生不同密文 |
| 迁移故障注入 | 缺旧凭据、Keychain 写失败、duplicate 并发、写文件/替换失败、任一步退出；不覆盖旧数据、不丢钥匙、不把损坏当空库 |
| 文件检查 | 新库及临时/恢复文件不含样本服务器名、地址、密码、插件参数和订阅 URL；权限保持；未进行安全擦除保证 |
| 真机 Keychain | Debug 与正式 Developer ID 构建分别验证；新增、同 Team 续证、换 Team、自编译/ad-hoc 重建、前台重新授权、升级、撤销授权、锁钥匙串、锁屏、重启首次登录、退出 GUI、切换用户；记录 OSStatus，不泄漏值 |
| 恢复验证 | 同机恢复、换机恢复、只有密文无钥匙、钥匙丢失、轮换后恢复旧备份；按选择的策略说明能否恢复 |
| 运行进程 | 检查加密库加载及凭据来源调整后，现有激活与运行流程仍兼容；不要求运行契约或派生认证文件加密 |

下一步需要确定的产品边界：

1. 是否采用推荐的经典登录钥匙串 + 严格 ACL，换签名时如何授权或迁移？
2. 希望默认本机绑定，还是支持迁移备份；丢钥匙时允许重新导入/订阅，还是必须提供独立加密导出？
3. 钥匙串锁定后的 GUI 行为、内存密钥缓存期限，以及何时阻止编辑或重新生成运行配置？
4. 迁移提交后旧凭据/旧明文与轮换历史钥匙保留多久？

算法本身已有足够依据选择 AES-256-GCM。上述边界会影响恢复能力、库加载行为和授权体验，宜在实现前形成设计决定。
