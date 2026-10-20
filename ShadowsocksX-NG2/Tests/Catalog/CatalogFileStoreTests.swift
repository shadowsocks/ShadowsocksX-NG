import XCTest

@testable import ShadowsocksX_NG2

/// 持久化缝：往返无损、文件缺失/损坏行为明确、权限基线、不含明文秘密。
final class CatalogFileStoreTests: XCTestCase {
  private var workDir: URL!
  var store: CatalogFileStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-file-store-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    store = makeTestCatalogStore(fileURL: workDir.appendingPathComponent("catalog.json"))
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: workDir)
    try super.tearDownWithError()
  }

  // MARK: 往返无损

  func testRoundTripIsLosslessAndKeepsIdentity() throws {
    let original = try Self.makeRichCatalog()

    try store.save(CatalogDocument(catalog: original))
    let loaded = try store.load()

    XCTAssertEqual(loaded.catalog, original, "结构、顺序、字段与订阅夹具全部无损")

    let serverID = NodeID(rawValue: "manual:server")
    let server = try XCTUnwrap(loaded.catalog.entry(for: serverID))
    XCTAssertEqual(server.id, serverID, "身份跨持久化稳定")
    guard case .server(let fields) = server.kind else { return XCTFail("目标应是服务器叶子") }
    XCTAssertEqual(fields.pluginProgram, "v2ray-plugin", "插件程序引用原样保留")
    XCTAssertEqual(fields.pluginOptions, "options")
  }

  func testSecondSaveReplacesContent() throws {
    var catalog = ConfigurationCatalog()
    let first = try catalog.addTestServer("first")
    try store.save(CatalogDocument(catalog: catalog))

    try catalog.remove(first)
    _ = try catalog.addTestServer("second")
    try store.save(CatalogDocument(catalog: catalog))

    XCTAssertEqual(try store.load().catalog, catalog)
    XCTAssertFalse(try store.load().catalog.contains(first), "旧内容被整体替换而非追加")
  }

  // MARK: 敏感信息

  func testPersistedFileContainsNoPlaintextSecrets() throws {
    var catalog = ConfigurationCatalog()
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      password: "TOPSECRET-密码",
      remark: "含插件",
      pluginProgram: "v2ray-plugin",
      pluginOptions: "obfs-local;obfs=http"
    )
    _ = try catalog.addServer(fields)

    try store.save(CatalogDocument(catalog: catalog))

    let raw = try Data(contentsOf: store.fileURL)
    XCTAssertFalse(raw.range(of: Data("TOPSECRET-密码".utf8)) != nil, "密码明文不得进入持久化文件")
    XCTAssertFalse(raw.range(of: Data("obfs-local;obfs=http".utf8)) != nil, "插件参数明文不得进入持久化文件")
  }

  /// 富夹具：订阅子树 + 手动组嵌套 + 空组 + 无效节点 + 重排后子序。
  static func makeRichCatalog() throws -> ConfigurationCatalog {
    var catalog = try CatalogFixtures.makeSubscriptionFixture(prefix: "sub9").catalog
    let group = NodeID(rawValue: "manual:group")
    try catalog.addGroup("手动组", id: group)
    let server = NodeID(rawValue: "manual:server")
    try catalog.addServer(
      ServerFields(
        address: "198.51.100.5",
        port: 443,
        encryptionMethod: "chacha20-ietf-poly1305",
        password: "password",
        remark: "带插件",
        pluginProgram: "v2ray-plugin",
        pluginOptions: "options"
      ),
      id: server,
      to: group
    )
    _ = try catalog.addTestServer("无效", to: group)
    try catalog.addGroup("空组", id: NodeID(rawValue: "manual:empty"))
    try catalog.move(server, to: group, index: 0)
    return catalog
  }

  // MARK: 订阅记录文档（v2）

  func testSubscriptionRecordRoundTripsWithStatus() throws {
    let catalog = try CatalogFixtures.makeSubscriptionFixture(prefix: "sub2").catalog
    let record = SubscriptionRecord(
      id: NodeID(rawValue: "sub2:source"),
      groupID: NodeID(rawValue: "sub2:group"),
      url: "https://provider.example/sub",
      status: .failed(
        at: Date(timeIntervalSince1970: 1_789_000_000),
        failure: .httpStatus(code: 503)))

    try store.save(CatalogDocument(catalog: catalog, subscriptions: [record]))
    let loaded = try store.load()

    XCTAssertEqual(loaded.subscriptions, [record], "订阅记录与刷新状态无损")
    XCTAssertEqual(loaded.catalog, catalog)
    XCTAssertFalse(
      try Data(contentsOf: store.fileURL).range(of: Data("https://".utf8)) != nil,
      "订阅 URL 明文不得落盘（D5：只存凭据引用）")
  }

  // MARK: 节点时间戳（v5，ADR-0031）

  func testNodeTimestampsRoundTripLosslessly() throws {
    var catalog = ConfigurationCatalog()
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let id = try catalog.addServer(
      ServerFields(
        address: "198.51.100.9",
        port: 8388,
        encryptionMethod: "aes-256-gcm",
        password: "password",
        remark: "时间戳"
      ),
      id: NodeID(rawValue: "manual:timestamped"),
      now: created
    )

    try store.save(CatalogDocument(catalog: catalog))
    let loaded = try store.load()

    let entry = try XCTUnwrap(loaded.catalog.entry(for: id))
    XCTAssertEqual(entry.createdAt, created, "创建时间无损")
    XCTAssertEqual(entry.updatedAt, created)
  }

  /// 订阅记录 JSON 用真编码器生成：枚举 Codable 形状是实现细节，不在测试里手写。
  private func subscriptionJSON(
    id: String, groupID: String, url: String = "https://provider.example/sub"
  ) throws -> String {
    let record = SubscriptionRecord(
      id: NodeID(rawValue: id),
      groupID: NodeID(rawValue: groupID),
      url: url,
      status: .never)
    return String(data: try JSONEncoder().encode(record), encoding: .utf8)!
  }

  func testSubscriptionGroupMissingLoadsAsCorrupt() throws {
    let recordJSON = try subscriptionJSON(id: "sub-x", groupID: "ghost")
    let payload =
      """
      {"version": 7, "rootChildren": [], "entries": [], "favoriteIDs": [], "subscriptions": [\(recordJSON)]}
      """
    XCTAssertThrowsError(try CatalogFileStore.decode(Data(payload.utf8))) { error in
      guard
        case CatalogFileStore.PersistenceError.corrupt? = error
          as? CatalogFileStore.PersistenceError
      else {
        return XCTFail("固定分组缺失应报 corrupt，实际 \(error)")
      }
    }
  }

  func testDuplicateSubscriptionIDLoadsAsCorrupt() throws {
    let first = try subscriptionJSON(id: "sub-x", groupID: "g1", url: "https://provider.example/u")
    let second = try subscriptionJSON(id: "sub-x", groupID: "g1", url: "https://provider.example/v")
    let payload =
      """
      {"version": 7, "rootChildren": [], "entries": [], "favoriteIDs": [], "subscriptions": [\(first), \(second)]}
      """
    XCTAssertThrowsError(try CatalogFileStore.decode(Data(payload.utf8))) { error in
      guard
        case CatalogFileStore.PersistenceError.corrupt? = error
          as? CatalogFileStore.PersistenceError
      else {
        return XCTFail("重复订阅身份应报 corrupt，实际 \(error)")
      }
    }
  }
}
