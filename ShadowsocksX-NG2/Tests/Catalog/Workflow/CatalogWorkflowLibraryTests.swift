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
      fileStore: CatalogFileStore(fileURL: url), runtime: runtime)
    let workflow = makeCatalogWorkflow(
      coordinator: coordinator, credentials: InMemoryCredentialStore())
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
    func makeStore(_ credentials: ServerLibraryCredentials) -> CatalogFileStore {
      CatalogFileStore(
        fileURL: url,
        library: ServerLibraryStorage(
          credentials: credentials, keys: keys, legacyCredentials: InMemoryCredentialStore()))
    }
    let original = makeStore(ServerLibraryCredentials())
    _ = try original.load()
    var catalog = ConfigurationCatalog()
    _ = try catalog.addGroup("saved-group")
    try original.save(CatalogDocument(catalog: catalog))
    let encrypted = try Data(contentsOf: url)
    keys.requiresInteraction = true
    let credentials = ServerLibraryCredentials()
    let store = makeStore(credentials)
    let runtime = FakeCatalogRuntime()
    let coordinator = CatalogCommitCoordinator(fileStore: store, runtime: runtime)
    let workflow = makeCatalogWorkflow(coordinator: coordinator, credentials: credentials)
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
    let credentials = ServerLibraryCredentials()
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: credentials, keys: keys, legacyCredentials: InMemoryCredentialStore()))
    _ = try store.load()
    var catalog = ConfigurationCatalog()
    _ = try catalog.addGroup("saved-group")
    try store.save(CatalogDocument(catalog: catalog))
    let encrypted = try Data(contentsOf: url)
    let runtime = FakeCatalogRuntime()
    runtime.hasActiveTarget = true
    let coordinator = CatalogCommitCoordinator(fileStore: store, runtime: runtime)
    let workflow = makeCatalogWorkflow(coordinator: coordinator, credentials: credentials)
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
    let bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: CatalogFileStore(fileURL: url))
    let agent = ProxyRuntimeFixture.FakeLaunchAgent(initialStatus: .registered)
    let controller = ProxyRuntimeController(
      catalogSnapshotReader: bootstrap.catalogSnapshotReader, activationFileStore: activation,
      runtimeFileStore: RuntimeFileStore(fileURL: runtimeURL),
      credentials: InMemoryCredentialStore(),
      settingsRestore: RestoredProxySettings(
        settings: ProxySettings(agentEnabled: true), unreadableError: nil),
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
    let credentials = ServerLibraryCredentials()
    let fixture = try CatalogFixtures.makeSubscriptionFixture(prefix: "edit-url")
    let record = SubscriptionRecord(
      id: NodeID.fresh(), groupID: fixture.groupID,
      urlRef: CredentialReference.fresh(), status: .never)
    let document = CatalogDocument(catalog: fixture.catalog, subscriptions: [record])
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: credentials, keys: keys, legacyCredentials: InMemoryCredentialStore()))
    _ = try store.load()
    for ref in document.libraryCredentialReferences {
      try credentials.save("sample-password", for: ref)
    }
    try credentials.save("https://old.example/sub", for: record.urlRef)
    try store.save(document)
    let fetcher = GatedFetcher()
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()),
      credentials: credentials, subscriptionFetcher: fetcher)
    let refresh = Task { await workflow.refreshSubscription(record.id) }
    await fetcher.waitUntilEntered()
    try await workflow.editSubscriptionURL(record.id, urlString: "https://new.example/sub")
    let restoredCredentials = ServerLibraryCredentials()
    let restored = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: restoredCredentials, keys: keys, legacyCredentials: InMemoryCredentialStore()))
    _ = try restored.load()
    #expect(try restoredCredentials.secret(for: record.urlRef) == "https://new.example/sub")
    fetcher.releaseAll()
    await refresh.value
  }

}
