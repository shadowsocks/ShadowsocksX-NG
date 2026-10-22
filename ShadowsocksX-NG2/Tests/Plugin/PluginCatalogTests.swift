import Foundation
import Testing
import XCTest

@testable import ShadowsocksX_NG2

struct QuietPluginInspector: PluginInspecting {
  func inspect(_ executable: URL) async -> PluginSecurityFacts {
    PluginSecurityFacts(quarantine: .absent, signature: .notApplicable, policy: .notApplicable)
  }
}

struct PluginCatalogTests {
  @Test func invalidOverrideDoesNotUseManagedExecutable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let snapshot = PluginCatalogSnapshot(
      mappings: ["v2ray-plugin": root.appendingPathComponent("missing").path],
      managed: BundleManagedPluginProvider(bundleURL: root))
    #expect(snapshot.resolve(program: "v2ray-plugin")?.path == nil)
    #expect(snapshot.entry(for: "v2ray-plugin")?.source == .user)
  }
  @Test @MainActor func savedMappingIsUsedAndRemovalRemovesCustomName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("custom-plugin")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let catalog = PluginCatalog(store: store, inspector: QuietPluginInspector())
    try catalog.addPlugin(program: "custom-plugin", path: binary.path)
    #expect(catalog.catalogSnapshot().resolve(program: "custom-plugin")?.path == binary.path)
    #expect(
      PluginCatalog(store: store, inspector: QuietPluginInspector()).catalogSnapshot().entry(
        for: "custom-plugin")?.source == .user)
    try catalog.removePlugin(program: "custom-plugin")
    #expect(catalog.catalogSnapshot().entry(for: "custom-plugin") == nil)
  }

  @Test @MainActor func userPluginCanBeSavedThroughServerFormInterface() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("custom-plugin")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let plugins = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      inspector: QuietPluginInspector())
    try plugins.addPlugin(program: "custom-plugin", path: binary.path)
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), plugins: plugins)
    let id = try await workflow.createServer(
      ServerEditDraft(
        address: "127.0.0.1", port: 8388, encryptionMethod: "aes-256-gcm", password: "pw",
        remark: "Custom", plugin: .named(program: "custom-plugin"), pluginOptions: "flag"),
      into: nil)
    #expect(try workflow.serverEditForm(for: id)?.plugin.options == "flag")
    let presentation = try #require(workflow.serverFormPresentation(for: id))
    #expect(
      presentation.plugin.programs.contains { $0.program == "custom-plugin" && $0.source == .user })
  }

  @Test @MainActor func commitPublishesBeforeSchedulingRuntimeApplication() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("custom-plugin")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let catalog = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      inspector: QuietPluginInspector())
    var events: [String] = []
    let applied = AsyncStream<Void>.makeStream()
    catalog.connect(
      invalidateRuntime: { events.append("invalidate") },
      revalidate: { events.append("publish") },
      converge: {
        events.append("apply")
        applied.continuation.yield(())
      })
    try catalog.addPlugin(program: "custom-plugin", path: binary.path)
    #expect(events == ["invalidate", "publish"])
    for await _ in applied.stream { break }
    #expect(events == ["invalidate", "publish", "apply"])
  }

  @Test @MainActor func corruptionBlocksManagedResolutionUntilExplicitRepair() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let file = root.appendingPathComponent("plugins.json")
    try Data("broken".utf8).write(to: file)
    let catalog = PluginCatalog(
      store: PluginMappingFileStore(fileURL: file),
      managed: BundleManagedPluginProvider(bundleURL: root), inspector: QuietPluginInspector())
    #expect(catalog.catalogSnapshot().mappingsUnreadable)
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), plugins: catalog)
    #expect(
      workflow.newFormPluginSection(selection: .named(program: "v2ray-plugin")).mappingsUnreadable)

    #expect(catalog.resolve(program: "v2ray-plugin")?.path == nil)
    #expect(catalog.catalogSnapshot().entry(for: "v2ray-plugin")?.source == .unknown)
    #expect(throws: PluginMappingError.unreadable) { try catalog.commit([]) }
    try catalog.replaceTestMappings([:])
    #expect(catalog.resolve(program: "v2ray-plugin")?.path == binary.path)
  }

  @Test @MainActor func failedPersistenceDoesNotPublishOrInvalidateRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let catalog = PluginCatalog(store: FailingMappingStore(), inspector: QuietPluginInspector())
    var published = false
    catalog.connect(
      invalidateRuntime: { published = true }, revalidate: { published = true }, converge: {})
    #expect(throws: PluginMappingError.unreadable) {
      try catalog.addPlugin(program: "tool", path: binary.path)
    }
    #expect(!published)
    #expect(catalog.catalogSnapshot().generation == 0)
    #expect(catalog.catalogSnapshot().entry(for: "tool") == nil)
  }

  @Test @MainActor func symlinkAndCaseSensitiveNamesSurviveAtomicRename() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)
    let catalog = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      inspector: QuietPluginInspector())
    try catalog.addPlugin(program: " Tool ", path: link.path)
    #expect(catalog.resolve(program: "Tool")?.path == link.path)
    #expect(catalog.resolve(program: "tool")?.path == nil)
    let captured = catalog.catalogSnapshot()
    try catalog.renamePlugin(program: "Tool", newProgram: "Other", path: link.path)
    #expect(catalog.resolve(program: "Tool")?.path == nil)
    #expect(captured.resolve(program: "Tool")?.path == link.path)
    try FileManager.default.removeItem(at: binary)
    #expect(catalog.resolve(program: "Other")?.path == nil)
    try catalog.removePlugin(program: "Other")
    #expect(catalog.catalogSnapshot().entry(for: "Other") == nil)
  }

  @Test @MainActor func mappingAdoptionRefreshesOnlyPluginDraft() throws {
    let id = NodeID.fresh()
    let fields = ServerFormFields()
    var plugin = PluginSectionState(
      selection: .unknown(program: "tool"), programs: [], mappingsUnreadable: false,
      optionsPresent: true, options: "")
    let original = ServerEditForm(
      address: "127.0.0.1", port: 8388, encryptionMethod: "aes-256-gcm", password: "pw",
      remark: "Original", plugin: plugin, isEditable: true)
    fields.showServer(id) { _ in original }
    fields.remark = "Unsaved name"
    plugin = PluginSectionState(
      selection: .named(program: "tool"),
      programs: [.init(program: "tool", source: .user, availability: .available)],
      mappingsUnreadable: false,
      optionsPresent: true, options: "flag")
    let mapped = ServerEditForm(
      address: original.address, port: original.port, encryptionMethod: original.encryptionMethod,
      password: original.password, remark: original.remark, plugin: plugin, isEditable: true)
    fields.updatePresentation(
      ServerFormPresentation(isEditable: true, plugin: plugin), load: { _ in mapped })
    #expect(fields.remark == "Unsaved name")
    #expect(fields.pluginChoice == .named(program: "tool"))
    #expect(fields.pluginOptions.composedString == "flag")
    #expect(fields.hasChanges)
  }

  @Test @MainActor func changedMappingSupersedesInFlightRuntimeHealthCheck() async throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let first = runtime.directory.appendingPathComponent("first-plugin")
    let second = runtime.directory.appendingPathComponent("second-plugin")
    for binary in [first, second] {
      try Data("#!/bin/sh\n".utf8).write(to: binary)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }
    let plugins = PluginCatalog(
      store: PluginMappingFileStore(
        fileURL: runtime.directory.appendingPathComponent("plugins.json")),
      inspector: QuietPluginInspector())
    try plugins.addPlugin(program: "tool", path: first.path)
    var catalog = ConfigurationCatalog()
    let id = try ActivationFixture.addPlainServer("Plugin", in: &catalog)
    var fields = try #require(catalog.entry(for: id)).serverFieldsForPluginTest
    fields.pluginProgram = "tool"
    try catalog.updateServer(id, with: fields)
    let catalogFile = runtime.directory.appendingPathComponent("catalog.json")
    try makeTestCatalogStore(fileURL: catalogFile).save(CatalogDocument(catalog: catalog))
    let agent = ProxyRuntimeFixture.FakeLaunchAgent()
    let files = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = {
      try? files.writePublishedRuntimeReceipt(processID: 42)
    }
    let probe = ProxyRuntimeFixture.BlockingProbe()
    let controller = ProxyRuntimeController(
      controlPreferences: makeTestProxyControlPreferences(),
      catalogSnapshotReader: ProxyRuntimeFixture.catalogSnapshotReader(at: catalogFile),
      activationFileStore: ActivationStateFileStore(
        fileURL: runtime.directory.appendingPathComponent("activation.json")),
      runtimeFileStore: files, plugins: plugins,
      listeningStore: InMemoryProxyListeningStore(),
      customRuleStore: CustomRuleStore(
        fileURL: runtime.directory.appendingPathComponent("rules.json")),
      appBundle: AppArtifact.bundle,
      ruleSnapshots: BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot),
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: true),
        unreadableError: nil),
      agent: agent, probe: probe, systemProxy: ProxyRuntimeFixture.FakeSystemProxy(),
      systemProxyHelper: ProxyRuntimeFixture.FakeSystemProxyHelperService(),
      firewallChecker: ProxyRuntimeFixture.FakeFirewallChecker(),
      sendSignal: { _, _ in 0 }, processIsAlive: { $0 == 42 })
    let started = XCTestExpectation(description: "old runtime entered health check")
    probe.arm(started: started)
    let oldActivation = Task { try await controller.activate(id) }
    let wait = await XCTWaiter.fulfillment(of: [started], timeout: 3)
    #expect(wait == .completed)
    let applied = AsyncStream<Void>.makeStream()
    plugins.connect(
      invalidateRuntime: { controller.pluginMappingsDidPublish() }, revalidate: {},
      converge: {
        _ = await controller.catalogDidCommit(snapshot: catalog)
        applied.continuation.yield(())
      })
    try plugins.updatePlugin(program: "tool", path: second.path)
    probe.release()
    _ = try await oldActivation.value
    for await _ in applied.stream { break }
    #expect(files.loadDocument()?.servers.first?.plugin == second.path)
    #expect(controller.state == .running)
  }

}

