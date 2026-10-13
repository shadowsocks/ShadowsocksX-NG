import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityCatalogTests {
  @Test func targetScopesExpandFavoriteGroupsWithoutChangingCatalogOrActivation() async throws {
    let subscription = try CatalogFixtures.makeSubscriptionFixture(prefix: UUID().uuidString)
    var catalog = subscription.catalog
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("Local")
    let nested = try catalog.addGroup("Nested", to: group)
    let firstTarget = try ActivationFixture.addPlainServer(
      "A", to: group, in: &catalog, credentials: credentials)
    let secondTarget = try ActivationFixture.addPlainServer(
      "B", to: nested, in: &catalog, credentials: credentials)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CatalogFileStore(fileURL: directory.appendingPathComponent("catalog.json"))
    try store.save(CatalogDocument(catalog: catalog))
    let runtime = FakeCatalogRuntime()
    let coordinator = CatalogCommitCoordinator(fileStore: store, runtime: runtime)
    let workflow = makeCatalogWorkflow(coordinator: coordinator, credentials: credentials)
    try workflow.setFavorite(group, isFavorite: true)
    try workflow.setFavorite(secondTarget, isFavorite: true)
    #expect(workflow.connectivityTargets(source: .manual) == [secondTarget, firstTarget])
    #expect(
      workflow.connectivityTargets(source: .subscription)
        == Array(subscription.serverIDs.reversed()))
    #expect(workflow.connectivityTargets(source: nil) == [secondTarget, firstTarget])
    #expect(
      workflow.tree.node(withID: group)?.connectivityServerIDs == [secondTarget, firstTarget])
    let before = try Data(contentsOf: store.fileURL)
    let tree = workflow.tree
    let version = workflow.connectivityRevision(for: firstTarget)
    let derived = try workflow.connectivityConfiguration(for: firstTarget)
    #expect(derived.id == firstTarget.rawValue)
    #expect(derived.password == "pw-A")
    #expect(runtime.convergeCount == 0)
    #expect(workflow.tree == tree)
    #expect(try Data(contentsOf: store.fileURL) == before)
    let fields = try #require(catalog.entry(for: firstTarget))
    guard case .server(let connection) = fields.kind else { return }
    try credentials.save("different", for: connection.passwordRef)
    #expect(workflow.connectivityRevision(for: firstTarget) != version)
    #expect(try workflow.connectivityConfiguration(for: firstTarget).password == "different")
  }
}
