import XCTest

@testable import ShadowsocksX_NG2

/// 代理控制命令矩阵：经生产 runtime adapter 包装的真实控制器
/// 验证 agent 开关、系统代理开关与模式切换的失败分类与恢复语义原样进入
/// snapshot。全部使用 fixture 替身，不启动真实 launch agent、不写真实
/// SystemConfiguration（这些替身测试不构成真实系统写入验证）。
@MainActor
final class ProxyControlWorkflowIntegrationTests: XCTestCase {
  var controlPreferences: ProxyControlPreferences!
  private var runtime: ProxyRuntimeFixture.TemporaryRuntime!
  private var catalogFileURL: URL!
  private var activationFileURL: URL!
  var agent: ProxyRuntimeFixture.FakeLaunchAgent!
  var systemProxy: ProxyRuntimeFixture.FakeSystemProxy!
  var networkMonitor = ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor()
  var systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService!

  override func setUp() async throws {
    try await super.setUp()
    controlPreferences = makeTestProxyControlPreferences()
    runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    catalogFileURL = runtime.directory.appendingPathComponent("catalog.json")
    activationFileURL = runtime.directory.appendingPathComponent("activation.json")

    agent = ProxyRuntimeFixture.FakeLaunchAgent()
    systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
    systemProxyHelper = ProxyRuntimeFixture.FakeSystemProxyHelperService()
    networkMonitor = ProxyRuntimeFixture.FakeSystemProxyNetworkChangeMonitor()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: runtime.directory)
    try await super.tearDown()
  }

  /// 控制器、目录工作流与代理控制工作流的生产组合（同一控制器经两条缝）。
  struct Composition {
    let catalog: CatalogWorkflow
    let control: ProxyControlWorkflow
    let controller: ProxyRuntimeController
  }

  /// 建一个含单台服务器的目录并落盘（服务器密码进内存凭据存储）。
  func makeSeededCatalog() throws -> NodeID {
    var catalog = ConfigurationCatalog()
    let server = try ActivationFixture.addPlainServer(
      "香港 01", in: &catalog)
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))
    return server
  }

  func makeProxies(
    probe: EndpointProbing,
    agentStatus: LaunchAgentStatus = .notRegistered,
    listeningStore: ProxyListeningStoring? = nil,
    settings: ProxyRuntimeSettings? = nil,
    proxyMode: ProxyMode = .rule
  ) -> Composition {
    agent.setStatus(agentStatus)
    let runtimeFileStore = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = { [runtimeFileStore] in
      try? runtimeFileStore.writePublishedRuntimeReceipt(processID: 42)
    }
    let controller = ProxyRuntimeController(
      controlPreferences: controlPreferences,
      catalogSnapshotReader: ProxyRuntimeFixture.catalogSnapshotReader(at: catalogFileURL),
      activationFileStore: ActivationStateFileStore(fileURL: activationFileURL),
      runtimeFileStore: runtimeFileStore,
      plugins: ActivationFixture.plugins,
      listeningStore: listeningStore ?? InMemoryProxyListeningStore(),
      appBundle: AppArtifact.bundle,
      // Keep real ACL compilation; corpus coverage belongs to the packaged-rule tests.
      ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: settings ?? ProxyRuntimeSettings(listen: ActivationFixture.listen),
        unreadableError: nil),
      agent: agent, probe: probe,
      systemProxy: systemProxy,
      systemProxyHelper: systemProxyHelper,
      systemProxyNetworkChangeMonitor: networkMonitor,
      proxyMode: proxyMode,
      firewallChecker: ProxyRuntimeFixture.FakeFirewallChecker(),
      firewallExecutableURLs: [URL(fileURLWithPath: "/bundle/Helpers/sslocal")],
      firewallPollIntervalNanoseconds: 1_000_000,
      // 生产默认 15 秒健康窗；FakeProbe 结果确定，短窗口走同一超时呈现路径。
      launchHealthTimeoutSeconds: 0.05,
      launchHealthRetryDelay: { try await Task.sleep(for: .milliseconds(1)) },
      systemProxyHealthPollIntervalNanoseconds: 20_000_000,
      helperRefreshDelayNanoseconds: 0,
      sendSignal: { _, _ in 0 },
      processIsAlive: { $0 == 42 })
    let fileStore = makeTestCatalogStore(fileURL: catalogFileURL)
    let bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: fileStore)
    let catalogWorkflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: fileStore,
        runtime: ProxyRuntimeSyncAdapter(controller: controller),
        bootstrap: bootstrap),
      plugins: ActivationFixture.plugins,
      activator: controller)
    let control = ProxyControlWorkflow(
      runtime: ControllerProxyRuntimeAdapter(controller: controller),
      targetFacts: catalogWorkflow,
      interfaceFacts: FakeLocalInterfaceFacts())
    return Composition(
      catalog: catalogWorkflow, control: control, controller: controller)
  }

  // MARK: - Agent 开关与首次默认

  func testAgentEnableWithoutActiveTargetListensThroughSnapshot() async throws {
    _ = try makeSeededCatalog()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))

    let snapshot = await composition.control.setAgentEnabled(true)

    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .running, isOn: true))
    XCTAssertTrue(snapshot.agentIntentEnabled, "开关意图进入 snapshot")
    XCTAssertTrue(snapshotAgentListening(composition), "空服务器监听契约已部署")
    XCTAssertTrue(systemProxy.applied.isEmpty, "系统代理意图默认关闭")
    XCTAssertEqual(snapshot.systemProxyApplication, .idle)
    XCTAssertEqual(agent.registerCount, 1)
  }

  /// 空监听判定辅助：契约存在且无服务器。
  private func snapshotAgentListening(_ composition: Composition) -> Bool {
    guard
      let data = try? Data(contentsOf: runtime.contract),
      let document = try? JSONDecoder().decode(SslocalConfigurationDocument.self, from: data)
    else { return false }
    return document.servers.isEmpty
  }

  func testAgentEnableConvergesToWholeRunningSnapshotWithRealCatalogFacts() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())

    // 目录激活走目录工作流（生产 activator 是同一控制器）；agent 开关走控制 seam。
    _ = try await composition.catalog.activate(server)
    let snapshot = await composition.control.setAgentEnabled(true)

    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .running, isOn: true))
    XCTAssertNil(snapshot.runtime.failure)
    XCTAssertTrue(snapshot.agentIntentEnabled)
    XCTAssertEqual(snapshot.proxyMode, .rule)
    XCTAssertEqual(snapshot.availableModes, [.rule, .global, .direct])
    XCTAssertEqual(snapshot.activeTarget?.pathSummary, "香港 01", "活动目标摘要来自真实目录树")
    XCTAssertEqual(snapshot.skippedInvalidServerCount, 0)
    XCTAssertTrue(
      snapshot.httpExport.copyableLine.contains("127.0.0.1:11087"),
      "HTTP 导出能力在 snapshot 中就绪")
  }

  func testUnhealthyEndpointSurfacesTypedLaunchFailureInSnapshot() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.refusing())

    _ = try await composition.catalog.activate(server)
    let snapshot = await composition.control.setAgentEnabled(true)

    XCTAssertEqual(snapshot.runtime.status, .launchFailed)
    XCTAssertFalse(snapshot.runtime.isOn)
    guard
      case .launch(.localEndpoint(let endpoint, let host, _, .refused)) = snapshot.runtime.failure
    else {
      return XCTFail("应点名本机端点失败，实际 \(String(describing: snapshot.runtime.failure))")
    }
    XCTAssertEqual(endpoint, "SOCKS")
    XCTAssertEqual(host, "127.0.0.1")
  }

  func testPendingBackgroundApprovalSurfacesTypedFactInSnapshot() async throws {
    let server = try makeSeededCatalog()
    agent.statusAfterRegister = .requiresApproval
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())

    _ = try await composition.catalog.activate(server)
    let snapshot = await composition.control.setAgentEnabled(true)

    XCTAssertEqual(
      snapshot.runtime,
      ProxyRuntimeFacts(
        status: .requiresApproval,
        isOn: true,
        failure: .requiresApproval))
  }

  // MARK: - Agent 关闭矩阵

  func testDisableReflectsClosedIntentAndKeepsModesAvailable() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)

    let snapshot = await composition.control.setAgentEnabled(false)

    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .off, isOn: false))
    XCTAssertFalse(snapshot.agentIntentEnabled)
    XCTAssertNil(snapshot.runtime.failure)
    XCTAssertEqual(snapshot.availableModes, [.rule, .global, .direct], "停用后可用操作不消失")
  }

  /// 关闭 agent 且系统代理清理失败：agent 停止，清理失败以系统代理 typed fact 呈现。
  func testAgentOffWithSystemProxyClearFailureSurfacesTypedFact() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
    systemProxy.clearError = SystemProxyError.commitFailed("busy")

    let snapshot = await composition.control.setAgentEnabled(false)

    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .off, isOn: false))
    XCTAssertEqual(
      snapshot.systemProxyApplication, .clearFailed(.operation(.commitFailed)),
      "清理失败以 typed fact 呈现，不静默视为已清理")
  }

  // MARK: - 模式命令矩阵

  func testModeSwitchWhileOffPersistsAndSnapshotConvergesWithoutRuntimeTouch() async throws {
    _ = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))

    let snapshot = await composition.control.setProxyMode(.global)

    XCTAssertEqual(snapshot.proxyMode, .global)
    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .off, isOn: false))
    XCTAssertEqual(composition.controller.controlPreferences.preferredMode, .global, "模式先持久化")
    XCTAssertTrue(systemProxy.applied.isEmpty, "agent 未运行时不触碰系统代理")
    XCTAssertEqual(systemProxy.clearCount, 0)
  }

  func testModeChoiceIgnoresListeningFileFailure() async throws {
    _ = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    listeningStore.saveError = ProxyListeningStoreError.ioFailure(detail: "disk unavailable")
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))

    let snapshot = await composition.control.setProxyMode(.global)

    XCTAssertEqual(snapshot.proxyMode, .global)
    XCTAssertEqual(controlPreferences.preferredMode, .global)
    XCTAssertEqual(snapshot.runtime, ProxyRuntimeFacts(status: .off, isOn: false))
    XCTAssertNil(listeningStore.saved)
  }

  func testSameModeCommandIsNoopWithoutSettingsOrSystemProxyWrites() async throws {
    _ = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))
    let before = composition.control.snapshot

    let after = await composition.control.setProxyMode(.rule)

    XCTAssertEqual(after, before, "同模式命令无副作用，snapshot 不动")
    XCTAssertNil(listeningStore.saved)
    XCTAssertTrue(systemProxy.applied.isEmpty)
    XCTAssertEqual(systemProxy.clearCount, 0)
  }

  // MARK: - 集成级 model test（deletion 验证）

  /// 状态菜单的呈现面只凭 ProxyControlWorkflow 的 snapshot 与 CatalogWorkflow
  /// 的目录事实即可完整推导；本文件不要求启动 SwiftUI，也不依赖控制器字段。
  func testStatusMenuSummaryProjectsWorkflowStateAndTarget() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    _ = await composition.control.setSystemProxyEnabled(true)

    let summary = StatusMenuModel.summary(from: composition.control.snapshot)

    XCTAssertTrue(summary.agentIntentEnabled)
    XCTAssertTrue(summary.isOn)
    XCTAssertEqual(summary.targetPath, "香港 01")
    XCTAssertNil(summary.detail)
    XCTAssertTrue(summary.systemProxyIntentEnabled)
    XCTAssertNil(summary.systemProxyDetail)
  }

}

/// Pause the first operation at its I/O seam; subsequent reads can finish normally.
@MainActor
final class ProxyControlOperationGate {
  let started: XCTestExpectation
  private var didPause = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(started: XCTestExpectation) { self.started = started }

  func wait() async {
    guard !didPause else { return }
    didPause = true
    await withCheckedContinuation {
      continuation = $0
      started.fulfill()
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

extension ProxyControlWorkflowIntegrationTests {
  func emitAndWaitForInspection(
    _ change: SystemProxyNetworkChange, in composition: Composition
  ) async {
    XCTAssertTrue(networkMonitor.isObserving)
    networkMonitor.emit(change)
    let inspection = composition.controller.systemProxyObserver.systemProxyInspectionTask
    XCTAssertNotNil(inspection, "被动事件应调度检查")
    await inspection?.value
  }
}
