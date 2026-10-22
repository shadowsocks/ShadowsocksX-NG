import AppKit
import XCTest

@testable import ShadowsocksX_NG2

/// Anchored app windows share activation policy; foreign windows are ignored.
/// Notifications, an injected spy, and a manually driven tick queue keep these
/// tests independent of presentation and wall-clock timing.
@MainActor
final class WindowActivationPolicyTests: XCTestCase {
  private var spy: SpyApplier!
  private var tickScheduler: SpyTickScheduler!
  private var coordinator: WindowActivationPolicyCoordinator!
  private var window: NSWindow!
  private var foreignWindow: NSWindow!

  override func setUp() async throws {
    try await super.setUp()
    spy = SpyApplier()
    tickScheduler = SpyTickScheduler()
    coordinator = WindowActivationPolicyCoordinator(
      applying: spy,
      tickScheduler: tickScheduler)
    // 离屏裸窗口仅作通知对象身份：不呈现、不抢 key，创建本身不触碰
    // WindowServer 的窗口呈现。
    window = Self.makeOffscreenWindow()
    foreignWindow = Self.makeOffscreenWindow()
    coordinator.anchorDidAttach(to: window)
    // 消化首个不可见锚点安排的兜底重扫（此时无可见窗口，必然空转），
    // 后续用例的 pending 队列保持确定。
    tickScheduler.drainOne()
  }

  override func tearDown() async throws {
    window = nil
    foreignWindow = nil
    try await super.tearDown()
  }

  /// 策略与激活落点 spy（ADR 0017）：只记录调用，不触碰真实 NSApp。
  /// `isActive`/`ownsMenuBar` 默认为真：启动激活重试首拍即短路，既有用例
  /// 不受异步影响。
  @MainActor
  private final class SpyApplier: WindowActivationPolicyApplying {
    var applied: [NSApplication.ActivationPolicy] = []
    var isActive = true
    var ownsMenuBar = true
    var isPolicyRegular = true
    var activationCalls = 0
    /// 第 N 次 activate 后视为激活成功（模拟稍后才成功）。
    var becomesActiveAfterCalls: Int?

    func apply(_ policy: NSApplication.ActivationPolicy) {
      applied.append(policy)
    }

    var isAppActive: Bool { isActive }

    func activateApp() {
      activationCalls += 1
      if let becomesActiveAfterCalls, activationCalls >= becomesActiveAfterCalls {
        isActive = true
      }
    }
  }

  /// 收集重试节拍的手动调度 spy：按需逐拍驱动，不依赖墙钟。
  @MainActor
  private final class SpyTickScheduler: ActivationTickScheduling {
    var pending: [@MainActor @Sendable () -> Void] = []

    func scheduleTick(
      after interval: TimeInterval, _ tick: @escaping @MainActor @Sendable () -> Void
    ) {
      pending.append(tick)
    }

    /// 手动驱动一拍已排定的重试；无待执行拍时返回 false。执行该拍可能
    /// 在队尾续排下一拍。
    @discardableResult
    func drainOne() -> Bool {
      guard !pending.isEmpty else { return false }
      pending.removeFirst()()
      return true
    }
  }

  private static func makeOffscreenWindow() -> NSWindow {
    NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
  }

  private func post(_ name: Notification.Name, on target: NSWindow) {
    NotificationCenter.default.post(name: name, object: target)
  }

  // MARK: 随窗收敛

  func testAttachToNotYetVisibleWindowAppliesNothing() {
    XCTAssertTrue(
      spy.applied.isEmpty,
      "静默启动预建未呈现的窗口不得触发 regular：启动应停留在 accessory")
  }

  func testDidBecomeKeyAppliesRegular() {
    post(NSWindow.didBecomeKeyNotification, on: window)

    XCTAssertEqual(spy.applied, [.regular])
  }

  func testWillCloseAppliesAccessory() {
    post(NSWindow.willCloseNotification, on: window)

    XCTAssertEqual(spy.applied, [.accessory])
  }

  // MARK: 身份过滤

  func testForeignWindowNotificationsAreIgnored() {
    post(NSWindow.didBecomeKeyNotification, on: foreignWindow)
    post(NSWindow.willCloseNotification, on: foreignWindow)

    XCTAssertTrue(spy.applied.isEmpty, "非锚定窗口（sheet/辅助窗口）不得驱动策略")
  }

  func testClosingOneOfTwoWindowsKeepsRegularUntilLastCloses() {
    coordinator.anchorDidAttach(to: foreignWindow)
    post(NSWindow.didBecomeKeyNotification, on: window)
    post(NSWindow.didBecomeKeyNotification, on: foreignWindow)
    spy.applied.removeAll()
    post(NSWindow.willCloseNotification, on: window)
    XCTAssertFalse(spy.applied.contains(.accessory))
    post(NSWindow.willCloseNotification, on: foreignWindow)
    XCTAssertEqual(spy.applied.last, .accessory)
  }

