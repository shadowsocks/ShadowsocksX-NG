# Wayfinder issue 4：SIP-008 嵌套分组扩展与订阅兼容边界

研究日期：2026-09-20  
研究范围：只研究 SIP-008、官方 Shadowsocks 文档/源码和一手 JSON 规范；不修改 `Legacy/`，不修改生产代码。

## 决策摘要

1. **保持 SIP-008 外层协议不变。** 根对象继续使用 `"version": 1` 和扁平的 `"servers"` 数组；每个 `servers` 元素仍必须是有效的 Shadowsocks 服务器配置。
2. **采用根级、项目命名空间扩展。** 使用 `"x_shadowsocksx_ng"` 作为 ShadowsocksX-NG 私有扩展字段，扩展对象内使用独立的 `"schema_version": 1`。SIP-008 要求自定义字段使用 snake_case，但没有定义扩展注册表或官方命名空间，因此该名称必须被视为产品私有协议，而不是 SIP-008 标准字段。
3. **服务器身份复用 SIP-008 的 `servers[].id`。** 该字段本来就是用于在线更新时区分服务器并保留客户端侧信息的稳定 UUID；扩展分组只引用这个 ID，不复制服务器配置，也不使用数组下标、备注、地址或端口作为身份。
4. **分组使用独立且持久的 UUID。** SIP-008 没有分组身份模型，因此扩展必须定义 `group.id`；刷新时只要分组仍代表同一逻辑分组，就必须保留该 ID，分组名称可以变化。
5. **标准客户端降级为扁平列表。** 普通 SIP-008 客户端只需要读取根 `servers`；扩展感知客户端才读取 `x_shadowsocksx_ng` 的树。扩展缺失、版本不支持或树校验失败时，ShadowsocksX-NG 应保留并显示根 `servers` 的扁平结果，而不是丢弃整个订阅。
6. **传输安全沿用 SIP-008 的硬约束。** 订阅必须使用 HTTPS，不能忽略证书或 TLS 握手错误；响应必须声明 `Content-Type: application/json; charset=utf-8`。扩展字段不提供额外的保密性，密码仍位于 SIP-008 的服务器对象中，不能把密码或其他凭据放进分组元数据。
7. **暂不需要独立的公开标准化流程。** 只要扩展是 ShadowsocksX-NG 2.0 与受控订阅提供方之间的私有协议，仓库内的版本化协议文档即可。若将来要求第三方客户端或订阅服务互操作，则必须在实现前发布公开、版本化的扩展规范，并明确下面的身份、降级、校验和安全规则。

## 一手来源与证据范围

以下来源均为规范拥有者或官方实现；`shadowsocks-rust` 链接固定到 2026-09-20 读取的提交 `157cefa96d44de848ff218119dbec2047826c1bb`，`shadowsocks-org` 源文档链接固定到提交 `34598d65054dad975d330ff9d7317b0d41cf1efd`。