struct PluginCatalogSecurityTests {
  @Test(arguments: ["unchanged", "replace", "remove", "permissions"])
  @MainActor func inspectionEvidenceFollowsCurrentMappingAndFile(change: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let inspector = HeldPluginInspector()
    let catalog = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      inspector: inspector)
    try catalog.addPlugin(program: "tool", path: binary.path)
    let check = catalog.refreshSecurityFacts()
    var started = inspector.started.makeAsyncIterator()
    _ = await started.next()
    if change == "replace" {
      try Data("#!/bin/sh\n# replacement\n".utf8).write(to: binary, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    } else if change == "permissions" {
      try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binary.path)
    } else if change == "remove" {
      try catalog.removePlugin(program: "tool")
    }
    await inspector.release()
    await check.value
    if change == "unchanged" {
      #expect(catalog.securityFacts["tool"]?.policy == .rejected)
      #expect(catalog.resolve(program: "tool")?.path == binary.path)
    } else {
      #expect(catalog.securityFacts["tool"] == nil)
      #expect(
        catalog.resolve(program: "tool")?.path
          == (["remove", "permissions"].contains(change) ? nil : binary.path))
    }
  }

  @Test func symlinkTargetsMustBeExecutableFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let directoryLink = root.appendingPathComponent("directory-link")
    let missingLink = root.appendingPathComponent("missing-link")
    try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: root)
    try FileManager.default.createSymbolicLink(
      at: missingLink, withDestinationURL: root.appendingPathComponent("missing"))
    let snapshot = PluginCatalogSnapshot(
      mappings: ["directory": directoryLink.path, "missing": missingLink.path])
    #expect(snapshot.entry(for: "directory")?.availability == .notExecutable)
    #expect(snapshot.entry(for: "missing")?.availability == .missing)
    #expect(snapshot.resolve(program: "directory")?.path == nil)
    #expect(snapshot.resolve(program: "missing")?.path == nil)
  }

  @Test func failedFileInspectionIsDistinctFromMissingFile() {
    let snapshot = PluginCatalogSnapshot(
      mappings: ["tool": "/unreadable/tool"],
      managed: BundleManagedPluginProvider(fileManager: UnreadablePluginFileManager()))
    #expect(snapshot.entry(for: "tool")?.availability == .unreadable)
    #expect(snapshot.resolve(program: "tool")?.path == nil)
  }

  /// 用户来源条目在生产映射中恒无版本（managedInfo 为 nil），
  /// 报告行内显示来源标签而不是版本号。
  @Test func userDiagnosticFactsShowSourceLabelInsteadOfVersion() {
    var snapshot = DiagnosticSnapshot()
    snapshot.managedPlugins = [
      DiagnosticPluginFacts(program: "v2ray-plugin", version: "", present: true, source: .user)
    ]
    let report = DiagnosticReportBuilder.markdown(from: snapshot)
    #expect(report.contains("v2ray-plugin user"))
  }

}

