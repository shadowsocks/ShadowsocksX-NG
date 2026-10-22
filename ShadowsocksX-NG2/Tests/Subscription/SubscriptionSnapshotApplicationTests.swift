import XCTest

@testable import ShadowsocksX_NG2

/// 订阅快照的目录应用语义：固定分组身份保留；远端删除不留
/// 墓碑；结构、字段与顺序远端权威，不存在本地启用覆盖层。
final class SubscriptionSnapshotApplicationTests: XCTestCase {
  private let groupID = NodeID(rawValue: "sub1:fixed-group")

  private func makeCatalog() throws -> ConfigurationCatalog {
    var catalog = ConfigurationCatalog()
    try catalog.addGroup("订阅分组", source: .subscription, id: groupID)
    let nested = NodeID(rawValue: "sub1:g:jp")
    try catalog.addGroup("日本", source: .subscription, id: nested, to: groupID)
    let serverA = NodeID(rawValue: "sub1:id:a")
    try catalog.addServer(
      CatalogFixtures.serverFields(remark: "香港 01"), source: .subscription, id: serverA,
      to: groupID)
    let serverB = NodeID(rawValue: "sub1:id:b")
    try catalog.addServer(
      CatalogFixtures.serverFields(remark: "日本 02"), source: .subscription, id: serverB,
      to: nested)
    return catalog
  }

  private func leaf(_ id: String, fields: ServerFields = CatalogFixtures.serverFields(remark: ""))
    -> CatalogSubscriptionSnapshot.Child
  {
    .server(CatalogSubscriptionSnapshot.ServerLeaf(id: NodeID(rawValue: id), fields: fields))
  }

  private func group(_ id: String, _ name: String, children: [CatalogSubscriptionSnapshot.Child])
    -> CatalogSubscriptionSnapshot.Child
  {
    .group(
      CatalogSubscriptionSnapshot.Group(id: NodeID(rawValue: id), name: name, children: children))
  }

  // MARK: 快照应用

  func testSnapshotReplacesSubtreeWithoutLocalEnableOverlay() throws {
    var catalog = try makeCatalog()

    let document = CatalogSubscriptionSnapshot(
      name: "远端新名",
      root: .init(
        id: groupID, name: "ignored-root",
        children: [
          leaf("sub1:id:b"),
          group(
            "sub1:g:jp", "JP", children: [leaf("sub1:id:a"), leaf("sub1:id:new")]),
        ]))
    let removed = try catalog.applySubscriptionSnapshot(document, into: groupID)

    XCTAssertEqual(removed.count, 2, "旧树两台服务器全部视为移除（b 从嵌套组移到根）")
    // 固定分组身份保持不变，名称跟随远端；远端子序原样落目录。
    let fixed = try XCTUnwrap(catalog.entry(for: groupID))
    XCTAssertEqual(
      try catalog.children(of: groupID),
      [NodeID(rawValue: "sub1:id:b"), NodeID(rawValue: "sub1:g:jp")])
    guard case .group(let fields) = fixed.kind else { return XCTFail("固定分组应存在") }
    XCTAssertEqual(fields.name, "远端新名")
    XCTAssertEqual(fixed.source, .subscription)
    // 旧树已重建，无墓碑：固定分组 + 根序 b + 嵌套组 + a + 新节点。
    XCTAssertEqual(catalog.entries.count, 5)
  }

  func testRemovedRemoteMembersLeaveNoTombstone() throws {
    var catalog = try makeCatalog()
    let removedTarget = NodeID(rawValue: "sub1:id:b")

    let document = CatalogSubscriptionSnapshot(
      name: "订阅分组", root: .init(id: groupID, name: "", children: [leaf("sub1:id:a")]))
    _ = try catalog.applySubscriptionSnapshot(document, into: groupID)

    XCTAssertNil(catalog.entry(for: removedTarget), "远端删除即移除")
    XCTAssertNil(catalog.entry(for: NodeID(rawValue: "sub1:g:jp")), "空嵌套组一并移除")
    XCTAssertEqual(catalog.entries.count, 2)
  }

  func testFixedGroupStateIsFullyRemoteOwnedOnRefresh() throws {
    var catalog = try makeCatalog()

    let document = CatalogSubscriptionSnapshot(
      name: "新名", root: .init(id: groupID, name: "", children: [leaf("sub1:id:a")]))
    _ = try catalog.applySubscriptionSnapshot(document, into: groupID)

    XCTAssertEqual(try XCTUnwrap(catalog.entry(for: groupID)).displayName, "新名")
  }

