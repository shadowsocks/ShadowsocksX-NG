# Per-variant ACL files behind a stable active link

**Status**: accepted

**Partially superseded (2026-10-19)**: [ADR-0038](0038-separate-agent-supervision-and-sslocal-input.md) replaces mutable fixed variant names and GUI link switching with immutable generation files, atomic supervision publication and Agent-owned links. Variant reuse, the stable ACL entry and restart-on-ACL-change remain.

(2026-09: the holistic preferences reset referenced below has since been removed from the product.)

**Supersedes in part**: ADR-0009 and ADR-0010's "ACL path, content, digest, and summary are runtime identity" — content is no longer carried in the contract, and the ACL path is a stable link that does not change across mode switches. The restart-on-change rule itself stands.

## Context

sslocal's routing policy is one of four ACL shapes — `direct`, `global`, `rule-proxy-default`, `rule-direct-default` — but all four were written into a single `sslocal-active.acl`, overwritten on every proxy mode switch and on every deploy even when the ACL body had not changed. The contract JSON also embedded the full ACL body (`x_shadowsocksx_ng_acl.content`), so a rule-mode switch paid roughly the same large write twice. Upstream sslocal is gaining signal-triggered ACL reload; mode switches should be cheap now and restart-free later.

## Decision

- Keep one ACL file per shape: `acl-direct.ini`, `acl-global.ini`, `acl-rule-proxy-default.ini`, `acl-rule-direct-default.ini`. The `.ini` extension names the actual format for debugging; content remains the sslocal ACL section syntax.
- Point sslocal at a stable symlink, `acl-active.ini`, atomically re-pointed to the variant in force. The contract's `acl` field is that link path and does not change across mode switches.
- The contract carries only the ACL path, summary, and sha256 — never the ACL body. The agent never reads ACL bytes; it checks only that the link resolves inside the runtime directory.
- The GUI materializes a variant file only for the ACL actually being deployed: mode and rule-default-action switches re-point the link, and a rule change rewrites only the active variant. Unchanged content is skipped via a small digest manifest (sha256 + size); a manifest miss falls back to hashing the file once.
- ACL summary or digest change still restarts sslocal in full, as in ADR-0009 and ADR-0010. The agent switch defaults to off and is not resettable via preferences reset. No migration is provided; the product is unreleased.

## Considered Options

- Rewrite a single `sslocal-active.acl` on every switch (previous behaviour): simple, but each switch paid a large redundant write.
- Point the contract at the variant file path directly: saves the write, but the ACL path is runtime identity and would change on every switch, forcing a restart and blocking a future signal-only reload.
- Content-addressed filenames (`acl-<sha256>.ini`): deduplicates naturally, but needs orphan garbage collection.

## Consequences

- When upstream sslocal supports ACL reload by signal, a mode switch becomes a link re-point plus a signal — no restart. Until then, digest changes restart sslocal exactly as before.
- Integrity relies on the GUI's write order (variant file, then link, then contract) and the digest manifest; agent-side content verification is deliberately absent, consistent with the credential exposure boundary.
- Stale `sslocal-active.acl` files from earlier builds are removed as ordinary runtime cleanup, not migrated.
