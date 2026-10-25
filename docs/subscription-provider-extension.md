# SIP-008 subscription extensions: provider guide

Use this guide to build SIP-008 responses compatible with ShadowsocksX-NG. It covers the supported standard fields, private extensions, and parsing rules.

[简体中文](subscription-provider-extension.zh.md)

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
| `servers[].id` | Required by SIP-008. Give each server a unique, canonical UUID and preserve it across refreshes for the same logical server. The grouping extension uses this field to reference servers. | The current parser tolerates a missing `id`, but any supplied value must be a valid UUID. Duplicate IDs reject the entire document. Entries without an ID cannot be referenced by the group tree and are handled as ungrouped servers. |
| `servers[].remarks` | Required by SIP-008. Provide a string to use as the server's display name. | The current parser tolerates omission; the name is empty when omitted. |
| `servers[].server` | Must be a non-empty string. | A missing or empty value rejects the entire document. |
| `servers[].server_port` | Must be an integer from `1` through `65535`. | A missing, non-integer, or out-of-range value rejects the entire document. |
| `servers[].password` | Must be a non-empty string. | A missing or empty value rejects the entire document. |
| `servers[].method` | Must be a non-empty string. Provide a Shadowsocks cipher supported by the client. | A missing or empty value rejects the entire document. The proxy runtime determines whether the method is available. |
| `servers[].plugin`, `servers[].plugin_opts` | Omit or leave both empty when no plugin is used. When using a plugin, provide its name and corresponding options as specified by SIP-008. | The client passes the values into the server configuration; subscription parsing does not validate plugin option semantics. |

A server ID represents logical identity, not its array position. Preserve the ID when renaming a server, changing its address or port, or updating its credentials if it remains the same logical server. Assign a new ID to a new logical server. Use the canonical hyphenated UUID form, and keep the exact same string in the server entry and extension references.

## Extension namespace and version

All ShadowsocksX-NG private extensions belong in the root-level `x_shadowsocksx_ng` object. This includes expiration and traffic reset dates, automatic update settings, and the group tree. Future project-specific fields must also use this namespace, rather than being added directly to the document root or server records.

These fields are not part of SIP-008. Clients that do not recognize them must still be able to obtain every server from the standard `servers` array. For SIP-008's provisions on custom fields, see [SIP-008 Online Configuration Delivery](https://shadowsocks.org/doc/sip008.html).

| Field | Format and meaning |
| --- | --- |
| `x_shadowsocksx_ng` | A JSON object at the document root containing ShadowsocksX-NG private extensions. |
| `x_shadowsocksx_ng.schema_version` | Required integer, currently `1`. If the version is missing or unsupported, the client does not accept new extension data from this object. |

Dates, `auto_update`, and the group tree are optional and can be used in any combination. With a supported schema version, each is parsed independently. An invalid group tree does not prevent a valid `auto_update` value from being accepted; an invalid `auto_update` value does not invalidate groups or dates. The `auto_update` section below specifies how missing and invalid values affect previously accepted data.

## Subscription information

Use the SIP-008 standard fields for traffic usage and the private extension fields for dates. Values must use the following formats.

| Field | Provider format | Meaning |
| --- | --- | --- |
| `bytes_used` | A non-negative JSON integer from `0` through `18446744073709551615`. | Number of bytes used by the user. Do not send a string, negative number, decimal, or exponent form. |
| `bytes_remaining` | A non-negative JSON integer in the same range. Omit it when there is no data limit; include `bytes_used` as well when a limit is enforced. | Number of bytes remaining. Do not duplicate this information in a private field. |
| `x_shadowsocksx_ng.expires_at` | An RFC 3339 date-time string, such as `2027-01-01T00:00:00Z` or `2027-01-01T08:00:00+08:00`. | A ShadowsocksX-NG private field for the service expiration time. |
| `x_shadowsocksx_ng.traffic_reset_at` | An RFC 3339 date-time string. | A ShadowsocksX-NG private field for the traffic reset time. |

Date fields are direct members of `x_shadowsocksx_ng` and require `schema_version: 1`; the namespace may contain only the version and dates, without a group tree. Root-level `expires_at` and `traffic_reset_at` are ignored. A missing or non-object namespace, or a missing or unsupported schema version, provides no date information. The standard traffic fields remain at the root.

An omitted date field or `null` means no value is provided. The client parses these fields independently. An invalid value is ignored without discarding valid servers, groups, or other valid information. The client reads this information from the JSON body; it does not parse response headers such as `Subscription-Userinfo`.

## Automatic updates: `auto_update`

The optional `x_shadowsocksx_ng.auto_update` object declares the provider's automatic update mode and whether users may override it. It does not require dates or a group tree.

