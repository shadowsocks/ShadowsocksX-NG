# 使用 age 加密敏感配置

[English](server-library-encryption-format.md) | 简体中文

服务器库和代理监听配置通过 [AgeSwift](https://github.com/qiuyuzhou/AgeSwift) 使用标准 [age v1 文件格式](https://age-encryption.org/v1)。采用理由与恢复边界见 [ADR-0050](adr/0050-age-encrypted-configuration-storage.md)。

## 文件与载荷

两个文件均位于 `~/Library/Application Support/ShadowsocksX-NG2/configuration/`：

| 文件 | 解密后的 UTF-8 JSON | 明文大小上限 |
| --- | --- | --- |
| `catalog.age` | 目录 schema v7：`version`、`rootChildren`、`entries`、`subscriptions`、`favoriteIDs` | 64 MiB |
| `proxy-listening.age` | `{ "version": 1, "configuration": { "local": …, "lan": … } }` | 1 MiB |

服务器库包含完整配置目录、订阅与有序收藏；服务器密码、完整插件参数、订阅 URL 直接保存在所属记录中。监听认证资料属于独立监听配置。运行 JSON、LAN 认证文件、用户主动导出与分享不属于本格式的范围。

保存使用单个 X25519 recipient 的二进制 age v1，不增加应用文件头、UUID 前缀、旁路索引、外层 Base64 或自研密码容器。读取也接受标准 ASCII armor；再次保存统一写二进制。JSON 结构版本位于加密载荷中，与 age 格式版本独立。完整模型通过校验后才发布。

空服务器库的载荷为：

```json
{
  "entries": [],
  "favoriteIDs": [],
  "rootChildren": [],
  "subscriptions": [],
  "version": 7
}
```

目录层级与顺序以 `rootChildren` 和分组子节点数组为准。秘密是记录中的普通值，不是凭据引用。完整结构以 Codable 模型为准，空白与对象键顺序不影响语义。

## Keychain identity

两个存储分别使用经典登录钥匙串中的 Generic Password service：

| 文件 | Service |
| --- | --- |
| `catalog.age` | `com.qiuyuzhou.ShadowsocksX-NG2.server-library.age` |
| `proxy-listening.age` | `com.qiuyuzhou.ShadowsocksX-NG2.proxy-listening.age` |

每条记录的 account 是 UUID，值为 UTF-8 编码的标准 `AGE-SECRET-KEY-1...` identity 文本，不是 AES 原始字节。记录不同步、不使用 Data Protection Keychain；创建时通过经典 Keychain ACL 仅授权当前应用。

文件不包含 Keychain account 定位信息。读取器枚举对应 service 的 account，尝试 identity 直至成功。存在无法访问或不匹配的候选时，其他可访问且匹配的 identity 仍能正常解密。正常保存复用匹配的 identity，并在当前进程缓存。确认重置时，先保存并回读新 identity，再原子替换密文；保留旧 identity，使提交失败或进程中断时旧文件仍可读取。记录随重置次数增加，不提供自动清理或手动轮换。

启动和后台读取不请求系统授权弹窗，继续沿用既有显式交互入口。丢失匹配 identity 后无法解密；更换格式不绕过 Keychain 授权，也不提供独立恢复能力。

## 使用标准工具检查

通过 `brew install age` 安装参考 CLI。在“钥匙串访问”中搜索上表完整 service，查看 account UUID。使用系统 `security` 工具，经系统授权后取得 identity。将 `ACCOUNT_UUID` 替换为实际账户；有多条记录时，可重复执行导出命令，把其他 identity 追加到同一个文件。

```bash
umask 077
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
security find-generic-password \
  -s com.qiuyuzhou.ShadowsocksX-NG2.server-library.age \
  -a ACCOUNT_UUID -w >> "$workdir/identities.txt"
age --decrypt -i "$workdir/identities.txt" \
  "$HOME/Library/Application Support/ShadowsocksX-NG2/configuration/catalog.age" | jq .
```

检查监听配置时，替换 service 和文件名为监听对应值。系统提示时选择单次授权，不放宽应用 ACL。identity 文件属于秘密，输出包含配置凭据。这些命令是维护者主动导出临时 identity 的调试操作；应用自身不向普通文件、日志或诊断报告写出 identity。删除临时文件不代表安全擦除。

标准 age 工具也能用对应的 `age1...` recipient 加密 JSON；应用仍会检查结构和大小。手动替换持久配置前退出 GUI，避免运行中的应用使用内存已提交值覆盖人工修改。无需项目专用解密器或应用内私钥导出界面。

## 读取、提交与恢复

读取前限制文件大小，计入 age 分块标签、文件头余量和 armor 开销；解密后再次检查明文上限。age 格式错误、identity 不可用、认证失败或 JSON 校验失败都会导致加载失败，不回退明文，不自动用默认值覆盖。

保存先编码并校验完整值，再在内存加密，使用同目录的纯密文临时文件原子替换目标。目录权限为 `0700`，临时文件和目标文件为 `0600`。当前写入器不显式调用 `fsync`，原子替换不保证断电持久性。成功保存后才发布应用内存状态。

新 `.age` 文件存在时优先使用它；不存在但对应 `.enc` 或历史 `.json` 存在时，报告不支持的格式，不按全新安装初始化。不迁移、读取、删除或回退到历史 NG2 文件，不访问或清理旧 AES 与逐项 Keychain 凭据。用户确认重置后创建新的 `.age` 文件，旧文件保持原样。

服务器库保留重试、显式解锁和确认创建空库；监听配置保留启动门禁和确认重置，默认关闭局域网监听。加载失败或重置失败期间保留原文件、已有后台代理与系统代理。用户主动执行的旧版 ShadowsocksX-NG 导入仍保留。

## 验证与限制

`AgeConfigurationStorageTests` 覆盖两份配置与标准 age CLI 的二进制、armor 双向互操作，以及旧文件拒绝、候选 identity 匹配、重置提交失败、结构和大小检查、隔离的真实 Keychain 操作。运行该测试需要 PATH 或 Homebrew bin 目录内存在 `age`，并能够访问登录钥匙串。

age 保护静态内容，文件大小与时间戳仍可见。它不提供回滚保护、安全内存擦除、跨机 identity 恢复或独立密码加密备份。应用持有已解密资料和匹配 identity 至退出。

源码入口：[EncryptedFileStorage](../ShadowsocksX-NG2/Domain/Credentials/EncryptedFileStorage.swift)、[MasterKeyStore](../ShadowsocksX-NG2/Domain/Credentials/MasterKeyStore.swift)、[CatalogFileStore](../ShadowsocksX-NG2/Domain/Catalog/CatalogFileStore.swift)、[ProxyListeningFileStore](../ShadowsocksX-NG2/Domain/Settings/ProxyListeningFileStore.swift)、[AtomicFileWriter](../ShadowsocksX-NG2/Domain/Runtime/AtomicFileWriter.swift)。
