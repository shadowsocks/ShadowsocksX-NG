import XCTest

@testable import ShadowsocksX_NG2

/// 系统代理观察机 interface 驱动测试（ADR-0022 策略机抽取后）：不经控制器
/// 夹具，直接以三条缝的替身驱动 cleanup-until-quiet 循环与操作互斥。
@MainActor
final class SystemProxyObserverTests: XCTestCase {
  func testCleanupRescansWhileNetworkKeepsChangingThenGoesQuiet() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let monitor = ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor()
    let observer = makeObserver(
      proxy: proxy, monitor: monitor, cleanupSettleNanoseconds: 1_000_000)
    // 第一次 clear 期间到达的网络变化触发整轮重扫；随后安静，循环收敛。
    var emittedChange = false
    proxy.onClear = {
      guard !emittedChange else { return }
      emittedChange = true
      monitor.emit([.networkConfiguration, .proxyConfiguration])
    }

    let outcome = await observer.clearAndStopSystemProxyObservation()

    XCTAssertEqual(outcome, .idle)
    XCTAssertEqual(proxy.clearCount, 2, "清理期内的网络变化必须触发整轮重扫")
    XCTAssertTrue(emittedChange)
    XCTAssertEqual(monitor.startCount, 1)
    XCTAssertEqual(monitor.stopCount, 1)
    XCTAssertEqual(observer.systemProxyObservationMode, .stopped)
    XCTAssertEqual(observer.systemProxyState, .idle)
    XCTAssertFalse(observer.systemProxyInspection.isBusy)
  }

  func testConvergeWaitsForInFlightOperationInsteadOfSkipping() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let observer = makeObserver(proxy: proxy, cleanupSettleNanoseconds: 1_000_000)
    // 拉长首次读服务的窗口，制造进行中的操作。
    proxy.beforeRead = { _ = try? await Task.sleep(nanoseconds: 30_000_000) }

    let first = Task { await observer.convergeSystemProxy(forceApply: true) }
    try await Task.sleep(nanoseconds: 10_000_000)
    await observer.convergeSystemProxy(forceApply: true)
    await first.value

    XCTAssertEqual(proxy.applied.count, 2, "并发收敛必须等操作收尾后执行而非被跳过")
  }

  func testEnableIntentAppliesFreshAndStartsObservation() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let monitor = ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor()
    let observer = makeObserver(proxy: proxy, monitor: monitor, cleanupSettleNanoseconds: 1_000_000)

    await observer.enableSystemProxyIntent()

    XCTAssertEqual(proxy.applied.count, 1, "开启意图必须真实应用一次（清理期可能已清空系统设置）")
    XCTAssertEqual(observer.systemProxyState, .applied)
    XCTAssertEqual(observer.systemProxyObservationMode, .enabled)
    XCTAssertEqual(monitor.startCount, 1)
  }

  func testDisableIntentClearsStopsObservationAndPublishesOutcome() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let monitor = ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor()
    let observer = makeObserver(proxy: proxy, monitor: monitor, cleanupSettleNanoseconds: 1_000_000)
    await observer.enableSystemProxyIntent()

    await observer.disableSystemProxyIntent()

    XCTAssertEqual(proxy.clearCount, 1)
    XCTAssertEqual(observer.systemProxyState, .idle)
    XCTAssertEqual(observer.systemProxyObservationMode, .stopped)
    XCTAssertEqual(monitor.stopCount, 1)
    XCTAssertFalse(observer.systemProxyApprovalRequired)
  }

  func testAgentStopPresentationFollowsProxyIntent() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let monitor = ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor()
    var intentEnabled = true
    let observer = makeObserver(
      proxy: proxy, monitor: monitor, cleanupSettleNanoseconds: 1_000_000,
      isIntentEnabled: { intentEnabled })

    observer.agentDidStop()
    XCTAssertEqual(observer.systemProxyState, .pending, "代理意图仍在开时，agent 停机保持待应用（issue #71）")
    XCTAssertEqual(observer.systemProxyObservationMode, .stopped)
    XCTAssertEqual(monitor.stopCount, 1)

    intentEnabled = false
    observer.agentDidStop()
    XCTAssertEqual(observer.systemProxyState, .idle, "代理意图已关时，agent 停机呈现空闲")
  }

  func testModeTransitionAwaitingRuntimeStampsPendingOnlyUnderIntent() async throws {
    var intentEnabled = false
    let observer = makeObserver(
      proxy: ProxyRuntimeFixture.FakeSystemProxy(), cleanupSettleNanoseconds: 1_000_000,
      isIntentEnabled: { intentEnabled })

    observer.modeTransitionAwaitingRuntime()
    XCTAssertEqual(observer.systemProxyState, .idle, "代理意图关闭时不打待应用图章")

    intentEnabled = true
    observer.modeTransitionAwaitingRuntime()
    XCTAssertEqual(observer.systemProxyState, .pending)
  }

  func testSettleLaunchAfterConvergedInspectsWithoutReapplying() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let observer = makeObserver(proxy: proxy, cleanupSettleNanoseconds: 1_000_000)

    await observer.settleLaunchAfterAgentConverged()

    XCTAssertEqual(proxy.applied.count, 0, "健康的 GUI 启动只巡检，不强推应用")
    XCTAssertGreaterThanOrEqual(proxy.readCount, 1)
    XCTAssertEqual(observer.systemProxyObservationMode, .enabled)
    XCTAssertFalse(observer.systemProxyStartupInProgress)
    // 播种 lastDesired 后，后续收敛（如网络变化回调）不得因相等而重新应用。
    await observer.convergeSystemProxy()
    XCTAssertEqual(proxy.applied.count, 0, "播种 lastDesired 后收敛不得重新应用")
  }

  func testStartupSuppressionBlocksConvergeUntilSettled() async throws {
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let observer = makeObserver(proxy: proxy, cleanupSettleNanoseconds: 1_000_000)
    observer.beginStartupResync()

    await observer.convergeSystemProxy(forceApply: true)
    XCTAssertEqual(proxy.applied.count, 0, "launch 重同步抑制期 converge 必须被拒绝")

    await observer.settleLaunchWithAgentOff()
    XCTAssertFalse(observer.systemProxyStartupInProgress)
    XCTAssertEqual(observer.systemProxyState, .paused, "抑制解除后按意图挂起残留配置")
    XCTAssertEqual(observer.systemProxyObservationMode, .enabled)
  }

  private func makeObserver(
    proxy: ProxyRuntimeFixture.FakeSystemProxy,
    monitor: SystemProxyNetworkChangeMonitoring =
      ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor(),
    cleanupSettleNanoseconds: UInt64,
    isIntentEnabled: @escaping @MainActor () -> Bool = { true }
  ) -> SystemProxyObserver {
    SystemProxyObserver(
      systemProxy: proxy,
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      systemProxyNetworkChangeMonitor: monitor,
      appBundle: AppArtifact.bundle,
      helperRefreshDelayNanoseconds: 1_000_000,
      cleanupSettleNanoseconds: cleanupSettleNanoseconds,
      isIntentEnabled: isIntentEnabled,
      isExitAvailable: { true },
      desiredConfiguration: {
        ProxyMode.direct.systemProxyConfiguration(
          for: SslocalRuntimeDocument(servers: [], listen: SslocalListenSettings()),
          exceptions: [])
      },
      systemProxyHealthObservationLoop: {})
  }
}
