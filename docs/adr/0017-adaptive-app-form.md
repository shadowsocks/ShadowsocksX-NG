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

## 2026-10-22 补充：启动激活重试

键盘启动器（Raycast、Spotlight 回车启动）没有关联的点击事件，启动瞬间发出的 activate 请求是否被系统的焦点抢占保护忽略，随当时前台应用而变——实测窗口可见、应用却经常进不了前台（鼠标双击启动因关联点击获得激活许可，不受影响；单次补 `makeKeyAndOrderFront` 亦不足以稳定解决）。为此协调器在窗口首次参与收敛的两条路径（启动呈现时的锚点 attach、不经 key 事件的首次可见化）上采取两层措施：其一，与 `.regular` 策略同拍调用 `NSApp.activate(ignoringOtherApps:)` 并对该窗口 `makeKeyAndOrderFront`；其二，进程内一次性的激活重试——默认每 0.2 秒检查 `NSApp.isActive`，未激活则重试 activate 并置前，应用激活、次数用尽（默认 5 次，约 1 秒窗口）或窗口关闭即止。双击启动首拍已激活，第一次检查即短路退出，不产生额外激活请求。

激活查询与请求经 applier 协议注入（生产为 NSApp 落点），延迟调度经初始化注入（生产为 Task+sleep），单测以收集回调的手动驱动获得确定性；`didBecomeKey` 路径（已是 key）不参与重试，重复可见化不反复置前。

实测重试后结果仍随前台应用分化（Xcode、Safari 等让位后激活成功；Finder、Chrome 持续不让位，重试全程被拒）——macOS 14 起 activate 为协作式激活，让位与否由前台应用决定。为此每拍重试在 activate 之外追加 `orderFrontRegardless`：激活持续被拒时也把主窗口抬到可见层（无键盘焦点，用户点击即完成激活）。每拍同时发射 `launchActivationRetry` 事件（拍数、激活状态、前台应用 bundle id、窗口是否在当前空间）进应用内日志查看器与统一日志（新 category `window`；前台应用属用户环境事实，不进共享诊断报告），用于定位残余失败场景。

诊断事件的首轮实测推翻了 isActive 单信号判据：失败场景 #1 即 active=true、policy=regular、frontmost=本应用，重试当即短路——与成功场景日志完全一致，而视觉上 Dock 图标缺失、窗口在后。即 isActive 可能呈现“激活假象”，真相要看菜单栏归属。收敛判据改为双信号：`isAppActive && menuBarOwningApplication == 本应用`；不齐则继续行动（首拍即重置窗口置前，弹跳序列补注册），诊断事件相应记录 menubar 归属。

GUI 日志的时序定位到启动路径的真正缺陷：重试链从未在启动时启动——首条 retry 事件距启动 8 秒（用户打开诊断窗口才由其锚点触发）；此前轮次观察到的事件均可能是诊断窗口触发的，工作区窗口在启动期一次参与事件都没发出，或链启动后首拍窗口尚未可见、被 isVisible 守卫静默终结且一次性标志已耗尽无法重启。据此三改：其一，链改为可 re-arm——未真正收敛（双信号齐备）前由任何参与/可见化事件重新拉起，收敛后永久闩死，防止会话中抢焦点；其二，锚点附着时尚未可见的窗口安排一次 0.5 秒兜底重扫，覆盖“可见化通知早于附着被错过”的次序（静默启动的窗口届时仍不可见，自然不触发）；其三，锚点附着本身发诊断事件（当时的可见/key 状态）、retry 事件补 visible 位，启动期次序从此可观测。

再实测锁定真正根因：失败场景中 Dock 图标从未出现，进入调度中心才显示——启动早期的 `setActivationPolicy(.regular)` 未注册到 WindowServer/Dock（进程本地已 regular、系统侧仍视作 accessory），activate 因此全程被拒，此前观察到的“前台应用差异”只是该注册竞态的不同结果。重试序列据此两级设计：首拍仍走普通 activate（重开等点击上下文足以生效，避免无谓的 Dock 图标闪烁）；第二拍起走强制弹跳序列。同拍 accessory→regular 弹跳实测会被系统合并吞掉，故拆成有真实间隔的三跳（降 accessory → 沉淀 0.1s → 回 regular 迫使重新注册 → 沉淀 0.15s → 激活置前），末跳续排主链保持单线调度。窗口先于 attach/可见化成为 key 的呈现次序（didBecomeKey 首参路径）同样启动重试，否则失败场景弹跳永不执行；诊断事件补充进程本地策略位（本地 regular 而 Dock 图标缺失即系统侧注册滞后的直接证据）。行动拍用尽后追加一拍只检查拍记录终态。
