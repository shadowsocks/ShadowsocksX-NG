import XCTest

@testable import ShadowsocksX_NG2

/// 非法操作拒绝：跨来源、身份复用（共享父）、成环、越界与不存在的容器/节点，
/// 全部带明确原因，且失败不产生任何变更。
final class ConfigurationCatalogRejectionTests: XCTestCase {
  func testCrossSourceMoveIsRejected() throws {
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    var catalog = fixture.catalog
    let manual = try catalog.addTestServer("手动节点")

    XCTAssertThrowsError(try catalog.move(manual, to: fixture.groupID)) { error in
      XCTAssertEqual(
        error as? CatalogError,
        .crossSourcePlacement(node: .manual, container: .subscription),
        "手动节点不得并入订阅子树"
      )
    }
    XCTAssertEqual(try catalog.parentID(of: manual), nil, "被拒操作不得产生任何变更")
  }

  func testSubscriptionNodesRejectMoveAndRemove() throws {
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    var catalog = fixture.catalog
    let subscriptionServer = fixture.serverIDs[0]

    XCTAssertThrowsError(try catalog.move(subscriptionServer, to: nil)) { error in
      XCTAssertEqual(error as? CatalogError, .subscriptionNodeImmutable(subscriptionServer))
    }
    XCTAssertThrowsError(try catalog.move(fixture.nestedGroupID, to: fixture.groupID)) { error in
      XCTAssertEqual(error as? CatalogError, .subscriptionNodeImmutable(fixture.nestedGroupID))
    }
    XCTAssertThrowsError(try catalog.remove(fixture.groupID)) { error in
      XCTAssertEqual(error as? CatalogError, .subscriptionNodeImmutable(fixture.groupID))
    }
    XCTAssertTrue(catalog.contains(fixture.groupID), "被拒删除不得产生任何变更")
  }

  func testSubscriptionNodesRejectRenameAndFieldEdit() throws {
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    var catalog = fixture.catalog
    let subscriptionServer = fixture.serverIDs[0]

    XCTAssertThrowsError(try catalog.renameGroup(fixture.groupID, to: "改名")) { error in
      XCTAssertEqual(error as? CatalogError, .subscriptionNodeImmutable(fixture.groupID))
    }
    XCTAssertThrowsError(
      try catalog.updateServer(subscriptionServer, with: CatalogFixtures.serverFields(remark: "x"))
    ) { error in
      XCTAssertEqual(error as? CatalogError, .subscriptionNodeImmutable(subscriptionServer))
    }
  }

  func testMoveGroupIntoItsOwnSubtreeIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组")
    let nested = try catalog.addGroup("嵌套组", to: group)

    XCTAssertThrowsError(try catalog.move(group, to: group)) { error in
      XCTAssertEqual(error as? CatalogError, .cycleDetected(group), "移入自身成环")
    }
    XCTAssertThrowsError(try catalog.move(group, to: nested)) { error in
      XCTAssertEqual(error as? CatalogError, .cycleDetected(group), "移入自身深层子树同样成环")
    }
    XCTAssertEqual(try catalog.children(of: group), [nested], "被拒操作不得产生任何变更")
  }

  func testAddingNodeWithExistingIdentityIsRejectedAsDuplicateID() throws {
    var catalog = ConfigurationCatalog()
    let existing = try catalog.addTestServer("已存在")
    let group = try catalog.addGroup("组")

    XCTAssertThrowsError(try catalog.addTestServer("新节点", id: existing)) { error in
      XCTAssertEqual(
        error as? CatalogError, .duplicateID(existing),
        "同一身份不得出现两份（身份复用即共享父）"
      )
    }
    XCTAssertThrowsError(try catalog.addGroup("新组", id: existing, to: group)) { error in
      XCTAssertEqual(error as? CatalogError, .duplicateID(existing))
    }
    XCTAssertEqual(catalog.entries.count, 2, "被拒操作不得产生任何变更")
  }

  func testSubscriptionServerAtRootIsRejected() throws {
    var catalog = ConfigurationCatalog()

    XCTAssertThrowsError(
      try catalog.addTestServer("游离订阅节点", source: .subscription)
    ) { error in
      guard case CatalogError.subscriptionServerAtRoot? = error as? CatalogError else {
        return XCTFail("应报 subscriptionServerAtRoot，实际 \(error)")
      }
    }
    XCTAssertTrue(catalog.isEmpty, "被拒操作不得产生任何变更")
  }

  func testMissingOrNonGroupParentIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let server = try catalog.addTestServer("leaf")
    let missing = NodeID(rawValue: "missing")

    XCTAssertThrowsError(try catalog.addTestServer("x", to: missing)) { error in
      XCTAssertEqual(error as? CatalogError, .parentNotFound(missing))
    }
    XCTAssertThrowsError(try catalog.addTestServer("x", to: server)) { error in
      XCTAssertEqual(error as? CatalogError, .parentNotAGroup(server), "服务器叶子不是容器")
    }
    XCTAssertThrowsError(try catalog.move(server, to: missing)) { error in
      XCTAssertEqual(error as? CatalogError, .parentNotFound(missing))
    }
    XCTAssertThrowsError(try catalog.move(server, to: server)) { error in
      XCTAssertEqual(error as? CatalogError, .cycleDetected(server), "叶子移入自身优先判成环")
    }
  }

  func testIndexOutOfRangeIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组")
    let leaf = try catalog.addTestServer("leaf")

    XCTAssertThrowsError(try catalog.addTestServer("x", to: group, index: 1)) { error in
      XCTAssertEqual(
        error as? CatalogError, .indexOutOfRange(parent: group, index: 1, childCount: 0))
    }
    XCTAssertThrowsError(try catalog.move(leaf, to: nil, index: -1)) { error in
      XCTAssertEqual(
        error as? CatalogError, .indexOutOfRange(parent: nil, index: -1, childCount: 1))
    }
    XCTAssertThrowsError(try catalog.move(leaf, to: nil, index: 2)) { error in
      XCTAssertEqual(
        error as? CatalogError, .indexOutOfRange(parent: nil, index: 2, childCount: 1),
        "重排范围以摘除自身后的子序计")
    }
  }

  func testOperationsOnUnknownNodesAreRejected() throws {
    var catalog = ConfigurationCatalog()
    let missing = NodeID(rawValue: "missing")

    XCTAssertThrowsError(try catalog.renameGroup(missing, to: "x")) { error in
      XCTAssertEqual(error as? CatalogError, .nodeNotFound(missing))
    }
    XCTAssertThrowsError(
      try catalog.updateServer(missing, with: CatalogFixtures.serverFields(remark: "x"))
    ) { error in
      XCTAssertEqual(error as? CatalogError, .nodeNotFound(missing))
    }
    XCTAssertThrowsError(try catalog.move(missing, to: nil)) { error in
      XCTAssertEqual(error as? CatalogError, .nodeNotFound(missing))
    }
    XCTAssertThrowsError(try catalog.remove(missing)) { error in
      XCTAssertEqual(error as? CatalogError, .nodeNotFound(missing))
    }
  }
}
