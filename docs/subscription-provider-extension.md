# SIP-008 Subscription Extensions: Provider Guide

This guide describes the SIP-008 fields and private extensions currently supported by ShadowsocksX-NG. It is intended for subscription providers generating compatible responses. It reflects the current implementation.

[简体中文](subscription-provider-extension.zh-CN.md)

`x_shadowsocksx_ng`, `expires_at`, and `traffic_reset_at` are private extensions recognized by ShadowsocksX-NG; they are not SIP-008 standard fields. Ordinary SIP-008 clients may not recognize them, and clients without extension support should still read the servers from the standard `servers` array. SIP-008 allows custom fields but does not guarantee that all clients support them. See the [SIP-008 Online Configuration Delivery specification](https://shadowsocks.org/doc/sip008.html).

## Response delivery

The subscription endpoint must meet these requirements:

- Use HTTPS. The client validates the system trust chain, does not accept plain HTTP, and does not relax certificate or TLS validation. HTTPS-to-HTTPS redirects are allowed; redirects to non-HTTPS are rejected.
- Return HTTP status `200` for a successful response.
- Send `Content-Type: application/json; charset=utf-8`. The client ignores case and whitespace, but the service should send this exact form. A missing header or a different media type or character set is rejected.
- Return one valid JSON object, not JSON5, Base64, or a list of `ss://` links.

SIP-008 subscription URLs often contain access tokens. Use unpredictable tokens, and avoid recording complete subscription URLs in access logs, error tracking, or analytics systems. The subscription body contains server passwords. HTTPS protects the response in transit; the extension fields do not encrypt the body.

## SIP-008 v1 base document

The root object must contain `version: 1` and a `servers` array. An empty array is valid. SIP-008 requires each server entry to include `id`, `remarks`, `server`, `server_port`, `password`, and `method`; include `plugin` and `plugin_opts` when using a plugin. Each entry must remain a complete Shadowsocks server record. Do not put the only copy of a server configuration in the grouping extension.

| Field | Provider requirement and recommendation | Client behavior |
| --- | --- | --- |
| `version` | Must be the integer `1`. | A missing or different version rejects the entire document. |
| `servers` | Must be an array. Each entry uses the SIP-008 server fields listed below. | A missing value or a non-array rejects the entire document. An empty array is valid. |
| `servers[].id` | Required by SIP-008. Give each server a unique, canonical UUID and preserve it across refreshes for the same logical server. The grouping extension uses this field to reference servers. | The current parser tolerates a missing `id`, but any supplied value must be a valid UUID. Duplicate IDs reject the entire document. Entries without an ID cannot be referenced by the extension tree and follow the flat compatibility path. |
| `servers[].remarks` | Required by SIP-008. Provide a string to use as the server's display name. | The current parser tolerates omission; the name is empty when omitted. |
| `servers[].server` | Must be a non-empty string. | A missing or empty value rejects the entire document. |
| `servers[].server_port` | Must be an integer from `1` through `65535`. | A missing, non-integer, or out-of-range value rejects the entire document. |
| `servers[].password` | Must be a non-empty string. | A missing or empty value rejects the entire document. |
| `servers[].method` | Must be a non-empty string. Provide a Shadowsocks cipher supported by the client. | A missing or empty value rejects the entire document. The proxy runtime determines whether the method is available. |
| `servers[].plugin`, `servers[].plugin_opts` | Omit or leave both empty when no plugin is used. When using a plugin, provide its name and corresponding options as specified by SIP-008. | The client passes the values into the server configuration; subscription parsing does not validate plugin option semantics. |

A server ID represents logical identity, not its array position. Preserve the ID when renaming a server, changing its address or port, or updating its credentials if it remains the same logical server. Assign a new ID to a new logical server. Use the canonical hyphenated UUID form, and keep the exact same string in the server entry and extension references.

## Root-level subscription information

The following traffic fields are defined by SIP-008. Providers should follow SIP-008's rules for these fields. The client displays only values that match the formats below.

| Field | Provider format | Meaning |
| --- | --- | --- |
| `bytes_used` | A non-negative JSON integer from `0` through `18446744073709551615`. | Number of bytes used by the user. Do not send a string, negative number, decimal, or exponent form. |
| `bytes_remaining` | A non-negative JSON integer in the same range. Omit it when there is no data limit; include `bytes_used` as well when a limit is enforced. | Number of bytes remaining. Do not use a private field to repeat the same traffic meaning. |
| `expires_at` | An RFC 3339 date-time string, such as `2027-01-01T00:00:00Z` or `2027-01-01T08:00:00+08:00`. | A ShadowsocksX-NG private field for the service expiration time. |
| `traffic_reset_at` | An RFC 3339 date-time string. | A ShadowsocksX-NG private field for the traffic reset time. |

An omitted date field or `null` means no value is provided. The client parses these fields independently. An invalid value is ignored without discarding valid servers, groups, or other valid information. The client reads this information from the JSON body; it does not parse response headers such as `Subscription-Userinfo`.

## Nested-group extension: `x_shadowsocksx_ng`

To provide nested groups to ShadowsocksX-NG, add the following private extension to the root object. Keep every server in `servers`; the extension carries only group names, hierarchy, order, and server references.

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
  "expires_at": "2027-01-01T00:00:00Z",
  "traffic_reset_at": "2026-11-01T00:00:00Z",
  "x_shadowsocksx_ng": {
    "schema_version": 1,
    "root_group_id": "f6ad0a41-2a1d-4db8-9da0-b6f4f3dc889d",
    "groups": [
      {
        "id": "f6ad0a41-2a1d-4db8-9da0-b6f4f3dc889d",
        "name": "My subscription",
        "children": [
          { "type": "group", "id": "a1e2b11c-2f53-4e39-bc36-95af6dbb5f1c" },
          { "type": "server", "id": "3c5e2af7-9f2c-4f42-bd1c-9e143d5f2d11" }
        ]
      },
      {
        "id": "a1e2b11c-2f53-4e39-bc36-95af6dbb5f1c",
        "name": "Japan",
        "children": [
          { "type": "server", "id": "b9f08d65-8be7-4b09-bf94-4f2bb53e4199" }
        ]
      }
    ]
  }
}
```

| Field | Meaning and constraints |
| --- | --- |
| `x_shadowsocksx_ng` | ShadowsocksX-NG private extension object. This field name is not an official SIP-008 field. |
| `schema_version` | The currently supported extension version must be the integer `1`. |
| `root_group_id` | A non-empty string that must match the `id` of the root group in `groups`. |
| `groups` | An array of group objects. Each `id` must be non-empty and unique; a UUID that remains stable across refreshes is recommended. A group ID must not conflict with a server ID. |
| `groups[].name` | Group display name. Providing it is recommended; the client displays an empty name if it is omitted. |
| `groups[].children` | An ordered array. Its order is the display order in the client. Each entry must be `{ "type": "group", "id": "group ID" }` or `{ "type": "server", "id": "server UUID" }`. |

The provider should make the extension a single-parent, acyclic tree rooted at `root_group_id`: each group has at most one parent, and every group and server reference resolves to an object. Reference each server at most once, and place every group intended for display in the tree reachable from the root. Group and server IDs are stable identities; do not use names, array positions, or mutable configuration values as IDs.

The client handles the extension as follows:

- If the extension version is missing or unsupported, the root group is missing, IDs conflict, a reference is invalid, a child type is unknown, a cycle exists, or a group has multiple parents, the client ignores the entire extension and uses the flat standard `servers` list. Valid servers are not lost because of an invalid extension.
- A server in `servers` that is not referenced by a valid tree is still shown at the end of the root group, in the order it appears in the `servers` array. If the extension is invalid or incomplete, servers may still appear, but their grouping is not preserved.
- Groups unreachable from the root are not shown. Do not rely on client behavior for unreachable groups or duplicate server references; providers should produce a valid tree without orphan groups or repeated server references.
- A record without a server `id` cannot be referenced by the tree. Provide a stable ID for every server to preserve grouping.

## Provider release checklist

- Use HTTPS and return HTTP `200` with `Content-Type: application/json; charset=utf-8`.
- Return valid JSON with root-level `version: 1` and complete server records in `servers`.
- Give every server a unique, stable UUID; use the exact same server ID in `servers` and group references.
- If using the extension, set `schema_version` to `1`, include the root group, resolve every reference, and keep the tree ordered, single-parent, and acyclic.
- Use the SIP-008 standard fields for traffic information; use RFC 3339 strings for expiration and reset dates.
- Verify that a standard SIP-008 client that does not support `x_shadowsocksx_ng` still receives all servers in the flat `servers` list.

For details about how the application presents subscription fields and handles refreshes, see [“Subscription information” in the configuration guide](configuration.md#订阅资料).
