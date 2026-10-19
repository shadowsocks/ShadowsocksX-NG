# Built-in rule snapshots drop absorbed candidates and conversion forensics

**Status**: accepted.

The custom-rule source-metadata and schema preservation clause is superseded by [ADR-0039](0039-rule-values-and-independent-storage-models.md). Built-in snapshot decisions remain in force.

Snapshots previously shipped every converted entry: effective rules plus same-action absorbed candidates (for example geolocation-cn domains covered by the synthesized `.cn` suffix) and GFWList `@@` exceptions shadowed by a broader proxy rule, each carrying conversion forensics (`originalEntry`, `absorbedBy`, per-rule notes). Runtime analysis recomputes absorption and shadowing from matches alone and never read those forensics, so the extra payload only widened the snapshot interface and slowed browsing and offline matching.

Maintainer updates now omit absorbed and shadowed entries from the snapshot entirely. The conversion report keeps numeric totals only (`convertedCount`, `absorbedCount`, per-reason `skipped`/`rejected`); individual upstream strings go to converter stdout, not into the shipped artifact. Each rule is just an action and a match; the source identity lives once at snapshot level. We accept that disabling a broader built-in rule (such as `.cn`) no longer restores narrower built-in candidates — a rare recovery path not worth carrying thousands of extra rows on every load. Custom-rule disablement, offline testing, and ACL compilation continue to work from the shipped effective set.

The artifact contract is schema version 2 with converter version 2.0.0 and compact JSON. `rules` contains only `{action, match}`; source identity appears only in `metadata.source`. `lossReport` contains `convertedCount`, `absorbedCount`, `skipped`, and `rejected`, with no notes or individual entries. Shadowed GFWList exceptions contribute only to `absorbedCount`, without a second count under `skipped`. Unsupported syntax retains its category count. Detailed conversion evidence is printed to maintainer stdout and is not saved as a sidecar.

The loader rejects old schema/converter versions and rule counts outside the generator limits: 100–200000 for geolocation-cn and 100–50000 for china-ipv4 and gfwlist. Source validation uses snapshot metadata; custom-rule documents keep their existing source metadata and schema. Browsing and independent offline matching consume only shipped rules, while relationships among surviving built-in and saved custom rules are still computed dynamically. Disabling `.cn` also removes the omitted domains from offline explanations; disabling a GFWList blocker does not bring back its omitted `@@` exceptions.

This supersedes the preserved-candidate recovery invariant in `CONTEXT.md`. Converter consolidation was outside this change. ADR-0025 subsequently makes Python the sole upstream conversion path and removes the duplicate Swift converters.
