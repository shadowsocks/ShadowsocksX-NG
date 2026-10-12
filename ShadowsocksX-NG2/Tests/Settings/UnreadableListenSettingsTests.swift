import XCTest

@testable import ShadowsocksX_NG2

/// 监听设置不可读时的控制器行为（「任何路径不静默改端口」）：
/// 占位出厂端口不得部署——停止运行时并点名呈现启动失败。
@MainActor
final class UnreadableListenSettingsTests: XCTestCase {
  private var runtime: ProxyRuntimeFixture.TemporaryRuntime!
  private var catalogFileURL: URL!
  private var activationFileURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var agent: ProxyRuntimeFixture.FakeLaunchAgent!
  private var systemProxy: ProxyRuntimeFixture.FakeSystemProxy!

  override func setUp() async throws {
    try await super.setUp()
    runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    catalogFileURL = runtime.directory.appendingPathComponent("catalog.json")
    activationFileURL = runtime.directory.appendingPathComponent("activation.json")
    credentials = InMemoryCredentialStore()
    agent = ProxyRuntimeFixture.FakeLaunchAgent()
    systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: runtime.directory)
    try await super.tearDown()
  }

  private func makeController(
    agentStatus: LaunchAgentStatus,
    listenUnreadable: ListenSettingsStoreError,
    settingsRestore: RestoredProxySettings? = nil
  ) -> ProxyRuntimeController {
    agent.setStatus(agentStatus)
    let catalogSnapshotReader = CatalogCommitCoordinator.bootstrap(
      fileStore: CatalogFileStore(fileURL: catalogFileURL)
    ).catalogSnapshotReader
    return ProxyRuntimeController(
      catalogSnapshotReader: catalogSnapshotReader,
      activationFileStore: ActivationStateFileStore(fileURL: activationFileURL),
      runtimeFileStore: RuntimeFileStore(fileURL: runtime.contract),
      credentials: credentials,
      plugins: ActivationFixture.plugins,
      listenRestore: RestoredListenSettings(
        settings: SslocalListenSettings(), unreadableError: listenUnreadable),
      appBundle: AppArtifact.bundle,
      settingsRestore: settingsRestore,
      agent: agent,
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      systemProxy: systemProxy,
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      launchHealthTimeoutSeconds: 0.05,
      sendSignal: { _, _ in 0 })
  }

  /// 建一个含单台服务器的目录并落盘（服务器密码进内存凭据存储）。
  private func makeSeededCatalog() throws -> NodeID {
    var catalog = ConfigurationCatalog()
    let server = try ActivationFixture.addPlainServer(
      "香港 01", in: &catalog, credentials: credentials)
    try CatalogFileStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))
    return server
  }

  func testEnableWithUnreadableListenSettingsRefusesDeploymentAndNamesReason() async throws {
    let server = try makeSeededCatalog()
    let controller = makeController(
      agentStatus: .notRegistered,
      listenUnreadable: .invalidPorts([
        .duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 1086)
      ]))

    try await controller.activate(server)
    await controller.setAgentEnabled(true)

    guard case .launchFailed(.unreadableSettings) = controller.state else {
      return XCTFail("应呈现启动失败，实际 \(controller.state)")
    }
    XCTAssertTrue(
      AppPresentation.message(for: RuntimeFailureFacts.launch(.unreadableSettings))
        .contains("配置无法读取"),
      "失败必须点名监听设置不可读：\(controller.state)")
    XCTAssertEqual(agent.registerCount, 0, "占位出厂端口不得部署")
    XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.contract.path))
    XCTAssertTrue(systemProxy.applied.isEmpty, "占位端口不得写系统代理")
  }

  func testResyncWithUnreadableListenSettingsStopsRunningAgentInsteadOfRedeploying() async throws {
    let server = try makeSeededCatalog()
    try ActivationStateFileStore(fileURL: activationFileURL).save(activeTargetID: server)
    try RuntimeFileStore(fileURL: runtime.contract).write(ProxyRuntimeFixture.makeDocument())
    let controller = makeController(
      agentStatus: .registered,
      listenUnreadable: .corrupt(detail: "test"),
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(listen: SslocalListenSettings(), agentEnabled: true),
        unreadableError: .legacyListenSettings(.corrupt(detail: "test"))))

    await controller.resyncOnLaunch()

    guard case .launchFailed(.unreadableSettings) = controller.state else {
      return XCTFail("应呈现启动失败，实际 \(controller.state)")
    }
    XCTAssertTrue(
      AppPresentation.message(for: RuntimeFailureFacts.launch(.unreadableSettings))
        .contains("配置无法读取"),
      "必须点名监听设置不可读：\(controller.state)")
    XCTAssertEqual(
      agent.unregisterCount, 1, "存续的上一会话 agent 必须停下，不得以占位端口重部署")
    XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.contract.path))
    XCTAssertTrue(systemProxy.applied.isEmpty)
    XCTAssertNil(controller.effectiveRuntimeListenFacts)
  }
}
