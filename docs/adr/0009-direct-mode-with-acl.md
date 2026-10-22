# Add direct proxy mode with an ACL

**Status**: accepted; system-proxy rollback clause superseded by ADR-0019. Runtime and mode rollback remain.

## Context

The proxy mode selector needs a direct option that does not require an active Shadowsocks server. Local SOCKS and HTTP proxy clients still enter through the existing `sslocal` listeners, so direct routing must be enforced by the shared runtime rather than by a separate listener or process.

## Decision

- Add persisted `direct` as a third system proxy mode. When applied, macOS points at the existing local SOCKS endpoint. Rule and global modes remain available; manual and external PAC modes remain removed as decided in ADR-0007. Local PAC is removed entirely by issue #67.
- Direct mode deploys an `sslocal` ACL with `[bypass_all]` and an explicit bypass list for loopback, private, link-local, unique-local, localhost, `.local`, and no-dot destinations. It needs no active target and produces an empty server list when no target is selected. SOCKS and HTTP use the same ACL.
- Keep the fixed local exceptions in the SystemConfiguration bypass list as well. Do not add carrier-grade NAT ranges to the fixed list.
- Treat ACL path, content, digest, and summary as runtime identity. An ACL change restarts `sslocal`; server-only changes use the existing hot-reload path, deferred until a direct-mode child owns its configured listeners if startup is still in progress.
- The runtime receipt identifies the child PID and contract digest. For ACL deployments the wrapper publishes it only after the child owns every configured TCP listener and the endpoints answer. Before accepting direct mode, the controller requires a matching digest and live PID, and rechecks both after endpoint probes. On verification failure it restores the previous mode and runtime; the former system-proxy restoration behavior is superseded by ADR-0019.

## Consequences

Direct mode remains within the existing SOCKS and HTTP runtime. ACL state lives in a protected sidecar and is validated against the runtime contract before launch. A stale listener cannot verify a candidate: the wrapper ties the receipt to the process that owns each configured TCP listener, and the controller checks that process throughout its health probes.
