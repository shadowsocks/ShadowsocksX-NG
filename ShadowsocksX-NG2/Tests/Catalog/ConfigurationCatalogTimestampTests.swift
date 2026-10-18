import XCTest

@testable import ShadowsocksX_NG2

/// 节点时间戳语义（ADR-0031）：节点自身资料变化更新自身修改时间；分组的
/// 直接子节点集合或顺序变化更新该分组（类目录修改时间）；被移动节点自身
/// 不动；内容未变不更新。订阅刷新按节点内容逐项比较。
final class ConfigurationCatalogTimestampTests: XCTestCase {
  private let time0 = Date(timeIntervalSince1970: 1_700_000_000)
  private let time1 = Date(timeIntervalSince1970: 1_700_001_000)
  private let time2 = Date(timeIntervalSince1970: 1_700_002_000)

  // MARK: 手动子树

  func testNewNodeStampsBothTimesAndBumpsParentGroup() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组", now: time0)
    let leaf = try catalog.addTestServer("a", to: group, now: time1)

    let groupEntry = try XCTUnwrap(catalog.entry(for: group))
    let leafEntry = try XCTUnwrap(catalog.entry(for: leaf))
    XCTAssertEqual(groupEntry.createdAt, time0)
    XCTAssertEqual(groupEntry.updatedAt, time1, "新增子节点更新落点分组修改时间")
    XCTAssertEqual(leafEntry.createdAt, time1)
    XCTAssertEqual(leafEntry.updatedAt, time1)
  }

  func testUpdateServerBumpsOnlyWhenContentChanges() throws {
    var catalog = ConfigurationCatalog()
    let id = try catalog.addTestServer("a", now: time0)
    guard case .server(var fields)? = catalog.entry(for: id)?.kind else {
      return XCTFail("应为服务器叶子")
    }

    fields.port = 9999
    try catalog.updateServer(id, with: fields, now: time1)
    XCTAssertEqual(catalog.entry(for: id)?.updatedAt, time1, "内容变化更新修改时间")
    XCTAssertEqual(catalog.entry(for: id)?.createdAt, time0, "创建时间保留")

    try catalog.updateServer(id, with: fields, now: time2)
    XCTAssertEqual(catalog.entry(for: id)?.updatedAt, time1, "内容未变不更新修改时间")
  }

  func testRenameGroupBumpsOnlyWhenNameChanges() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("旧名", now: time0)

    try catalog.renameGroup(group, to: "旧名", now: time1)
    XCTAssertEqual(catalog.entry(for: group)?.updatedAt, time0, "同名重命名是内容未变")

    try catalog.renameGroup(group, to: "新名", now: time2)
    XCTAssertEqual(catalog.entry(for: group)?.updatedAt, time2)
    XCTAssertEqual(catalog.entry(for: group)?.createdAt, time0)
  }

  func testMoveBumpsSourceAndTargetGroupsButNotMovedNode() throws {
    var catalog = ConfigurationCatalog()
    let source = try catalog.addGroup("源组", now: time0)
    let target = try catalog.addGroup("目标组", now: time0)
    let leaf = try catalog.addTestServer("a", to: source, now: time0)

    try catalog.move(leaf, to: target, now: time1)

    XCTAssertEqual(catalog.entry(for: leaf)?.updatedAt, time0, "被移动节点自身内容不变")
    XCTAssertEqual(catalog.entry(for: source)?.updatedAt, time1, "原分组失去子节点")
    XCTAssertEqual(catalog.entry(for: target)?.updatedAt, time1, "目标分组获得子节点")
  }

  func testReorderBumpsParentOnly() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组", now: time0)
    let first = try catalog.addTestServer("a", to: group, now: time0)
    let second = try catalog.addTestServer("b", to: group, now: time0)

    try catalog.move(second, to: group, index: 0, now: time1)

    XCTAssertEqual(try catalog.children(of: group), [second, first])
    XCTAssertEqual(catalog.entry(for: group)?.updatedAt, time1, "直接子序变化更新分组")
    XCTAssertEqual(catalog.entry(for: first)?.updatedAt, time0)
    XCTAssertEqual(catalog.entry(for: second)?.updatedAt, time0)
  }

  func testRemoveBumpsParentGroupOfRemovedRoot() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组", now: time0)
    let leaf = try catalog.addTestServer("a", to: group, now: time0)

    _ = try catalog.remove(leaf, now: time1)

    XCTAssertFalse(catalog.contains(leaf))
    XCTAssertEqual(catalog.entry(for: group)?.updatedAt, time1, "分组失去子节点")
  }

  func testRootLevelChangesDoNotTouchAnyTimestamp() throws {
    var catalog = ConfigurationCatalog()
    let first = try catalog.addTestServer("a", now: time0)
    let second = try catalog.addTestServer("b", now: time1)

    _ = try catalog.remove(first, now: time2)

    XCTAssertEqual(catalog.entry(for: second)?.updatedAt, time1, "根层结构变化无分组可更新")
  }

  // MARK: 订阅快照刷新

  private let groupID = NodeID(rawValue: "t:group")
  private let nestedID = NodeID(rawValue: "t:nested")
  private let leafA = NodeID(rawValue: "t:a")
  private let leafB = NodeID(rawValue: "t:b")

  private func fields(remark: String, port: Int = 8388) -> ServerFields {
    ServerFields(
      address: "203.0.113.7",
      port: port,
      encryptionMethod: "aes-256-gcm",
      password: "password",
      remark: remark
    )
  }

  /// 固定分组（嵌套分组 + 两个服务器叶子）与快照同构的目录夹具。
  private func makeSubscriptionCatalog() throws -> ConfigurationCatalog {
    var catalog = ConfigurationCatalog()
    try catalog.addGroup("订阅分组", source: .subscription, id: groupID, now: time0)
    try catalog.addGroup("嵌套分组", source: .subscription, id: nestedID, to: groupID, now: time0)
    try catalog.addServer(
      fields(remark: "a"), source: .subscription, id: leafA, to: groupID, now: time0)
    try catalog.addServer(
      fields(remark: "b"), source: .subscription, id: leafB, to: nestedID, now: time0)
    return catalog
  }

  /// 与夹具同构的快照（固定分组 = 嵌套分组 + 服务器 a；嵌套 = 服务器 b），
  /// 各参数可单独改写以制造远端变化。
  private func snapshot(
    name: String = "订阅分组",
    nestedName: String = "嵌套分组",
    nestedChildren: [CatalogSubscriptionSnapshot.Child]
  ) -> CatalogSubscriptionSnapshot {
    let nested = CatalogSubscriptionSnapshot.Group(
      id: nestedID, name: nestedName, children: nestedChildren)
    return CatalogSubscriptionSnapshot(
      name: name,
      root: CatalogSubscriptionSnapshot.Group(
        id: NodeID(rawValue: "t:remote-root"), name: name,
        children: [
          CatalogSubscriptionSnapshot.Child.group(nested),
          leaf(leafA, fields(remark: "a")),
        ]))
  }

  private func leaf(
    _ id: NodeID, _ leafFields: ServerFields
  ) -> CatalogSubscriptionSnapshot.Child {
    .server(.init(id: id, fields: leafFields))
  }

  func testIdenticalSnapshotRefreshKeepsEveryTimestamp() throws {
    var catalog = try makeSubscriptionCatalog()
    let before = catalog
    let snap = snapshot(nestedChildren: [leaf(leafB, fields(remark: "b"))])

    _ = try catalog.applySubscriptionSnapshot(snap, into: groupID, now: time1)

    XCTAssertEqual(catalog, before, "内容未变的刷新不动任何节点的时间戳")
  }

  func testChangedLeafBumpsOnlyThatLeaf() throws {
    var catalog = try makeSubscriptionCatalog()
    let snap = snapshot(nestedChildren: [leaf(leafB, fields(remark: "b", port: 9999))])

    _ = try catalog.applySubscriptionSnapshot(snap, into: groupID, now: time1)

    XCTAssertEqual(catalog.entry(for: leafB)?.updatedAt, time1, "内容变化的叶子更新修改时间")
    XCTAssertEqual(catalog.entry(for: leafB)?.createdAt, time0, "延续叶子保留创建时间")
    XCTAssertEqual(catalog.entry(for: nestedID)?.updatedAt, time0, "嵌套分组名称与直接子序未变")
    XCTAssertEqual(catalog.entry(for: groupID)?.updatedAt, time0, "固定分组名称与直接子序未变")
  }

  func testNewLeafStampsFreshTimesAndBumpsItsParentGroup() throws {
    var catalog = try makeSubscriptionCatalog()
    let leafC = NodeID(rawValue: "t:c")
    let snap = snapshot(
      nestedChildren: [leaf(leafB, fields(remark: "b")), leaf(leafC, fields(remark: "c"))])

    _ = try catalog.applySubscriptionSnapshot(snap, into: groupID, now: time1)

    XCTAssertEqual(catalog.entry(for: leafC)?.createdAt, time1)
    XCTAssertEqual(catalog.entry(for: leafC)?.updatedAt, time1)
    XCTAssertEqual(catalog.entry(for: nestedID)?.updatedAt, time1, "嵌套分组直接子节点集合变化")
    XCTAssertEqual(catalog.entry(for: groupID)?.updatedAt, time0, "固定分组直接子序未变")
  }

  func testRemoteRenameBumpsOnlyRenamedGroup() throws {
    var catalog = try makeSubscriptionCatalog()
    let snap = snapshot(
      nestedName: "远端新名", nestedChildren: [leaf(leafB, fields(remark: "b"))])

    _ = try catalog.applySubscriptionSnapshot(snap, into: groupID, now: time1)

    XCTAssertEqual(catalog.entry(for: nestedID)?.updatedAt, time1)
    XCTAssertEqual(catalog.entry(for: leafB)?.updatedAt, time0)
    XCTAssertEqual(catalog.entry(for: groupID)?.updatedAt, time0, "固定分组自身名称未变")
  }

  func testRemoteFixedGroupNameChangeBumpsFixedGroup() throws {
    var catalog = try makeSubscriptionCatalog()
    let snap = snapshot(
      name: "远端新订阅名", nestedChildren: [leaf(leafB, fields(remark: "b"))])

    _ = try catalog.applySubscriptionSnapshot(snap, into: groupID, now: time1)

    XCTAssertEqual(catalog.entry(for: groupID)?.updatedAt, time1)
    XCTAssertEqual(catalog.entry(for: groupID)?.createdAt, time0, "固定分组身份客户端所有，创建时间保留")
    XCTAssertEqual(catalog.entry(for: nestedID)?.updatedAt, time0)
  }

  func testRemovedLeafBumpsItsParentGroup() throws {
    var catalog = try makeSubscriptionCatalog()
    let snap = snapshot(nestedChildren: [])

    _ = try catalog.applySubscriptionSnapshot(snap, into: groupID, now: time1)

    XCTAssertFalse(catalog.contains(leafB))
    XCTAssertEqual(catalog.entry(for: nestedID)?.updatedAt, time1, "子节点被远端移除")
    XCTAssertEqual(catalog.entry(for: groupID)?.updatedAt, time0)
  }
}