| Field | Type | Meaning and constraints |
| --- | --- | --- |
| `auto_update.mode` | String | Required and case-sensitive. Accepts only `"off"` (disabled), `"daily"` (daily updates), or `"weekly"` (weekly updates). |
| `auto_update.allow_user_override` | Boolean | Required. When `true`, `mode` is a default that users may override. When `false`, the provider's `mode` must be used. |

Neither field has a default. For example, `mode: "off"` with `allow_user_override: true` disables automatic updates by default but allows users to enable them. With `allow_user_override: false`, it requires automatic updates to remain disabled. The protocol has no fields for custom intervals or fixed update times.

### Missing and invalid values

The entire `auto_update` object is invalid if either required field is missing, has the wrong type, or contains an unsupported `mode`. An empty object, `null`, an array, or a boolean is also invalid. The string `"true"` and the number `1` are not accepted as substitutes for the boolean `true`.

Once a response passes base-document validation and is successfully applied, the client handles `auto_update` as follows:

| Response content | Result |
| --- | --- |
| `schema_version: 1` with a complete, valid `auto_update` object | Accept the new value, replacing any previous value. |
| `schema_version: 1` with `auto_update` omitted | Clear the previous value. |
| `x_shadowsocksx_ng` omitted or set to `null` | Clear the previous value. |
| `auto_update` present but invalid, including `null` | Ignore the new value and retain the previous value. |
| A non-object, non-null namespace, or a missing, incorrectly typed, or unsupported `schema_version` | Ignore the new value and retain the previous value. |

To withdraw `auto_update`, omit the field. Sending `null` or an empty object will retain the previous value. An invalid `auto_update` value does not prevent valid servers, groups, or dates from being parsed.

## Group tree

The group tree defines names, hierarchy, display order, and server references. All fields in this section belong inside `x_shadowsocksx_ng`; server configurations stay in the root-level `servers` array.

| Field | Meaning and constraints |
| --- | --- |
| `root_group_id` | A non-empty string that must match the `id` of the root group in `groups`. |
| `groups` | An array of group objects. Each `id` must be non-empty and unique; a UUID that remains stable across refreshes is recommended. A group ID must not conflict with a server ID. |
| `groups[].name` | Group display name. Providing it is recommended; the client displays an empty name if it is omitted. |
| `groups[].children` | An ordered array. Its order is the display order in the client. Each entry must be `{ "type": "group", "id": "group ID" }` or `{ "type": "server", "id": "server UUID" }`. |

The groups must form an acyclic tree rooted at `root_group_id`: each group has at most one parent, and every group and server reference resolves to an object. Reference each server at most once, and place every group intended for display in the tree reachable from the root. Group and server IDs are stable identities; do not use names, array positions, or mutable configuration values as IDs.

Group parsing and fallback rules:

- If the extension version is missing or unsupported, the root group is missing, IDs conflict, a reference is invalid, a child type is unknown, a cycle exists, or a group has multiple parents, the client ignores the group tree and uses the flat standard `servers` list. Valid servers are not lost because of an invalid group tree.
- A server in `servers` that is not referenced by a valid tree is still shown at the end of the root group, in the order it appears in the `servers` array. If the extension is invalid or incomplete, servers may still appear, but their grouping is not preserved.
- Groups unreachable from the root are not shown. Do not rely on client behavior for unreachable groups or duplicate server references; providers should produce a valid tree without orphan groups or repeated server references.
- A record without a server `id` cannot be referenced by the tree. Provide a stable ID for every server to preserve grouping.

## Complete response example

This response includes two servers, traffic usage and dates, a daily update default that users may override, and nested groups.

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
    "auto_update": {
      "mode": "daily",
      "allow_user_override": true
    },
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

## Provider checklist

- Serve the response over HTTPS with HTTP status `200` and `Content-Type: application/json; charset=utf-8`.
- Return valid JSON with `version: 1` at the root and complete server records in `servers`.
- Assign each server a unique, stable UUID. Use exactly the same string in server records and group references.
- Set `schema_version` to `1` when using private extensions. If a group tree is included, ensure the root exists, all references resolve, and the tree is ordered, single-parent, and acyclic.
- Use the standard SIP-008 fields for traffic usage. Put expiration and reset dates inside `x_shadowsocksx_ng` as RFC 3339 strings.
- If `auto_update` is included, provide both a valid `mode` and a boolean `allow_user_override`. Check that the override setting matches your intent. To withdraw the value, omit it instead of sending `null` or an empty object.
- Check compatibility with a SIP-008 client that does not support `x_shadowsocksx_ng`: the flat `servers` array must still contain every server.
