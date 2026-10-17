import XCTest

@testable import ShadowsocksX_NG2

/// SettingsWorkflow 与真实 ProxyRuntimeController 的监听设置提交集成。
@MainActor
final class SettingsWorkflowTests: XCTestCase {
  private var runtime: ProxyRuntimeFixture.TemporaryRuntime!
  private var catalogFileURL: URL!
  private var activationFileURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var agent: ProxyRuntimeFixture.FakeLaunchAgent!
  private var systemProxy: ProxyRuntimeFixture.FakeSystemProxy!
  private var settingsStore: InMemorySettingsStore!

  override func setUp() async throws {
    try await super.setUp()
    runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    catalogFileURL = runtime.directory.appendingPathComponent("catalog.json")
    activationFileURL = runtime.directory.appendingPathComponent("activation.json")
    credentials = InMemoryCredentialStore()
    agent = ProxyRuntimeFixture.FakeLaunchAgent()
    systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
    settingsStore = InMemorySettingsStore()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: runtime.directory)
    try await super.tearDown()
  }

  func testListenerModeSavePersistsWithoutStartingAnOffAgent() async throws {
    let pair = makePair()

    var draft = try pair.workflow.beginLANListeningEditing()
    draft.isEnabled = true
    draft.mode = .allIPv4AndIPv6Interfaces
    let outcome = await pair.workflow.saveLANListening(draft)

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(pair.controller.settings.listen.listenerMode, .allIPv4AndIPv6Interfaces)
    XCTAssertEqual(settingsStore.saved?.listen.listenerMode, .allIPv4AndIPv6Interfaces)
    XCTAssertEqual(pair.controller.state, .off)
    XCTAssertEqual(agent.registerCount, 0)
  }

  private func makePair() -> (controller: ProxyRuntimeController, workflow: SettingsWorkflow) {
    let catalogSnapshotReader = CatalogCommitCoordinator.bootstrap(
      fileStore: CatalogFileStore(fileURL: catalogFileURL)
    ).catalogSnapshotReader
    let runtimeFileStore = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = { [runtimeFileStore] in
      guard let document = runtimeFileStore.loadDocument() else { return }
      try? runtimeFileStore.writeRuntimeReceipt(for: document, processID: 42)
    }
    let controller = ProxyRuntimeController(
      catalogSnapshotReader: catalogSnapshotReader,
      activationFileStore: ActivationStateFileStore(fileURL: activationFileURL),
      runtimeFileStore: runtimeFileStore,
      credentials: credentials,
      plugins: ActivationFixture.plugins,
      settingsStore: settingsStore,
      appBundle: AppArtifact.bundle,
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(listen: ActivationFixture.listen), unreadableError: nil),
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
      committing: controller, occupancyProbe: FakeOccupancyProbe(), credentials: credentials)
    return (controller, workflow)
  }

  final class InMemorySettingsStore: ProxySettingsStoring {
    var saved: ProxySettings?

    func load() throws -> ProxySettings {
      saved ?? ProxySettings()
    }

    func save(_ settings: ProxySettings) throws {
      saved = settings
    }
  }
}
