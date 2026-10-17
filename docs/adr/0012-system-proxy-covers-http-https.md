# Write HTTP and HTTPS system proxies alongside SOCKS

**Status**: accepted; ownership snapshot and restore clauses superseded by ADR-0019.

Enabling the system proxy switch writes the macOS HTTP and HTTPS proxy entries in addition to the SOCKS entry (ADR-0007 had disabled the HTTP/HTTPS families and projected a SOCKS target only). All three families point at 2.0's own local inbounds: SOCKS at the SOCKS5 listener, and HTTP and HTTPS at the always-on local HTTP inbound — shadowsocks-rust serves HTTP CONNECT directly, so no Privoxy-style bridge returns. HTTPS and HTTP share one endpoint because both are served by the same CONNECT-capable inbound. Exceptions and PAC/auto-discovery suppression remain; the ownership snapshot/restore protocol retained here was superseded by ADR-0019.

The launch health gate already probes every configured inbound, so the HTTP endpoint must be reachable before any system proxy write happens. A runtime document without a usable HTTP inbound port is rejected at the runtime-document contract (`isWellFormed`) instead of pointing the system at an invalid port; the mode projection itself is total over any document. At the time of this decision NG2 had not shipped, so no migration was planned; ADR-0019 later replaced pre-app snapshot restoration with endpoint-matched cleanup.
