import Security
import XCTest

@testable import ShadowsocksX_NG2

/// 订阅端到端语义经目录工作流 module interface 观察：创建
/// 门禁、刷新失败保留快照、身份连续性、URL 编辑保身份、删除递归清除、卡片
/// projection 与提交接线。获取走 FakeSubscriptionFetcher（传输侧契约在
/// SubscriptionFetcherTests）；提交后的运行时收敛以确定性 fake 计数。
@MainActor
final class CatalogWorkflowSubscriptionTests: XCTestCase {
  private var workDir: URL!
  var fileURL: URL!
  var fetcher: FakeSubscriptionFetcher!
  var runtime: FakeCatalogRuntime!
  var workflow: CatalogWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("subscription-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    fileURL = workDir.appendingPathComponent("catalog.json")

    runtime = FakeCatalogRuntime()
    fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.flat(serverCount: 1)))
    workflow = makeWorkflow()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  func makeWorkflow(fetcher override: SubscriptionFetching? = nil) -> CatalogWorkflow {
    // 计数即提交计数：提交后的运行时收敛由协调器异步调度。
    runtime.hasActiveTarget = true
    let coordinator = CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(fileURL: fileURL), runtime: runtime)
    return makeCatalogWorkflow(
      coordinator: coordinator,
      plugins: NoManagedPluginProvider(),
      subscriptionFetcher: override ?? fetcher!)
  }

  /// 文档稳定 ID 后缀在树 projection 中定位节点（订阅前缀随机）。
  func findNode(withSuffix suffix: String) -> CatalogTreeNode? {
    var stack = workflow.tree.roots
    while let node = stack.popLast() {
      if node.id.rawValue.hasSuffix(suffix) { return node }
      stack.append(contentsOf: node.children ?? [])
    }
    return nil
  }

  var serverAID: NodeID {
    findNode(withSuffix: "aaaaaaaa-0000-4000-8000-00000000000a")?.id
      ?? NodeID(rawValue: "missing-a")
  }

  private var serverBID: NodeID {
    findNode(withSuffix: "bbbbbbbb-0000-4000-8000-00000000000b")?.id
      ?? NodeID(rawValue: "missing-b")
  }

  /// b 移到根 + a 改名 + 重排（远端改名/移动/排序跟随的对照文档）。
  var treeDoc: Data { SubscriptionDocs.tree() }
  private var changedTreeDoc: Data { SubscriptionDocs.treeRenamedAndReordered() }

  // MARK: 创建门禁

  func testCreateRequiresHTTPSURL() async {
    for bad in ["http://example.com/sub.json", "ftp://x/y", "不是 URL", "https://"] {
      do {
        _ = try await workflow.createSubscription(urlString: bad)
        XCTFail("「\(bad)」应被拒绝")
      } catch {
        XCTAssertEqual(error as? SubscriptionFormError, .invalidURL)
      }
    }
    XCTAssertTrue(workflow.subscriptions.isEmpty, "创建失败不留半成品")
    XCTAssertTrue(workflow.tree.isEmpty)
  }

  func testCreateAddsRecordEmptyGroupAndRefreshes() async throws {
    fetcher = FakeSubscriptionFetcher(behavior: .success(treeDoc))
    workflow = makeWorkflow()

    let summary = try await workflow.createSubscription(
      urlString: "https://provider.example.com/sub.json")

    XCTAssertEqual(summary.id, workflow.subscriptions.first?.id)
    XCTAssertEqual(fetcher.lastURL?.host, "provider.example.com", "创建即首次刷新")
    let group = try XCTUnwrap(workflow.tree.node(withID: summary.groupID))
    XCTAssertTrue(group.isGroup)
    XCTAssertEqual(group.name, "Example subscription", "名称跟随远端根分组")
    XCTAssertFalse(group.isManual)
    guard case .succeeded = workflow.subscriptions[0].status else {
      return XCTFail("首次刷新成功应记成功态")
    }
  }

  func testFirstRefreshFailureLeavesEmptyGroupWithFailedStatus() async throws {
    fetcher = FakeSubscriptionFetcher(
      behavior: .failure(.transport(detail: "URLError.timedOut")))
    workflow = makeWorkflow()

    let created = try await workflow.createSubscription(
      urlString: "https://provider.example.com/s.json")

    XCTAssertNotNil(workflow.tree.node(withID: created.groupID), "首刷失败仍留空分组")
    XCTAssertEqual(created.name, "provider.example.com", "空分组以 host 兜底")
    guard case .failed(_, let reason) = workflow.subscriptions[0].status else {
      return XCTFail("首刷失败应记失败态")
    }
    XCTAssertEqual(reason, .transport(.timedOut))
  }

  // MARK: 身份连续性

  func testRemoteRenameMoveReorderFollowsWithoutLocalOverlay() async throws {
    fetcher = FakeSubscriptionFetcher(behavior: .success(treeDoc))
    workflow = makeWorkflow()
    let record = try await workflow.createSubscription(urlString: "https://p.example.com/s.json")
    fetcher.setBehavior(.success(changedTreeDoc))
    await workflow.refreshSubscription(record.id)

    // 身份不变；名称/位置/顺序跟随远端。
    XCTAssertEqual(findNode(withSuffix: "aaaaaaaa-0000-4000-8000-00000000000a")?.name, "香港 01（新名）")
    let group = try XCTUnwrap(workflow.tree.node(withID: record.groupID))
    let japanGroupID = try XCTUnwrap(
      findNode(withSuffix: "g:jp")?.id,
      "嵌套分组应存在")
    XCTAssertEqual(group.children?.map(\.id), [serverBID, japanGroupID], "远端排序跟随")
  }

  func testIdLessServerContinuityOnlyForExactMatch() async throws {
    fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.idLess()))
    workflow = makeWorkflow()
    let record = try await workflow.createSubscription(urlString: "https://p.example.com/s.json")
    let serverID = try XCTUnwrap(onlyServerChildID(ofGroup: record.groupID))
    // 完全相同记录 → 身份延续。
    await workflow.refreshSubscription(record.id)
    XCTAssertEqual(onlyServerChildID(ofGroup: record.groupID), serverID)

    // 端口变化 → 新身份：旧节点删除（无墓碑）。
    fetcher.setBehavior(.success(SubscriptionDocs.idLess(port: 9999)))
    await workflow.refreshSubscription(record.id)
    XCTAssertNil(workflow.tree.node(withID: serverID), "无稳定 ID 且记录变化即不同节点")
    let newID = try XCTUnwrap(onlyServerChildID(ofGroup: record.groupID))
    XCTAssertNotEqual(newID, serverID)
  }

  // MARK: URL 编辑与删除

  func testEditURLKeepsIdentityAndRetainsSnapshotUntilSuccess() async throws {
    let record = try await seedSuccessfulSubscription()
    let originalRecordID = record.id
    let originalGroupID = record.groupID

    // 新地址先失败：快照保留、身份不动。
    fetcher.setBehavior(.failure(.httpStatus(code: 404)))
    try await workflow.editSubscriptionURL(
      record.id, urlString: "https://other.example.com/v2.json")
    XCTAssertEqual(workflow.subscriptions[0].id, originalRecordID, "订阅身份保留")
    guard case .failed = workflow.subscriptions[0].status else {
      return XCTFail("新地址失败应记失败态")
    }
    XCTAssertEqual(fetcher.lastURL?.host, "other.example.com")
    XCTAssertNotNil(findNode(withSuffix: "aaaaaaaa-0000-4000-8000-00000000000a"), "失败保留最后成功快照")

    // 新地址成功：同一身份命名空间下应用新内容。
    fetcher.setBehavior(.success(SubscriptionDocs.flat(serverCount: 1)))
    await workflow.refreshSubscription(record.id)
    XCTAssertEqual(workflow.subscriptions[0].groupID, originalGroupID)
    guard case .succeeded = workflow.subscriptions[0].status else {
      return XCTFail("换址成功应记成功态，实际 \(workflow.subscriptions[0].status)")
    }
    XCTAssertEqual(workflow.tree.roots.count, 1)
  }

  func testEditURLRequiresHTTPS() async throws {
    let record = try await seedSuccessfulSubscription()
    await expectThrowsAsync(
      { try await workflow.editSubscriptionURL(record.id, urlString: "http://p.example.com/x") },
      onThrow: { error in
        XCTAssertEqual(error as? SubscriptionFormError, .invalidURL)
      })
  }

  func testRemoveSubscriptionClearsSubtreeCredentialsAndReportsInvalidation() async throws {
    let record = try await seedSuccessfulSubscription()
    // 身份在删除前捕获(删除后树上已不存在)。
    let serverA = serverAID
    let serverB = serverBID
    let convergesBefore = runtime.convergeCount

    let outcome = try await workflow.removeSubscription(record.id)

    XCTAssertTrue(workflow.subscriptions.isEmpty, "订阅记录移除")
    XCTAssertNil(workflow.tree.node(withID: record.groupID), "固定分组递归清除")
    XCTAssertNil(workflow.tree.node(withID: serverA))
    XCTAssertNil(workflow.tree.node(withID: serverB))
    XCTAssertTrue(
      outcome.removedNodeIDs.contains(serverA) && outcome.removedNodeIDs.contains(record.groupID)
        && outcome.removedNodeIDs.contains(serverB),
      "删除结果携带被删子树身份（selection invalidation，story 18/30）")
    XCTAssertNil(readURLSecret(), "订阅 URL 凭据一并清理")
    await waitUntilRuntimeSettles(runtime.convergeCount - convergesBefore == 1)
    XCTAssertEqual(runtime.convergeCount - convergesBefore, 1, "删除经提交协调器触发活动目标重展开")
  }

  // MARK: 夹具与辅助

  private func onlyServerChildID(ofGroup groupID: NodeID) -> NodeID? {
    guard let group = workflow.tree.node(withID: groupID),
      group.childCount == 1,
      let only = group.children?.first,
      !only.isGroup
    else { return nil }
    return only.id
  }

  /// 订阅 URL 秘密的观察口：创建后恰有一个订阅 URL 凭据；删除后应为 nil。
  /// （凭据引用不进投影；经存储快照里的唯一 URL 值反查。）
  private func readURLSecret() -> String? {
    workflow.subscriptions.first.flatMap { try? workflow.subscriptionURL(for: $0.id) }
  }

  /// 建一个「创建 + 首刷成功（tree 文档，服务器 a/b）」的订阅。
  func seedSuccessfulSubscription() async throws -> SubscriptionSummary {
    fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.tree()))
    workflow = makeWorkflow()
    return try await createOnly(urlString: "https://p.example.com/s.json")
  }

  func createOnly(urlString: String) async throws -> SubscriptionSummary {
    try await workflow.createSubscription(urlString: urlString)
  }
}

