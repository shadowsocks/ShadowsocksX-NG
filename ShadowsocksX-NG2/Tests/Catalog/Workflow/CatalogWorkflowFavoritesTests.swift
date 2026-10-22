import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct CatalogWorkflowFavoritesTests {
  @Test(arguments: [false, true], [false, true])
  func textImportSelectsNewNodeIncludingPartialSuccess(partial: Bool, intoGroup: Bool) async throws
  {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let parent =
      intoGroup ? try await fixture.workflow.createGroup(named: "Existing", into: nil) : nil
    let uri = "ss://YWVzLTI1Ni1nY206cHc@203.0.113.7:8388#New"
    let outcome = await fixture.workflow.importServers(
      from: [.clipboardText(partial ? uri + "\ninvalid" : uri)], into: parent)
    let children =
      parent.flatMap { fixture.workflow.tree.node(withID: $0)?.childNodes }
      ?? fixture.workflow.tree.roots
    let added = try #require(children.first)
    #expect(outcome.newNodeSelectionCandidate == added.id)
    #expect(fixture.workflow.favoriteIDs.isEmpty)
  }

  @Test func legacyImportPreservesExistingFavorites() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let group = try await fixture.workflow.createGroup(named: "Existing", into: nil)
    try fixture.workflow.setFavorite(group, isFavorite: true)
    let snapshot = try LegacySnapshot(propertyList: [
      "ServerProfiles": [
        [
          "ServerHost": "203.0.113.8", "ServerPort": 8388,
          "Method": "aes-256-gcm", "Password": "fixture", "Remark": "Imported",
        ]
      ]
    ])
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: fixture.store, runtime: fixture.runtime),
      legacyImportService: LegacyImportService(
        source: FixedLegacySnapshotProvider(snapshot: snapshot), catalogStore: fixture.store,
        marker: InMemoryLegacyImportMarker()))
    let outcome = try await workflow.importLegacy()
    #expect(outcome.report.importedServerCount == 1)
    #expect(workflow.favoriteIDs == [group])
    #expect(fixture.reloaded().favoriteIDs == [group])
  }

  @Test(arguments: [1, 2, 3, 4, 5])
  func historicalDocumentsAreRejected(version: Int) throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let json =
      "{\"version\":\(version),\"rootChildren\":[],\"entries\":[],\"subscriptions\":[],\"favoriteIDs\":[]}"
    #expect(throws: CatalogFileStore.PersistenceError.self) {
      try CatalogFileStore.decode(Data(json.utf8))
    }
  }

  @Test func failedSavesKeepTheCommittedOrder() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let first = try await fixture.workflow.createGroup(named: "First", into: nil)
    let second = try await fixture.workflow.createGroup(named: "Second", into: nil)
    try fixture.workflow.setFavorite(first, isFavorite: true)
    try fixture.workflow.setFavorite(second, isFavorite: true)
    let originalData = try CatalogFileStore.encode(fixture.store.load())
    let gate = fixture.store.fileURL.deletingLastPathComponent()
    let backup = fixture.directory.appendingPathComponent("backup")
    try FileManager.default.moveItem(at: gate, to: backup)
    try Data().write(to: gate)

    #expect(throws: (any Error).self) {
      try fixture.workflow.moveFavorite(second, before: first)
    }
    #expect(throws: (any Error).self) {
      try fixture.workflow.setFavorite(first, isFavorite: false)
    }
    #expect(fixture.workflow.favoriteIDs == [first, second])
    try FileManager.default.removeItem(at: gate)
    try FileManager.default.moveItem(at: backup, to: gate)
    #expect(try CatalogFileStore.encode(fixture.store.load()) == originalData)
    #expect(fixture.reloaded().favoriteIDs == [first, second])
  }

  @Test func invalidReorderTargetsLeaveFavoritesUnchanged() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let group = try await fixture.workflow.createGroup(named: "Group", into: nil)
    try fixture.workflow.setFavorite(group, isFavorite: true)
    let missing = NodeID(rawValue: "missing")
    #expect(throws: CatalogError.nodeNotFound(missing)) {
      try fixture.workflow.moveFavorite(group, before: missing)
    }
    #expect(throws: CatalogError.nodeNotFound(missing)) {
      try fixture.workflow.setFavorite(missing, isFavorite: true)
    }
    try fixture.workflow.moveFavorite(group, before: group)
    #expect(fixture.reloaded().favoriteIDs == [group])
  }

  @Test func subscriptionRefreshPreservesSurvivorsAndNeverRestoresRemovedFavorites() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let summary = try await fixture.workflow.createSubscription(
      urlString: "https://example.com/sub.json")
    let group = try #require(fixture.workflow.tree.node(withID: summary.groupID))
    let nestedNode = group.childNodes.first { $0.isGroup }
    let nested = try #require(nestedNode)
    let server = try #require(nested.childNodes.first)
    for id in [server.id, summary.groupID, nested.id] {
      try fixture.workflow.setFavorite(id, isFavorite: true)
    }

    fixture.fetcher.setBehavior(.success(SubscriptionDocs.treeRenamedAndReordered()))
    await fixture.workflow.refreshSubscription(summary.id)
    #expect(fixture.workflow.favoriteIDs == [server.id, summary.groupID, nested.id])

    fixture.fetcher.setBehavior(.success(Data("invalid".utf8)))
    await fixture.workflow.refreshSubscription(summary.id)
    #expect(fixture.reloaded().favoriteIDs == [server.id, summary.groupID, nested.id])

    fixture.fetcher.setBehavior(.success(SubscriptionDocs.flat(serverCount: 0)))
    await fixture.workflow.refreshSubscription(summary.id)
    #expect(fixture.reloaded().favoriteIDs == [summary.groupID])
    fixture.fetcher.setBehavior(.success(SubscriptionDocs.tree()))
    await fixture.workflow.refreshSubscription(summary.id)
    #expect(fixture.workflow.tree.containsNode(server.id))
    #expect(fixture.workflow.favoriteIDs == [summary.groupID])

    try fixture.workflow.setFavorite(server.id, isFavorite: true)
    _ = try await fixture.workflow.removeSubscription(summary.id)
    #expect(fixture.reloaded().favorites.isEmpty)
  }

  @Test func importingNewNodesDoesNotInheritFavorites() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let uri = "ss://YWVzLTI1Ni1nY206cHc@203.0.113.7:8388#Same"
    _ = await fixture.workflow.importServers(from: [.clipboardText(uri)], into: nil)
    let first = try #require(fixture.workflow.tree.roots.first)
    try fixture.workflow.setFavorite(first.id, isFavorite: true)
    _ = await fixture.workflow.importServers(from: [.clipboardText(uri)], into: nil)
    #expect(fixture.workflow.tree.roots.count == 2)
    #expect(fixture.workflow.favoriteIDs == [first.id])
  }

  @Test(arguments: [["group", "group"], ["missing"]])
  func inconsistentFavoritesCannotBeLoaded(ids: [String]) throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    var catalog = ConfigurationCatalog()
    try catalog.addGroup("Group", id: NodeID(rawValue: "group"))
    try fixture.store.save(CatalogDocument(catalog: catalog))
    let raw = try JSONSerialization.jsonObject(with: CatalogFileStore.encode(fixture.store.load()))
    var payload = try #require(raw as? [String: Any])
    payload["favoriteIDs"] = ids
    let invalid = try JSONSerialization.data(withJSONObject: payload)
    #expect(throws: CatalogFileStore.PersistenceError.self) { try CatalogFileStore.decode(invalid) }
  }

  @Test func directoryEditsPreserveFavoritesAndRemovalCleansDescendants() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let parent = try await fixture.workflow.createGroup(named: "Parent", into: nil)
    let child = try await fixture.workflow.createGroup(named: "Child", into: parent)
    let other = try await fixture.workflow.createGroup(named: "Other", into: nil)
    for id in [child, parent, other] {
      try fixture.workflow.setFavorite(id, isFavorite: true)
    }
    try await fixture.workflow.renameGroup(child, to: "Renamed")
    try await fixture.workflow.move(parent, to: other)
    let copy = try await fixture.workflow.duplicate(parent, nameSuffix: "Copy")
    #expect(fixture.workflow.favorites.map(\.id) == [child, parent, other])
    #expect(fixture.workflow.favorites.first?.name == "Renamed")
    #expect(!fixture.workflow.isFavorite(copy))

    _ = try await fixture.workflow.remove(parent)
    #expect(fixture.workflow.favoriteIDs == [other])
    #expect(fixture.reloaded().favoriteIDs == [other])
  }

  @Test func reorderingAndRefavoritingChangeOnlyFavorites() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let first = try await fixture.workflow.createGroup(named: "First", into: nil)
    let second = try await fixture.workflow.createGroup(named: "Second", into: nil)
    let third = try await fixture.workflow.createGroup(named: "Third", into: nil)
    let originalTree = fixture.workflow.tree
    fixture.runtime.hasActiveTarget = true
    for id in [first, second, third] {
      try fixture.workflow.setFavorite(id, isFavorite: true)
    }

    try fixture.workflow.moveFavorite(third, before: first)
    #expect(fixture.workflow.favorites.map(\.id) == [third, first, second])
    try fixture.workflow.moveFavorite(third, before: nil)
    #expect(fixture.workflow.favorites.map(\.id) == [first, second, third])
    try fixture.workflow.setFavorite(second, isFavorite: false)
    try fixture.workflow.setFavorite(second, isFavorite: true)
    #expect(fixture.reloaded().favorites.map(\.id) == [first, third, second])
    #expect(fixture.workflow.tree == originalTree)
    #expect(fixture.workflow.runtimeSync == .idle)
    await Task.yield()
    #expect(fixture.runtime.convergeCount == 0)
  }

  @Test func favoritesAreUniqueOrderedAndRestored() async throws {
    let fixture = try FavoritesFixture()
    defer { fixture.cleanUp() }
    let first = try await fixture.workflow.createGroup(named: "First", into: nil)
    let second = try await fixture.workflow.createGroup(named: "Second", into: first)

    try fixture.workflow.setFavorite(first, isFavorite: true)
    try fixture.workflow.setFavorite(second, isFavorite: true)
    try fixture.workflow.setFavorite(first, isFavorite: true)

    #expect(fixture.workflow.favorites.map(\.id) == [first, second])
    #expect(fixture.reloaded().favorites.map(\.id) == [first, second])
  }
}

@MainActor
private struct FavoritesFixture {
  let directory: URL
  let store: CatalogFileStore
  let runtime = FakeCatalogRuntime()
  let fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.tree()))
  let workflow: CatalogWorkflow

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("favorites-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let gate = directory.appendingPathComponent("gate", isDirectory: true)
    try FileManager.default.createDirectory(at: gate, withIntermediateDirectories: true)
    store = makeTestCatalogStore(fileURL: gate.appendingPathComponent("catalog.json"))
    workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: runtime),
      plugins: NoManagedPluginProvider(), subscriptionFetcher: fetcher)
  }

  func reloaded() -> CatalogWorkflow {
    makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: runtime),
      plugins: NoManagedPluginProvider(), subscriptionFetcher: fetcher)
  }

  func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}
