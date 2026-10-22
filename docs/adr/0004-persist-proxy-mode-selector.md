# Persist the proxy mode selector and drop enabled-modes

The proxy mode selector (status menu, the single entry point since the settings-page selector was removed) persists its choice with the settings snapshot, so a GUI restart restores the selected mode instead of reverting to PAC. A persistence failure keeps the previous mode in force and names the reason rather than switching silently. While the live mode is external PAC, saving settings resolves the mode from the new snapshot before persisting, so the mode kind and its URL commit as one logical change. The `enabledModes` set is removed from the persisted snapshot: since ADR-0002 dropped Legacy preference migration it had no writer, and 2.0 exposes no editing UI for it. The built-in modes (PAC, global, manual) are always available; the external PAC mode requires a configured valid URL.

## Status

Superseded by [ADR-0007](0007-remove-manual-and-external-pac.md). (2026-09: the holistic preferences reset referenced below has since been removed from the product; the reset and PAC wording here is historical — the factory mode was rule before that removal.)

## Considered options

- Keep mode switches as transient runtime state: rejected because the selector is the common control for how macOS traffic is routed; losing the choice on every GUI restart contradicts its persisted-snapshot slot (`preferredMode`) and surprises users.
- Persist the mode in a separate preference key: rejected because the mode already belongs to the settings snapshot (an external PAC mode resolves its URL from it); a second key would split one logical change into two stores.
- Keep `enabledModes` as read-only legacy data: rejected because a persisted set with no writer is dead state that still gates the menu for no product meaning.

## Consequences

- `setProxyMode` writes the settings snapshot before switching the live mode; on write failure it presents a service failure and leaves the mode unchanged.
- `updateSettings` re-resolves an external-PAC mode from the incoming snapshot before persisting; clearing the URL falls back to PAC and persists that fallback.
- Resetting preferences returns the mode to PAC, consistent with the factory snapshot.
- The persisted settings document no longer contains `enabledModes`; existing files simply stop reading it, and no migration is needed because no release shipped with it populated by any 2.0 path.
