import AppKit
import SwiftUI

/// All explicitly anchored application windows share one coordinator. Sheets and
/// unrelated windows do not participate. Hiding does not count as closing.
@MainActor
protocol WindowActivationPolicyApplying: AnyObject {
  func apply(_ policy: NSApplication.ActivationPolicy)

  /// 应用是否已激活（NSApp.isActive 的可注入口径）。
  var isAppActive: Bool { get }

  /// 菜单栏是否实际归属本应用（NSWorkspace.menuBarOwningApplication 的
  /// 可注入口径）。激活自检第二信号：失败场景实测 isActive 与 frontmost
  /// 均指向本应用、重试即停，但 Dock 图标缺失、窗口在后——单看 isActive
  /// 无法分辨这种系统侧注册滞后，菜单栏归属仍指此前台应用才是真相。
  var ownsMenuBar: Bool { get }

  /// 进程本地激活策略是否已为 regular 的可注入口径。注意本地值可能已
  /// regular 而系统侧注册仍滞后——Dock 图标缺失即此态，故仅作诊断事实。
  var isPolicyRegular: Bool { get }

  /// 请求激活应用（NSApp.activate 的可注入口径）。
  func activateApp()
}

/// 启动激活重试的节拍调度口。生产经 Task+sleep 延迟执行；测试实现收集
/// 回调手动驱动，获得与墙钟无关的确定性节奏。
@MainActor
protocol ActivationTickScheduling: AnyObject {
  func scheduleTick(after interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void)
}

@MainActor
private final class TaskActivationTickScheduler: ActivationTickScheduling {
  func scheduleTick(after interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void)
  {
    Task {
      try? await Task.sleep(for: .seconds(interval))
      tick()
    }
  }
}

@MainActor
final class WindowActivationPolicyCoordinator: ObservableObject {
  private let anchoredWindows = NSHashTable<NSWindow>.weakObjects()
  private var openWindows: Set<ObjectIdentifier> = []
  private let applier: any WindowActivationPolicyApplying
  private let activationRetryInterval: TimeInterval
  private let activationRetryLimit: Int
  private var activationAttemptsLeft: Int
  private let launchRescanInterval: TimeInterval
  private let tickScheduler: any ActivationTickScheduling
  /// 激活收敛或预算用尽后永久停止，避免窗口事件重启重试并抢焦点。
  private var activationFinished = false
  /// 重试链是否在调度中。链可能在窗口尚未可见时静默终结（key 先于可见的
  /// 呈现次序），未收敛前由参与事件重新拉起（re-arm）。
  private var isRetryChainActive = false