- [SIP-008 Online Configuration Delivery（Shadowsocks 官方文档）](https://shadowsocks.org/doc/sip008.html)：定义 JSON 结构、服务器 UUID、自定义字段、HTTPS、TLS 错误处理和响应 Content-Type。
- [SIP-008 源文档（shadowsocks-org）](https://github.com/shadowsocks/shadowsocks-org/blob/34598d65054dad975d330ff9d7317b0d41cf1efd/docs/doc/sip008.md)：官方文档源文件。
- [shadowsocks-rust README：Configuration](https://github.com/shadowsocks/shadowsocks-rust/blob/157cefa96d44de848ff218119dbec2047826c1bb/README.md#configuration)：官方实现对多服务器配置和 `sslocal` 自动选择行为的说明。
- [shadowsocks-rust 配置解析源码](https://github.com/shadowsocks/shadowsocks-rust/blob/157cefa96d44de848ff218119dbec2047826c1bb/crates/shadowsocks-service/src/config.rs)：`SSConfig`、`SSServerExtConfig` 和 SIP-008 `id`/`remarks` 字段的反序列化模型。
- [shadowsocks-rust 核心服务器配置源码](https://github.com/shadowsocks/shadowsocks-rust/blob/157cefa96d44de848ff218119dbec2047826c1bb/crates/shadowsocks/src/config.rs)：`ServerConfig` 对 SIP-008 `id` 与备注的保存和访问。
- [shadowsocks-rust SIP-008 在线配置源码](https://github.com/shadowsocks/shadowsocks-rust/blob/157cefa96d44de848ff218119dbec2047826c1bb/crates/shadowsocks-service/src/local/online_config/mod.rs)：官方客户端如何检查 HTTP 状态、Content-Type、解析 JSON 并加载在线服务器。
- [RFC 8259 §4（JSON objects）](https://www.rfc-editor.org/rfc/rfc8259#section-4)：JSON 对象名称应唯一；这是命名空间避免碰撞的通用互操作性依据。

## 规范约束

### SIP-008 的标准部分必须保持可独立使用

SIP-008 的标准文档要求根对象包含 `version`，当前版本值为 `1`；根对象的 `servers` 数组承载服务器配置；数组中的每个对象必须表示一个有效的 Shadowsocks 服务器。文档还允许根对象和服务器对象携带自定义字段，但明确说明这些字段不保证被所有客户端支持。

因此，嵌套分组不能把 `servers` 改成分组对象，也不能只在自定义字段中传递服务器配置。正确的兼容基线是：

- 根 `servers` 始终是完整、扁平、可导入的服务器列表。
- 每个服务器对象保留 SIP-008 标准字段：至少包括 `id`、`remarks`、`server`、`server_port`、`password`、`method`；不使用分组对象替代这些字段。
- 分组和树结构全部放在单独的根级自定义字段中。
- 扩展感知客户端将树视为组织/呈现信息；标准客户端仍能看到所有服务器，只是看不到嵌套关系。

这不能保证面对不遵循 SIP-008 的严格解析器时绝对不出错。SIP-008 只保证“自定义字段被允许”，并没有保证每个历史客户端都会忽略它们；因此不能把“普通客户端一定成功”写成协议承诺，只能把标准客户端的扁平降级作为设计目标和测试要求。

### 自定义字段与命名空间

SIP-008 建议自定义字段采用 snake_case，并允许在根对象增加自定义字段。文档没有给出扩展注册表、保留的 vendor prefix 或嵌套分组字段名。基于此，推荐只增加一个根级字段：

```json
"x_shadowsocksx_ng": {
  "schema_version": 1,
  "root_group_id": "...",
  "groups": []
}
```

选择根级单一对象有三个目的：

1. `servers` 内的对象继续是标准服务器对象，便于没有扩展能力的客户端处理。
2. 一个项目命名空间可以容纳未来的扩展字段，减少多个顶层字段与未来 SIP-008 字段冲突的机会。
3. `x_` 只是本项目的私有约定，不应被描述为 SIP-008 官方保留前缀；公开互操作前需要在扩展规范中固定它的含义。

不应复用 `bytes_used` 或 `bytes_remaining` 表达其他含义。SIP-008 对这两个流量字段有明确语义，并要求支持它们的客户端以标准字段为唯一数据源。

### 稳定服务器身份

SIP-008 的 `servers[].id` 是随机生成的 UUID，用于在线更新时区分服务器，使客户端可以保留该服务器的本地附加信息。因此：

- 提供方创建服务器时生成一次 UUID，并在后续订阅刷新中保留它。
- `x_shadowsocksx_ng` 中的 server 引用必须等于对应 `servers[].id`。
- 服务器的显示名、地址、端口、密码、加密方法变化都不应自动产生新的 ID；只有“这是一个不同的逻辑服务器”时才生成新 ID。
- 绝不能用数组下标、`remarks`、`server:server_port` 或配置内容哈希取代 SIP-008 ID；这些值会因排序、改名或配置更新而变化。
- 本地应用应在订阅作用域内解释这些 ID；不同订阅源出现相同字符串时，不能因此合并成同一服务器。订阅本身的稳定身份和刷新合并规则留给 wayfinder issue 9 决定。

### 稳定分组身份

SIP-008 没有分组字段或分组 UUID。扩展必须自行定义分组身份：

- `group.id` 使用随机 UUID 或同等不可变、不透明的字符串。
- ID 只表示逻辑身份；`name` 是可变的显示名称。
- 提供方刷新时保留同一逻辑分组的 ID；删除分组时删除该 ID，不能把它立即复用于其他分组。
- 分组 ID 与服务器 ID 应在整个扩展文档内保持唯一；子引用仍通过 `type` 区分 `group` 和 `server`。
- 分组必须形成有序、无环的树。父分组的 `children` 顺序是用户可见顺序；不能依赖 JSON 对象成员的顺序，因为 RFC 8259 明确指出对象成员顺序不应成为互操作基础。

## 建议的 JSON 形状

下面的文档仍是合法的 SIP-008 形状；新增部分只是项目私有自定义字段。示例中根标准列表包含全部叶子服务器，扩展树只保存身份引用和分组关系。

```json
{
  "version": 1,
  "servers": [
    {
      "id": "3c5e2af7-9f2c-4f42-bd1c-9e143d5f2d11",
      "remarks": "Tokyo 1",
      "server": "tokyo.example.com",
      "server_port": 443,
      "password": "example-secret-1",
      "method": "chacha20-ietf-poly1305"
    },
    {
      "id": "b9f08d65-8be7-4b09-bf94-4f2bb53e4199",
      "remarks": "Osaka 1",
      "server": "osaka.example.com",
      "server_port": 443,
      "password": "example-secret-2",
      "method": "chacha20-ietf-poly1305"
    }
  ],
  "x_shadowsocksx_ng": {
    "schema_version": 1,
    "root_group_id": "f6ad0a41-2a1d-4db8-9da0-b6f4f3dc889d",
    "groups": [
      {
        "id": "f6ad0a41-2a1d-4db8-9da0-b6f4f3dc889d",
        "name": "Example subscription",
        "children": [
          {
            "type": "group",
            "id": "a1e2b11c-2f53-4e39-bc36-95af6dbb5f1c"
          },
          {
            "type": "server",
            "id": "3c5e2af7-9f2c-4f42-bd1c-9e143d5f2d11"
          }
        ]
      },
      {
        "id": "a1e2b11c-2f53-4e39-bc36-95af6dbb5f1c",
        "name": "Japan",
        "children": [
          {
            "type": "server",
            "id": "b9f08d65-8be7-4b09-bf94-4f2bb53e4199"
          }
        ]
      }
    ]
  }
}
```

### 字段语义

| 字段 | 语义 | 兼容性要求 |
| --- | --- | --- |
| `version` | SIP-008 文档版本 | 固定为 `1`，不用于表示本扩展版本 |
| `servers` | 完整扁平服务器列表 | 所有服务器必须仍是有效 SIP-008 服务器对象 |
| `servers[].id` | SIP-008 服务器稳定 UUID | 扩展中的 `type: server` 引用必须指向它 |
| `x_shadowsocksx_ng` | ShadowsocksX-NG 私有命名空间 | 未识别客户端可忽略；不能承载标准列表的唯一副本 |
| `schema_version` | 私有扩展版本 | 初始值为 `1`；未知版本按扩展不可用处理 |
| `root_group_id` | 唯一根分组 | 必须指向 `groups` 中的一个分组 |
| `groups[].id` | 分组稳定身份 | 不使用名称或数组位置作为身份 |
| `groups[].name` | 展示名称 | 可变，不参与身份匹配 |
| `groups[].children` | 有序的分组/服务器引用 | 必须解析到现有 ID，且整棵树无环 |

### 客户端校验与降级

ShadowsocksX-NG 2.0 的扩展解析器应按以下顺序处理：

1. 先按 SIP-008 解析并校验根 `version` 和 `servers`。
2. 无论扩展是否存在，先建立根 `servers` 的扁平候选集。
3. 只有 `schema_version` 支持、ID 唯一、引用完整、根存在且无环时，才建立嵌套树。
4. 扩展失败时记录可诊断错误，并回退到同一响应中的扁平 `servers`；不能因为私有字段损坏而丢失标准服务器。
5. 对于未被树引用但存在于 `servers` 的服务器，保留在一个本地“未分组”集合中，除非后续领域模型票据明确规定提供方必须做到严格一一引用。
6. 下载到的密码只作为服务器配置数据处理；分组对象不得引入另一份密码、密钥或可执行内容。

## 官方实现观察

官方 `shadowsocks-rust` README 描述了扩展配置中的 `servers` 数组，并说明 `sslocal` 会依据延迟和可用性自动选择最佳服务器；这支持 ShadowsocksX-NG 在激活分组时把其后代服务器扁平化为 `shadowsocks-rust` 的多服务器配置。

官方实现的配置模型 `SSConfig` 使用 `servers: Option<Vec<SSServerExtConfig>>`，服务器模型包含 `server`、`server_port`、`password`、`method`、`remarks`、`id` 等字段；这些结构派生 Serde 的 `Deserialize`，源码中没有为这些结构声明 `deny_unknown_fields`。因此，**对该实现而言**，根级未知扩展字段通常会被忽略；这是实现观察，不应扩大解释为所有 SIP-008 客户端都必须忽略未知字段。

官方 `sslocal` 在线配置实现还会：

- 检查 HTTP 状态为 200；
- 检查 `Content-Type` 是否为 `application/json; charset=utf-8`；当前实现对缺失或不匹配的类型记录 warning，而不是在该检查处直接拒绝；
- 将正文解析为在线配置，执行完整性检查，然后把在线服务器替换到在线配置来源的 balancer 中。

因此，2.0 订阅实现应遵守 SIP-008 的规范要求，不能因为当前 `shadowsocks-rust` 对 Content-Type 采取 warning 行为，就把错误 Content-Type 当成协议上安全的输入。

## 安全与兼容边界

- **HTTPS 是要求，不是优化项。** 必须校验证书和 TLS 握手，不能为了“兼容订阅地址”忽略证书错误或降级到明文 HTTP。HTTP 仅适合明确的调试场景，并应向用户警告或拒绝。
- **订阅 URL 仍然是敏感凭据。** SIP-008 建议在 URL 路径或查询参数中使用秘密以降低爬取风险；应用日志、错误信息和诊断报告不得无意记录完整订阅 URL。
- **Content-Type 必须精确处理。** 服务端应发送 `application/json; charset=utf-8`；客户端可以容忍官方实现的实际 warning 行为，但 2.0 自己的服务端/测试应把它作为契约验证。
- **扩展不改变凭据暴露面。** `password` 已在标准 `servers` 对象中，扩展只传 ID 和树关系；不要在分组中重复密码，不要把凭据放入 `name`、`id` 或其他可被 UI/日志展示的字段。
- **自定义字段不可承载标准流量语义。** 流量计量必须使用 SIP-008 的 `bytes_used` 和 `bytes_remaining`，不要另定义同义字段。
- **未知扩展必须可忽略。** 普通客户端至少应能按标准 `servers` 工作；扩展感知客户端也必须在扩展失败时保留标准列表。

## 是否需要公开扩展规范

### 2.0 私有订阅：不是当前阻塞项

如果订阅提供方与 ShadowsocksX-NG 2.0 是明确的控制方/消费方，`x_shadowsocksx_ng` 可以作为私有 SIP-008 自定义字段使用。实现前只需在本仓库维护版本化协议文档，固定：字段名、UUID 生命周期、树不变量、未知版本处理、扁平回退、HTTPS/Content-Type 和安全日志策略。

### 对外互操作：需要公开规范

以下任一条件成立时，应先发布公开的扩展规范，而不是继续依靠实现代码作为唯一契约：

- 第三方订阅服务需要生成嵌套分组；
- 其他客户端需要显示或激活相同分组；
- 需要承诺跨版本的刷新合并和本地元数据保留；
- 需要由多个实现独立验证同一订阅文档。

这份公开文档不一定要成为新的 SIP，也不应冒充 SIP-008 官方字段；它可以是 ShadowsocksX-NG 的公开 vendor extension spec，并明确“未实现该扩展的客户端按 SIP-008 扁平列表处理”。若未来希望让多个独立项目采用，应再评估向 Shadowsocks SIP 流程提交正式提案的价值。

## 对后续票据的边界

- 本票据确定扩展 JSON 的兼容与安全边界，不决定订阅 URL 的本地 canonicalization、订阅身份、刷新合并和失败恢复；这些属于 wayfinder issue 9。
- 本票据不决定密码是否进入 Keychain、临时配置文件权限和删除时机；这些属于 shadowsocks-rust 配置生命周期票据。
- 本票据不修改 Legacy、XcodeGen 工程、SwiftUI UI 或生产实现。
