# 服务器库加密文件格式 v2

[English](server-library-encryption-format.md) | 简体中文

记录日期：2026-10-18。实现快照：`507917a`。

本文记录该提交中的 `catalog.enc` 格式，供维护、排错和编写兼容读取器时参考。本文属于实现时点的格式说明，不持续维护为最新现状；当前行为以源码和 [ADR-0035](adr/0035-encrypt-persistent-server-library.md) 为准。

## 1. 文件与保护范围

默认路径为 `~/Library/Application Support/ShadowsocksX-NG2/configuration/catalog.enc`。文件是二进制，结构为：

```text
完整文件 = 明文文件头 || nonce || ciphertext || tag
认证附加数据 AAD = 明文文件头的原始 45 字节
加密算法 = AES-256-GCM
```

`||` 表示按字节拼接。文件头不加密，但参与认证。文件内没有主密钥。

密文包含完整配置目录、订阅记录、有序收藏，以及由所属记录直接保存的密码、完整插件参数和订阅 URL。运行配置 `sslocal-active.json`、监听认证派生文件、用户主动生成的分享或导出文件不属于此格式。

## 2. 二进制布局

偏移从 0 开始，单位均为字节。令 `P` 为加密前完整 payload 的 UTF-8 字节数；AES-GCM 的 ciphertext 长度也为 `P`。

| 偏移 | 长度 | 字段 | 编码与含义 |
| --- | --- | --- | --- |
| 0 | 8 | magic | ASCII `SSXNG2LB`，十六进制为 `53 53 58 4E 47 32 4C 42` |
| 8 | 1 | envelopeVersion | 固定为二进制 `0x02`，不是字符 `2` |
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

v2 没有独立算法字段。版本 `0x02` 固定对应 AES-256-GCM；读取器不在失败后尝试另一种算法。

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

解密结果直接是目录的 UTF-8 JSON。没有外层 `catalog`/`secrets` 对象、嵌套的 Base64 目录或独立凭据引用映射。

写入器生成目录 schema v7，读取器只接受 v7。该 schema 版本与文件头的 envelopeVersion 独立：`0x02` 不等于目录 schema v2。

### 4.1 目录 JSON

五个顶层字段均为必需字段，空数组也不能省略：

| 字段 | JSON 类型 | 含义 |
| --- | --- | --- |
| `version` | number | 目录 schema 版本，固定为 `7` |
| `rootChildren` | array | 根层节点身份的有序数组 |
| `entries` | array | 全部节点；写入时按节点 `id.rawValue` 排序 |
| `subscriptions` | array | 订阅记录，包含 URL 值与刷新资料 |
| `favoriteIDs` | array | 收藏节点身份的有序数组 |

空库的 payload 如下：

```json
{
  "entries": [],
  "favoriteIDs": [],
  "rootChildren": [],
  "subscriptions": [],
  "version": 7
}
```

节点的层级和显示顺序由 `rootChildren` 与配置组的子节点数组表达，不能用 `entries` 数组顺序替代。写入器启用 `prettyPrinted` 和 `sortedKeys`；兼容读取器不能依赖空白或对象键顺序。

### 4.2 秘密由记录直接持有

| 所属模型 | 字段 | JSON 类型 | 含义 |
| --- | --- | --- | --- |
| `ServerFields` | `password` | string | 服务器密码 |
| `ServerFields` | `pluginOptions` | optional string | 完整、不解析内容的插件参数 |
| `SubscriptionRecord` | `url` | string | 完整订阅 URL |

这些字段在解密后的 JSON 中是普通字符串，由整个 payload 的加密提供保护。写入器不再用 `passwordRef`、`pluginOptionsRef` 或 `urlRef` 代替它们，也不再校验引用集合。局域网监听认证凭据仍在服务器库范围之外。

`ServerFields` 是 `CatalogEntry.Kind.server` 的关联值，其 JSON 位于节点的 `kind.server._0` 对象中。订阅 `url` 直接位于 `subscriptions` 数组的记录内。合成的 Codable 编码器在可选字段为 nil 时省略该字段。节点、订阅、枚举字段和可选元数据的完整编码以对应 Swift Codable 模型为准，本文不另行复制整个目录 schema。

## 5. 读取顺序与错误

存在 `catalog.enc` 时，读取器按以下顺序检查：

1. 检查文件大小。
2. 校验 magic。
3. 校验 envelopeVersion。
4. 解析 keyID。
5. ID 匹配时使用缓存的主密钥，否则从 Keychain 读取对应密钥；检查长度为 32 字节。
6. 用原始文件头作为 AAD，验证并解密 `combined`。
7. 按当前 payload 模型解码目录 JSON。
8. 要求 schema 为 v7，再校验节点身份唯一性、目录结构、订阅身份与固定分组关联，以及收藏。

