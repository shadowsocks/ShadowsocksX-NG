# Treat 2.0 as an independent application, not a Legacy upgrade

2.0 ships under its own bundle identity (`com.qiuyuzhou.ShadowsocksX-NG2`), making it and the frozen Legacy app two independently installed applications that can run side by side. We therefore drop the planned smooth transition: the Legacy handoff flow (retiring Legacy launchd jobs, cleaning Legacy-owned system proxy values, gating on Legacy port release, quitting the old app) is removed entirely, and a Legacy import brings over only server configurations — no mode, target, login-item, or other preferences. 2.0's factory-default local endpoint ports (SOCKS 11086 / HTTP 11087 / PAC 11089) differ from Legacy's (1086 / 1087 / 1089) so both apps' defaults can listen concurrently.

## Status

Accepted; the system-proxy ownership and conflict clauses are superseded by ADR-0019.

## Considered options

- Keep the handoff flow delivered in #37 (commit 8d1cdf2): rejected because it couples 2.0 to Legacy's runtime specifics (launchd labels, proxy signature fingerprints, port takeover) for a one-time transition, while the new bundle id already makes coexistence the primary state the product must support.
- Reuse Legacy's default ports and take them over on conflict: rejected because concurrent operation — the state the bundle id split creates — would then require a conflict on every launch.
- Migrate more Legacy preferences along with server records: rejected because 2.0's preference semantics differ (e.g. mode availability); partial translation would import stale meanings.

## Consequences

- Removes the #37 deliverable and voids decision D12 of spec #21; the live-fire research doc `docs/research/legacy-handoff-bootout-live-fire.md` is retained as history.
- This ADR originally kept 2.0 from cleaning Legacy launchd residues or system proxy values and relied on ownership-conflict reporting; ADR-0019 supersedes only the system-proxy part. The decision not to clean Legacy launchd residues remains.
- No releases exist yet, so the port-default change burdens only development machines; their already-persisted port settings remain in force unchanged.
