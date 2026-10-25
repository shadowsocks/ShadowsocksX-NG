import XCTest

@testable import ShadowsocksX_NG2

/// Mode restoration and commands share the Domain availability policy without
/// starting a real runtime or touching host proxy settings.
@MainActor
final class ProxyRuntimeControllerModeTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  func testRuntimeFactsProjectControllerStateAtStableSeam() async {
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())

    XCTAssertEqual(
      controller.runtimeFacts,
      ProxyRuntimeFacts(status: .off, isOn: false))

    await controller.resyncOnLaunch()

    XCTAssertEqual(
      controller.runtimeFacts,
      ProxyRuntimeFacts(status: .running, isOn: true),
      "默认 agent 意图开启：重同步后无目标也进入空列表监听")
  }
}

// MARK: - 收敛票据全事实检查（候选①：agent 关闭不得被任何 await 窗口内的
// 旧收敛复活；restore 先查时效再动持久层）

@MainActor
extension ProxyRuntimeControllerModeTests {
  /// agent-off 落在 mode 切换的健康门 await 窗口内：票据查全四事实 →
  /// superseded，不触发 restore 重注册，用户的 mode 意图保留在持久层与内存。
  func testAgentOffDuringModeTransitionHealthGateSupersedesWithoutRestore() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.BlockingProbe()
    let started = expectation(description: "mode transition health probe paused")
    let listeningStore = InMemoryProxyListeningStore()
    let controller = makeController(
      probe: probe,
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .global,
        agentEnabled: true, systemProxyEnabled: true),
      proxyMode: .global)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.state, .running)

    probe.arm(started: started)
    let modeSwitch = Task { await controller.setProxyMode(.direct) }
    await fulfillment(of: [started], timeout: 3)
    await controller.setAgentEnabled(false)
    XCTAssertEqual(controller.state, .off)
    let registrationsAfterStop = agent.registerCount
    probe.release()
    await modeSwitch.value

    XCTAssertEqual(
      agent.registerCount, registrationsAfterStop, "被取代的切换不得经 restore 重注册 agent")
    XCTAssertEqual(controller.state, .off)
    XCTAssertFalse(controller.settings.agentEnabled)
    XCTAssertEqual(controller.settings.preferredMode, ProxyModeKind.direct, "切换意图保留在内存")
    XCTAssertEqual(controller.controlPreferences.preferredMode, ProxyModeKind.direct, "切换意图保留在持久层")
    XCTAssertEqual(controller.settings.agentEnabled, false)
    XCTAssertNil(controller.runtimeObservation)
  }

  /// agent-off 落在 mode→rule 的派生窗口内：派生缝 preparationIsCurrent
  /// 恒查 agent 意图与并发流，派生即弃权，apply 根本不会启动。
  func testAgentOffDuringModeRuleDerivationSupersedesDeployment() async throws {
    let seeded = try makeSeededCatalog()
    let started = expectation(description: "rule snapshot load paused")
    let release = TestAsyncGate("rule snapshot load release")
    defer { release.release() }
    let loader = BuiltinRuleSnapshots(loader: { source -> RuleSnapshot in
      if source == .geolocationCN {
        started.fulfill()
        _ = await release.wait()
      }
      return rulesFixture(source)
    })
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .global,
        rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .global,
      ruleSnapshots: loader)
    try await controller.activate(seeded.server)

    let modeSwitch = Task { await controller.setProxyMode(.rule) }
    await fulfillment(of: [started], timeout: 3)
    await controller.setAgentEnabled(false)
    XCTAssertEqual(controller.state, .off)
    let registrationsAfterStop = agent.registerCount
    release.release()
    await modeSwitch.value

    XCTAssertEqual(agent.registerCount, registrationsAfterStop, "派生被取代后不得部署")
    XCTAssertEqual(controller.state, .off)
    XCTAssertNil(controller.runtimeObservation)
    XCTAssertFalse(controller.settings.agentEnabled)
    XCTAssertEqual(controller.settings.preferredMode, ProxyModeKind.rule, "切换意图保留")
  }

  /// agent-off 落在目录部署的健康门窗口内：结果必须是
  /// superseded（而非误分类的 failed），运行时保持 off、lastDocument 不复活。
  func testAgentOffDuringDeploymentHealthGateSupersedesDeployment() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.BlockingProbe()
    let started = expectation(description: "deployment health probe paused")
    let controller = makeController(
      probe: probe,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .global, agentEnabled: true),
      proxyMode: .global)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.state, .running)

    probe.arm(started: started)
    let deployment = Task {
      await controller.deploy(SslocalRuntimeDocument(servers: [], listen: ActivationFixture.listen))
    }
    await fulfillment(of: [started], timeout: 3)
    await controller.setAgentEnabled(false)
    XCTAssertEqual(controller.state, .off)
    let registrationsAfterStop = agent.registerCount
    probe.release()
    let result = await deployment.value

    XCTAssertEqual(result, .superseded)
    XCTAssertEqual(controller.state, .off)
    XCTAssertEqual(agent.registerCount, registrationsAfterStop)
    XCTAssertNil(controller.runtimeObservation)
  }

  /// 防火墙轮询在 await 恢复后代际已推进（含取消本任务的 stop 路径）时，
  /// 不得把过期的 .firewallBlocked 盖到最新状态呈现上。
  func testFirewallPollDoesNotWriteAfterExecutionSupersedesIt() async throws {
    let seeded = try makeSeededCatalog()
    let started = expectation(description: "firewall poll awaiting checker")
    let checker = ProxyRuntimeFixture.BlockingFirewallChecker(
      outcomes: [.permitted, .blocked], blockOnCall: 2, started: started)
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listen: ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces),
      firewallChecker: checker)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.state, .running, "首次防火墙检查通过后进入运行态并武装轮询")

    await fulfillment(of: [started], timeout: 3)
    await controller.setAgentEnabled(false)
    XCTAssertEqual(controller.state, .off)
    checker.release()
    try await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertEqual(controller.state, .off, "被取代的轮询不得改写状态")
  }

}

