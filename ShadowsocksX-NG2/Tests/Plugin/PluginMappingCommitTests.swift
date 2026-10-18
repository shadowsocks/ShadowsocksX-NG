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
  let agent = ProxyRuntimeFixture.FakeLaunchAgent()
  let probe = ProxyRuntimeFixture.BlockingProbe()
  let signals = CommitSignals()
  let controller: ProxyRuntimeController
  let workflow: CatalogWorkflow
  let group: NodeID
  let pluginServer: NodeID
  let plainServer: NodeID
  private(set) var applicationStarts = 0
  private(set) var applicationPaths: [String] = []
  private var applications: AsyncStream<RuntimeSyncOutcome>.Iterator

  init() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    directory = runtime.directory
    first = directory.appendingPathComponent("first")
    second = directory.appendingPathComponent("second")
    third = directory.appendingPathComponent("third")
    for binary in [first, second, third] {
      try Data("#!/bin/sh\n".utf8).write(to: binary)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }
    store = PluginMappingFileStore(
      fileURL: directory.appendingPathComponent("mappings/plugins.json"))
    plugins = PluginCatalog(store: store, inspector: CommitPluginInspector())
    try plugins.addPlugin(program: "tool", path: first.path)
    let credentials = InMemoryCredentialStore()
    var catalog = ConfigurationCatalog()
    group = try catalog.addGroup("Group")
    pluginServer = try ActivationFixture.addPlainServer(
      "Plugin", to: group, in: &catalog)
    plainServer = try ActivationFixture.addPlainServer(
      "Plain", to: group, in: &catalog)
    guard case .server(var fields) = try #require(catalog.entry(for: pluginServer)).kind else {
      throw CocoaError(.fileReadCorruptFile)
    }
    fields.pluginProgram = "tool"
    try catalog.updateServer(pluginServer, with: fields)
    let catalogStore = makeTestCatalogStore(
      fileURL: directory.appendingPathComponent("catalog.json"))
    try catalogStore.save(CatalogDocument(catalog: catalog))
    let bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: catalogStore)
    files = RuntimeFileStore(fileURL: runtime.contract)
    let files = files
    agent.onRegister = {
      try? Data("42".utf8).write(to: files.pidFileURL)
      if let document = files.loadDocument() {
        try? files.writeRuntimeReceipt(for: document, processID: 42)
      }
    }
    let contractURL = files.fileURL
    let signals = signals
    controller = ProxyRuntimeController(
      catalogSnapshotReader: bootstrap.catalogSnapshotReader,
      activationFileStore: ActivationStateFileStore(
        fileURL: directory.appendingPathComponent("activation.json")),
      runtimeFileStore: files, credentials: credentials, plugins: plugins,
      settingsStore: InMemoryProxySettingsStore(),
      customRuleStore: CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json")),
      appBundle: AppArtifact.bundle,
      ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: true),
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
        if let document = store.loadDocument() {
          try? store.writeRuntimeReceipt(for: document, processID: 42)
        }
        return 0
      }, processIsAlive: { $0 == 42 })
    workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: catalogStore, runtime: ProxyRuntimeSyncAdapter(controller: controller),
        bootstrap: bootstrap), plugins: plugins)
    let stream = AsyncStream<RuntimeSyncOutcome>.makeStream()
    applications = stream.stream.makeAsyncIterator()
    let controller = controller
    let workflow = workflow
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
        stream.continuation.yield(outcome)
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
