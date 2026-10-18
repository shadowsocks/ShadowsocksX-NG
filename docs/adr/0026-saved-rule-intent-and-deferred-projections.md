# Saved rule intent and deferred projections

**Status**: accepted (2026-10-03).

The runtime-only recovery decision below is superseded by [ADR-0037](0037-runtime-failure-preserves-latest-intent.md) (2026-10-19). That replacement is implemented; the remaining decisions continue to apply.

## Context

Enabling, disabling, adding, editing, and deleting rules previously waited for ACL compilation, sslocal restart and verification, and then complete browsing analysis. The computations already ran outside the UI actor, but the rule operation remained busy until all phases finished. A failed deployment restored the older rule document as well as the runtime, making persistence success depend on runtime health.

## Decision

- Validation and atomic persistence determine rule-operation success. Once saved, the document remains the user's intent even if analysis, deployment, or runtime recovery fails.
- Browsing immediately reflects saved entries, source memberships, enablement, counts, and version. Existing coverage explanations remain visible until their replacement is ready; there is no pending-analysis or stale-explanation UI state. Offline matching uses current saved entries and enablement and does not wait for coverage analysis.
- Browsing analysis and ACL application independently debounce nearby saves. Persistence itself is never delayed by debounce. Each consumes immutable captured facts, and late analysis cannot replace newer saved facts.
- Rule deployments are serialized. A save while a deployment is underway remains accepted and schedules application of the latest document after the in-flight operation settles. Preparation retains the existing revision, mode, target, and runtime-intent checks.
- ACL application failures after publication stop the runtime and suspend the system proxy while retaining saved intent and a persistent deployment failure (ADR-0037). They appear through proxy runtime status while the rule page continues to show successful persistence. A new runtime intent or an explicit agent-on retry can attempt application again.
- Remove user-controlled display sorting and retain deterministic first-source-occurrence order. Content versions and ACL bytes retain their own deterministic ordering. Rule ordering continues to carry no routing priority.

## Consequences

Saved rules and the active ACL can temporarily differ during preparation or after a failed publication. A confirmed failure after publication stops the service rather than replaying an older ACL. This is preferable to silently discarding the user's saved change or keeping rule controls busy through runtime verification. Existing absorption and shadowing explanations may briefly describe an earlier saved document; that small inconsistency is accepted without adding user-visible state tracking.

This replaces the prior whole-rule-document rollback contract recorded in CONTEXT.md and associated tests. ADR-0023 identity, disablement, and offline matching semantics, ADR-0024 snapshot slimming, and ADR-0011 restart-on-ACL-change remain in force. No converter or snapshot format changes are involved.
