import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 通过模式命令验证配置派生失败和无 ACL 变化路径，不调用恢复实现。
@MainActor
struct RuntimeConvergenceTests {
  @Test(arguments: [false, true])
  func modeAndRuleChangesUseLatestCommittedCatalog(savedRules: Bool) async throws {
    let fixture = try Fixture(systemProxyEnabled: false)
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    if savedRules { await fixture.controller.setProxyMode(.rule) }
    var catalog = fixture.catalogReader.catalogSnapshot
    var fields = ActivationFixture.plainFields(remark: "更新资料", password: "updated-password")
    fields.address = "198.51.100.9"
    try catalog.updateServer(fixture.server, with: fields)
    try makeTestCatalogStore(
      fileURL: fixture.runtime.directory.appendingPathComponent("catalog.json")
    )
    .save(CatalogDocument(catalog: catalog))
    fixture.catalogReader.catalogSnapshot = catalog

    if savedRules {
      await fixture.controller.convergeRuntime(.savedRules)
    } else {
      await fixture.controller.setProxyMode(.direct)
    }

    let output = try #require(fixture.runtimeStore.loadDocument())
    #expect(output.servers.first?.server == "198.51.100.9")
    #expect(output.servers.first?.password == "updated-password")
    #expect(fixture.controller.state == .running)
  }

