import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 偏好设置不可读时的控制器行为（「任何路径不静默改端口」）：
/// 占位出厂端口不得部署——停止运行时并点名呈现启动失败。
@MainActor
struct UnreadableSettingsTests {
  private struct Fixture {
    let runtime: ProxyRuntimeFixture.TemporaryRuntime
    let controller: ProxyRuntimeController
    let agent: ProxyRuntimeFixture.FakeLaunchAgent
    let systemProxy: ProxyRuntimeFixture.FakeSystemProxy
    let serverID: NodeID
  }

  private func makeFixture(
    agentStatus: LaunchAgentStatus,
    settingsRestore: RestoredProxySettings
  ) throws -> Fixture {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    let catalogFileURL = runtime.directory.appendingPathComponent("catalog.json")
    let activationFileURL = runtime.directory.appendingPathComponent("activation.json")
    let credentials = InMemoryCredentialStore()
    let agent = ProxyRuntimeFixture.FakeLaunchAgent()
    let systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
    agent.setStatus(agentStatus)

    var catalog = ConfigurationCatalog()
    let server = try ActivationFixture.addPlainServer(
      "香港 01", in: &catalog, credentials: credentials)
    try CatalogFileStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))

    let catalogSnapshotReader = CatalogCommitCoordinator.bootstrap(
      fileStore: CatalogFileStore(fileURL: catalogFileURL)
    ).catalogSnapshotReader
    let controller = ProxyRuntimeController(
      catalogSnapshotReader: catalogSnapshotReader,
      activationFileStore: ActivationStateFileStore(fileURL: activationFileURL),
      runtimeFileStore: RuntimeFileStore(fileURL: runtime.contract),
      credentials: credentials,
      plugins: ActivationFixture.plugins,
      appBundle: AppArtifact.bundle,
      settingsRestore: settingsRestore,
      agent: agent,
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      systemProxy: systemProxy,
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      launchHealthTimeoutSeconds: 0.05,
      sendSignal: { _, _ in 0 })
    return Fixture(
      runtime: runtime, controller: controller, agent: agent,
      systemProxy: systemProxy, serverID: server)
  }

  @Test
  func enableWithUnreadableSettingsRefusesDeploymentAndNamesReason() async throws {
    let fixture = try makeFixture(
      agentStatus: .notRegistered,
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(),
        unreadableError: .invalid([
          .duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 1086)
        ])))
    defer { try? FileManager.default.removeItem(at: fixture.runtime.directory) }

    try await fixture.controller.activate(fixture.serverID)
    await fixture.controller.setAgentEnabled(true)

    guard case .launchFailed(.unreadableSettings) = fixture.controller.state else {
      Issue.record("应呈现启动失败，实际 \(fixture.controller.state)")
      return
    }
    #expect(
      AppPresentation.message(for: RuntimeFailureFacts.launch(.unreadableSettings))
        .contains("配置无法读取"))
    #expect(fixture.agent.registerCount == 0, "占位出厂端口不得部署")
    #expect(!FileManager.default.fileExists(atPath: fixture.runtime.contract.path))
    #expect(fixture.systemProxy.applied.isEmpty, "占位端口不得写系统代理")
  }

  @Test
  func resyncWithUnreadableSettingsStopsRunningAgentInsteadOfRedeploying() async throws {
    let fixture = try makeFixture(
      agentStatus: .registered,
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(agentEnabled: true),
        unreadableError: .corrupt(detail: "test")))
    defer { try? FileManager.default.removeItem(at: fixture.runtime.directory) }

    try ActivationStateFileStore(
      fileURL: fixture.runtime.directory.appendingPathComponent("activation.json")
    ).save(activeTargetID: fixture.serverID)
    try RuntimeFileStore(fileURL: fixture.runtime.contract)
      .write(ProxyRuntimeFixture.makeDocument())

    await fixture.controller.resyncOnLaunch()

    guard case .launchFailed(.unreadableSettings) = fixture.controller.state else {
      Issue.record("应呈现启动失败，实际 \(fixture.controller.state)")
      return
    }
    #expect(
      AppPresentation.message(for: RuntimeFailureFacts.launch(.unreadableSettings))
        .contains("配置无法读取"))
    #expect(
      fixture.agent.unregisterCount == 1, "存续的上一会话 agent 必须停下，不得以占位端口重部署")
    #expect(!FileManager.default.fileExists(atPath: fixture.runtime.contract.path))
    #expect(fixture.systemProxy.applied.isEmpty)
    #expect(fixture.controller.effectiveRuntimeListenFacts == nil)
  }
}
