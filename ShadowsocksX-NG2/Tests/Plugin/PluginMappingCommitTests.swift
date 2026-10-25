import Foundation
import Testing
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
struct PluginMappingCommitTests {
  @Test func savedTransportModeUpdatesActiveRuntime() async throws {
    let fixture = try PluginMappingCommitFixture()
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.group)
    var record = try #require(fixture.plugins.userRecords.first { $0.names.contains("tool") })
    record.mode = .tcpAndUDP
    try fixture.plugins.commit([.save(record)])
    _ = await fixture.nextApplication()
    #expect(
      fixture.files.loadDocument()?.servers.first { $0.plugin != nil }?.pluginMode == .tcpAndUDP)
    #expect(fixture.controller.state == .running)
    record.mode = .tcpOnly
    try fixture.plugins.commit([.save(record)])
    _ = await fixture.nextApplication()
    #expect(fixture.files.loadDocument()?.servers.first { $0.plugin != nil }?.pluginMode == nil)
  }

  @Test func runtimeFailureDoesNotUndoSavedMapping() async throws {
    let fixture = try PluginMappingCommitFixture()
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.group)
    #expect(fixture.controller.state == .running)
    try FileManager.default.removeItem(at: fixture.files.pidFileURL)
    fixture.agent.registerError = NSError(domain: "PluginMappingCommitTests", code: 1)
    try fixture.plugins.updatePlugin(program: "tool", path: fixture.second.path)
    let outcome = await fixture.nextApplication()
    guard case .failed = outcome else {
      Issue.record("Expected runtime failure after the mapping was saved")
      return
    }
    #expect(fixture.plugins.testMappings["tool"] == fixture.second.path)
    let restored = PluginCatalog(store: fixture.store, inspector: CommitPluginInspector())
    #expect(restored.resolve(program: "tool")?.path == fixture.second.path)
  }

  @Test func unrelatedAndIdenticalMappingsDoNotRestartHealthyRuntime() async throws {
    let fixture = try PluginMappingCommitFixture()
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.group)
    #expect(fixture.controller.state == .running)
    let registered = fixture.agent.registerCount
    let unregistered = fixture.agent.unregisterCount
    let signals = fixture.signals.count
    let deployed = try #require(fixture.files.readData())
    try fixture.plugins.addPlugin(program: "unused", path: fixture.second.path)
    _ = await fixture.nextApplication()
    #expect(fixture.agent.registerCount == registered)
    #expect(fixture.agent.unregisterCount == unregistered)
    #expect(fixture.signals.count == signals)
    #expect(fixture.files.readData() == deployed)
    let generation = fixture.plugins.catalogSnapshot().generation
    try fixture.plugins.updatePlugin(program: "unused", path: fixture.second.path)
    await fixture.drainMainQueue()
    #expect(fixture.plugins.catalogSnapshot().generation == generation)
    #expect(fixture.agent.registerCount == registered)
    #expect(fixture.agent.unregisterCount == unregistered)
    #expect(fixture.signals.count == signals)
  }

  @Test func mappingRemovalRevalidatesGroupBeforeRuntimeApplication() async throws {
    let fixture = try PluginMappingCommitFixture()
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.group)
    #expect(fixture.controller.state == .running)
    try fixture.plugins.removePlugin(program: "tool")
    let group = try #require(fixture.workflow.tree.roots.first)
    #expect(group.invalidDescendantCount == 1)
    #expect(
      group.find(fixture.pluginServer)?.invalidReasons == [.pluginNotProvided(program: "tool")])
    #expect(group.find(fixture.plainServer)?.isInvalid == false)
    _ = await fixture.nextApplication()
    #expect(fixture.controller.activeTargetID == fixture.group)
    #expect(
      fixture.controller.skippedServers == [
        SkippedServer(id: fixture.pluginServer, reason: .pluginNotProvided(program: "tool"))
      ])
    let document = try #require(fixture.files.loadDocument())
    #expect(document.servers.count == 1)
    #expect(document.servers.first?.password == "pw-Plain")
    #expect(fixture.controller.state == .running)
  }

  @Test(arguments: [false, true])
  func newerMappingWinsBeforeApplicationAndDuringHealthCheck(inFlight: Bool) async throws {
    let fixture = try PluginMappingCommitFixture()
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.group)
    #expect(fixture.controller.state == .running)
    let started = XCTestExpectation(description: "mapping A entered health check")
    if inFlight { fixture.probe.arm(started: started) }
    try fixture.plugins.updatePlugin(program: "tool", path: fixture.second.path)
    if inFlight {
      let result = await XCTWaiter.fulfillment(of: [started], timeout: 3)
      #expect(result == .completed)
    }
    try fixture.plugins.updatePlugin(program: "tool", path: fixture.third.path)
    fixture.probe.release()
    _ = await fixture.nextApplication()
    if inFlight { _ = await fixture.nextApplication() }
    #expect(fixture.plugins.testMappings["tool"] == fixture.third.path)
    #expect(
      try fixture.store.load().userPlugins.first { $0.names.contains("tool") }?.path
        == fixture.third.path)
    #expect(fixture.files.loadDocument()?.servers.first?.plugin == fixture.third.path)
    #expect(fixture.controller.state == .running)
    if !inFlight { #expect(fixture.applicationPaths == [fixture.third.path]) }
  }

  @Test func atomicWriteFailurePreservesCommittedFactsAndDoesNotApply() async throws {
    let fixture = try PluginMappingCommitFixture()
    defer { fixture.cleanUp() }
    try await fixture.controller.activate(fixture.group)
    let generation = fixture.plugins.catalogSnapshot().generation
    let tree = fixture.workflow.tree
    let contract = fixture.files.readData()
    let registered = fixture.agent.registerCount
    let mappingsDirectory = fixture.store.fileURL.deletingLastPathComponent()
    let backup = fixture.directory.appendingPathComponent("saved-mappings")
    try FileManager.default.moveItem(at: mappingsDirectory, to: backup)
    try Data("blocks temporary file creation".utf8).write(to: mappingsDirectory)
    #expect(throws: (any Error).self) {
      try fixture.plugins.updatePlugin(program: "tool", path: fixture.second.path)
    }
    #expect(fixture.plugins.testMappings["tool"] == fixture.first.path)
    #expect(fixture.plugins.catalogSnapshot().generation == generation)
    #expect(fixture.workflow.tree == tree)
    #expect(fixture.agent.registerCount == registered)
    #expect(fixture.files.readData() == contract)
    await fixture.drainMainQueue()
    #expect(fixture.applicationStarts == 0)
    #expect(fixture.applicationPaths.isEmpty)
    try FileManager.default.removeItem(at: mappingsDirectory)
    try FileManager.default.moveItem(at: backup, to: mappingsDirectory)
    #expect(
      try fixture.store.load().userPlugins.first { $0.names.contains("tool") }?.path
        == fixture.first.path)
  }

}

