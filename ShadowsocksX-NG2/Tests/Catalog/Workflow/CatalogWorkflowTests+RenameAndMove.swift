import XCTest

@testable import ShadowsocksX_NG2

@MainActor
extension CatalogWorkflowTests {
  // MARK: - 重命名与移动

  func testRenameGroupKeepsIdentityParentAndOrder() async throws {
    let groupID = try await workflow.createGroup(named: "旧名", into: nil)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: groupID)
    try await workflow.renameGroup(groupID, to: "新名")
    let node = try XCTUnwrap(workflow.tree.node(withID: groupID))
    XCTAssertEqual(node.name, "新名")
    XCTAssertEqual(node.childCount, 1, "identity 与子项顺序不变(story 6)")
    await expectThrowsAsync(
      { try await workflow.renameGroup(groupID, to: "  ") },
      onThrow: { error in XCTAssertEqual(error as? ServerFormError, .emptyName) })
  }

  func testMoveRejectsCrossSourceAndCycle() async throws {
    try makeSubscriptionCatalog()
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    let manualGroupID = try await workflow.createGroup(named: "手动组", into: nil)

    await expectThrowsAsync { try await workflow.move(fixture.serverIDs[0], to: manualGroupID) }
    await expectThrowsAsync { _ = try await workflow.remove(fixture.serverIDs[0]) }
    await expectThrowsAsync { try await workflow.renameGroup(fixture.groupID, to: "改名") }
    await expectThrowsAsync {
      try await workflow.updateServer(
        fixture.serverIDs[0],
        draft: ServerEditDraft(
          address: "0.0.0.0", port: 1, encryptionMethod: "x", password: "p",
          remark: "", plugin: .none, pluginOptions: nil))
    }
    // 手动节点移进订阅子树同样被拒（跨来源）。
    await expectThrowsAsync { try await workflow.move(manualGroupID, to: fixture.groupID) }
    // 分组移动进自身子树被拒（成环）。
    let nestedID = try await workflow.createGroup(named: "嵌套", into: manualGroupID)
    await expectThrowsAsync { try await workflow.move(manualGroupID, to: nestedID) }
  }
}
