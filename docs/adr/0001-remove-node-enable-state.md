# Remove node enable state and use activation preflight candidates

The 2.0 configuration catalog no longer stores or exposes an enable/disable state on servers or groups. Imported and subscribed records with structurally complete but unsupported encryption methods or plugins remain visible as invalid activation candidates, while malformed records are rejected at their source boundary; activation preflight filters invalid group members and requires at least one usable server. This preserves recoverable user data without treating opaque plugin options or remote connectivity as app-verifiable facts, and keeps the active target identity separate from proxy runtime health.

## Status

Accepted.

## Considered options

- Keep the old state as a hidden compatibility flag: rejected because it would preserve a second eligibility model with no user-facing meaning.
- Reject an entire group when any descendant is invalid: rejected because one broken imported or subscribed record would hide otherwise usable servers.
- Reject every unsupported method or plugin at import time: rejected because users need to see and repair recoverable configuration data.

## Consequences

- Catalog persistence migrates old `enabled` values away and writes the next document version without them.
- Group activation can succeed with a subset of descendants, but surfaces the skipped invalid records and fails when none remain.
- App validation reports only known local blockers; opaque plugin options and remote reachability remain runtime concerns.
