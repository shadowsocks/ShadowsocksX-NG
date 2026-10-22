# Save settings as independent items

**Status**: accepted; port range and listener items amended by ADR-0034

Settings editing is moving gradually from one form-level commit to independently saved setting items. Saving an item persists and applies only that item's complete value, while unrelated unsaved settings remain pending; the first item is the SOCKS5 and HTTP port pair, saved together because the values are cross-validated and restricted to 1000–65535. Runtime convergence remains separate from persistence: a saved port change is not rolled back after a runtime failure, and the settings item does not need a separate runtime-error message.