  func testClosedWindowCanReopenWhileOtherWindowRemainsTracked() {
    coordinator.anchorDidAttach(to: foreignWindow)
    post(NSWindow.didBecomeKeyNotification, on: window)
    post(NSWindow.willCloseNotification, on: window)
    post(NSWindow.didBecomeKeyNotification, on: window)
    post(NSWindow.didBecomeKeyNotification, on: foreignWindow)
    spy.applied.removeAll()
    post(NSWindow.willCloseNotification, on: foreignWindow)
    XCTAssertFalse(spy.applied.contains(.accessory))
    post(NSWindow.willCloseNotification, on: window)
    XCTAssertEqual(spy.applied.last, .accessory)
  }

  func testWindowShownWithoutBecomingKeyParticipatesInLastClosePolicy() {
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    coordinator.anchorDidAttach(to: visible)
    visible.pretendVisible = true
    post(NSWindow.didChangeOcclusionStateNotification, on: visible)
    XCTAssertEqual(spy.applied.last, .regular)
    XCTAssertEqual(visible.orderFrontCalls, 1, "首次可见化必须置前成 key")
    post(NSWindow.didBecomeKeyNotification, on: window)
    spy.applied.removeAll()
    post(NSWindow.willCloseNotification, on: window)
    XCTAssertFalse(spy.applied.contains(.accessory))
    post(NSWindow.willCloseNotification, on: visible)
    XCTAssertEqual(spy.applied.last, .accessory)
  }

  func testCloseIncludesVisibleSiblingWhenPresentationNotificationWasMissed() {
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    coordinator.anchorDidAttach(to: visible)
    visible.pretendVisible = true
    post(NSWindow.didBecomeKeyNotification, on: window)
    spy.applied.removeAll()
    post(NSWindow.willCloseNotification, on: window)
    XCTAssertFalse(spy.applied.contains(.accessory))
    visible.pretendVisible = false
    post(NSWindow.willCloseNotification, on: visible)
    XCTAssertEqual(spy.applied.last, .accessory)
  }

  // MARK: 首次参与收敛置前

  func testVisibleAttachAppliesRegularAndOrdersFront() {
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true

    coordinator.anchorDidAttach(to: visible)

    XCTAssertEqual(spy.applied, [.regular])
    XCTAssertEqual(visible.orderFrontCalls, 1)
  }

  func testOcclusionInsertionOrdersFrontOnce() {
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    coordinator.anchorDidAttach(to: visible)
    visible.pretendVisible = true
    post(NSWindow.didChangeOcclusionStateNotification, on: visible)
    post(NSWindow.didChangeOcclusionStateNotification, on: visible)

    XCTAssertEqual(visible.orderFrontCalls, 1, "重复可见化不得反复置前")
  }

  // MARK: 启动激活重试

  func testLaunchRetryRunsOncePerProcess() {
    spy.isActive = false
    let first = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    first.pretendVisible = true
    let second = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    second.pretendVisible = true
    coordinator.anchorDidAttach(to: first)
    coordinator.anchorDidAttach(to: second)

    XCTAssertEqual(tickScheduler.pending.count, 1, "后续窗口参与不得再启动一轮重试")
  }

  /// 激活假象（实测失败场景）：isActive 与 frontmost 均指向本应用、重试即停，
  /// 但菜单栏仍归此前台应用——双信号不齐必须继续行动。
  func testActivationIllusionKeepsRetryingUntilMenuBarReturns() {
    spy.isActive = true
    spy.ownsMenuBar = false
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true
    coordinator.anchorDidAttach(to: visible)

    tickScheduler.drainOne()
    XCTAssertEqual(visible.orderRegardlessCalls, 1, "active=true 但菜单栏未归位也要抬窗")
    spy.ownsMenuBar = true
    while tickScheduler.drainOne() {}

    XCTAssertEqual(visible.orderRegardlessCalls, 1, "菜单栏归位后不得再行动")
    XCTAssertTrue(tickScheduler.pending.isEmpty)
  }

  // MARK: 启动期次序兜底

  /// 锚点附着时窗口尚未可见、其可见化通知又早于附着被错过：延迟重扫补上
  /// 参与与激活重试（实测失败场景启动期无任何事件即此序）。
  func testDeferredRescanRecoversWindowVisibleAfterAttach() {
    spy.isActive = false
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    coordinator.anchorDidAttach(to: visible)
    visible.pretendVisible = true

    tickScheduler.drainOne()
    XCTAssertEqual(spy.applied, [.regular], "重扫对已可见窗口补上参与并拉起重试")
    XCTAssertEqual(visible.orderFrontCalls, 1)
    while tickScheduler.drainOne() {}
  }

