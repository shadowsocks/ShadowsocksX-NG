import XCTest

@testable import ShadowsocksX_NG2

extension ProxyControlWorkflowIntegrationTests {
  func testPassiveNetworkChangesNeverReapplySystemProxy() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    _ = await composition.control.setSystemProxyEnabled(true)
    let writes = systemProxy.applied.count
    XCTAssertEqual(writes, 1)
    await emitAndWaitForInspection(
      [.networkConfiguration, .proxyConfiguration, .networkPath], in: composition)
    XCTAssertEqual(systemProxy.applied.count, writes)
    XCTAssertEqual(systemProxy.clearCount, 0)
  }

  // MARK: - 系统代理开关

  func testSystemProxyIntentAppliesThroughSnapshot() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())

    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    let snapshot = await composition.control.setSystemProxyEnabled(true)

    XCTAssertTrue(snapshot.systemProxyIntentEnabled)
    XCTAssertEqual(snapshot.systemProxyApplication, .applied)
    XCTAssertEqual(snapshot.runtime.status, .running, "agent 运行状态不受系统代理影响")
    XCTAssertEqual(systemProxy.applied.count, 1)
  }

  /// 健康门禁：端点不健康时系统代理意图保持待应用（快照呈现 pending）。
  func testSystemProxyIntentStaysPendingWhenEndpointsUnhealthy() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.refusing())

    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    let snapshot = await composition.control.setSystemProxyEnabled(true)

    XCTAssertTrue(snapshot.systemProxyIntentEnabled)
    XCTAssertEqual(snapshot.systemProxyApplication, .paused, "待应用进入 snapshot")
    XCTAssertEqual(snapshot.runtime.status, .launchFailed)
    XCTAssertTrue(systemProxy.applied.isEmpty, "健康门未过不写系统设置")
  }

  /// 系统代理写入失败：typed fact 进入 snapshot，agent 继续运行。
  func testSystemProxyFailureSurfacesTypedFactInSnapshot() async throws {
    let server = try makeSeededCatalog()
    systemProxy.applyError = SystemProxyError.applyFailed("denied")
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())

    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    let snapshot = await composition.control.setSystemProxyEnabled(true)

    XCTAssertTrue(snapshot.systemProxyIntentEnabled)
    XCTAssertEqual(
      snapshot.systemProxyApplication, .failed(.operation(.applyFailed)))
    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .running, isOn: true))
  }

  /// 关闭系统代理：清理匹配端点的设置；本地监听不停止。
  func testSystemProxyOffKeepsAgentRunningAndReflectsIdleInSnapshot() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    _ = await composition.control.setSystemProxyEnabled(true)

    let snapshot = await composition.control.setSystemProxyEnabled(false)

    XCTAssertFalse(snapshot.systemProxyIntentEnabled)
    XCTAssertEqual(snapshot.systemProxyApplication, .idle)
    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .running, isOn: true))
    XCTAssertEqual(systemProxy.clearCount, 1)
    XCTAssertEqual(agent.unregisterCount, 0, "不注销 agent")
  }

  /// 无活动目标：agent 监听，但需要出口的系统代理意图保持待应用。
  func testSystemProxyIntentStaysPendingWithoutActiveTarget() async throws {
    _ = try makeSeededCatalog()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: false))
    _ = await composition.control.setAgentEnabled(true)

    let snapshot = await composition.control.setSystemProxyEnabled(true)

    XCTAssertEqual(snapshot.runtime.status, .running, "agent 以空列表监听")
    XCTAssertEqual(snapshot.systemProxyApplication, .paused, "无可用出口保持待应用")
    XCTAssertTrue(systemProxy.applied.isEmpty)
    XCTAssertNil(snapshot.activeTarget)
  }

  /// 待应用意图在目标激活后自动收敛。目录命令后的 snapshot 更新
  /// 经主队列 hop 到达，有界等待收敛。
  func testPendingSystemProxyIntentConvergesAfterTargetActivation() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    _ = await composition.control.setAgentEnabled(true)
    let pending = await composition.control.setSystemProxyEnabled(true)
    XCTAssertEqual(pending.systemProxyApplication, .paused)

    _ = try await composition.catalog.activate(server)
    let deadline = Date().addingTimeInterval(2)
    while composition.control.snapshot.systemProxyApplication != .applied && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied, "激活后自动收敛")
    XCTAssertEqual(systemProxy.applied.count, 1)
  }

  // MARK: - HTTP 导出能力派生（生产 adapter 的唯一点）

  func testHTTPExportCapabilityDerivesSafeCopyableLineForLoopback() {
    XCTAssertEqual(
      HTTPExportCapability(listen: SslocalListenSettings()).copyableLine,
      "export http_proxy=http://127.0.0.1:11087;export https_proxy=http://127.0.0.1:11087;")
  }

  func testHTTPExportCapabilityUsesLoopbackAddressForAllIPv4Interfaces() {
    var listen = SslocalListenSettings()
    listen.listenerMode = .allIPv4Interfaces
    listen.httpPort = 8080
    XCTAssertEqual(
      HTTPExportCapability(listen: listen).copyableLine,
      "export http_proxy=http://127.0.0.1:8080;export https_proxy=http://127.0.0.1:8080;")
  }

  func testHTTPExportCapabilityUsesIPv4LoopbackForDualStackMode() {
    var listen = SslocalListenSettings()
    listen.listenerMode = .allIPv4AndIPv6Interfaces
    listen.httpPort = 8080

    XCTAssertEqual(
      HTTPExportCapability(listen: listen).copyableLine,
      "export http_proxy=http://127.0.0.1:8080;export https_proxy=http://127.0.0.1:8080;")
  }

  func testHTTPExportCapabilityBracketsIPv6LoopbackOnlyForIPv6OnlyMode() {
    var listen = SslocalListenSettings()
    listen.listenerMode = .allIPv6Interfaces
    listen.httpPort = 8080
    XCTAssertEqual(
      HTTPExportCapability(listen: listen).copyableLine,
      "export http_proxy=http://127.0.0.1:8080;export https_proxy=http://127.0.0.1:8080;")
  }
}