当前限制 `P ≤ 64 × 1024 × 1024`，即最多 67,108,864 字节。该限制针对完整目录 JSON，包含密码、插件参数和 URL 值的编码开销，没有嵌套 Base64 的额外开销。

文件大小检查区间为 **73–67,108,937 字节**。73 字节只是结构检查的下限；空 payload 不是合法 JSON，因此不能据此构造有效空库。

| 情况 | 当前错误 |
| --- | --- |
| 大小越界、magic 无效或 UUID 无效 | `ServerLibraryError.malformedFile` |
| envelopeVersion 不是 `0x02` | `ServerLibraryError.unsupportedVersion` |
| 找不到密钥，或密钥不是 32 字节 | `ServerLibraryError.keyUnavailable` |
| GCM 认证或 SealedBox 解析失败 | `ServerLibraryError.authenticationFailed` |
| 目录 JSON 解码、schema 版本或目录结构校验失败 | `CatalogFileStore.PersistenceError.corrupt` |
| 钥匙串拒绝访问或需要交互授权 | `CredentialStoreError.keychainStatus`，保留系统状态码 |
| 当前存储实例加载后文件消失，或未成功加载、重置服务器库就尝试保存 | `ServerLibraryError.notLoaded` |

文件系统读取错误按原错误抛出。多个条件同时不满足时，以读取顺序最先遇到的错误为准。Codable 解码先于 schema 版本检查，因此不兼容的 payload 可能在检查版本之前就解码失败。

存在 `catalog.enc` 时，即使读取失败，也不自动退回 `catalog.json`、尝试明文解码或创建空库。应用阻止服务器库写入，保留已有代理运行。只有用户明确确认放弃原配置后，才执行覆盖重置。

## 6. 写入与历史格式

写入顺序为：完整目录 JSON 编码 → 内存加密 → 写入密文临时文件 → 原子替换。服务器库不再单独收集秘密，也不执行逐项凭据写入日志。工作流使用完整工作副本，只有持久化成功后才发布新的已提交值。

目录权限为 `0700`，临时文件创建时的权限为 `0600`。临时文件与目标文件位于同一目录，名称采用 `.catalog.enc.tmp-<UUID>`；临时文件也只包含完整的加密格式。当前写入器没有显式 `fsync`，本文不承诺断电持久性。

NG2 尚未发版，读取器不迁移其历史数据：

- 已有封装 v1 文件返回 `ServerLibraryError.unsupportedVersion`；目录 schema v1–v6 不再支持。
- 没有 `catalog.enc` 但存在 `catalog.json` 时，启动返回 `ServerLibraryError.unsupportedVersion`。只检查旧文件是否存在，不读取其内容，不解析旧逐项 Keychain 凭据，也不清理这些文件或凭据。
- 新存储实例仅在两种库文件均不存在时创建加密空库；提交密文前先保存并读回校验新主密钥。
- 用户确认重置时，用新主密钥写入新的空 `catalog.enc`，不删除旧 `catalog.json` 或旧逐项 Keychain 凭据。只有新文件保存成功后，才替换当前主密钥与应用已提交状态。

保留用户主动执行的旧版 ShadowsocksX-NG 服务器导入。该功能构造直接携带秘密值的新记录，与 NG2 历史存储格式迁移不同。

## 7. 格式能力的边界

- 文件头、文件大小和文件系统时间仍然可见。
- 认证能检测文件篡改，但该格式没有独立的防回滚状态。
- 主密钥和解密资料在获准读取后保留于当前应用进程，直到退出。
- 此格式不是可脱离本机钥匙串使用的密码加密备份格式。

## 8. 源码入口

- [ServerLibraryStorage.swift](../ShadowsocksX-NG2/Domain/Catalog/ServerLibraryStorage.swift)：文件头、加解密、payload 大小限制与历史文件处理。
- [CatalogFileStore.swift](../ShadowsocksX-NG2/Domain/Catalog/CatalogFileStore.swift)：直接目录 JSON 编码、schema v7 和结构校验。
- [MasterKeyStore.swift](../ShadowsocksX-NG2/Domain/Credentials/MasterKeyStore.swift)：主密钥的 Keychain 属性与访问方式。
- [CatalogModels.swift](../ShadowsocksX-NG2/Domain/Catalog/CatalogModels.swift)、[SubscriptionRecord.swift](../ShadowsocksX-NG2/Domain/Subscription/SubscriptionRecord.swift)：目录记录及内联秘密的 Codable 模型。
- [AtomicFileWriter.swift](../ShadowsocksX-NG2/Domain/Runtime/AtomicFileWriter.swift)：临时文件与权限基线。