private struct CommitPluginInspector: PluginInspecting {
  func inspect(_ executable: URL) async -> PluginSecurityFacts {
    PluginSecurityFacts(quarantine: .absent, signature: .notApplicable, policy: .notApplicable)
  }
}

/// Production commit wiring with private files and controllable runtime effects.
@MainActor
private final class PluginMappingCommitFixture {
  let directory: URL
  let first: URL
  let second: URL
  let third: URL
  let store: PluginMappingFileStore
  let plugins: PluginCatalog
  let files: RuntimeFileStore
  let agent: ProxyRuntimeFixture.FakeLaunchAgent
  let probe: ProxyRuntimeFixture.BlockingProbe
  let signals: CommitSignals
  let controller: ProxyRuntimeController
  let workflow: CatalogWorkflow
  let group: NodeID
  let pluginServer: NodeID
  let plainServer: NodeID
  private(set) var applicationStarts = 0
  private(set) var applicationPaths: [String] = []
  private var applications: AsyncStream<RuntimeSyncOutcome>.Iterator

  init() throws {
    let setup = try makePluginMappingCommitSetup()
    directory = setup.runtime.directory
    first = setup.first
    second = setup.second
    third = setup.third
    store = setup.store
    plugins = setup.plugins
    files = setup.files
    agent = setup.agent
    probe = setup.probe
    signals = setup.signals
    controller = setup.controller
    workflow = setup.workflow
    group = setup.group
    pluginServer = setup.pluginServer
    plainServer = setup.plainServer
    let stream = AsyncStream<RuntimeSyncOutcome>.makeStream()
    applications = stream.stream.makeAsyncIterator()
    connectPluginCatalog(stream.continuation)
  }

  private func connectPluginCatalog(
    _ continuation: AsyncStream<RuntimeSyncOutcome>.Continuation
  ) {
    let controller = controller
    let workflow = workflow
    let files = files
    plugins.connect(
      invalidateRuntime: { [weak controller] in controller?.pluginMappingsDidPublish() },
      revalidate: { [weak workflow] in workflow?.republishCommittedState() },
      converge: { [weak self, weak controller] in
        guard let controller else { return }
        self?.applicationStarts += 1
        let outcome = await controller.catalogDidCommit(
          snapshot: controller.catalogSnapshotReader.catalogSnapshot)
        if let path = files.loadDocument()?.servers.first?.plugin {
          self?.applicationPaths.append(path)
        }
        continuation.yield(outcome)
      })
  }

  func nextApplication() async -> RuntimeSyncOutcome? {
    var iterator = applications
    let outcome = await iterator.next(isolation: MainActor.shared)
    applications = iterator
    return outcome
  }

  /// Observe jobs already submitted to the main executor before asserting no application.
  func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  func cleanUp() {
    probe.release()
    try? FileManager.default.removeItem(at: directory)
  }
}

private final class CommitSignals: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded = 0

  var count: Int { lock.withLock { recorded } }

  func record() { lock.withLock { recorded += 1 } }
}

