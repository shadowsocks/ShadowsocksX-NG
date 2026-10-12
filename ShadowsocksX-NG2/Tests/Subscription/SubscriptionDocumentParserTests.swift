import XCTest

@testable import ShadowsocksX_NG2

/// SIP-008 v1 + 私有扩展解析（验收：解码/schema/重复 ID/环/记录校验
/// 失败逐项覆盖；扩展缺失/未知/无效回退标准列表）。
final class SubscriptionDocumentParserTests: XCTestCase {
  private let subscriptionID = NodeID(rawValue: "sub-test")

  // MARK: 文档夹具

  private func flatDoc(serverCount: Int = 2) -> Data {
    let servers = (1...serverCount).map { index in
      """
      {"id": "00000000-0000-4000-8000-00000000000\(index)",
       "remarks": "节点 \(index)",
       "server": "203.0.113.\(index)", "server_port": \(8387 + index),
       "password": "pw\(index)", "method": "aes-256-gcm"}
      """
    }.joined(separator: ",")
    return Data(
      """
      {"version": 1, "servers": [\(servers)]}
      """.utf8)
  }

  private func treeDoc(
    schemaVersion: Int = 1,
    serverRefIDs: [String] = ["aaaaaaaa-0000-4000-8000-00000000000a"],
    groups: String? = nil,
    rootGroupID: String = "root"
  ) -> Data {
    let groupJSON: String
    if let groups {
      groupJSON = groups
    } else {
      let refs =
        serverRefIDs
        .map { #"{"type": "server", "id": "\#($0)"}"# }
        .joined(separator: ",")
      groupJSON = """
        {"id": "root", "name": "Example subscription", "children": [
           {"type": "group", "id": "jp"}\(refs.isEmpty ? "" : ", \(refs)")]},
        {"id": "jp", "name": "Japan", "children": [{"type": "server", "id": "bbbbbbbb-0000-4000-8000-00000000000b"}]}
        """
    }
    return Data(
      """
      {"version": 1,
       "servers": [
         {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "server": "203.0.113.1", "server_port": 8388,
          "password": "p1", "method": "aes-256-gcm"},
         {"id": "bbbbbbbb-0000-4000-8000-00000000000b", "server": "203.0.113.2", "server_port": 8389,
          "password": "p2", "method": "aes-256-gcm"}],
       "x_shadowsocksx_ng": {"schema_version": \(schemaVersion), "root_group_id": "\(rootGroupID)",
         "groups": [\(groupJSON)]}}
      """.utf8)
  }

  func parse(_ data: Data) throws -> SubscriptionSnapshot {
    try SubscriptionDocumentParser.parse(data, subscriptionID: subscriptionID)
  }

  private func serverIDs(_ group: SubscriptionSnapshot.Group) -> [String] {
    group.children.compactMap {
      if case .server(let leaf) = $0 { return leaf.id.rawValue }
      return nil
    }
  }

  private func serverRecords(_ group: SubscriptionSnapshot.Group) -> [RemoteServerRecord] {
    group.children.compactMap {
      if case .server(let leaf) = $0 { return leaf.record }
      return nil
    }
  }

  // MARK: 标准列表与扩展树

  func testFlatDocumentParsesServersInArrayOrder() throws {
    let snapshot = try parse(flatDoc())

    XCTAssertEqual(
      snapshot.root.children.filter { if case .group = $0 { return true } else { return false } }
        .count, 0, "扁平回退无嵌套分组")
    XCTAssertEqual(serverIDs(snapshot.root).count, 2)
    XCTAssertTrue(serverIDs(snapshot.root).allSatisfy { $0.hasPrefix("sub-test:id:") })
    let records = serverRecords(snapshot.root)
    XCTAssertEqual(records[0].address, "203.0.113.1")
    XCTAssertEqual(records[0].port, 8388)
    XCTAssertEqual(records[0].remark, "节点 1")
    XCTAssertEqual(records[1].password, "pw2")
  }

  func testExtensionTreeParsesNestedGroupsAndOrder() throws {
    let snapshot = try parse(treeDoc())

    XCTAssertEqual(snapshot.root.name, "Example subscription")
    // 根分组子序 = [嵌套组 Japan, 服务器 a]（远端交错顺序原样保留）。
    XCTAssertEqual(snapshot.root.children.count, 2)
    guard case .group(let japan) = snapshot.root.children[0] else {
      return XCTFail("首子应为嵌套组")
    }
    guard case .server(let rootServer) = snapshot.root.children[1] else {
      return XCTFail("次子应为服务器")
    }
    XCTAssertEqual(japan.name, "Japan")
    XCTAssertEqual(rootServer.record.address, "203.0.113.1")
    XCTAssertEqual(serverRecords(japan).map(\.address), ["203.0.113.2"])
    // 分组身份按订阅作用域限定且跨刷新稳定。
    XCTAssertTrue(japan.id.rawValue.hasPrefix("sub-test:g:jp"))
  }

  func testEmptyServersIsValidEmptySnapshot() throws {
    let snapshot = try parse(Data(#"{"version": 1, "servers": []}"#.utf8))

    XCTAssertEqual(snapshot.root.children.count, 0)
  }

  func testPluginFieldsCarriedVerbatim() throws {
    let data = Data(
      """
      {"version": 1, "servers": [
        {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "server": "203.0.113.1", "server_port": 443,
        "password": "p", "method": "aes-256-gcm",
        "plugin": "v2ray-plugin", "plugin_opts": "mode=websocket;host=example.com"}]}
      """.utf8)

    let snapshot = try parse(data)

    let records = serverRecords(snapshot.root)
    XCTAssertEqual(records[0].pluginProgram, "v2ray-plugin")
    XCTAssertEqual(records[0].pluginOptions, "mode=websocket;host=example.com")
  }

  // MARK: 扩展缺失/未知/无效 → 回退扁平

  func testMissingExtensionFallsBackToFlat() throws {
    let snapshot = try parse(flatDoc())

    XCTAssertEqual(snapshot.root.name, "", "扁平回退无根名（由调用方以 host 兜底）")
    XCTAssertEqual(serverIDs(snapshot.root).count, 2)
  }

  func testUnknownSchemaVersionFallsBackToFlat() throws {
    let snapshot = try parse(treeDoc(schemaVersion: 2))

    XCTAssertEqual(snapshot.root.name, "")
    XCTAssertEqual(serverIDs(snapshot.root).count, 2, "标准服务器不因扩展版本未知而丢失")
    XCTAssertEqual(
      snapshot.root.children.filter { if case .group = $0 { return true } else { return false } }
        .count, 0)
  }

  func testExtensionNotAnObjectFallsBackToFlat() throws {
    let data = Data(
      """
      {"version": 1, "servers": [], "x_shadowsocksx_ng": "broken"}
      """.utf8)

    let snapshot = try parse(data)

    XCTAssertEqual(serverIDs(snapshot.root).count, 0)
  }

  func testUnknownServerRefFallsBackToFlat() throws {
    let snapshot = try parse(treeDoc(serverRefIDs: ["ghost"]))

    XCTAssertEqual(snapshot.root.name, "")
    XCTAssertEqual(serverIDs(snapshot.root).count, 2, "引用损坏时保留标准服务器")
  }

  func testCycleFallsBackToFlat() throws {
    let groups = """
      {"id": "root", "name": "R", "children": [{"type": "group", "id": "jp"}]},
      {"id": "jp", "name": "J", "children": [{"type": "group", "id": "root"}]}
      """
    let snapshot = try parse(treeDoc(groups: groups))

    XCTAssertEqual(snapshot.root.name, "", "环使扩展无效 → 回退扁平")
    XCTAssertEqual(serverIDs(snapshot.root).count, 2)
    XCTAssertEqual(
      snapshot.root.children.filter { if case .group = $0 { return true } else { return false } }
        .count, 0)
  }

  func testSharedParentFallsBackToFlat() throws {
    let groups = """
      {"id": "root", "name": "R", "children": [
        {"type": "group", "id": "x"}, {"type": "group", "id": "y"}]},
      {"id": "x", "name": "X", "children": [{"type": "group", "id": "shared"}]},
      {"id": "y", "name": "Y", "children": [{"type": "group", "id": "shared"}]},
      {"id": "shared", "name": "S", "children": []}
      """
    let snapshot = try parse(treeDoc(groups: groups))

    XCTAssertEqual(snapshot.root.name, "", "同一分组被两个父引用 → 扩展无效")
  }

  func testDuplicateGroupIDFallsBackToFlat() throws {
    let groups = """
      {"id": "root", "name": "R", "children": []},
      {"id": "root", "name": "R2", "children": []}
      """
    let snapshot = try parse(treeDoc(groups: groups))

    XCTAssertEqual(snapshot.root.name, "")
  }

  func testGroupIDCollidingWithServerIDFallsBackToFlat() throws {
    let groups = """
      {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "name": "冒充服务器 ID", "children": []},
      {"id": "root", "name": "R", "children": [{"type": "group", "id": "aaaaaaaa-0000-4000-8000-00000000000a"}]}
      """
    let snapshot = try parse(treeDoc(groups: groups))

    XCTAssertEqual(snapshot.root.name, "")
  }

  func testMissingRootGroupFallsBackToFlat() throws {
    let snapshot = try parse(treeDoc(rootGroupID: "ghost"))

    XCTAssertEqual(snapshot.root.name, "")
    XCTAssertEqual(serverIDs(snapshot.root).count, 2)
  }

  func testUnreferencedServersAppendedToRootInArrayOrder() throws {
    let groups = """
      {"id": "root", "name": "R", "children": [{"type": "server", "id": "aaaaaaaa-0000-4000-8000-00000000000a"}]}
      """
    let data = Data(
      """
      {"version": 1,
       "servers": [
         {"id": "bbbbbbbb-0000-4000-8000-00000000000b", "server": "203.0.113.2", "server_port": 8389,
          "password": "p2", "method": "m"},
         {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "server": "203.0.113.1", "server_port": 8388,
          "password": "p1", "method": "m"}],
       "x_shadowsocksx_ng": {"schema_version": 1, "root_group_id": "root",
         "groups": [\(groups)]}}
      """.utf8)

    let snapshot = try parse(data)

    XCTAssertEqual(serverIDs(snapshot.root).count, 2, "未引用服务器不丢弃")
    XCTAssertEqual(serverRecords(snapshot.root)[0].address, "203.0.113.1", "树引用在前")
    XCTAssertEqual(serverRecords(snapshot.root)[1].address, "203.0.113.2", "未引用按数组序追加")
  }

  // MARK: 身份延续规则（无稳定 ID 按地址端口精确匹配延续）

  func testIdLessRecordIdentityIsStableForIdenticalContent() throws {
    let record =
      #"{"server": "203.0.113.1", "server_port": 8388, "password": "p", "method": "m"}"#
    let first = try parse(Data("{\"version\": 1, \"servers\": [\(record)]}".utf8))
    let second = try parse(Data("{\"version\": 1, \"servers\": [\(record)]}".utf8))

    XCTAssertEqual(serverIDs(first.root)[0], serverIDs(second.root)[0])
  }

  func testIdLessRecordIdentitySurvivesRemoteRename() throws {
    let base =
      #"{"server": "203.0.113.1", "server_port": 8388, "password": "p", "method": "m", "remarks": "r"}"#
    let original = try parse(Data("{\"version\": 1, \"servers\": [\(base)]}".utf8))
    // 仅改 remarks（远端改名）：显示元数据不参与端点指纹。
    let renamed =
      #"{"server": "203.0.113.1", "server_port": 8388, "password": "p", "method": "m", "remarks": "r2"}"#
    let changed = try parse(Data("{\"version\": 1, \"servers\": [\(renamed)]}".utf8))

    XCTAssertEqual(serverIDs(original.root)[0], serverIDs(changed.root)[0])
  }

  func testIdentityScopedPerSubscription() throws {
    let data = flatDoc()
    let other = try SubscriptionDocumentParser.parse(
      data, subscriptionID: NodeID(rawValue: "sub-other"))

    XCTAssertTrue(serverIDs(other.root).allSatisfy { $0.hasPrefix("sub-other:id:") })
    let baseline = try parse(data)
    XCTAssertNotEqual(serverIDs(other.root)[0], serverIDs(baseline.root)[0])
  }
}
