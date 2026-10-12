# Use a fixed TCP+UDP mode for the local SOCKS5 endpoint

**Status**: accepted; fixed UDP applies to local listening under ADR-0034.

NG2 no longer exposes SOCKS5 UDP relay as a user preference. The local SOCKS5 endpoint always uses `tcp_and_udp`, while the HTTP endpoint remains `tcp_only`; stale `udpRelayEnabled` keys in unreleased NG2 JSON are ignored without migration or cleanup, and Legacy remains frozen. This keeps the runtime capability available without presenting a misleading system-wide UDP proxy control.