  /// `applier` 与 `tickScheduler` 注入以便 hermetic 单测；生产实现里单测
  /// host 不触碰真实 NSApp、不依赖墙钟。
  init(
    applying applier: any WindowActivationPolicyApplying,
    activationRetryInterval: TimeInterval = 0.2,
    activationRetryLimit: Int = 5,
    launchRescanInterval: TimeInterval = 0.5,
    tickScheduler: (any ActivationTickScheduling)? = nil
  ) {
    self.applier = applier
    self.activationRetryInterval = activationRetryInterval
    self.activationRetryLimit = activationRetryLimit
    self.activationAttemptsLeft = activationRetryLimit
    self.launchRescanInterval = launchRescanInterval
    self.tickScheduler = tickScheduler ?? TaskActivationTickScheduler()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification, object: nil)
    center.addObserver(
      self, selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification, object: nil)
    center.addObserver(
      self, selector: #selector(windowVisibilityChanged(_:)),
      name: NSWindow.didChangeOcclusionStateNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// 锚点视图捕获到宿主窗口时上交（幂等）。窗口已可见才立刻收敛（覆盖不走
  /// key 事件的可见路径）；尚未可见则安排一次延迟重扫兜底——可见化通知可能
  /// 早于锚点附着被错过（实测失败场景启动期无任何事件即此序）。
  func anchorDidAttach(to window: NSWindow) {
    if !anchoredWindows.contains(window) {
      anchoredWindows.add(window)
      RuntimeLog.emit(
        .windowAnchorAttached(visible: window.isVisible, key: window.isKeyWindow))
    }
    if window.isVisible {
      openWindows.insert(ObjectIdentifier(window))
      applier.apply(.regular)
      // 键盘启动器（Raycast/Spotlight 回车启动）无关联点击，启动瞬间的
      // activate 请求可能被焦点抢占保护忽略，窗口可见但不成为 key；
      // 补一次置前成 key，激活被采纳时窗口即在前台。
      window.makeKeyAndOrderFront(nil)
      startLaunchActivationRetry(for: window)
    } else {
      scheduleLaunchVisibilityRescan()
    }
  }

  /// 锚点附着后的一次性兜底重扫：附着时窗口尚未可见、其可见化通知又早于
  /// 附着被错过时，这里补上参与与激活重试。静默启动的窗口届时仍不可见，
  /// 自然不触发。
  private func scheduleLaunchVisibilityRescan() {
    tickScheduler.scheduleTick(after: launchRescanInterval) { [weak self] in
      guard let self, !self.activationFinished, !self.isRetryChainActive else { return }
      guard let window = self.anchoredWindows.allObjects.first(where: { $0.isVisible })
      else { return }
      if self.openWindows.insert(ObjectIdentifier(window)).inserted {
        self.applier.apply(.regular)
        window.makeKeyAndOrderFront(nil)
      }
      self.startLaunchActivationRetry(for: window)
    }
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard let window = trackedWindow(in: notification) else { return }
    openWindows.insert(ObjectIdentifier(window))
    applier.apply(.regular)
    // 窗口可能在 attach/可见化通知之前先成为 key（SwiftUI 呈现次序不同）：
    // 该路径同样要启动启动激活重试，否则失败场景下弹跳序列永不执行。
    startLaunchActivationRetry(for: window)
  }

  @objc private func windowWillClose(_ notification: Notification) {
    guard let window = trackedWindow(in: notification) else { return }
    // A background window can be presented without ever becoming key. Include
    // visible siblings even if their initial visibility notification was missed.
    for sibling in anchoredWindows.allObjects where sibling !== window && sibling.isVisible {
      openWindows.insert(ObjectIdentifier(sibling))
    }
    openWindows.remove(ObjectIdentifier(window))
    if openWindows.isEmpty { applier.apply(.accessory) }
  }

  @objc private func windowVisibilityChanged(_ notification: Notification) {
    guard let window = trackedWindow(in: notification), window.isVisible else { return }
    let inserted = openWindows.insert(ObjectIdentifier(window)).inserted
    if inserted {
      applier.apply(.regular)
      // 不走 key 事件的首次可见化同样补置前，缘由见 anchorDidAttach。
      window.makeKeyAndOrderFront(nil)
    }
    // 可见化无论是否首次插入都尝试拉起重试：链可能在窗口尚未可见时
    // 静默终结过（key 先行的呈现次序），未收敛前由此 re-arm。
    startLaunchActivationRetry(for: window)
  }

  /// 预算在进程内共享；窗口尚未可见时允许后续事件续排，但不重置预算。
  /// 重试仅激活并置前，不切换策略，避免反复向 Dock 注册应用。
  private func startLaunchActivationRetry(for window: NSWindow) {
    guard !activationFinished, !isRetryChainActive else { return }
    isRetryChainActive = true
    scheduleActivationRetryTick(for: window)
  }

  private func endRetryChain() {
    isRetryChainActive = false
  }

  private func scheduleActivationRetryTick(for window: NSWindow) {
    tickScheduler.scheduleTick(after: activationRetryInterval) { [weak self] in
      self?.runActivationRetryTick(for: window)
    }
  }

  private func runActivationRetryTick(for window: NSWindow) {
    let visible = window.isVisible
    let attempt = activationRetryLimit - activationAttemptsLeft + 1
    let menuBarOwner = NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier ?? "-"
    let active = applier.isAppActive
    RuntimeLog.emit(
      .launchActivationRetry(
        attempt: attempt, active: active, policyRegular: applier.isPolicyRegular,
        frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-",
        menuBarOwner: menuBarOwner, onActiveSpace: window.isOnActiveSpace,
        windowVisible: visible))
    guard visible else {
      endRetryChain()
      return
    }
    if (applier.isAppActive && applier.ownsMenuBar) || activationAttemptsLeft == 0 {
      activationFinished = true
      endRetryChain()
      return
    }
    activationAttemptsLeft -= 1
    applier.activateApp()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    scheduleActivationRetryTick(for: window)
  }

  private func trackedWindow(in notification: Notification) -> NSWindow? {
    guard let window = notification.object as? NSWindow, anchoredWindows.contains(window)
    else { return nil }
    return window
  }
}

/// 挂在 Window scene 内容上的壳修饰器：零尺寸锚点视图捕获宿主 NSWindow，
/// 协调器据其生命周期收敛 app 激活策略。NSApp 侧 applier 由 MainApp 注入
/// （hermetic 判定 `ApplicationDependencies` 是组合根的 private 类型）。
struct WindowActivationPolicy: ViewModifier {
  @ObservedObject var coordinator: WindowActivationPolicyCoordinator

  func body(content: Content) -> some View {
    content.background(WindowActivationAnchor(onAttach: coordinator.anchorDidAttach))
  }
}

/// 锚点视图：随内容装进宿主窗口，`viewDidMoveToWindow` 上交宿主。
private struct WindowActivationAnchor: NSViewRepresentable {
  let onAttach: (NSWindow) -> Void

  func makeNSView(context: Context) -> AnchorView {
    AnchorView(onAttach: onAttach)
  }

  func updateNSView(_ nsView: AnchorView, context: Context) {}

  final class AnchorView: NSView {
    private let onAttach: (NSWindow) -> Void

    init(onAttach: @escaping (NSWindow) -> Void) {
      self.onAttach = onAttach
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("NSView 不走 storyboard 初始化")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // 关窗时 SwiftUI 可能置 nil（复用窗口语义下内容也可能保留）；nil 不回写，
      // 已捕获引用留给 willClose 匹配，重开由重新 attach 或 key 事件覆盖。
      if let window {
        onAttach(window)
      }
    }
  }
}
