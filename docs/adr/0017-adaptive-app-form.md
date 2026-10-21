# Adaptive app form: window-following activation policy with an opt-out silent launch

The GUI returns to runtime activation-policy switching, this time driven entirely by the workspace window's own NSWindow lifecycle: while the workspace window is open the app presents as a regular app (Dock icon, app switcher, default menu bar); when it closes the app returns to the menu-bar accessory baseline. `LSUIElement` stays in the Info.plist so launches never flash a Dock icon and the unit-test host stays clean; the policy is applied from `didBecomeKey` (→ regular) and `willClose` (→ accessory) notifications of the window captured by a zero-size anchor view embedded in the scene content, so the target window is matched by object identity and sheets or auxiliary windows can never drive the switch. `NSApp.setActivationPolicy` is the only AppKit surface. A new inline-toggled **silent launch** preference (off by default, persisted in the app's standard UserDefaults domain since the 2026-09-29 amendment; originally its own file) suppresses launch presentation so launches start in the menu-bar baseline; it takes effect on the next launch.

## Status

Accepted (2026-09-29). Supersedes ADR-0016's constant menu-bar-only form. The scene model, launch presentation, and status-menu reopening from 0016 carry over unchanged; only the "never a Dock icon" rule is replaced. The 2026-09-24 hybrid's AppKit window adapter stays gone — no window ownership, no opening-intent adapter, no delegate.

(2026-09-29 amendment: silent launch persistence has moved from its own JSON file to the app's standard UserDefaults domain (key `silentLaunch`), the platform's canonical KV store for GUI-scalar preferences. The separation rationale stands unchanged — it stays out of settings.json, whose record the proxy controller whole-writes from its in-memory snapshot, and the runtime controller chain still never consumes it. The file-form consequence "a persistence failure keeps the toggle at its previous value and names the reason" is dropped: `UserDefaults.set` reports no failure, so persistence for this presentation-only preference is best-effort. The legacy file never shipped in any release; a one-shot migration preserves its value and deletes it.)

## Considered options

- Drive the switch from the window scene's `scenePhase`: attempted first and rejected after real-machine testing — on macOS `scenePhase` follows the application, not the window; closing the window (close button or ⌘W alike) fires no phase event, so the Dock icon never returned to accessory.
- Keep the constant accessory form (ADR-0016): rejected — the user wants a Dock icon exactly while the workspace window is open, and the window is presented at every launch by default, so the constant-accessory rule no longer matches the product.
- Distinguish login-item launches from manual launches and present the window only for the latter: rejected — `SMAppService.mainApp` launches are indistinguishable in-process, so the distinction would need unreliable launch-reason machinery. The silent-launch preference replaces it as an explicit user choice that applies to every launch.
- Persist silent launch as a field of settings.json: rejected — the proxy controller persists settings as whole in-memory snapshots, so any parallel writer's field would be clobbered by the controller's next write; a separate one-purpose store follows the `ActivationStateFileStore` precedent and keeps the runtime controller chain from consuming a GUI presentation preference.

## Consequences

- While the workspace window is open the app gains a Dock icon, app-switcher and Cmd-Tab presence, and the default SwiftUI menu bar (⌘W/⌘Q come with it; no custom commands are added yet).
- With silent launch off, every launch — including login-item launches — presents the window and therefore the Dock icon until the user closes it; with silent launch on, launches start silent and proxy runtime restoration still happens at every launch.
- ⌘H hiding orders the window out without posting `willClose`, so hiding is never mistaken for closing: the current form is kept and the Dock icon stays available to unhide.
- With silent launch on, the scene's pre-built but unpresented window triggers no policy change (not visible, never key): launches start and stay accessory until the user opens the window.
- The preference is inline-toggled and persisted immediately; it affects only the next launch. (2026-09-29: with the UserDefaults migration the failure clause is historical — `UserDefaults.set` reports no failure, so persistence is best-effort and the toggle simply reflects the attempted value.)

## 2026-10-02 amendment: independent rule-report window

The user-confirmed rule-browser simplification adds a single independent conversion-report window. It may remain open after the workspace closes. Activation policy therefore follows all explicitly anchored application windows through one shared coordinator: any open workspace or report window keeps the regular form, and closing the last one returns to accessory. Unanchored sheets and system panels still do not participate; hiding remains distinct from closing. Report launch presentation is suppressed and restoration is disabled, since its contents are an explicitly opened, session-only snapshot.

## 2026-10-06 补充：独立诊断窗口

诊断从工作区移至唯一独立窗口，入口位于菜单栏“打开主窗口…”之后。诊断窗口共享既有窗口激活协调器，可在工作区关闭后独立存续；最后一个受管窗口关闭才回到 accessory。启动呈现被抑制，会话恢复被禁用，重复打开恢复并前置已有窗口。

诊断轮询按宿主 NSWindow 的真实开关状态运行：打开立即采样，失焦、遮挡、隐藏或最小化时继续每秒刷新，关闭后停止；不依赖 SwiftUI scenePhase 或视图销毁。日志来源选择仅在进程内保留，关闭清理导出成功提示与错误弹窗。诊断功能和 ADR-0006 的原始日志与脱敏报告边界不变。

## 2026-10-21 补充：启动窗口前置

静默启动关闭时，`Window` scene 会自动呈现主窗口；窗口激活协调器切换应用为 `.regular` 后调用 `NSApp.activate(ignoringOtherApps:)`，确保应用与主窗口进入前台。静默启动开启时，窗口不呈现，不触发此激活，仍以 accessory 形态启动。
