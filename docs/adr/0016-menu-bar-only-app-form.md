# Menu-bar-only app form; workspace window as a scene

The GUI is a menu-bar-only app at all times: `LSUIElement` stays in effect and the app never switches its activation policy at runtime. The main workspace window is a SwiftUI `Window` scene presented automatically at every launch (`defaultLaunchBehavior(.presented)`); the status menu's "open main window" item reopens it after it is closed. Closing the window never terminates the GUI process — the status menu (and the launchd-hosted proxy agent with it) stays available.

## Status

Accepted (2026-09-28). Superseded by ADR-0017 (2026-09-29), which replaces the constant menu-bar-only form with the adaptive app form (window-following activation policy plus an opt-out silent launch); the scene model, launch presentation, and status-menu reopening below carry over unchanged. Supersedes the earlier hybrid form (2026-09-24): `LSUIElement` plus runtime accessory⇄regular activation-policy switching, launch-time auto-presentation implemented through an AppKit-owned `NSWindow`, and the window-opening intents built around it.

## Considered options

- Keep the hybrid form (activation-policy switching plus AppKit window ownership): rejected because the AppKit window adapter existed only to serve the policy dance and the launch intents; the plain scene model provides both launch presentation and reopening without it.
- Menu-bar-only with no launch presentation (window opens only from the status menu): considered as an intermediate step on 2026-09-28 and reversed the same day — scene-based launch presentation was verified to work under `LSUIElement` (`defaultLaunchBehavior(.presented)`), so the launch-presentation behavior returns without bringing the AppKit adapter back.
- Keep an AppKit-direct window adapter solely to reuse a retained window across close/open: rejected; the scene window survives close by being re-shown with its content state intact, so the adapter's remaining value was the activation-policy switching this decision removes.

## Consequences

- The app never gains a Dock icon or app-switcher presence, including while the workspace window is open; launch presents the window without a Dock icon appearing.
- Reopening from the status menu activates the app before `openWindow`, so the window lands above the frontmost app.
- Keyboard shortcuts that rely on owning the menu bar (for example ⌘W or Edit-menu shortcuts) are unavailable while the workspace window is frontmost; the close button and mouse interaction are unaffected. If this proves unacceptable, the fix is a product decision to re-introduce a foreground form, not a partial AppKit adapter.
- The launch intent, reopen intent, presentation intents, and the `WorkspaceWindowOpening` seam are removed; `WorkspaceRoute` is navigation state only, and the scene id is defined once there.
- Window title follows the workspace destination via `navigationTitle` instead of an AppKit title binding.
