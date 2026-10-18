# 服务器库加密文件格式 v1

[English](server-library-encryption-format.md) | 简体中文

记录日期：2026-10-18。实现快照：`6cbef4e`。

本文记录该提交中的 `catalog.enc` 格式，供维护、排错和编写兼容读取器时参考。本文属于实现时点的格式说明，不持续维护为最新现状；当前行为以源码和 [ADR-0035](adr/0035-encrypt-persistent-server-library.md) 为准。

## 1. 文件与保护范围

默认路径为 `~/Library/Application Support/ShadowsocksX-NG2/catalog.enc`。文件是二进制，结构为：

```text
完整文件 = 明文文件头 || nonce || ciphertext || tag
认证附加数据 AAD = 明文文件头的原始 45 字节
加密算法 = AES-256-GCM
```

`||` 表示按字节拼接。文件头不加密，但参与认证。文件内没有主密钥。

密文包含完整配置目录、订阅记录、有序收藏，以及这些资料引用的密码、完整插件参数和订阅 URL。运行配置 `sslocal-active.json`、监听认证派生文件、用户主动生成的分享或导出文件不属于此格式。

## 2. 二进制布局

偏移从 0 开始，单位均为字节。令 `P` 为加密前完整 payload 的 UTF-8 字节数；AES-GCM 的 ciphertext 长度也为 `P`。

| 偏移 | 长度 | 字段 | 编码与含义 |
| --- | --- | --- | --- |
| 0 | 8 | magic | ASCII `SSXNG2LB`，十六进制为 `53 53 58 4E 47 32 4C 42` |
| 8 | 1 | envelopeVersion | 固定为二进制 `0x01`，不是字符 `1` |
| 9 | 36 | keyID | UUID 的 UTF-8 文本，含连字符，不含引号、结束零字节或换行 |
| 45 | 12 | nonce | CryptoKit 默认生成的随机 nonce |
| 57 | `P` | ciphertext | 完整 payload 的 AES-GCM 密文 |
| `57 + P` | 16 | tag | GCM 认证标签 |

因此：

```text
headerLength = 8 + 1 + 36 = 45
combined = nonce || ciphertext || tag
fileLength = P + 73
P = fileLength - 73
```

文件没有额外长度字段、填充、分隔符、压缩层或 Base64 外壳。`keyID` 示例为 `65A4F8AE-28F6-46A2-B61F-7CFA9A85D7F2`；写入器使用 `UUID.uuidString` 生成文本，不能把它替换成 UUID 的 16 字节二进制表示。

v1 没有独立算法字段。版本 `0x01` 固定对应 AES-256-GCM；读取器不在失败后尝试另一种算法。

## 3. 主密钥与认证

主密钥由 `SymmetricKey(size: .bits256)` 随机生成，长度为 32 字节。它不是用户口令，也不是由 `keyID` 派生的值。

生产存储使用经典钥匙串的 Generic Password 项：

| 属性 | 值 |
| --- | --- |
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `com.qiuyuzhou.ShadowsocksX-NG2.server-library` |
| `kSecAttrAccount` | 文件头 UUID 解析后的 `uuidString` |
| `kSecValueData` | 主密钥原始 32 字节，不是十六进制或 Base64 文本 |
| `kSecAttrSynchronizable` | `false` |
| `kSecUseDataProtectionKeychain` | `false` |

创建项时，`SecAccessCreate` 的获准应用列表只包含当前应用。文件头只负责定位密钥，不授予钥匙串访问权限。只有 `catalog.enc` 而没有对应主密钥时，无法解密服务器库。

写入器使用 CryptoKit 默认 nonce，每次保存重新生成。主密钥在正常保存时保持不变；用户确认重置服务器库时生成新主密钥。nonce 和 tag 直接使用 `AES.GCM.SealedBox.combined` 的布局。

加密和解密都将原始头字节作为 AAD。兼容读取器必须使用文件中的原始 45 字节，不能解析 UUID 后重新编码文件头来替代 AAD。

## 4. 解密后的 payload

解密结果是 UTF-8 JSON，具有两个必需字段：

| 字段 | JSON 类型 | 含义 |
| --- | --- | --- |
| `catalog` | string | 目录 JSON 的 UTF-8 字节，经 Foundation `Data` 的 Codable 规则编码为 Base64 字符串 |
| `secrets` | object | 凭据引用字符串到秘密字符串的映射；空映射为 `{}` |

处理层次为：

```text
catalog.enc
  └─ AES-GCM 解密 → payload JSON
       ├─ catalog → Base64 解码 → 目录 JSON
       └─ secrets → 凭据引用到秘密值的映射
```

外层 JSON 不是直接嵌入目录对象。`catalog` 也不是经过 JSON 转义的目录文本；它必须先做 Base64 解码。这里的 Base64 仅用于序列化嵌套字节，不承担保密作用。

空库的示意 payload 如下。为缩短示例，其 `catalog` 对应的目录 JSON 省略了实际写入器的缩进。

```json
{
  "catalog": "eyJlbnRyaWVzIjpbXSwiZmF2b3JpdGVJRHMiOltdLCJyb290Q2hpbGRyZW4iOltdLCJzdWJzY3JpcHRpb25zIjpbXSwidmVyc2lvbiI6Nn0=",
  "secrets": {}
}
```

其中 `catalog` 解码后为：

```json
{"entries":[],"favoriteIDs":[],"rootChildren":[],"subscriptions":[],"version":6}
```

外层 JSON 没有独立的 payload 版本字段，也没有固定键顺序或空白约定。不要依赖某次 JSON 编码产生的确切文本布局。

### 4.1 内层目录 JSON

