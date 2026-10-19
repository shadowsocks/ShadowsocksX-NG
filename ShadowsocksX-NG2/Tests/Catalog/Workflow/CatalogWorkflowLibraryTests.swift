import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct CatalogWorkflowLibraryTests {
  @Test func failedLoadPreventsEditsAndPreservesFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("catalog.json")
    let damaged = Data("damaged-library".utf8)
    try damaged.write(to: url)
    let runtime = FakeCatalogRuntime()
    runtime.hasActiveTarget = true
    let coordinator = CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(fileURL: url), runtime: runtime)
    let workflow = makeCatalogWorkflow(
      coordinator: coordinator)
    await #expect(throws: (any Error).self) {
      try await workflow.createGroup(named: "must-not-save", into: nil)
    }
    #expect(try Data(contentsOf: url) == damaged)
    #expect(runtime.convergeCount == 0)
  }
  @Test func explicitUnlockLoadsLibraryAndResumesRuntime() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    func makeStore() -> CatalogFileStore {
      CatalogFileStore(
        fileURL: url,
        library: ServerLibraryStorage(
          keys: keys))
    }
    let original = makeStore()
    _ = try original.load()
    var catalog = ConfigurationCatalog()
    _ = try catalog.addGroup("saved-group")
    try original.save(CatalogDocument(catalog: catalog))
    let encrypted = try Data(contentsOf: url)
    keys.requiresInteraction = true
    let store = makeStore()
    let runtime = FakeCatalogRuntime()
    let coordinator = CatalogCommitCoordinator(fileStore: store, runtime: runtime)
    let workflow = makeCatalogWorkflow(coordinator: coordinator)
    #expect(workflow.libraryFailure == .authorization(-25308))
    #expect(!coordinator.committedCatalog.contains(catalog.rootChildren[0]))
    #expect(runtime.convergeCount == 0)
    await withCheckedContinuation { continuation in
      runtime.onNextConverge = { continuation.resume() }
      workflow.unlockLibrary()
    }
    #expect(workflow.libraryFailure == nil)
    #expect(workflow.tree.roots.first?.name == "saved-group")
    #expect(try Data(contentsOf: url) == encrypted)
    #expect(runtime.convergeCount == 1)
  }

  @Test func failedResetPreservesOldLibraryAndSuccessfulResetUsesNewKey() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        keys: keys))
    _ = try store.load()
    var catalog = ConfigurationCatalog()
    _ = try catalog.addGroup("saved-group")
    try store.save(CatalogDocument(catalog: catalog))
    let encrypted = try Data(contentsOf: url)
    let runtime = FakeCatalogRuntime()
    runtime.hasActiveTarget = true
    let coordinator = CatalogCommitCoordinator(fileStore: store, runtime: runtime)
    let workflow = makeCatalogWorkflow(coordinator: coordinator)
    keys.createFails = true
    workflow.resetLibrary()
    #expect(workflow.libraryFailure != nil)
    #expect(try Data(contentsOf: url) == encrypted)
    #expect(workflow.tree.roots.first?.name == "saved-group")
    #expect(runtime.convergeCount == 0)
    keys.createFails = false
    await withCheckedContinuation { continuation in
      runtime.onNextConverge = { continuation.resume() }
      workflow.resetLibrary()
    }
    #expect(workflow.libraryFailure == nil)
    #expect(workflow.tree.roots.isEmpty)
    #expect(try store.load().catalog.isEmpty)
    #expect(keys.values.count == 2)
    #expect(runtime.convergeSnapshots.last?.catalog.isEmpty == true)
  }

  @Test func failedLoadDoesNotClearActiveTargetOrRewriteRuntimeOnLaunch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("catalog.json")
    try Data("broken-library".utf8).write(to: url)
    let activation = ActivationStateFileStore(
      fileURL: directory.appendingPathComponent("activation.json"))
    let target = NodeID(rawValue: "existing-target")
    try activation.save(activeTargetID: target)
    let runtimeURL = directory.appendingPathComponent("sslocal-active.json")
    let previousContract = Data("existing-runtime-contract".utf8)
    try previousContract.write(to: runtimeURL)
    let bootstrap = CatalogCommitCoordinator.bootstrap(
      fileStore: makeTestCatalogStore(fileURL: url))
    let agent = ProxyRuntimeFixture.FakeLaunchAgent(initialStatus: .registered)
    let controller = ProxyRuntimeController(
      controlPreferences: makeTestProxyControlPreferences(),
      catalogSnapshotReader: bootstrap.catalogSnapshotReader, activationFileStore: activation,
      runtimeFileStore: RuntimeFileStore(fileURL: runtimeURL),
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(agentEnabled: true), unreadableError: nil),
      agent: agent)
    await controller.resyncOnLaunch()
    await controller.convergeAgent()
    #expect(try activation.loadActiveTargetID() == target)
    #expect(controller.activeTargetID == target)
    #expect(try Data(contentsOf: runtimeURL) == previousContract)
    #expect(agent.registerCount == 0)
    #expect(agent.unregisterCount == 0)
  }

  @Test func editedSubscriptionURLPersistsWhileRefreshIsInProgress() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let fixture = try CatalogFixtures.makeSubscriptionFixture(prefix: "edit-url")
    let record = SubscriptionRecord(
      id: NodeID.fresh(), groupID: fixture.groupID,
      url: "https://old.example/sub", status: .never)
    let document = CatalogDocument(catalog: fixture.catalog, subscriptions: [record])
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        keys: keys))
    _ = try store.load()
    try store.save(document)
    let fetcher = GatedFetcher()
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()),
      subscriptionFetcher: fetcher)
    let refresh = Task { await workflow.refreshSubscription(record.id) }
    await fetcher.waitUntilEntered()
    try await workflow.editSubscriptionURL(record.id, urlString: "https://new.example/sub")
    let restored = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        keys: keys))
    _ = try restored.load()
    #expect(try restored.load().subscriptions.first?.url == "https://new.example/sub")
    fetcher.releaseAll()
    await refresh.value
  }

  @Test func failedURLSaveDoesNotFetchOrPublishAndFailedRefreshKeepsSecrets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeTestCatalogStore(fileURL: directory.appendingPathComponent("gate/catalog.enc"))
    let fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.tree()))
    let runtime = FakeCatalogRuntime()
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: runtime),
      subscriptionFetcher: fetcher)
    let subscription = try await workflow.createSubscription(urlString: "https://old.example/sub")
    let server = try #require(
      workflow.tree.node(withID: subscription.groupID)?.childNodes
        .first(where: { !$0.isGroup }))
    let before = try #require(try workflow.serverEditForm(for: server.id))
    let requests = fetcher.requestCount
    let gate = directory.appendingPathComponent("gate")
    try FileManager.default.removeItem(at: gate)
    try Data().write(to: gate)
    await #expect(throws: (any Error).self) {
      try await workflow.editSubscriptionURL(subscription.id, urlString: "https://new.example/sub")
    }
    #expect(try workflow.subscriptionURL(for: subscription.id) == "https://old.example/sub")
    #expect(fetcher.requestCount == requests)
    #expect(runtime.convergeCount == 0)
    fetcher.setBehavior(
      .success(
        Data(
          String(decoding: SubscriptionDocs.tree(), as: UTF8.self)
            .replacingOccurrences(of: "\"pa\"", with: "\"changed-password\"").utf8)))
    await workflow.refreshSubscription(subscription.id)
    let after = try #require(try workflow.serverEditForm(for: server.id))
    #expect(after.password == before.password)
    #expect(after.plugin.options == before.plugin.options)
    #expect(workflow.subscriptionRefreshFailure(for: subscription.id) == .commit)
  }

}
