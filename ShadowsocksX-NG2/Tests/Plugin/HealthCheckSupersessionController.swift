import Foundation

@testable import ShadowsocksX_NG2

@MainActor
struct HealthCheckSupersessionControllerContext {
  let directory: URL
  let catalogFile: URL
  let files: RuntimeFileStore
  let plugins: PluginCatalog
  let agent: ProxyRuntimeFixture.FakeLaunchAgent
  let probe: ProxyRuntimeFixture.BlockingProbe
}

@MainActor
func makeHealthCheckSupersessionController(
  _ context: HealthCheckSupersessionControllerContext
) -> ProxyRuntimeController {
  let directory = context.directory
  let catalogFile = context.catalogFile
  let files = context.files
  let plugins = context.plugins
  let agent = context.agent
  let probe = context.probe
  ProxyRuntimeController(
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