  func testApplyToManualGroupRejected() throws {
    var catalog = ConfigurationCatalog()
    let manual = try catalog.addGroup("手动组")
    let document = CatalogSubscriptionSnapshot(
      name: "x", root: .init(id: groupID, name: "", children: []))

    XCTAssertThrowsError(try catalog.applySubscriptionSnapshot(document, into: manual))
  }

  func testApplyToMissingGroupRejected() throws {
    var catalog = ConfigurationCatalog()
    let document = CatalogSubscriptionSnapshot(
      name: "x", root: .init(id: groupID, name: "", children: []))

    XCTAssertThrowsError(
      try catalog.applySubscriptionSnapshot(document, into: NodeID(rawValue: "ghost")))
  }

  // MARK: 订阅子树删除

  func testRemoveSubscriptionSubtreeRemovesEverythingAndReportsCredentials() throws {
    var catalog = try makeCatalog()
    let manual = try catalog.addGroup("手动组", id: NodeID(rawValue: "manual:g"))
    _ = try catalog.addTestServer("手动服务器", id: NodeID(rawValue: "manual:s"), to: manual)

    let removed = try catalog.removeSubscriptionSubtree(of: groupID)

    XCTAssertEqual(removed.count, 4, "固定分组 + 嵌套组 + 两台服务器")
    XCTAssertEqual(catalog.entries.count, 2, "手动子树不受影响")
    XCTAssertFalse(catalog.rootChildren.contains(groupID))
    XCTAssertTrue(removed.allSatisfy { $0.source == .subscription })
    // 返回条目带凭据引用供调用方清理。
    let credentialRefs = removed.compactMap { entry -> String? in
      if case .server(let fields) = entry.kind { return fields.password }
      return nil
    }
    XCTAssertEqual(credentialRefs.count, 2)
  }

  func testRemoveMissingSubscriptionRejected() {
    var catalog = ConfigurationCatalog()
    XCTAssertThrowsError(
      try catalog.removeSubscriptionSubtree(of: NodeID(rawValue: "ghost")))
  }

  // MARK: 订阅子树变更后重展开（接线语义： 验收 4）

  func testActiveTargetInsideRefreshedSubtreeStillExpandsAfterSnapshot() throws {
    var catalog = try makeCatalog()
    var machine = ActivationStateMachine(activeTargetID: NodeID(rawValue: "sub1:id:a"))

    // 快照后 a 仍在（身份不变）→ 目标有效，重展开产出部署效应。叶子无插件，
    // 激活校验只依赖凭据解析；快照重建后按目录里的真实引用解析秘密。
    let document = CatalogSubscriptionSnapshot(
      name: "订阅分组",
      root: .init(
        id: groupID, name: "",
        children: [
          .server(
            CatalogSubscriptionSnapshot.ServerLeaf(
              id: NodeID(rawValue: "sub1:id:a"),
              fields: ServerFields(
                address: "203.0.113.1", port: 8388,
                encryptionMethod: "aes-256-gcm", password: "password")))
        ]))
    _ = try catalog.applySubscriptionSnapshot(document, into: groupID)

    let effect = machine.catalogDidCommit(
      catalog, plugins: NoManagedPluginProvider(),
      options: RuntimeDocumentOptions(listen: ProxyListeningConfiguration()))
    guard case .deployed(let configuration) = try XCTUnwrap(effect) else {
      return XCTFail("身份未变的活动目标应部署而非清除")
    }
    XCTAssertEqual(configuration.targetID, NodeID(rawValue: "sub1:id:a"))

    // 快照清空该目标 → 清除并停止。
    let empty = CatalogSubscriptionSnapshot(
      name: "订阅分组", root: .init(id: groupID, name: "", children: []))
    _ = try catalog.applySubscriptionSnapshot(empty, into: groupID)
    let cleared = machine.catalogDidCommit(
      catalog, plugins: NoManagedPluginProvider(),
      options: RuntimeDocumentOptions(listen: ProxyListeningConfiguration()))
    guard case .clearedAndStopped = try XCTUnwrap(cleared) else {
      return XCTFail("目标随远端删除消失后应清除并停止")
    }
    XCTAssertNil(machine.activeTargetID)
  }
}
