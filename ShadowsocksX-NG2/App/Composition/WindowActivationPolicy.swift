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
  private let policySettleInterval: TimeInterval
  private let activationSettleInterval: TimeInterval
  private let launchRescanInterval: TimeInterval
  private let tickScheduler: any ActivationTickScheduling
  /// 激活已真正收敛（双信号齐备）后的永久闩：此后任何事件不再重启链，
  /// 避免会话中抢焦点。
  private var activationSettled = false
  /// 重试链是否在调度中。链可能在窗口尚未可见时静默终结（key 先于可见的
  /// 呈现次序），未收敛前由参与事件重新拉起（re-arm）。
  private var isRetryChainActive = false

  /// `applier` 与 `tickScheduler` 注入以便 hermetic 单测；生产实现里单测
  /// host 不触碰真实 NSApp、不依赖墙钟。
  init(
    applying applier: any WindowActivationPolicyApplying,
    activationRetryInterval: TimeInterval = 0.2,
    activationRetryLimit: Int = 5,
    policySettleInterval: TimeInterval = 0.1,
    activationSettleInterval: TimeInterval = 0.15,
    launchRescanInterval: TimeInterval = 0.5,
    tickScheduler: (any ActivationTickScheduling)? = nil
  ) {
    self.applier = applier
    self.activationRetryInterval = activationRetryInterval
    self.activationRetryLimit = activationRetryLimit
    self.policySettleInterval = policySettleInterval
    self.activationSettleInterval = activationSettleInterval
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
      guard let self, !self.activationSettled, !self.isRetryChainActive else { return }
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

  /// 启动激活重试（未收敛前可 re-arm）：首拍 activate 是否被焦点抢占保护
  /// 忽略随当时前台应用而变；短窗口内轮询双信号（激活 + 菜单栏归属），
  /// 不齐则重试 activate 并置前，收敛后永久闩死、次数用尽或窗口关闭则
  /// 结束本链（后续参与事件可再拉起，直到收敛）。双击启动首拍即收敛。
  private func startLaunchActivationRetry(for window: NSWindow) {
    guard !activationSettled, !isRetryChainActive else { return }
    isRetryChainActive = true
    scheduleActivationRetryTick(for: window, attemptsLeft: activationRetryLimit)
  }

  private func endRetryChain() {
    isRetryChainActive = false
  }

  private func scheduleActivationRetryTick(for window: NSWindow, attemptsLeft: Int) {
    tickScheduler.scheduleTick(after: activationRetryInterval) { [weak self] in
      self?.runActivationRetryTick(for: window, attemptsLeft: attemptsLeft)
    }
  }

  private func runActivationRetryTick(for window: NSWindow, attemptsLeft: Int) {
    let visible = window.isVisible
    let attempt = activationRetryLimit - attemptsLeft + 1
    let menuBarOwner = NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier ?? "-"
    let active = applier.isAppActive
    RuntimeLog.emit(
      .launchActivationRetry(
        attempt: attempt, active: active, policyRegular: applier.isPolicyRegular,
        frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-",
        menuBarOwner: menuBarOwner, onActiveSpace: window.isOnActiveSpace,
        windowVisible: visible))
    guard visible else {
      // 窗口尚未可见（key 先行的呈现次序）或已关闭：结束本链留待可见化
      // 事件或兜底重扫 re-arm。
      endRetryChain()
      return
    }
    // 双信号收敛判据：isActive 可能为真而菜单栏实际仍归此前台应用
    // （注册滞后的真相），此时继续重试——重置窗口置前本身就能盖回
    // 可见层，后续弹跳再补 Dock 图标注册。
    if applier.isAppActive && applier.ownsMenuBar {
      activationSettled = true
      endRetryChain()
      return
    }
    guard attemptsLeft > 0 else {
      endRetryChain()
      return
    }
    if attempt == 1 {
      // 首拍仍用普通 activate（重开等点击上下文里足以生效，避免无谓的
      // Dock 图标闪烁）。
      applier.activateApp()
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
      scheduleActivationRetryTick(for: window, attemptsLeft: attemptsLeft - 1)
    } else {
      scheduleForcedActivationSequence(for: window, attemptsLeft: attemptsLeft - 1)
    }
  }

  /// 强制激活序列（跨拍沉淀）：失败场景实测 Dock 图标从未出现、进调度
  /// 中心才刷新——启动早期的 regular 策略切换未注册到 WindowServer/Dock，
  /// activate 因此全程被拒。同拍 accessory→regular 弹跳会被系统合并吞掉，
  /// 必须拆成有真实间隔的三跳：降 accessory → 沉淀 → 回 regular（迫使
  /// 重新注册）→ 沉淀 → 激活置前。末跳续排主链保持单线调度。
  private func scheduleForcedActivationSequence(for window: NSWindow, attemptsLeft: Int) {
    applier.apply(.accessory)
    tickScheduler.scheduleTick(after: policySettleInterval) { [weak self] in
      guard let self, window.isVisible else {
        self?.endRetryChain()
        return
      }
      self.applier.apply(.regular)
      self.tickScheduler.scheduleTick(after: self.activationSettleInterval) { [weak self] in
        guard let self, window.isVisible else {
          self?.endRetryChain()
          return
        }
        if !(self.applier.isAppActive && self.applier.ownsMenuBar) {
          self.applier.activateApp()
          window.makeKeyAndOrderFront(nil)
          window.orderFrontRegardless()
        }
        self.scheduleActivationRetryTick(for: window, attemptsLeft: attemptsLeft)
      }
    }
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
