# Implement global mode with a minimal ACL

**Status**: accepted; system-proxy rollback clause superseded by ADR-0019. Runtime and mode rollback remain.

**ACL reload superseded (2026-10-20)**: [ADR-0048](0048-reload-sslocal-acl-by-signal.md) replaces restart-on-ACL-change with `SIGUSR2` reload. Listener and authentication changes still require restart.

## Context

Global mode previously projected only the system SOCKS endpoint and relied on sslocal's default proxy-everything behaviour. That left local-network targets without a product-owned direct guarantee: LAN-sharing clients, IPv6 destinations whose system-proxy exceptions macOS does not reliably honour, and any request that reaches the SOCKS/HTTP inbounds still needed a defined routing policy. The ACL work (spec #59) requires global mode to mean "public targets default through Shadowsocks, local targets stay direct", using only the fixed local safety rules.

## Decision

- Global mode deploys an `sslocal` ACL with `[proxy_all]` and a `[bypass_list]` containing only the fixed local safety rules: IPv4 loopback, RFC 1918, link-local; IPv6 loopback, link-local, and ULA; `localhost`, `*.local`, and no-dot hostnames. No China list, GFWList, or custom rules enter this ACL. CGNAT is excluded.
- The same ACL is the routing policy for the local SOCKS inbound, the local HTTP inbound, and LAN-sharing clients that connect to those listeners directly. It is not a substitute for the system proxy exception list; both use the same fixed local scope, but the ACL is the verified bypass for requests that already entered `sslocal`.
- IPv6 CIDR strings in the macOS SystemConfiguration exceptions list are not a verified bypass guarantee (only exact IPv6 addresses were observed to match). The ACL's IPv6 rules are the routing guarantee; this limitation is recorded rather than papered over by the exception list.
- ACL path, content, digest, and summary are runtime identity, exactly as in ADR-0009. Switching into or out of global mode changes the ACL and therefore requires a full `sslocal` restart through the wrapper — never a bare SIGUSR1 server-list reload. On verification failure it restores the previous mode and runtime document; the former system-proxy restoration behavior is superseded by ADR-0019.
- Without a valid active target the agent still listens with an empty server list under the global ACL; local targets remain reachable, public targets have no exit. System proxy intent stays pending and converges automatically once an active target is valid and the local endpoints are healthy.

## Consequences

Global mode and direct mode share one fixed local safety policy and one ACL deployment path. Global is no longer "no ACL": it is a minimal `proxy_all` ACL. System proxy writes still require the system proxy switch, agent health, and an available exit (an active target for global). PAC mode remains unchanged until the rules-mode work replaces it.