/// SIP-008 文档夹具（订阅工作流语义测试）。
enum SubscriptionDocs {
  private static let stableServerA = "aaaaaaaa-0000-4000-8000-00000000000a"
  private static let stableServerB = "bbbbbbbb-0000-4000-8000-00000000000b"

  static func serverJSON(id: String, address: String, port: Int, remark: String) -> String {
    """
    {"id": "\(id)", "remarks": "\(remark)", "server": "\(address)", "server_port": \(port), \
    "password": "pw", "method": "aes-256-gcm"}
    """
  }

  static func flat(serverCount: Int) -> Data {
    guard serverCount > 0 else {
      return Data(#"{"version": 1, "servers": []}"#.utf8)
    }
    let servers = (1...serverCount).map {
      serverJSON(
        id: String(format: "%08x-0000-4000-8000-%012d", $0, $0), address: "203.0.113.\($0)",
        port: 8388 + $0, remark: "节点 \($0)")
    }.joined(separator: ",")
    return Data(
      """
      {"version": 1, "servers": [\(servers)]}
      """.utf8)
  }

  /// 根分组 [嵌套组 Japan(→b), 服务器 a]；稳定 UUID a/b。
  static func tree() -> Data {
    Data(
      """
      {"version": 1,
       "servers": [
         {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "remarks": "香港 01", "server": "203.0.113.1",
          "server_port": 8388, "password": "pa", "method": "aes-256-gcm"},
         {"id": "bbbbbbbb-0000-4000-8000-00000000000b", "remarks": "日本 02", "server": "203.0.113.2",
          "server_port": 8389, "password": "pb", "method": "aes-256-gcm"}],
       "x_shadowsocksx_ng": {"schema_version": 1, "root_group_id": "root",
         "groups": [
           {"id": "root", "name": "Example subscription", "children": [
             {"type": "group", "id": "jp"}, {"type": "server", "id": "aaaaaaaa-0000-4000-8000-00000000000a"}]},
           {"id": "jp", "name": "Japan", "children": [
             {"type": "server", "id": "bbbbbbbb-0000-4000-8000-00000000000b"}]}]}}
      """.utf8)
  }

  /// 远端改名 + b 移到根 + 重排：[b, Japan(空)]，a 改名留在 Japan。
  static func treeRenamedAndReordered() -> Data {
    Data(
      """
      {"version": 1,
       "servers": [
         {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "remarks": "香港 01（新名）", "server": "203.0.113.1",
          "server_port": 8388, "password": "pa", "method": "aes-256-gcm"},
         {"id": "bbbbbbbb-0000-4000-8000-00000000000b", "remarks": "日本 02", "server": "203.0.113.2",
          "server_port": 8389, "password": "pb", "method": "aes-256-gcm"}],
       "x_shadowsocksx_ng": {"schema_version": 1, "root_group_id": "root",
         "groups": [
           {"id": "root", "name": "Example subscription", "children": [
             {"type": "server", "id": "bbbbbbbb-0000-4000-8000-00000000000b"},
             {"type": "group", "id": "jp"}]},
           {"id": "jp", "name": "Japan", "children": [
             {"type": "server", "id": "aaaaaaaa-0000-4000-8000-00000000000a"}]}]}}
      """.utf8)
  }

  static func duplicateIDs() -> Data {
    let server = serverJSON(id: stableServerA, address: "203.0.113.1", port: 8388, remark: "x")
    let duplicate = serverJSON(id: stableServerA, address: "203.0.113.2", port: 9999, remark: "y")
    return Data(
      """
      {"version": 1, "servers": [\(server), \(duplicate)]}
      """.utf8)
  }

  static func invalidRecord() -> Data {
    Data(
      """
      {"version": 1, "servers": [
        {"id": "\(stableServerA)", "server": "203.0.113.1", "server_port": 0,
         "password": "p", "method": "m"}]}
      """.utf8)
  }

  static func idLess(port: Int = 8388) -> Data {
    Data(
      """
      {"version": 1, "servers": [
        {"server": "203.0.113.5", "server_port": \(port), "password": "p",
         "method": "m", "remarks": "无名"}]}
      """.utf8)
  }

  static func cycleExtension() -> Data {
    Data(
      """
      {"version": 1,
       "servers": [
         {"id": "\(stableServerA)", "server": "203.0.113.1", "server_port": 8388, "password": "pa", "method": "m"},
         {"id": "\(stableServerB)", "server": "203.0.113.2", "server_port": 8389, "password": "pb", "method": "m"}],
       "x_shadowsocksx_ng": {"schema_version": 1, "root_group_id": "root",
         "groups": [
           {"id": "root", "name": "R", "children": [{"type": "group", "id": "x"}]},
           {"id": "x", "name": "X", "children": [{"type": "group", "id": "root"}]}]}}
      """.utf8)
  }
}
