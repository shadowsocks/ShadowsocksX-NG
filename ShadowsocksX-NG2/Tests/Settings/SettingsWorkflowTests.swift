import XCTest

@testable import ShadowsocksX_NG2

/// SettingsWorkflow 与真实 ProxyRuntimeController 的监听设置提交集成。
@MainActor
final class SettingsWorkflowTests: XCTestCase {
  private var runtime: ProxyRuntimeFixture.TemporaryRuntime!
  private var catalogFileURL: URL!
  private var activationFileURL: URL!
  private var agent: ProxyRuntimeFixture.FakeLaunchAgent!
  private var systemProxy: ProxyRuntimeFixture.FakeSystemProxy!
  private var listeningStore: InMemorySettingsStore!

  override func setUp() async throws {
    try await super.setUp()
    runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    catalogFileURL = runtime.directory.appendingPathComponent("catalog.json")
    activationFileURL = runtime.directory.appendingPathComponent("activation.json")

    agent = ProxyRuntimeFixture.FakeLaunchAgent()
    systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
    listeningStore = InMemorySettingsStore()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: runtime.directory)
    try await super.tearDown()
  }

  func testListenerModeSavePersistsWithoutStartingAnOffAgent() async throws {
    let pair = makePair()

    var draft = pair.workflow.beginLANListeningEditing()
    draft.isEnabled = true
    draft.mode = .allIPv4AndIPv6Interfaces
    let outcome = await pair.workflow.saveLANListening(draft)

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(pair.controller.settings.listen.listenerMode, .allIPv4AndIPv6Interfaces)
    XCTAssertEqual(listeningStore.saved?.listenerMode, .allIPv4AndIPv6Interfaces)
    XCTAssertEqual(pair.controller.state, .off)
    XCTAssertEqual(agent.registerCount, 0)
  }

  private func makePair() -> (controller: ProxyRuntimeController, workflow: SettingsWorkflow) {
    let catalogSnapshotReader = CatalogCommitCoordinator.bootstrap(
      fileStore: makeTestCatalogStore(fileURL: catalogFileURL)
    ).catalogSnapshotReader
    let runtimeFileStore = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = { [runtimeFileStore] in
      try? runtimeFileStore.writePublishedRuntimeReceipt(processID: 42)
    }
    let controller = ProxyRuntimeController(
      controlPreferences: makeTestProxyControlPreferences(),
      catalogSnapshotReader: catalogSnapshotReader,
      activationFileStore: ActivationStateFileStore(fileURL: activationFileURL),
      runtimeFileStore: runtimeFileStore,
      plugins: ActivationFixture.plugins,
      listeningStore: listeningStore,
      appBundle: AppArtifact.bundle,
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(listen: ActivationFixture.listen), unreadableError: nil),
      agent: agent,
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      systemProxy: systemProxy,
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      firewallExecutableURLs: [URL(fileURLWithPath: "/bundle/Helpers/sslocal")],
      firewallPollIntervalNanoseconds: 1_000_000,
      launchHealthTimeoutSeconds: 0.05,
      sendSignal: { _, _ in 0 },
      processIsAlive: { $0 == 42 })
    let workflow = SettingsWorkflow(
      committing: controller, occupancyProbe: FakeOccupancyProbe())
    return (controller, workflow)
  }

  final class InMemorySettingsStore: ProxyListeningStoring {
    var saved: ProxyListeningConfiguration?

    func load() throws -> ProxyListeningConfiguration {
      saved ?? ProxyListeningConfiguration()
    }

    func save(_ settings: ProxyListeningConfiguration) throws {
      saved = settings
    }
  }
}
