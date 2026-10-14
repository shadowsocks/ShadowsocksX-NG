import Testing
import XCTest

@testable import ShadowsocksX_NG2

/// CatalogTreeSnapshot 树投影的纯单元测试：折叠可见行与服务器叶子计数。
/// 直接构造 snapshot（memberwise init），不经工作流。
final class CatalogTreeProjectionTests: XCTestCase {
  private func server(_ id: String) -> CatalogTreeNode {
    CatalogTreeNode(
      id: NodeID(rawValue: id), name: id, isGroup: false, source: .manual, parentID: nil,
      createdAt: nil, updatedAt: nil,
      invalidReasons: [], childCount: 0, subtreeNodeCount: 0, invalidDescendantCount: 0,
      children: nil)
  }

  private func group(_ id: String, children: [CatalogTreeNode]) -> CatalogTreeNode {
    CatalogTreeNode(
      id: NodeID(rawValue: id), name: id, isGroup: true, source: .manual, parentID: nil,
      createdAt: nil, updatedAt: nil,
      invalidReasons: [], childCount: children.count,
      subtreeNodeCount: children.reduce(0) { $0 + 1 + $1.subtreeNodeCount },
      invalidDescendantCount: 0, children: children)
  }

  /// 两层嵌套 + 根叶子 + 空组：覆盖深度、子树跳过与空组语义。
  private func nestedTree() -> CatalogTreeSnapshot {
    CatalogTreeSnapshot(roots: [
      server("root-server"),
      group(
        "outer",
        children: [
          group("inner", children: [server("deep-leaf")]),
          server("outer-leaf"),
        ]),
      group("empty", children: []),
    ])
  }

  // MARK: - 可见行折叠投影

  func testVisibleRowsWalkDepthFirstWithDepth() {
    let rows = nestedTree().visibleRows(collapsed: [])
    XCTAssertEqual(
      rows.map(\.id.rawValue),
      ["root-server", "outer", "inner", "deep-leaf", "outer-leaf", "empty"])
    XCTAssertEqual(rows.map(\.depth), [0, 0, 1, 2, 1, 0])
    XCTAssertEqual(rows.map(\.node.name), rows.map(\.id.rawValue), "行身份即节点身份")
  }

  func testVisibleRowsSkipCollapsedSubtrees() {
    let tree = nestedTree()
    XCTAssertEqual(
      tree.visibleRows(collapsed: [NodeID(rawValue: "outer")]).map(\.id.rawValue),
      ["root-server", "outer", "empty"], "收起组的子树不出现，组行自身保留可再展开")
    XCTAssertEqual(
      tree.visibleRows(collapsed: [NodeID(rawValue: "inner")]).map(\.id.rawValue),
      ["root-server", "outer", "inner", "outer-leaf", "empty"])
  }

  func testVisibleRowsTreatUnknownAndLeafIDsAsInert() {
    let collapsed: Set<NodeID> = [NodeID(rawValue: "nope"), NodeID(rawValue: "root-server")]
    XCTAssertEqual(
      nestedTree().visibleRows(collapsed: collapsed).map(\.id.rawValue),
      ["root-server", "outer", "inner", "deep-leaf", "outer-leaf", "empty"])
  }

  // MARK: - 服务器叶子计数

  func testServerLeafCountCountsLeavesAcrossNesting() {
    XCTAssertEqual(nestedTree().serverLeafCount, 3)
    XCTAssertEqual(CatalogTreeSnapshot(roots: []).serverLeafCount, 0)
  }
}

struct CatalogTreeTimestampProjectionTests {
  @Test
  func treeExposesCommittedCreationAndModificationTimes() throws {
    var catalog = ConfigurationCatalog()
    let created = Date(timeIntervalSince1970: 100)
    let modified = Date(timeIntervalSince1970: 200)
    let group = try catalog.addGroup("原名", now: created)
    try catalog.renameGroup(group, to: "新名", now: modified)
    let tree = CatalogTreeSnapshot.build(
      from: catalog, credentials: InMemoryCredentialStore(), plugins: NoManagedPluginProvider())

    #expect(tree.node(withID: group)?.createdAt == created)
    #expect(tree.node(withID: group)?.updatedAt == modified)
  }
}

struct SubscriptionRootGroupClassificationTests {
  private func node(
    _ id: String, source: NodeSource, parentID: NodeID?, isGroup: Bool = true
  ) -> CatalogTreeNode {
    CatalogTreeNode(
      id: NodeID(rawValue: id), name: id, isGroup: isGroup, source: source, parentID: parentID,
      createdAt: nil, updatedAt: nil, invalidReasons: [], childCount: 0,
      subtreeNodeCount: 0, invalidDescendantCount: 0, children: isGroup ? [] : nil)
  }

  @Test
  func onlyRootSubscriptionGroupsQualify() {
    let rootID = NodeID(rawValue: "subscription-root")
    let root = node("subscription-root", source: .subscription, parentID: nil)
    let nested = node("nested-subscription-group", source: .subscription, parentID: rootID)
    let manual = node("manual-group", source: .manual, parentID: nil)
    let server = node("subscription-server", source: .subscription, parentID: nil, isGroup: false)

    #expect(root.isRootSubscriptionGroup)
    #expect(!nested.isRootSubscriptionGroup)
    #expect(!manual.isRootSubscriptionGroup)
    #expect(!server.isRootSubscriptionGroup)
  }
}

