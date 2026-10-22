# Remove system-level shortcuts from NG2

NG2 no longer provides user-configurable system-level shortcuts for toggling the proxy or cycling proxy modes. We remove the `KeyboardShortcuts` integration and keep status-menu controls and window-local default action shortcuts; Legacy remains frozen, and existing stored shortcut preferences are neither migrated nor proactively cleaned up.

## Considered options

- Keep the feature or replace it with another global shortcut library: rejected because the product now has an explicit menu-driven interaction boundary and no approved replacement gesture.
- Remove only the UI while retaining the dependency and handlers: rejected because it would leave an invisible system-level behavior and dead configuration state.

## Consequences

- Proxy enablement and mode selection remain available from the status menu. Settings/window flows remain available for configuration and window-local default action shortcuts.
- The `nextMode` helper and its tests are removed because no remaining product behavior needs implicit mode cycling.
- Historical Legacy research and prior ADRs remain unchanged as historical records.