@MainActor
private struct PluginMappingCommitSetup {
  let runtime: ProxyRuntimeFixture.TemporaryRuntime
  let first: URL
  let second: URL
  let third: URL
  let store: PluginMappingFileStore
  let plugins: PluginCatalog
  let files: RuntimeFileStore
  let agent: ProxyRuntimeFixture.FakeLaunchAgent
  let probe: ProxyRuntimeFixture.BlockingProbe
  let signals: CommitSignals
  let controller: ProxyRuntimeController
  let workflow: CatalogWorkflow
  let group: NodeID
  let pluginServer: NodeID
  let plainServer: NodeID
}

@MainActor
private struct PluginMappingCatalogSetup {
  let fileStore: CatalogFileStore
  let bootstrap: CatalogCommitBootstrap
  let group: NodeID
  let pluginServer: NodeID
  let plainServer: NodeID
}

@MainActor
private struct PluginMappingControllerContext {
  let directory: URL
  let bootstrap: CatalogCommitBootstrap
  let files: RuntimeFileStore
  let plugins: PluginCatalog
  let agent: ProxyRuntimeFixture.FakeLaunchAgent
  let probe: ProxyRuntimeFixture.BlockingProbe
  let signals: CommitSignals
}

@MainActor
private func makePluginMappingCommitSetup() throws -> PluginMappingCommitSetup {
  let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
  let first = runtime.directory.appendingPathComponent("first")
  let second = runtime.directory.appendingPathComponent("second")
  let third = runtime.directory.appendingPathComponent("third")
  try installPluginCommitExecutables([first, second, third])
  let store = PluginMappingFileStore(
    fileURL: runtime.directory.appendingPathComponent("mappings/plugins.json"))
  let plugins = PluginCatalog(store: store, inspector: CommitPluginInspector())
  try plugins.addPlugin(program: "tool", path: first.path)
  let catalog = try makePluginMappingCatalogSetup(in: runtime.directory)
  let files = RuntimeFileStore(fileURL: runtime.contract)
  let agent = ProxyRuntimeFixture.FakeLaunchAgent()
  let probe = ProxyRuntimeFixture.BlockingProbe()
  let signals = CommitSignals()
  agent.onRegister = {
    try? Data("42".utf8).write(to: files.pidFileURL)
    try? files.writePublishedRuntimeReceipt(processID: 42)
  }
  let controller = makePluginMappingCommitController(
    PluginMappingControllerContext(
      directory: runtime.directory, bootstrap: catalog.bootstrap, files: files,
      plugins: plugins, agent: agent, probe: probe, signals: signals))
  let workflow = makeCatalogWorkflow(
    coordinator: CatalogCommitCoordinator(
      fileStore: catalog.fileStore, runtime: ProxyRuntimeSyncAdapter(controller: controller),
      bootstrap: catalog.bootstrap), plugins: plugins)
  return PluginMappingCommitSetup(
    runtime: runtime, first: first, second: second, third: third, store: store,
    plugins: plugins, files: files, agent: agent, probe: probe, signals: signals,
    controller: controller, workflow: workflow, group: catalog.group,
    pluginServer: catalog.pluginServer, plainServer: catalog.plainServer)
}

private func installPluginCommitExecutables(_ binaries: [URL]) throws {
  for binary in binaries {
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
  }
}

@MainActor
private func makePluginMappingCatalogSetup(in directory: URL) throws -> PluginMappingCatalogSetup {
  let store = makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json"))
  var catalog = ConfigurationCatalog()
  let group = try catalog.addGroup("Group")
  let pluginServer = try ActivationFixture.addPlainServer("Plugin", to: group, in: &catalog)
  let plainServer = try ActivationFixture.addPlainServer("Plain", to: group, in: &catalog)
  guard case .server(var fields) = try #require(catalog.entry(for: pluginServer)).kind else {
    throw CocoaError(.fileReadCorruptFile)
  }
  fields.pluginProgram = "tool"
  try catalog.updateServer(pluginServer, with: fields)
  try store.save(CatalogDocument(catalog: catalog))
  return PluginMappingCatalogSetup(
    fileStore: store, bootstrap: CatalogCommitCoordinator.bootstrap(fileStore: store),
    group: group, pluginServer: pluginServer, plainServer: plainServer)
}

@MainActor
private func makePluginMappingCommitController(
  _ context: PluginMappingControllerContext
) -> ProxyRuntimeController {
  let directory = context.directory
  let bootstrap = context.bootstrap
  let files = context.files
  let plugins = context.plugins
  let agent = context.agent
  let probe = context.probe
  let signals = context.signals
  let contractURL = files.fileURL
  return ProxyRuntimeController(
    controlPreferences: makeTestProxyControlPreferences(),
    catalogSnapshotReader: bootstrap.catalogSnapshotReader,
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
    launchHealthTimeoutSeconds: 0.2,
    launchHealthRetryDelay: { try await Task.sleep(for: .milliseconds(10)) },
    sendSignal: { _, signal in
      guard signal != 0 else { return 0 }
      signals.record()
      let store = RuntimeFileStore(fileURL: contractURL)
      try? store.writePublishedRuntimeReceipt(processID: 42)
      return 0
    }, processIsAlive: { $0 == 42 })
}
