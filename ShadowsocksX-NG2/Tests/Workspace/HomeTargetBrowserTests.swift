import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct HomeTargetBrowserTests {
  @Test
  func firstEntryRevealsCurrentTargetOnlyOnceAndPersistsAncestors() throws {
    let domain = UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    let tree = CatalogTreeSnapshot.build(
      from: fixture.catalog, credentials: InMemoryCredentialStore(),
      plugins: NoManagedPluginProvider())
    let browser = HomeTargetBrowser(defaults: defaults)
    #expect(browser.rows(in: tree, favorites: []).map(\.id) == [fixture.groupID])

    #expect(
      browser.enterHome(current: fixture.serverIDs[1], in: tree, favorites: [])
        == fixture.serverIDs[1])
    #expect(browser.selection == fixture.serverIDs[1])
    #expect(
      browser.rows(in: tree, favorites: []).map(\.id)
        == [fixture.groupID, fixture.nestedGroupID, fixture.serverIDs[1], fixture.serverIDs[0]])
    browser.select(fixture.groupID)
    #expect(browser.enterHome(current: fixture.serverIDs[0], in: tree, favorites: []) == nil)
    #expect(browser.selection == fixture.groupID)

    let restored = HomeTargetBrowser(defaults: defaults)
    #expect(restored.selection == nil)
    #expect(restored.rows(in: tree, favorites: []).count == 4)
  }

  @Test
  func collapsingAncestorSelectsGroupWithoutChangingOtherGroups() throws {
    let domain = UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    let tree = CatalogTreeSnapshot.build(
      from: fixture.catalog, credentials: InMemoryCredentialStore(),
      plugins: NoManagedPluginProvider())
    let browser = HomeTargetBrowser(defaults: defaults)
    browser.enterHome(current: fixture.serverIDs[1], in: tree, favorites: [])

    browser.toggleGroup(fixture.groupID, in: tree)

    #expect(browser.selection == fixture.groupID)
    #expect(browser.rows(in: tree, favorites: []).map(\.id) == [fixture.groupID])
    #expect(browser.expandedGroupIDs == [fixture.nestedGroupID])
    browser.toggleGroup(fixture.groupID, in: tree)
    #expect(browser.selection == fixture.groupID)
    #expect(browser.rows(in: tree, favorites: []).count == 4)
  }

  @Test
  func favoritesAreFlatAndSwitchingClearsHiddenSelectionWhileLocateRestoresAll() throws {
    let domain = UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    let tree = CatalogTreeSnapshot.build(
      from: fixture.catalog, credentials: InMemoryCredentialStore(),
      plugins: NoManagedPluginProvider())
    let favorites = [fixture.groupID, fixture.serverIDs[0]].compactMap { tree.node(withID: $0) }
    let browser = HomeTargetBrowser(defaults: defaults)
    browser.enterHome(current: fixture.serverIDs[1], in: tree, favorites: favorites)
    browser.setMode(.favorites, in: tree, favorites: favorites)
    #expect(browser.selection == nil)
    #expect(
      browser.rows(in: tree, favorites: favorites).map(\.id)
        == [fixture.groupID, fixture.serverIDs[0]])
    #expect(browser.rows(in: tree, favorites: favorites).allSatisfy { $0.depth == 0 })
    #expect(HomeTargetBrowser(defaults: defaults).mode == .favorites)

    browser.locate(fixture.serverIDs[1], in: tree, favorites: favorites)
    #expect(browser.mode == .all)
    #expect(browser.selection == fixture.serverIDs[1])
    #expect(HomeTargetBrowser(defaults: defaults).mode == .all)
    browser.setMode(.favorites, in: tree, favorites: favorites)
    browser.locate(fixture.groupID, in: tree, favorites: favorites)
    #expect(browser.mode == .favorites)
    #expect(browser.selection == fixture.groupID)
  }

  @Test
  func catalogChangesPruneRemovedExpansionAndHiddenSelection() throws {
    let domain = UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    let tree = CatalogTreeSnapshot.build(
      from: fixture.catalog, credentials: InMemoryCredentialStore(),
      plugins: NoManagedPluginProvider())
    let browser = HomeTargetBrowser(defaults: defaults)
    browser.enterHome(current: fixture.serverIDs[1], in: tree, favorites: [])
    let reduced = CatalogTreeSnapshot(roots: [])

    browser.reconcile(in: reduced, favorites: [])

    #expect(browser.selection == nil)
    #expect(browser.expandedGroupIDs.isEmpty)
    #expect(HomeTargetBrowser(defaults: defaults).expandedGroupIDs.isEmpty)
    browser.select(fixture.groupID)
    browser.setMode(.favorites, in: tree, favorites: [tree.roots[0]])
    browser.reconcile(in: tree, favorites: [])
    #expect(browser.selection == nil)
  }
}