/// Coordinator/controller integration for the shared committed catalog source.
@MainActor
final class CatalogRuntimeSnapshotIntegrationTests: XCTestCase {
  private var runtime: ProxyRuntimeFixture.TemporaryRuntime!
  private var catalogFileURL: URL!
  private var activationFileURL: URL!
  private var agent: ProxyRuntimeFixture.FakeLaunchAgent!
  private var systemProxy: ProxyRuntimeFixture.FakeSystemProxy!

  override func setUp() async throws {
    try await super.setUp()
    runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    catalogFileURL = runtime.directory.appendingPathComponent("catalog.json")
    activationFileURL = runtime.directory.appendingPathComponent("activation.json")

    agent = ProxyRuntimeFixture.FakeLaunchAgent()
    systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: runtime.directory)
    try await super.tearDown()
  }

  func testCommitWithoutActiveTargetFeedsLaterActivationThroughSharedSnapshot() async throws {
    let fileStore = makeTestCatalogStore(fileURL: catalogFileURL)
    let bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: fileStore)
    let controller = makeController(
      catalogSnapshotReader: bootstrap.catalogSnapshotReader,
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))
    let coordinator = CatalogCommitCoordinator(
      fileStore: fileStore,
      runtime: ProxyRuntimeSyncAdapter(controller: controller),
      bootstrap: bootstrap)

    let server = try coordinator.commit { catalog, _ in
      try ActivationFixture.addPlainServer(
        "提交后激活", in: &catalog)
    }

    XCTAssertEqual(coordinator.syncStatus, .idle, "无目标时目录只发布，不触发运行时")
    XCTAssertNil(controller.activeTargetID)
    try await controller.activate(server)

    XCTAssertEqual(controller.activeTargetID, server, "激活读取协调器刚发布的唯一快照")
    XCTAssertEqual(controller.state, .off, "agent 意图关闭时该命令仅选择目标，不部署")
  }

  func testCoordinatorUsesProductionAdapterToClearRemovedActiveTarget() async throws {
    let server = try makeSeededCatalog()
    try ActivationStateFileStore(fileURL: activationFileURL).save(activeTargetID: server)
    let fileStore = makeTestCatalogStore(fileURL: catalogFileURL)
    let bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: fileStore)
    let controller = makeController(
      catalogSnapshotReader: bootstrap.catalogSnapshotReader,
      probe: ProxyRuntimeFixture.FakeProbe.reachable())
    let coordinator = CatalogCommitCoordinator(
      fileStore: fileStore,
      runtime: ProxyRuntimeSyncAdapter(controller: controller),
      bootstrap: bootstrap)

    _ = try coordinator.commit { catalog, _ in try catalog.remove(server) }

    await waitUntilRuntimeSettles(
      {
        if case .finished = coordinator.syncStatus { return true }
        return false
      }())

    guard case .finished(_, .clearedAndStopped) = coordinator.syncStatus else {
      return XCTFail("生产 adapter 应以刚提交快照清理无效目标")
    }
    XCTAssertNil(controller.activeTargetID)
    XCTAssertNil(
      try ActivationStateFileStore(fileURL: activationFileURL).loadActiveTargetID(),
      "adapter 收敛后持久化清除失效目标")
  }

  private func makeController(
    catalogSnapshotReader: RuntimeCatalogSnapshotReading,
    settings: ProxyRuntimeSettings? = nil,
    probe: EndpointProbing = SystemEndpointProbe()
  ) -> ProxyRuntimeController {
    let runtimeFileStore = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = { [runtimeFileStore] in
      try? runtimeFileStore.writePublishedRuntimeReceipt(processID: 42)
    }
    return ProxyRuntimeController(
      controlPreferences: makeTestProxyControlPreferences(),
      catalogSnapshotReader: catalogSnapshotReader,
      activationFileStore: ActivationStateFileStore(fileURL: activationFileURL),
      runtimeFileStore: runtimeFileStore,
      plugins: ActivationFixture.plugins,
      listeningStore: InMemoryProxyListeningStore(),
      appBundle: AppArtifact.bundle,
      ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: settings ?? ProxyRuntimeSettings(listen: ActivationFixture.listen),
        unreadableError: nil),
      agent: agent,
      probe: probe,
      systemProxy: systemProxy,
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      firewallExecutableURLs: [URL(fileURLWithPath: "/bundle/Helpers/sslocal")],
      firewallPollIntervalNanoseconds: 1_000_000,
      launchHealthTimeoutSeconds: 0.05,
      sendSignal: { _, _ in 0 },
      processIsAlive: { $0 == 42 })
  }

  private func makeSeededCatalog() throws -> NodeID {
    var catalog = ConfigurationCatalog()
    let server = try ActivationFixture.addPlainServer(
      "待删除", in: &catalog)
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))
    return server
  }
}
