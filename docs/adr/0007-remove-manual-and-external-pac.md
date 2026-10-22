# Remove manual proxy mode, external PAC, and local PAC

**Status**: accepted; mode-set scope superseded by ADR-0009

Remove `ProxyMode.manual`, `ProxyMode.externalPAC`, and `ProxyMode.pac`, including the external PAC URL setting, local PAC HTTP service and port, PAC user-rule editing, GFW List URL setting, PAC URL system-proxy projection, PAC health probing, and related UI, logs, diagnostics, and presentation surfaces. The product exposes rule / global / direct modes only, all projected as a local SOCKS system-proxy target.

Retained: manual catalog groups and servers, subscriptions, Legacy server-record import, independent local SOCKS and HTTP inbounds, and the built-in rule snapshots (geolocation-cn, china-ipv4, gfwlist). The affected NG2 version has not shipped, so no persisted-settings migration or upgrade transition is required.

ADR-0009 added direct ACL mode and ADR-0010 added global ACL mode while keeping these removals in force. This ADR's title and body now record the full PAC removal completed by issue #67.
