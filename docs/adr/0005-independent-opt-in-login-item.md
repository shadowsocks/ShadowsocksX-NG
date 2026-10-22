# Independent opt-in login item

The GUI's login-item registration is its own preference domain, separate from proxy preferences. It is off until the user explicitly enables it: no registration happens at launch. The system's login-item registration status (`SMAppService.mainApp.status`) is the only source of truth — there is no UserDefaults mirror — and a pending-approval registration counts as enabled because both states come from that system query. Resetting preferences never touches the login item.

## Status

Accepted. (2026-09: the holistic preferences reset referenced below has since been removed from the product; the statements about it describe a capability that no longer exists.)

## Considered options

- Keep the persisted-intent mirror (`launchAtLogin.enabled`, default on) and reconcile at launch: rejected because the mirror can disagree with the system after the user edits the login item in System Settings, producing a toggle that lies about the actual state.
- Drop the mirror but keep default-on via a one-time launch registration: rejected because opting the user's machine into a background login item without an explicit action is not 2.0's default posture; the status-menu app is deliberately explicit.

## Consequences

- `LaunchAtLoginController` reads `isEnabled` from the system status only; enabling and disabling issue the corresponding system call and re-read the status.
- The toggle reflects external changes only after the controller re-reads the status (on init, on toggle, and when approval completes); no continuous observation is added.
- Resetting preferences in the settings window no longer calls into the login-item domain; its confirmation message already names only ports, listen scope, and PAC settings.
