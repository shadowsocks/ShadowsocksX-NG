import Testing
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class CatalogExpansionStateTests: XCTestCase {
  func testFreshStateIsFullyExpanded() {
    let expansion = CatalogExpansionState()

    XCTAssertTrue(expansion.collapsedGroupIDs.isEmpty)
    XCTAssertFalse(expansion.isCollapsed(NodeID(rawValue: "g1")))
  }

  /// 切换语义：未收起 → 收起 → 再切换 → 展开（分区切换往返不重置的事实基础）。
  func testToggleCollapsesThenReexpands() {
    let expansion = CatalogExpansionState()
    let id = NodeID(rawValue: "g1")

    expansion.toggleCollapsed(id)
    XCTAssertTrue(expansion.isCollapsed(id))

    expansion.toggleCollapsed(id)
    XCTAssertFalse(expansion.isCollapsed(id))
  }

  /// 服务器管理树的各组折叠事实按身份独立保存。
  func testCollapseSetIsKeyedPerGroupID() {
    let expansion = CatalogExpansionState()
    let first = NodeID(rawValue: "g-first")
    let second = NodeID(rawValue: "g-second")

    expansion.toggleCollapsed(first)
    expansion.toggleCollapsed(second)

    XCTAssertEqual(expansion.collapsedGroupIDs, [first, second])

    expansion.toggleCollapsed(first)
    XCTAssertEqual(expansion.collapsedGroupIDs, [second])
    XCTAssertFalse(expansion.isCollapsed(first))
    XCTAssertTrue(expansion.isCollapsed(second))
  }
}

@MainActor
struct CatalogCreationExpansionTests {
  @Test
  func collapsingAncestorSelectsThatGroupAndPreservesOtherExpansionState() throws {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("外层")
    let inner = try catalog.addGroup("内层", to: outer)
    let selected = try catalog.addGroup("选中项", to: inner)
    let other = try catalog.addGroup("其他")
    let tree = CatalogTreeSnapshot.build(
      from: catalog, plugins: NoManagedPluginProvider())
    let node = try #require(tree.node(withID: outer))
    let expansion = CatalogExpansionState()
    expansion.toggleCollapsed(other)

    let selection = expansion.setExpanded(false, for: node, selection: selected)

    #expect(selection == outer)
    #expect(expansion.collapsedGroupIDs == [outer, other])
    #expect(expansion.setExpanded(true, for: node, selection: outer) == outer)
    #expect(expansion.collapsedGroupIDs == [other])
  }

  @Test
  func revealingCreatedNodeExpandsAncestorsAndPreservesOtherCollapsedGroups() throws {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("工作")
    let inner = try catalog.addGroup("香港", to: outer)
    let created = try catalog.addGroup("新组", to: inner)
    let other = try catalog.addGroup("其他")
    let tree = CatalogTreeSnapshot.build(
      from: catalog, plugins: NoManagedPluginProvider())
    let expansion = CatalogExpansionState()
    for id in [outer, inner, other] { expansion.toggleCollapsed(id) }

    expansion.reveal(created, in: tree)

    #expect(expansion.collapsedGroupIDs == [other])
    #expect(tree.visibleRows(collapsed: expansion.collapsedGroupIDs).map(\.id).contains(created))
  }

  @Test(arguments: [false, true])
  func removedCreationParentRejectsWithoutFallingBackToRoot(createServer: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()))
    let parent = try await workflow.createGroup(named: "目标组", into: nil)
    _ = try await workflow.remove(parent)

    do {
      if createServer {
        _ = try await workflow.createServer(
          ServerEditDraft(
            address: "203.0.113.1", port: 8388, encryptionMethod: "aes-256-gcm",
            password: "pw", remark: "新服务器", plugin: .none, pluginOptions: nil), into: parent)
      } else {
        _ = try await workflow.createGroup(named: "新组", into: parent)
      }
      Issue.record("失效的父组应拒绝创建")
    } catch {
      let underlying = error
      #expect(underlying as? CatalogError == .parentNotFound(parent))
    }
    #expect(workflow.tree.isEmpty)
  }
}
