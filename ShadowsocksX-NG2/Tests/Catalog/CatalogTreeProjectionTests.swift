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
      from: catalog, plugins: NoManagedPluginProvider())

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

struct ServerTableDirectoryOrderTests {
  @Test
  func hierarchyKeepsDirectoryOrderAndCollapseHidesOnlyThatSubtree() throws {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("Z 外层")
    let root = try catalog.addGroup("A 根层")
    let childZ = try catalog.addGroup("Z 子组", to: outer)
    let childA = try catalog.addGroup("A 子组", to: outer)
    let leaf = try catalog.addGroup("孙节点", to: childA)
    let tree = CatalogTreeSnapshot.build(
      from: catalog, plugins: NoManagedPluginProvider())
    let rows = tree.visibleRows(source: .manual, collapsed: [])

    #expect(rows.map(\.id) == [outer, childZ, childA, leaf, root])
    #expect(rows.map(\.depth) == [0, 1, 1, 2, 0])
    #expect(
      tree.visibleRows(
        source: .manual, collapsed: [outer]
      ).map(\.id) == [outer, root])
    #expect(tree.roots.map(\.id) == [outer, root])
    #expect(tree.node(withID: outer)?.childNodes.map(\.id) == [childZ, childA])
  }

  @Test
  func sourceFilteringKeepsDirectoryOrderAndCompleteSubtrees() {
    func node(
      _ id: String, source: NodeSource = .manual, parentID: NodeID? = nil,
      children: [CatalogTreeNode] = []
    ) -> CatalogTreeNode {
      CatalogTreeNode(
        id: NodeID(rawValue: id), name: id, isGroup: true, source: source, parentID: parentID,
        createdAt: nil, updatedAt: nil, invalidReasons: [], childCount: children.count,
        subtreeNodeCount: children.count, invalidDescendantCount: 0, children: children)
    }
    let subscription = node(
      "subscription", source: .subscription,
      children: [
        node(
          "subscription-child", source: .subscription,
          parentID: NodeID(rawValue: "subscription"))
      ])
    let tree = CatalogTreeSnapshot(roots: [
      node("Z-first"), subscription, node("A-last"),
    ])
    #expect(
      tree.visibleRows(source: .manual, collapsed: []).map(\.id.rawValue)
        == ["Z-first", "A-last"])
    let subscriptionRows = tree.visibleRows(source: .subscription, collapsed: [])
    #expect(subscriptionRows.map(\.id.rawValue) == ["subscription", "subscription-child"])
    #expect(subscriptionRows.map(\.depth) == [0, 1])
    #expect(
      tree.visibleRows(source: .subscription, collapsed: [subscription.id]).map(\.id.rawValue)
        == ["subscription"])
    #expect(
      tree.visibleRows(collapsed: []).map(\.id.rawValue)
        == ["Z-first", "subscription", "subscription-child", "A-last"])
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
      from: catalog, plugins: NoManagedPluginProvider())
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

/// 活动目标行标记的祖先推导：空心闪电候选是活动目标的严格祖先分组。
struct CatalogTreeActiveTargetAncestorTests {
  private struct Fixture {
    let tree: CatalogTreeSnapshot
    let outer: NodeID
    let inner: NodeID
    let deepLeaf: NodeID
    let rootServer: NodeID
  }

  private func nestedTree() throws -> Fixture {
    var catalog = ConfigurationCatalog()
    let outer = try catalog.addGroup("外层")
    let inner = try catalog.addGroup("内层", to: outer)
    let deepLeaf = try catalog.addTestServer("深层服务器", to: inner)
    let rootServer = try catalog.addTestServer("根层服务器")
    let tree = CatalogTreeSnapshot.build(from: catalog, plugins: NoManagedPluginProvider())
    return Fixture(
      tree: tree, outer: outer, inner: inner, deepLeaf: deepLeaf, rootServer: rootServer)
  }

  @Test
  func absentOrUnknownActiveTargetYieldsNoAncestors() throws {
    let fixture = try nestedTree()
    #expect(fixture.tree.ancestors(of: nil).isEmpty)
    #expect(fixture.tree.ancestors(of: NodeID(rawValue: "nope")).isEmpty)
  }

  @Test
  func deepServerYieldsEveryAncestorGroup() throws {
    let fixture = try nestedTree()
    #expect(fixture.tree.ancestors(of: fixture.deepLeaf) == [fixture.outer, fixture.inner])
    #expect(fixture.tree.ancestors(of: fixture.rootServer).isEmpty)
  }

  @Test
  func activeGroupItselfIsExcludedFromItsOwnAncestors() throws {
    let fixture = try nestedTree()
    #expect(fixture.tree.ancestors(of: fixture.inner) == [fixture.outer])
    #expect(fixture.tree.ancestors(of: fixture.outer).isEmpty)
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
      from: catalog, plugins: NoManagedPluginProvider())
    let memberNode = try #require(tree.node(withID: member))
    let parent = ServerTableDropState.rowParent(for: memberNode)
    #expect(parent == inner)
    #expect(ServerTableDropState.rowParent(for: try #require(tree.node(withID: inner))) == inner)
    #expect(ServerTableDropState.rowParent(for: try #require(tree.node(withID: outside))) == nil)

    try catalog.move(outside, to: parent)
    let movedTree = CatalogTreeSnapshot.build(
      from: catalog, plugins: NoManagedPluginProvider())
    #expect(movedTree.node(withID: outside)?.parentID == inner)
    #expect(movedTree.node(withID: member)?.parentID == inner)
    #expect(movedTree.node(withID: inner)?.childNodes.map(\.id) == [member, outside])
  }
}
