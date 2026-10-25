# SIP-008 订阅扩展：供应方说明

本文说明 ShadowsocksX-NG 当前支持的 SIP-008 订阅字段和私有扩展，供订阅服务提供方生成兼容响应时参考。内容以当前实现为准。

[English](subscription-provider-extension.md)

`x_shadowsocksx_ng` 是 ShadowsocksX-NG 所有私有扩展的命名空间，包含 `expires_at`、`traffic_reset_at`，这些都不是 SIP-008 标准字段。今后本项目新增的扩展字段也必须归入根对象的这个命名空间，不直接放在根层或服务器对象中。普通 SIP-008 客户端不一定识别这些字段；没有扩展支持的客户端仍应从标准 `servers` 数组读取服务器。SIP-008 允许自定义字段，但不保证所有客户端支持。详见 [SIP-008 Online Configuration Delivery](https://shadowsocks.org/doc/sip008.html)。

## 响应传输

订阅端点必须满足以下条件：

- 使用 HTTPS。客户端验证系统信任链，不接受明文 HTTP，也不放宽证书或 TLS 校验；HTTPS 到 HTTPS 的重定向可以跟随，降级到非 HTTPS 会被拒绝。
- 成功响应状态码为 `200`。
- 响应头使用 `Content-Type: application/json; charset=utf-8`。客户端不区分大小写并忽略空白，但服务端应按此格式发送；缺少该头或使用其他类型、字符集都会被拒绝。
- 响应正文是一个合法的 JSON 对象，不是 JSON5、Base64 或 `ss://` 链接列表。

SIP-008 订阅 URL 通常包含访问令牌。请使用不可猜测的令牌，并避免在服务端访问日志、错误追踪或分析系统中记录完整订阅 URL。订阅正文含服务器密码；HTTPS 负责传输保护，扩展字段本身不加密正文。

## SIP-008 v1 基础对象

根对象必须包含 `version: 1` 和 `servers` 数组。空数组有效。服务器项按 SIP-008 应提供 `id`、`remarks`、`server`、`server_port`、`password` 和 `method`；使用插件时再提供 `plugin`、`plugin_opts`。每个服务器项仍须是完整的 Shadowsocks 服务器记录；不能只在分组扩展里发送服务器配置。

| 字段 | 供应方要求与建议 | 客户端处理 |
| --- | --- | --- |
| `version` | 必须是整数 `1`。 | 缺失或其他版本会拒绝整份文档。 |
| `servers` | 必须是数组；每项使用下表所列的 SIP-008 服务器字段。 | 缺失或不是数组会拒绝整份文档。空数组有效。 |
| `servers[].id` | SIP-008 服务器项必需字段。每台服务器提供唯一、规范格式的 UUID，并在同一逻辑服务器的后续刷新中保持不变。分组扩展依赖此字段引用服务器。 | 当前解析器容忍省略 `id`，但提供后必须是有效 UUID；重复 ID 会拒绝整份文档。无 ID 项不能被扩展树引用，会按扁平兼容路径处理。 |
| `servers[].remarks` | SIP-008 服务器项必需字段，提供服务器显示名称字符串。 | 当前解析器容忍省略；缺省时名称为空。 |
| `servers[].server` | 必须是非空字符串。 | 缺失或为空会拒绝整份文档。 |
| `servers[].server_port` | 必须是 `1` 到 `65535` 范围内的整数。 | 缺失、非整数或越界会拒绝整份文档。 |
| `servers[].password` | 必须是非空字符串。 | 缺失或为空会拒绝整份文档。 |
| `servers[].method` | 必须是非空字符串。请提供客户端可用的 Shadowsocks 加密方法。 | 缺失或为空会拒绝整份文档；方法是否可用由代理运行时决定。 |
| `servers[].plugin`、`servers[].plugin_opts` | 未使用插件时两项省略或留空；使用插件时按 SIP-008 提供插件名及对应选项。 | 客户端将值带入服务器配置，不会在订阅解析时校验插件选项语义。 |

服务器 ID 表示逻辑身份，不是数组位置。改名、改地址、改端口或更新凭据时，如果仍是同一逻辑服务器，应保留原 ID；新增一台逻辑服务器时分配新 ID。UUID 应采用连字符分隔的规范形式，并在正文和扩展引用中保持完全相同的字符串。

## 订阅资料

以下流量字段来自 SIP-008。供应方应遵守 SIP-008 对数据量字段的约定；客户端仅把符合下表格式的值显示为订阅资料。

| 字段 | 供应方格式 | 说明 |
| --- | --- | --- |
| `bytes_used` | JSON 非负整数，范围为 `0` 至 `18446744073709551615`。 | 用户已使用的字节数。不要发送字符串、负数、小数或指数形式。 |
| `bytes_remaining` | JSON 非负整数，范围同上。没有流量上限时省略；有限额时同时提供 `bytes_used`。 | 用户剩余可用字节数。不要用私有字段重复表达同一流量含义。 |
| `x_shadowsocksx_ng.expires_at` | RFC 3339 日期时间字符串，例如 `2027-01-01T00:00:00Z` 或 `2027-01-01T08:00:00+08:00`。 | ShadowsocksX-NG 私有字段，表示服务到期时间。 |
| `x_shadowsocksx_ng.traffic_reset_at` | RFC 3339 日期时间字符串。 | ShadowsocksX-NG 私有字段，表示流量重置时间。 |

时间字段直接放在 `x_shadowsocksx_ng` 中，要求 `schema_version: 1`；该对象可以只包含版本和时间字段，无需提供分组树。根层的 `expires_at`、`traffic_reset_at` 不再读取，也不会作为兼容来源。命名空间缺失、不是对象，或版本缺失、不支持时，视为未提供时间资料。标准流量字段仍放在根层。

日期字段缺失或为 `null` 表示未提供。客户端逐项解析这些资料；某一项格式错误只会忽略该项，不会丢弃有效服务器、分组或其他有效资料。客户端从 JSON 正文读取资料，不解析 HTTP `Subscription-Userinfo` 等响应头。

## 私有扩展命名空间 `x_shadowsocksx_ng`

在根对象中增加私有扩展命名空间。以下示例同时提供时间资料和嵌套分组树。`servers` 仍须包含全部服务器；分组树只表达分组名称、层级、顺序和服务器引用。时间、分组树与 `auto_update` 独立解析：版本受支持时，一个功能内容错误不影响其他有效功能。

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
  "bytes_used": 1073741824,
  "bytes_remaining": 9663676416,
  "x_shadowsocksx_ng": {
    "schema_version": 1,
    "expires_at": "2027-01-01T00:00:00Z",
    "traffic_reset_at": "2026-11-01T00:00:00Z",
    "root_group_id": "f6ad0a41-2a1d-4db8-9da0-b6f4f3dc889d",
    "groups": [
      {
        "id": "f6ad0a41-2a1d-4db8-9da0-b6f4f3dc889d",
        "name": "我的订阅",
        "children": [
          { "type": "group", "id": "a1e2b11c-2f53-4e39-bc36-95af6dbb5f1c" },
          { "type": "server", "id": "3c5e2af7-9f2c-4f42-bd1c-9e143d5f2d11" }
        ]
      },
      {
        "id": "a1e2b11c-2f53-4e39-bc36-95af6dbb5f1c",
        "name": "日本",
        "children": [
          { "type": "server", "id": "b9f08d65-8be7-4b09-bf94-4f2bb53e4199" }
        ]
      }
    ]
  }
}
```

| 字段 | 含义和约束 |
| --- | --- |
| `x_shadowsocksx_ng` | ShadowsocksX-NG 私有扩展对象。该字段名不是 SIP-008 官方标准字段。 |
| `schema_version` | 当前支持的扩展版本必须是整数 `1`。 |
| `root_group_id` | 非空字符串，必须对应 `groups` 中根分组的 `id`。 |
| `groups` | 分组对象数组。每个 `id` 必须非空且唯一；建议使用不随刷新变化的 UUID。分组 ID 不得与服务器 ID 冲突。 |
| `groups[].name` | 分组显示名称。建议始终提供；缺省时客户端显示空名称。 |
| `groups[].children` | 有序数组，数组顺序就是客户端显示顺序。每项必须是 `{ "type": "group", "id": "分组 ID" }` 或 `{ "type": "server", "id": "服务器 UUID" }`。 |

供应方应确保扩展构成从 `root_group_id` 出发的单父、无环树：每个分组最多有一个父分组，所有分组和服务器引用都能解析到相应对象。每个服务器最多引用一次；请将每个预期展示的分组放在根分组可到达的树中。分组与服务器 ID 都是稳定身份，不要把名称、数组下标或可变配置内容当作 ID。

客户端的扩展处理行为如下：

- 扩展版本缺失或不支持、根分组不存在、ID 冲突、引用无效、子项类型未知、出现环或分组被多个父分组引用时，分组树会被忽略，客户端改用标准 `servers` 扁平列表；有效服务器不会因此丢失。
- 未被有效树引用但存在于 `servers` 的服务器仍会显示在根分组末尾，顺序沿用其在 `servers` 数组中的顺序。因此扩展失效或不完整时，服务器仍可能显示，但分组关系不会保留。
- 树中不可从根到达的分组不会显示。请勿依赖客户端对不可达分组或重复服务器引用的处理；供应方应输出没有孤立分组、没有重复服务器引用的有效树。
- 缺少服务器 `id` 的记录无法被树引用；为保证分组准确，请给所有服务器提供稳定 ID。

## 提供方发布前检查

- 使用 HTTPS，返回 HTTP `200` 和 `Content-Type: application/json; charset=utf-8`。
- 提供合法 JSON，根级 `version` 为 `1`，`servers` 包含完整服务器记录。
- 为每台服务器提供唯一且稳定的 UUID；服务器 ID 在 `servers` 和分组引用中逐字一致。
- 若使用扩展，`schema_version` 为 `1`；若提供分组树，根分组须存在，所有引用有效，树有序、单父、无环。
- 流量字段使用 SIP-008 标准字段；到期与重置日期放在 `x_shadowsocksx_ng` 下，使用本文规定的 RFC 3339 字符串。
- 以不支持 `x_shadowsocksx_ng` 的普通 SIP-008 客户端验证时，扁平 `servers` 列表仍包含全部服务器。

订阅字段的应用内呈现与刷新行为见[配置文档中的“订阅资料”](configuration.zh.md#订阅资料)。

成功刷新会替换订阅资料，缺失或无效的时间字段清除对应旧值；获取、文档校验或保存失败则保留原资料。本地已保存的时间保留到下次成功刷新，无需迁移本地存储。配置组导出只携带服务器和分组，不携带订阅时间、流量或供应商更新策略；文件导入创建独立手动子树，不保留订阅资料。