  func testDeferredRescanSkipsStillInvisibleWindow() {
    let silent = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    coordinator.anchorDidAttach(to: silent)

    while tickScheduler.drainOne() {}

    XCTAssertTrue(spy.applied.isEmpty, "静默启动的不可见窗口不得由重扫触发参与")
  }

  /// 链在窗口呈现完成前启动、首拍因不可见静默终结后，可见化事件必须能
  /// 重新拉起（re-arm），直到真正收敛。
  func testVisibilityEventRearmsChainEndedBeforeWindowVisible() {
    spy.isActive = false
    spy.becomesActiveAfterCalls = 1
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true
    coordinator.anchorDidAttach(to: visible)
    visible.pretendVisible = false

    while tickScheduler.drainOne() {}
    XCTAssertEqual(spy.activationCalls, 0, "首拍窗口不可见时链静默终结")

    visible.pretendVisible = true
    post(NSWindow.didChangeOcclusionStateNotification, on: visible)
    tickScheduler.drainOne()
    XCTAssertEqual(spy.activationCalls, 1, "可见化事件必须能重启已终结的链")
    while tickScheduler.drainOne() {}
    XCTAssertTrue(tickScheduler.pending.isEmpty)
  }
}

private final class VisibilityWindow: NSWindow {
  var pretendVisible = false
  override var isVisible: Bool { pretendVisible }

  /// 离屏拦截：真实置前会在测试宿主呈现窗口，只记录调用。
  var orderFrontCalls = 0
  override func makeKeyAndOrderFront(_ sender: Any?) {
    orderFrontCalls += 1
  }

  var orderRegardlessCalls = 0
  override func orderFrontRegardless() {
    orderRegardlessCalls += 1
  }
}

extension WindowActivationPolicyTests {
  func testLaunchRetryReactivatesWhileInactiveAndStopsAtLimit() {
    spy.isActive = false
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true
    coordinator.anchorDidAttach(to: visible)

    XCTAssertEqual(tickScheduler.pending.count, 1)
    tickScheduler.drainOne()
    XCTAssertEqual(spy.activationCalls, 1)
    XCTAssertEqual(
      spy.applied.filter { $0 == .accessory }, [], "首拍必须先走普通 activate，不弹跳")
    while tickScheduler.drainOne() {}
    XCTAssertEqual(spy.activationCalls, 5, "默认上限 5 次激活（1 普通 + 4 次弹跳末跳）")
    XCTAssertEqual(
      spy.applied.filter { $0 == .accessory }.count, 4,
      "第二拍起每次强制激活都要降一次 accessory")
    XCTAssertEqual(
      spy.applied.filter { $0 == .regular }.count, 5,
      "attach 一次 regular + 每次弹跳回一次 regular")
    XCTAssertEqual(visible.orderFrontCalls, 6, "attach 置前一次，每次激活后再置前")
    XCTAssertEqual(visible.orderRegardlessCalls, 5)
    XCTAssertTrue(tickScheduler.pending.isEmpty, "终态检查拍后不得再排")
  }

  func testLaunchRetryStopsOnceAppActive() {
    spy.isActive = false
    spy.becomesActiveAfterCalls = 2
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true
    coordinator.anchorDidAttach(to: visible)

    while tickScheduler.drainOne() {}

    XCTAssertEqual(spy.activationCalls, 2, "已激活后的检查不得再激活")
    XCTAssertEqual(spy.applied.suffix(2), [.accessory, .regular], "弹跳序列在激活成功处收敛")
    XCTAssertTrue(tickScheduler.pending.isEmpty, "已激活后不得再排下一拍")
  }

  func testLaunchRetryStopsWhenWindowCloses() {
    spy.isActive = false
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true
    coordinator.anchorDidAttach(to: visible)
    visible.pretendVisible = false

    tickScheduler.drainOne()

    XCTAssertEqual(spy.activationCalls, 0, "窗口已不可见不得再激活")
    XCTAssertTrue(tickScheduler.pending.isEmpty)
  }

  func testForcedSequenceAbortsWhenWindowClosesMidBounce() {
    spy.isActive = false
    let visible = VisibilityWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    visible.pretendVisible = true
    coordinator.anchorDidAttach(to: visible)
    tickScheduler.drainOne()
    tickScheduler.drainOne()
    XCTAssertEqual(spy.applied, [.regular, .accessory], "第二拍已降级 accessory 待弹跳")
    visible.pretendVisible = false

    while tickScheduler.drainOne() {}

    XCTAssertEqual(spy.activationCalls, 1, "窗口关闭后弹跳末跳不得再激活")
    XCTAssertEqual(
      spy.applied, [.regular, .accessory], "中途关闭后不得再回 regular")
  }
}
