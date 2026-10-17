import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityFormalRuntimeTests {
  @Test func changingTestURLDoesNotConvergeTheRunningFormalProxy() async throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let credentials = InMemoryCredentialStore()
    let agent = ProxyRuntimeFixture.FakeLaunchAgent()
    let systemProxy = ProxyRuntimeFixture.FakeSystemProxy()
    let store = SettingsWorkflowTests.InMemorySettingsStore()
    let fileStore = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = {
      if let document = fileStore.loadDocument() {
        try? fileStore.writeRuntimeReceipt(for: document, processID: 42)
      }
    }
    let controller = ProxyRuntimeController(
      catalogSnapshotReader: ProxyRuntimeFixture.catalogSnapshotReader(
        at: runtime.directory.appendingPathComponent("catalog.json")),
      activationFileStore: ActivationStateFileStore(
        fileURL: runtime.directory.appendingPathComponent("activation.json")),
      runtimeFileStore: fileStore, credentials: credentials, plugins: ActivationFixture.plugins,
      settingsStore: store,
      customRuleStore: CustomRuleStore(
        fileURL: runtime.directory.appendingPathComponent("rules.json")),
      appBundle: AppArtifact.bundle,
      ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(listen: ActivationFixture.listen), unreadableError: nil),
      agent: agent,
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), systemProxy: systemProxy,
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      launchHealthTimeoutSeconds: 0.05,
      sendSignal: { _, _ in 0 }, processIsAlive: { $0 == 42 })
    await controller.setAgentEnabled(true)
    let state = controller.state
    let calls = agent.registerCount
    let target = controller.activeTargetID
    let document = try Data(contentsOf: runtime.contract)
    let workflow = SettingsWorkflow(committing: controller, credentials: credentials)
    #expect(await workflow.saveConnectivityURL("http://example.com/probe?token=private"))
    #expect(controller.state == state)
    #expect(controller.activeTargetID == target)
    #expect(agent.registerCount == calls)
    #expect(agent.unregisterCount == 0)
    #expect(systemProxy.applied.isEmpty)
    #expect(try Data(contentsOf: runtime.contract) == document)
  }
}
