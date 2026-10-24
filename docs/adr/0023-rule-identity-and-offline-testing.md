# Rule identity across sources and independent offline testing

**Status**: accepted and implemented. [ADR-0039](0039-rule-values-and-independent-storage-models.md) consolidates the rule value representation while preserving the identity and disablement semantics below.

[ADR-0051](0051-explicit-rule-preset-modeling.md) supersedes the preset-independent disablement and complete-source offline-test scope as an accepted, not-yet-implemented design. Rule identity and within-preset cross-source disablement remain unchanged.

Equivalent entries from multiple rule sources share a normalized match-and-action identity. Disablement applies to that identity across sources and persists even when no source currently contains it; deleting or editing a custom entry does not implicitly enable the old identity. Fixed local bypass rules remain immutable. This avoids duplicate sources silently defeating disablement and preserves the user's exclusion intent through source updates.

Offline testing evaluates all enabled rule sources and the fixed local policy, returning proxy, direct, or no matching rule. It reads no proxy mode, default action, or runtime state, performs no DNS resolution, and is unaffected by browsing filters. This deliberately explains the complete rule collection rather than predicting current traffic: runtime source selection remains a separate policy and can use a different subset. Domain inputs explicitly leave DNS-dependent IP rules untested.
