import Foundation

@testable import ShadowsocksX_NG2

@MainActor
func makeHealthCheckSupersessionController(
  runtime: ProxyRuntimeFixture.TemporaryRuntime, catalogFile: URL, plugins: PluginCatalog,
  agent: ProxyRuntimeFixture.FakeLaunchAgent, probe: ProxyRuntimeFixture.BlockingProbe
) -> ProxyRuntimeController {
  let directory = runtime.directory
  let files = RuntimeFileStore(fileURL: runtime.contract)
  agent.onRegister = {
    try? files.writePublishedRuntimeReceipt(processID: 42)
  }
  return ProxyRuntimeController(
    controlPreferences: makeTestProxyControlPreferences(),
    catalogSnapshotReader: ProxyRuntimeFixture.catalogSnapshotReader(at: catalogFile),
    activationFileStore: ActivationStateFileStore(
      fileURL: directory.appendingPathComponent("activation.json")),
    runtimeFileStore: files, plugins: plugins,
    listeningStore: InMemoryProxyListeningStore(),
    customRuleStore: CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json")),
    appBundle: AppArtifact.bundle,
    ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
    settingsRestore: RestoredProxyRuntimeSettings(
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: true),
      unreadableError: nil),
    agent: agent, probe: probe, systemProxy: ProxyRuntimeFixture.FakeSystemProxy(),
    systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
    firewallChecker: ProxyRuntimeFixture.FakeFirewallChecker(),
    sendSignal: { _, _ in 0 }, processIsAlive: { $0 == 42 })
}