当前写入目录 schema v6，读取兼容 v1–v6。该 schema 版本与文件头的 envelopeVersion 独立：`0x01` 不等于目录 schema v1。

v6 的顶层字段为：

| 字段 | 含义 |
| --- | --- |
| `version` | 目录 schema 版本，当前写入 `6` |
| `rootChildren` | 根层节点身份的有序数组 |
| `entries` | 全部节点；写入时按节点 `id.rawValue` 排序 |
| `subscriptions` | 订阅记录，包含 URL 凭据引用与刷新资料 |
| `favoriteIDs` | 收藏节点身份的有序数组 |

节点的层级和显示顺序由 `rootChildren` 与配置组的子节点数组表达，不能用 `entries` 数组顺序替代。内层写入器启用 `prettyPrinted` 和 `sortedKeys`。节点、订阅与枚举字段的完整编码以对应 Swift Codable 模型为准，本文不另行复制整个目录 schema。

### 4.2 凭据引用的一致性

`secrets` 的键集合必须与目录实际引用的凭据集合完全相等。读取器同时拒绝缺少引用值和多余的秘密项。

引用集合是以下字段的并集：

- 每个服务器的 `passwordRef`。
- 每个服务器非空的 `pluginOptionsRef`。
- 每条订阅的 `urlRef`。

值是原始秘密字符串。写入器只保存当前目录引用的值，不把进程内残留的其他凭据加入 payload。该规则不包含局域网监听认证凭据。

## 5. 读取顺序与错误

当前读取器按以下顺序检查：

1. 检查文件大小。
2. 校验 magic。
3. 校验 envelopeVersion。
4. 解析 keyID。
5. 查找对应主密钥，并检查长度为 32 字节。
6. 用原始文件头作为 AAD，验证并解密 `combined`。
7. 解码外层 payload JSON。
8. Base64 解码 `catalog`，再按目录 schema 解码和校验。
9. 检查凭据引用集合与 `secrets` 键集合相等。

`Data` 的 Base64 解码属于外层 Codable 解码的一部分；上面的第 8 步用于说明数据依赖关系。

当前限制 `P ≤ 64 × 1024 × 1024`，即最多 67,108,864 字节。该限制针对完整 payload JSON，包含 Base64 字符串与 `secrets` 的编码开销，不是内层目录 JSON 的大小。

文件大小检查区间为 **73–67,108,937 字节**。73 字节只是结构检查的下限；空 payload 不是合法 JSON，因此不能据此构造有效空库。

| 情况 | 当前错误 |
| --- | --- |
| 大小越界、magic 无效、UUID 无效、外层 JSON 或 Base64 无效 | `ServerLibraryError.malformedFile` |
| envelopeVersion 不是 `0x01` | `ServerLibraryError.unsupportedVersion` |
| 找不到密钥，或密钥不是 32 字节 | `ServerLibraryError.keyUnavailable` |
| GCM 认证或 SealedBox 解析失败 | `ServerLibraryError.authenticationFailed` |
| 目录引用与 `secrets` 键集合不一致 | `ServerLibraryError.missingCredential` |
| 内层目录 JSON、schema 或目录结构校验失败 | `CatalogFileStore.PersistenceError.corrupt` |
| 钥匙串拒绝访问或需要交互授权 | `CredentialStoreError.keychainStatus`，保留系统状态码 |

文件系统读取错误按原错误抛出。多个条件同时不满足时，以读取顺序最先遇到的错误为准。

存在 `catalog.enc` 时，即使读取失败，也不自动退回 `catalog.json`、尝试明文解码或创建空库。用户明确确认放弃原配置后，应用才执行覆盖重置。

## 6. 写入与迁移

写入顺序为：收集被引用的秘密 → 目录编码 → 外层 JSON 编码 → 内存加密 → 写入密文临时文件 → 原子替换。

目录权限为 `0700`，临时文件创建时的权限为 `0600`。临时文件与目标文件位于同一目录，名称采用 `.catalog.enc.tmp-<UUID>`；临时文件也只包含完整的加密格式。当前写入器没有显式 `fsync`，本文不承诺断电持久性。

没有 `catalog.enc` 时，启动流程读取旧 `catalog.json` 并解析其所需旧凭据；全部读取成功后生成主密钥、提交新密文，再重新读取核对。验证成功后尝试删除旧文件与迁入的逐项凭据。两种库文件都不存在的首次启动，创建新的加密空库。

## 7. 格式能力的边界

- 文件头、文件大小和文件系统时间仍然可见。
- 认证能检测文件篡改，但该格式没有独立的防回滚状态。
- 主密钥和解密资料在获准读取后保留于当前应用进程，直到退出。
- 此格式不是可脱离本机钥匙串使用的密码加密备份格式。

## 8. 源码入口

- [ServerLibraryStorage.swift](../ShadowsocksX-NG2/Domain/Catalog/ServerLibraryStorage.swift)：文件头、加解密、payload、大小限制与引用集合检查。
- [CatalogFileStore.swift](../ShadowsocksX-NG2/Domain/Catalog/CatalogFileStore.swift)：目录 JSON 编码、schema 版本和结构校验。
- [LibraryMasterKeyStore.swift](../ShadowsocksX-NG2/Domain/Credentials/LibraryMasterKeyStore.swift)：主密钥的 Keychain 属性与访问方式。
- [CatalogModels.swift](../ShadowsocksX-NG2/Domain/Catalog/CatalogModels.swift)、[SubscriptionRecord.swift](../ShadowsocksX-NG2/Domain/Subscription/SubscriptionRecord.swift)：内层目录的 Codable 模型。
- [AtomicFileWriter.swift](../ShadowsocksX-NG2/Domain/Runtime/AtomicFileWriter.swift)：临时文件与权限基线。
