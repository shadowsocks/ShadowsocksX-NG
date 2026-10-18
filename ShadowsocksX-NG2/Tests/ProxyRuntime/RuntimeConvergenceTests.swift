import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 通过模式命令验证配置派生失败和无 ACL 变化路径，不调用恢复实现。
@MainActor
struct RuntimeConvergenceTests {
  @Test(arguments: [false, true])
  func modeDerivationFailureRestoresRuntimeAndReportsPersistenceFailure(
    restorePersistenceFails: Bool
  ) async throws {
    let fixture = try Fixture(
      systemProxyEnabled: true,
      snapshots: BuiltinRuleSnapshots(loader: { _ in throw RuleSnapshotError.missing }))
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    let previous = try #require(fixture.runtimeStore.loadDocument())
    let appliedCount = fixture.proxy.applied.count
    fixture.settings.rejectGlobalMode = restorePersistenceFails

    await fixture.controller.setProxyMode(.rule)

    #expect(fixture.controller.proxyMode == .global)
    #expect(fixture.controller.settings.preferredMode == .global)
    #expect(fixture.runtimeStore.loadDocument() == previous)
    #expect(
      fixture.controller.state
        == (restorePersistenceFails ? .serviceFailed(.persistence) : .running))
    #expect(fixture.settings.saved?.preferredMode == (restorePersistenceFails ? .rule : .global))
    #expect(fixture.controller.systemProxyState == .applied)
    #expect(fixture.proxy.applied.count == appliedCount)
    #expect(fixture.proxy.clearCount == 0)
  }

  @Test(arguments: [false, true])
  func unchangedModeACLOnlyChecksHealthWhenSystemProxyIsEnabled(
    systemProxyEnabled: Bool
  ) async throws {
    let fixture = try Fixture(systemProxyEnabled: systemProxyEnabled)
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    let bytes = try Data(contentsOf: fixture.runtimeStore.fileURL)
    let registers = fixture.agent.registerCount
    let unregisters = fixture.agent.unregisterCount
    let probes = fixture.probe.ports.count
    let signals = fixture.signals.signalsSent.filter { $0.signal != 0 }.count

    // 全局模式仍保存规则默认动作，但它不改变全局 ACL。
    await fixture.controller.setRuleDefaultAction(.directWhenUnmatched)

    #expect(fixture.settings.saved?.ruleDefaultAction == .directWhenUnmatched)
    #expect(fixture.controller.proxyMode == .global)
    #expect(fixture.controller.state == .running)
    #expect(try Data(contentsOf: fixture.runtimeStore.fileURL) == bytes)
    #expect(fixture.agent.registerCount == registers)
    #expect(fixture.agent.unregisterCount == unregisters)
    #expect(fixture.signals.signalsSent.filter { $0.signal != 0 }.count == signals)
    #expect(fixture.probe.ports.count == probes + (systemProxyEnabled ? 2 : 0))
  }

  @MainActor
  private struct Fixture {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    let agent = ProxyRuntimeFixture.FakeLaunchAgent()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let settings = ModeRestoreSettingsStore()
    let signals = ProxyRuntimeControllerTests.SignalRecorder()
    let runtimeStore: RuntimeFileStore
    let controller: ProxyRuntimeController
    let server: NodeID

    init(
      systemProxyEnabled: Bool,
      snapshots: BuiltinRuleSnapshots = BuiltinRuleSnapshots(
        loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
    ) throws {
      let credentials = InMemoryCredentialStore()
      var catalog = ConfigurationCatalog()
      server = try ActivationFixture.addPlainServer("收敛测试", in: &catalog)
      let catalogURL = runtime.directory.appendingPathComponent("catalog.json")
      try makeTestCatalogStore(fileURL: catalogURL).save(CatalogDocument(catalog: catalog))
      runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
      let store = runtimeStore
      let recorder = signals
      agent.onUnregister = { recorder.terminateWrapper() }
      agent.onRegister = {
        recorder.relaunchWrapper()
        if let document = store.loadDocument() {
          try? store.writeRuntimeReceipt(for: document, processID: 42)
        }
      }
      recorder.reloadReceipt = {
        if let document = store.loadDocument() {
          try? store.writeRuntimeReceipt(for: document, processID: 42)
        }
      }
      controller = ProxyRuntimeController(
        catalogSnapshotReader: ProxyRuntimeFixture.catalogSnapshotReader(at: catalogURL),
        activationFileStore: ActivationStateFileStore(
          fileURL: runtime.directory.appendingPathComponent("activation.json")),
        runtimeFileStore: runtimeStore, credentials: credentials,
        plugins: ActivationFixture.plugins, settingsStore: settings,
        customRuleStore: CustomRuleStore(
          fileURL: runtime.directory.appendingPathComponent("rules.json")),
        appBundle: AppArtifact.bundle, ruleSnapshots: snapshots,
        settingsRestore: RestoredProxySettings(
          settings: ProxySettings(
            listen: ActivationFixture.listen, preferredMode: .global,
            agentEnabled: true, systemProxyEnabled: systemProxyEnabled),
          unreadableError: nil),
        agent: agent, probe: probe, systemProxy: proxy,
        systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
        proxyMode: .global, firewallChecker: ProxyRuntimeFixture.FakeFirewallChecker(),
        launchHealthTimeoutSeconds: 0.05,
        launchHealthRetryDelay: { await Task.yield() },
        systemProxyHealthPollIntervalNanoseconds: 60_000_000_000,
        helperRefreshDelayNanoseconds: 0,
        sendSignal: { recorder.send($0, $1) },
        processIsAlive: { recorder.send($0, 0) == 0 })
    }

    func cleanUp() {
      controller.systemProxyObserver.systemProxyHealthTask?.cancel()
      controller.cancelFirewallObservation()
      try? FileManager.default.removeItem(at: runtime.directory)
    }
  }
}

private final class ModeRestoreSettingsStore: ProxySettingsStoring {
  private let store = InMemoryProxySettingsStore()
  var rejectGlobalMode = false
  var saved: ProxySettings? { store.saved }

  func load() throws -> ProxySettings { try store.load() }

  func save(_ settings: ProxySettings) throws {
    if rejectGlobalMode && settings.preferredMode == .global {
      throw ProxySettingsStoreError.ioFailure(detail: "restore fixture failure")
    }
    try store.save(settings)
  }
}
