import XCTest

@testable import ShadowsocksX_NG2

/// 主缝测试：配置目录树操作。覆盖增删改、移动和重排，保持身份与
/// 子序；空组持久保留。非法操作的拒绝用例见 ConfigurationCatalogRejectionTests。
final class ConfigurationCatalogTests: XCTestCase {
  func testAddServersAtRootGeneratesFreshIdentityAndPreservesOrder() throws {
    var catalog = ConfigurationCatalog()
    let first = try catalog.addTestServer("香港 01")
    let second = try catalog.addTestServer("日本 02")

    XCTAssertNotEqual(first, second, "每次新建必须生成全新身份")
    XCTAssertEqual(try catalog.children(of: nil), [first, second], "根子序按插入顺序")
    let entry = try XCTUnwrap(catalog.entry(for: first))
    XCTAssertEqual(entry.source, .manual)
    guard case .server(let fields) = entry.kind else { return XCTFail("应为服务器叶子") }
    XCTAssertEqual(fields.remark, "香港 01")
    XCTAssertEqual(fields.address, "203.0.113.7")
    XCTAssertEqual(fields.port, 8388)
  }

  func testAddGroupWithProposedIDAndExplicitChildIndex() throws {
    var catalog = ConfigurationCatalog()
    let group = NodeID(rawValue: "manual-group-1")
    try catalog.addGroup("自用", id: group)
    let first = try catalog.addTestServer("a", to: group, index: 0)
    let second = try catalog.addTestServer("b", to: group)

    XCTAssertEqual(try catalog.children(of: group), [first, second])
    let third = try catalog.addTestServer("c", to: group, index: 1)
    XCTAssertEqual(try catalog.children(of: group), [first, third, second], "显式索引插入")
  }

  func testUpdateServerAndRenameGroupPreserveIdentityAndOrder() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("旧名")
    let orderBefore = try catalog.children(of: nil)
    let first = try catalog.addTestServer("a", to: group)
    let second = try catalog.addTestServer("b", to: group)

    let newFields = ServerFields(
      address: "198.51.100.9",
      port: 443,
      encryptionMethod: "chacha20-ietf-poly1305",
      password: "password",
      remark: "a-改名",
      pluginProgram: nil,
      pluginOptions: nil
    )
    try catalog.updateServer(first, with: newFields)
    try catalog.renameGroup(group, to: "新名")

    XCTAssertEqual(catalog.entry(for: first)?.id, first, "改字段不改身份")
    XCTAssertEqual(try catalog.children(of: group), [first, second], "改字段不改子序")
    XCTAssertEqual(try catalog.children(of: nil), orderBefore)
    guard case .server(let fields)? = catalog.entry(for: first)?.kind else {
      return XCTFail("目标应是服务器叶子")
    }
    XCTAssertEqual(fields.address, "198.51.100.9")
    XCTAssertEqual(fields.pluginProgram, nil, "插件字段按提交值原样存储")
    guard case .group(let groupFields) = catalog.entry(for: group)?.kind else {
      return XCTFail("目标应是分组")
    }
    XCTAssertEqual(groupFields.name, "新名")
  }

  func testMoveCarriesSubtreeWithoutChangingIdentityOrChildOrder() throws {
    var catalog = ConfigurationCatalog()
    let target = try catalog.addGroup("目标组")
    let moved = try catalog.addGroup("被移组")
    let leaf = try catalog.addTestServer("leaf", to: moved)
    let nested = try catalog.addGroup("嵌套组", to: moved)
    let deepLeaf = try catalog.addTestServer("deep", to: nested)

    try catalog.move(moved, to: target)

    XCTAssertEqual(try catalog.parentID(of: moved), target, "单父随移动更新")
    XCTAssertEqual(try catalog.children(of: moved), [leaf, nested], "子树与显子序原样携带")
    XCTAssertEqual(try catalog.children(of: nested), [deepLeaf])
    XCTAssertEqual(try catalog.children(of: nil), [target], "根子序只剩未移动节点")
    XCTAssertNotNil(catalog.entry(for: deepLeaf), "后代身份不变")
  }

  func testReorderWithinParentChangesOnlyPosition() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组")
    let first = try catalog.addTestServer("a", to: group)
    let second = try catalog.addTestServer("b", to: group)
    let third = try catalog.addTestServer("c", to: group)

    try catalog.move(second, to: group, index: 0)

    XCTAssertEqual(try catalog.children(of: group), [second, first, third])
  }

  func testRemoveServerLeafKeepsSiblingsAndReturnsEntryForCredentialCleanup() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组")
    let first = try catalog.addTestServer("a", to: group)
    let second = try catalog.addTestServer("b", to: group)

    let removed = try catalog.remove(first)

    XCTAssertEqual(removed.map(\.id), [first])
    XCTAssertEqual(catalog.contains(first), false)
    XCTAssertEqual(try catalog.children(of: group), [second])
    let entry = try XCTUnwrap(removed.first)
    guard case .server(let fields) = entry.kind else { return XCTFail("被删节点应是服务器叶子") }
    XCTAssertNotEqual(fields.password, "", "被删节点携带凭据引用，供调用方清理 Keychain")
  }

  func testRemoveNonEmptyManualGroupIsRecursive() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组")
    let leaf = try catalog.addTestServer("leaf", to: group)
    let nested = try catalog.addGroup("嵌套组", to: group)
    let deep = try catalog.addTestServer("deep", to: nested)

    let removed = try catalog.remove(group)

    XCTAssertEqual(Set(removed.map(\.id)), Set([group, leaf, nested, deep]))
    XCTAssertEqual(catalog.entries.count, 0, "整棵子树全部移除")
    XCTAssertEqual(try catalog.children(of: nil), [], "根子序同步移除")
  }

  func testEmptyGroupIsExplicitlyRemovableAndOtherwiseRetained() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("组")
    let only = try catalog.addTestServer("only", to: group)

    try catalog.remove(only)
    XCTAssertTrue(catalog.contains(group), "删空子节点后空组持久保留，不被回收")

    let removed = try catalog.remove(group)
    XCTAssertEqual(removed.map(\.id), [group])
    XCTAssertFalse(catalog.contains(group), "空组允许显式删除")
  }

}