  @Test func modeDerivationFailurePreservesNewIntentAndPublishedFiles() async throws {
    let fixture = try Fixture(
      systemProxyEnabled: true,
      snapshots: BuiltinRuleSnapshots(loader: { _ in throw RuleSnapshotError.missing }))
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    let previous = try #require(fixture.runtimeStore.loadDocument())
    let appliedCount = fixture.proxy.applied.count

    await fixture.controller.setProxyMode(.rule)

    #expect(fixture.controller.proxyMode == .rule)
    #expect(fixture.controller.settings.preferredMode == .rule)
    #expect(fixture.runtimeStore.loadDocument() == previous)
    #expect(
      fixture.controller.state
        == .serviceFailed(.runtimeFile))
    #expect(fixture.controller.controlPreferences.preferredMode == .rule)
    #expect(fixture.controller.systemProxyState == .applied)
    #expect(fixture.proxy.applied.count == appliedCount)
    #expect(fixture.proxy.clearCount == 0)
  }

  @Test func publishedFailureSurvivesGUIReconstructionAndExplicitRetryWorks() async throws {
    let fixture = try Fixture(systemProxyEnabled: true)
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    fixture.probe.setOutcomes([.refused(detail: "test failure")])
    await fixture.controller.setProxyMode(.direct)
    #expect(fixture.controller.proxyMode == .direct)
    #expect(fixture.controller.settings.agentEnabled)
    #expect(fixture.controller.settings.systemProxyEnabled)
    #expect(!fixture.controller.state.isOn)
    #expect(fixture.proxy.clearCount > 0)
    let failure = try #require(fixture.runtimeStore.readFailure())
    let requested = try #require(fixture.runtimeStore.loadDocument())
    #expect(requested.aclRuntime?.summary == "direct")
    let registerCount = fixture.agent.registerCount
    fixture.probe.setOutcomes([.reachable])
    await fixture.controller.resyncOnLaunch()
    #expect(fixture.agent.registerCount == registerCount)
    #expect(fixture.runtimeStore.readFailure() == failure)
    // 文件存取对象重建后仍使用磁盘失败身份，而非控制器中的瞬时状态。
    let reopened = RuntimeFileStore(fileURL: fixture.runtimeStore.fileURL)
    #expect(reopened.readFailure()?.deploymentID == reopened.receiptIdentity(for: requested))
    await fixture.controller.setAgentEnabled(true)
    #expect(fixture.controller.state == .running)
    #expect(fixture.runtimeStore.readFailure() == nil)
    #expect(fixture.agent.registerCount > registerCount)
  }

  @Test(arguments: ["configuration", "acl", "intent"])
  func missingResourcesCannotTurnGUIRestartIntoRetry(resource: String) async throws {
    let fixture = try Fixture(systemProxyEnabled: true)
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    fixture.probe.setOutcomes([.refused(detail: "failure")])
    await fixture.controller.setProxyMode(.direct)
    let snapshot = try #require(
      RuntimePublication.load(at: fixture.runtimeStore.supervisionFileURL))
    let name =
      resource == "configuration"
      ? snapshot.configuration
      : resource == "intent" ? snapshot.intentMetadata : try #require(snapshot.acl?.file)
    try FileManager.default.removeItem(at: fixture.runtime.directory.appendingPathComponent(name))
    let count = fixture.agent.registerCount
    let restarted = fixture.reopeningController()
    defer {
      restarted.systemProxyObserver.systemProxyHealthTask?.cancel()
      restarted.cancelFirewallObservation()
    }
    fixture.probe.setOutcomes([.reachable])
    await restarted.resyncOnLaunch()
    #expect(fixture.agent.registerCount == count)
    #expect(restarted.state == .serviceFailed(.agent))
    #expect(fixture.runtimeStore.readFailure()?.deploymentID == snapshot.deploymentID)
    await restarted.setAgentEnabled(true)
    #expect(restarted.state == .running)
    #expect(fixture.agent.registerCount > count)
  }

  @Test(arguments: [false, true])
  func unchangedModeACLDoesNotReprobeHealthyListeners(
    systemProxyEnabled: Bool
  ) async throws {
    let fixture = try Fixture(systemProxyEnabled: systemProxyEnabled)
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.server)
    try Data("42".utf8).write(to: fixture.runtime.pidFile)
    let bytes = try Data(contentsOf: fixture.runtimeStore.fileURL)
    let registers = fixture.agent.registerCount
    let unregisters = fixture.agent.unregisterCount
    let probes = fixture.probe.ports.count
    let signals = fixture.signals.signalsSent.filter { $0.signal != 0 }.count

    // 全局模式仍保存规则默认动作，但它不改变全局 ACL。
    await fixture.controller.setRuleDefaultAction(.directWhenUnmatched)

    #expect(fixture.controller.controlPreferences.ruleDefaultAction == .directWhenUnmatched)
    #expect(fixture.controller.proxyMode == .global)
    #expect(fixture.controller.state == .running)
    #expect(try Data(contentsOf: fixture.runtimeStore.fileURL) == bytes)
    #expect(fixture.agent.registerCount == registers)
    #expect(fixture.agent.unregisterCount == unregisters)
    #expect(fixture.signals.signalsSent.filter { $0.signal != 0 }.count == signals)
    #expect(fixture.probe.ports.count == probes)
  }

  @MainActor
  private final class CatalogReader: RuntimeCatalogSnapshotReading {
    var catalogSnapshot: ConfigurationCatalog
    init(_ catalog: ConfigurationCatalog) { catalogSnapshot = catalog }
  }

  @MainActor
  private struct Fixture {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    let agent = ProxyRuntimeFixture.FakeLaunchAgent()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let proxy = ProxyRuntimeFixture.FakeSystemProxy()
    let settings = InMemoryProxyListeningStore()
    let signals = ProxyRuntimeControllerTests.SignalRecorder()
    let runtimeStore: RuntimeFileStore
    let controller: ProxyRuntimeController
    let server: NodeID
    let catalogReader: CatalogReader

    init(
      systemProxyEnabled: Bool,
      snapshots: BuiltinRuleSnapshots = BuiltinRuleSnapshots(
        loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
    ) throws {
      var catalog = ConfigurationCatalog()
      server = try ActivationFixture.addPlainServer("收敛测试", in: &catalog)
      let catalogURL = runtime.directory.appendingPathComponent("catalog.json")
      try makeTestCatalogStore(fileURL: catalogURL).save(CatalogDocument(catalog: catalog))
      catalogReader = CatalogReader(catalog)
      runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
      let store = runtimeStore
      let recorder = signals
      agent.onUnregister = { recorder.terminateWrapper() }
      agent.onRegister = {
        recorder.relaunchWrapper()
        try? store.writePublishedRuntimeReceipt(processID: 42)
      }
      recorder.reloadReceipt = {
        try? store.writePublishedRuntimeReceipt(processID: 42)
      }
      controller = ProxyRuntimeController(
        controlPreferences: makeTestProxyControlPreferences(),
        catalogSnapshotReader: catalogReader,
        activationFileStore: ActivationStateFileStore(
          fileURL: runtime.directory.appendingPathComponent("activation.json")),
        runtimeFileStore: runtimeStore,
        plugins: ActivationFixture.plugins, listeningStore: settings,
        customRuleStore: CustomRuleStore(
          fileURL: runtime.directory.appendingPathComponent("rules.json")),
        appBundle: AppArtifact.bundle, ruleSnapshots: snapshots,
        settingsRestore: RestoredProxyRuntimeSettings(
          settings: ProxyRuntimeSettings(
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

    func reopeningController() -> ProxyRuntimeController {
      ProxyRuntimeController(
        controlPreferences: makeTestProxyControlPreferences(),
        catalogSnapshotReader: controller.catalogSnapshotReader,
        activationFileStore: controller.activationFileStore,
        runtimeFileStore: runtimeStore,
        plugins: ActivationFixture.plugins, listeningStore: settings,
        customRuleStore: CustomRuleStore(
          fileURL: runtime.directory.appendingPathComponent("rules.json")),
        appBundle: AppArtifact.bundle,
        ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
        settingsRestore: RestoredProxyRuntimeSettings(
          settings: controller.settings, unreadableError: nil),
        agent: agent, probe: probe, systemProxy: proxy,
        systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
        firewallChecker: ProxyRuntimeFixture.FakeFirewallChecker(),
        launchHealthTimeoutSeconds: 0.05, launchHealthRetryDelay: { await Task.yield() },
        systemProxyHealthPollIntervalNanoseconds: 60_000_000_000,
        helperRefreshDelayNanoseconds: 0,
        sendSignal: { [signals] in signals.send($0, $1) },
        processIsAlive: { [signals] in signals.send($0, 0) == 0 })
    }

    func cleanUp() {
      controller.systemProxyObserver.systemProxyHealthTask?.cancel()
      controller.cancelFirewallObservation()
      try? FileManager.default.removeItem(at: runtime.directory)
    }
  }
}