struct ServerTableOrderingTests {
  @Test
  func hierarchySortsEachSiblingSetAndCollapseHidesOnlyThatSubtree() throws {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("Z 外层")
    let root = try catalog.addGroup("A 根层")
    let childZ = try catalog.addGroup("Z 子组", to: outer)
    let childA = try catalog.addGroup("A 子组", to: outer)
    let leaf = try catalog.addGroup("孙节点", to: childA)
    let tree = CatalogTreeSnapshot.build(
      from: catalog, credentials: InMemoryCredentialStore(), plugins: NoManagedPluginProvider())
    let rows = tree.visibleRows(source: .manual, sortedBy: [ServerTableSort(.name)], collapsed: [])

    #expect(rows.map(\.id) == [root, outer, childA, leaf, childZ])
    #expect(rows.map(\.depth) == [0, 0, 1, 2, 1])
    #expect(
      tree.visibleRows(
        source: .manual, sortedBy: [ServerTableSort(.name)], collapsed: [outer]
      ).map(\.id) == [root, outer])
    #expect(tree.roots.map(\.id) == [outer, root])
    #expect(tree.node(withID: outer)?.childNodes.map(\.id) == [childZ, childA])
  }

  @Test(arguments: [SortOrder.forward, .reverse])
  func sourceFilteringAndTimeSortingKeepUnknownLastAndEqualValuesStable(order: SortOrder) {
    func node(_ id: String, source: NodeSource = .manual, date: Date?) -> CatalogTreeNode {
      CatalogTreeNode(
        id: NodeID(rawValue: id), name: id, isGroup: true, source: source, parentID: nil,
        createdAt: date, updatedAt: date, invalidReasons: [], childCount: 0,
        subtreeNodeCount: 0, invalidDescendantCount: 0, children: [])
    }
    let tree = CatalogTreeSnapshot(roots: [
      node("unknown", date: nil),
      node("newer", date: Date(timeIntervalSince1970: 200)),
      node("equal-first", date: Date(timeIntervalSince1970: 100)),
      node("equal-second", date: Date(timeIntervalSince1970: 100)),
      node("subscription", source: .subscription, date: Date(timeIntervalSince1970: 50)),
    ])
    let sorted = tree.roots(for: .manual, sortedBy: [ServerTableSort(.createdAt, order: order)])
    #expect(
      sorted.map(\.id.rawValue)
        == (order == .forward
          ? ["equal-first", "equal-second", "newer", "unknown"]
          : ["newer", "equal-first", "equal-second", "unknown"]))
    #expect(
      tree.roots(for: .manual, sortedBy: []).map(\.id.rawValue)
        == ["unknown", "newer", "equal-first", "equal-second"])
  }
}

@MainActor
struct ServerTableInsertionTests {
  @Test
  func insertionLinesUseTheDestinationRowsParent() throws {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("外层")
    let inner = try catalog.addGroup("内层", to: outer)
    let leaf = try catalog.addGroup("内层成员", to: inner)
    let sibling = try catalog.addGroup("外层成员", to: outer)
    let root = try catalog.addGroup("根层")
    let tree = CatalogTreeSnapshot.build(
      from: catalog, credentials: InMemoryCredentialStore(), plugins: NoManagedPluginProvider())
    let rows = tree.visibleRows(collapsed: [])
    #expect(rows.map(\.id) == [outer, inner, leaf, sibling, root])

    #expect(ServerTableDropState.insertionParent(at: 0, in: rows) == nil)
    #expect(ServerTableDropState.insertionParent(at: 1, in: rows) == outer)
    #expect(ServerTableDropState.insertionParent(at: 2, in: rows) == inner)
    #expect(ServerTableDropState.insertionParent(at: 3, in: rows) == outer)
    #expect(ServerTableDropState.insertionParent(at: 4, in: rows) == nil)
    #expect(ServerTableDropState.insertionParent(at: rows.count, in: rows) == nil)

    let collapsed = tree.visibleRows(collapsed: [inner])
    #expect(ServerTableDropState.insertionParent(at: 2, in: collapsed) == outer)
    #expect(ServerTableDropState.insertionParent(at: 0, in: []) == nil)
  }
}

@MainActor
struct ServerTableRowDropTests {
  @Test
  func serverRowMovesAnOutsideNodeIntoItsContainingGroup() throws {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("外层")
    let inner = try catalog.addGroup("内层", to: outer)
    let member = try catalog.addTestServer("组内服务器", to: inner)
    let outside = try catalog.addTestServer("组外服务器")
    let tree = CatalogTreeSnapshot.build(
      from: catalog, credentials: InMemoryCredentialStore(), plugins: NoManagedPluginProvider())
    let memberNode = try #require(tree.node(withID: member))
    let parent = ServerTableDropState.rowParent(for: memberNode)
    #expect(parent == inner)
    #expect(ServerTableDropState.rowParent(for: try #require(tree.node(withID: inner))) == inner)
    #expect(ServerTableDropState.rowParent(for: try #require(tree.node(withID: outside))) == nil)

    try catalog.move(outside, to: parent)
    let movedTree = CatalogTreeSnapshot.build(
      from: catalog, credentials: InMemoryCredentialStore(), plugins: NoManagedPluginProvider())
    #expect(movedTree.node(withID: outside)?.parentID == inner)
    #expect(movedTree.node(withID: member)?.parentID == inner)
    #expect(movedTree.node(withID: inner)?.childNodes.map(\.id) == [member, outside])
  }
}