private struct FailingMappingStore: PluginMappingStoring {
  func load() throws -> PluginConfiguration { PluginConfiguration() }
  func save(_ configuration: PluginConfiguration) throws { throw PluginMappingError.unreadable }
}

extension CatalogEntry {
  fileprivate var serverFieldsForPluginTest: ServerFields {
    guard case .server(let fields) = kind else { preconditionFailure("expected server") }
    return fields
  }
}

private actor HeldPluginInspector: PluginInspecting {
  nonisolated let started: AsyncStream<Void>
  private let signal: AsyncStream<Void>.Continuation
  private var pending: CheckedContinuation<PluginSecurityFacts, Never>?

  init() {
    let stream = AsyncStream<Void>.makeStream()
    started = stream.stream
    signal = stream.continuation
  }

  func inspect(_ executable: URL) async -> PluginSecurityFacts {
    await withCheckedContinuation { continuation in
      pending = continuation
      signal.yield(())
    }
  }

  func release() {
    pending?.resume(
      returning: PluginSecurityFacts(
        quarantine: .present, signature: .unsigned, policy: .rejected))
    pending = nil
  }
}

private final class UnreadablePluginFileManager: FileManager, @unchecked Sendable {
  override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
    throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
  }
}

/// Server-form behavior through workflow and draft interfaces.
struct PluginFormCatalogTests {
  @Test(arguments: [
    PluginCatalogSnapshot.Availability.available, .missing, .notExecutable, .unreadable,
  ])
  @MainActor func formRetainsAvailabilityForNewlySelectedPlugin(
    availability: PluginCatalogSnapshot.Availability
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = PluginCatalogSnapshot(entries: [
      .init(
        program: "tool", path: "/private/tool", source: .user,
        availability: availability, managedInfo: nil)
    ])
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), plugins: snapshot)
    let form = workflow.newFormPluginSection(selection: .named(program: "tool"))
    #expect(form.programs.first?.source == .user)
    #expect(form.programs.first?.availability == availability)
    #expect(!form.mappingsUnreadable)
  }

  @Test @MainActor func missingUnsavedChoiceHasUnresolvedPresentation() {
    let plugin = PluginSectionState(
      selection: .named(program: "saved"),
      programs: [.init(program: "saved", source: .managed, availability: .available)],
      mappingsUnreadable: false, optionsPresent: true, options: "flag")
    let form = ServerEditForm(
      address: "127.0.0.1", port: 8388,
      encryptionMethod: "aes-256-gcm", password: "pw", remark: "Original",
      plugin: plugin, isEditable: true)
    let fields = ServerFormFields()
    fields.showServer(.fresh()) { _ in form }
    fields.pluginChoice = .named(program: "removed")
    fields.pluginOptions.load("host=unsaved")
    fields.updatePresentation(ServerFormPresentation(isEditable: true, plugin: plugin))
    #expect(fields.pluginChoice == .named(program: "removed"))
    #expect(fields.presentation?.plugin.unresolvedProgram(for: fields.pluginChoice) == "removed")
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    #expect(plugin.unresolvedProgram(for: .none) == nil)
    #expect(plugin.unresolvedProgram(for: .named(program: "saved")) == nil)
  }

  @Test @MainActor func mappingRemovalAndOverrideChangesPreserveServerDraft() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let managedBinary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: managedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: managedBinary)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: managedBinary.path)
    let plugins = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      managed: BundleManagedPluginProvider(bundleURL: root), inspector: QuietPluginInspector())
    try plugins.addPlugin(program: "tool", path: managedBinary.path)
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), plugins: plugins)
    let id = try await workflow.createServer(
      ServerEditDraft(
        address: "127.0.0.1", port: 8388, encryptionMethod: "aes-256-gcm",
        password: "pw", remark: "Original", plugin: .named(program: "tool"), pluginOptions: "flag"),
      into: nil)
    let fields = ServerFormFields()
    fields.showServer(id, load: workflow.serverEditForm)
    fields.remark = "Unsaved"
    fields.pluginOptions.load("host=unsaved")
    try plugins.removePlugin(program: "tool")
    fields.updatePresentation(
      workflow.serverFormPresentation(for: id), load: workflow.serverEditForm)
    #expect(fields.pluginChoice == .unknown(program: "tool"))
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    try plugins.addPlugin(program: "tool", path: managedBinary.path)
    fields.updatePresentation(
      workflow.serverFormPresentation(for: id), load: workflow.serverEditForm)
    #expect(fields.pluginChoice == .named(program: "tool"))
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    #expect(try workflow.serverEditForm(for: id)?.plugin.options == "flag")
    #expect(fields.remark == "Unsaved")

    // An unsaved choice disappearing must retain a selectable unresolved reference.
    fields.pluginChoice = .named(program: "tool")
    try plugins.removePlugin(program: "tool")
    fields.updatePresentation(
      workflow.serverFormPresentation(for: id), load: workflow.serverEditForm)
    #expect(fields.presentation?.plugin.unresolvedProgram(for: .named(program: "tool")) == "tool")
    #expect(
      workflow.newFormPluginSection(selection: .named(program: "tool"))
        .unresolvedProgram(for: .named(program: "tool")) == "tool")
    #expect(fields.pluginOptions.composedString == "host=unsaved")

    fields.pluginChoice = .named(program: "v2ray-plugin")
    try plugins.addPlugin(program: "v2ray-plugin", path: managedBinary.path)
    fields.updatePresentation(
      workflow.serverFormPresentation(for: id), load: workflow.serverEditForm)
    #expect(
      fields.presentation?.plugin.programs.first { $0.program == "v2ray-plugin" }?.source == .user)
    try plugins.removePlugin(program: "v2ray-plugin")
    fields.updatePresentation(
      workflow.serverFormPresentation(for: id), load: workflow.serverEditForm)
    #expect(
      fields.presentation?.plugin.programs.first { $0.program == "v2ray-plugin" }?.source
        == .managed)
    #expect(fields.pluginChoice == .named(program: "v2ray-plugin"))
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    #expect(fields.remark == "Unsaved")
  }

}
