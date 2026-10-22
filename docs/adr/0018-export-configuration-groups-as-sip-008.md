# Export configuration groups as SIP-008 snapshots

Status: Accepted (2026-09-29)

Export any manual or subscription configuration group as a SIP-008 v1 JSON file, with the selected group as the root and all descendant servers and nested groups included. The standard `servers` array contains every server configuration in depth-first sibling order; the `x_shadowsocksx_ng` v1 extension preserves the selected root, group names, nesting, and child order. This keeps a flat list available to standard consumers while allowing NG2 to retain the group tree.

Preserve provider UUIDs for subscription servers and local UUIDs for manual servers. Derive IDs for subscription servers without a provider UUID, and opaque IDs for extension groups, deterministically from node identity using UUIDv5 and the fixed namespace `0d89e9f8-8f0e-4a55-941a-77d61736eaa3`; IDs remain stable when a node is exported alone or under an ancestor. The export action is in every group row's context menu and is disabled when its subtree has no server configuration. A system save panel proposes `<group name>.json`. The export contains resolved passwords and configured plugin options without a separate warning prompt. If any server cannot be emitted completely—including unresolved credentials or `plugin_opts` without a plugin name—the entire export fails without writing a partial file. Servers that are not activation candidates remain exportable when their SIP-008 fields can be emitted.

## Considered options

- A standard flat list alone would be simpler for consumers but would discard the selected group's names and nested structure.
- Fresh IDs on every export would break server identity for clients that use `servers[].id` to retain per-server state. A persisted export-ID map would add redundant durable state. Deterministic IDs preserve continuity without another stored mapping.
- Omitting unrepresentable plugin options would silently lose imported configuration; emitting `plugin_opts` without a plugin name would violate the SIP-008 plugin-field contract. Failing the whole export makes the problem visible and preserves all-or-nothing behavior.

## Consequences

- The selected group is the export root; its ancestors and siblings are excluded. Empty groups and subtrees with no server configurations cannot be exported.
- SIP-008 consumers that ignore the private extension still receive the flat server list. SIP-008 does not guarantee every client will accept custom fields.
- The exported file contains plaintext server passwords and plugin options. The explicit export action and save panel are the user-facing controls; no additional confirmation is shown.
