import XCTest

@testable import ShadowsocksX_NG2

/// 目录工作流 module 的 UI-facing interface 测试：三入口导入、
/// 手动服务器/分组创建、重命名、移动、删除、来源所有权、树 projection 与
/// 分享往返。全部观察 projection、command outcome 与 typed error，不锁定
/// SwiftUI 视图层级或内部存储；凭据生命周期经注入的内存存储观察。提交后的
/// 运行时收敛以确定性 fake 计数。
@MainActor
final class CatalogWorkflowTests: XCTestCase {
  private var workDir: URL!
  private var fileURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var runtime: FakeCatalogRuntime!
  var workflow: CatalogWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    // 专用工作目录：写入器会把父目录强制 0700（不得指向临时根）。
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    fileURL = workDir.appendingPathComponent("catalog.json")
    credentials = InMemoryCredentialStore()
    runtime = FakeCatalogRuntime()
    workflow = makeWorkflow()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  private func makeWorkflow() -> CatalogWorkflow {
    // 计数即提交计数：提交后的运行时收敛由协调器异步调度。
    runtime.hasActiveTarget = true
    let coordinator = CatalogCommitCoordinator(
      fileStore: CatalogFileStore(fileURL: fileURL), runtime: runtime)
    return makeCatalogWorkflow(
      coordinator: coordinator,
      credentials: credentials,
      plugins: NoManagedPluginProvider())
  }

  func makeSubscriptionCatalog() throws {
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: fixture.catalog))
    workflow = makeWorkflow()
  }

  // MARK: - 三入口导入（共同落点）

  func testImportMixedLinesAddsParsedAndReportsFailures() async throws {
    let validSIP002 = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#香港 01"
    let legacy = "ss://YWVzLTI1Ni1nY206dGVzdEAyMDMuMC4xMTMuNzo4Mzg4"
    let outcome = await workflow.importServers(
      from: [.clipboardText("\(validSIP002)\n垃圾行\n\(legacy)")], into: nil)
    let facts = try XCTUnwrap(outcome.sources.first?.result.partialFacts)
    XCTAssertEqual(facts.addedCount, 2)
    XCTAssertEqual(facts.failures.count, 1)
    XCTAssertEqual(facts.failures[0].lineIndex, 1, "失败行按换行切分点名")

    let roots = workflow.tree.roots
    XCTAssertEqual(roots.count, 2)
    XCTAssertEqual(roots[0].name, "香港 01", "备注优先的显示名")
    XCTAssertEqual(
      try workflow.serverEditForm(for: roots[0].id)?.password, "password123", "密码入凭据存储")
    XCTAssertTrue(roots[0].invalidReasons.isEmpty)
    // 两个身份均为全新 UUID 形态（不按内容去重）。
    XCTAssertNotEqual(roots[0].id, roots[1].id)
  }

  func testImportWithPluginStoresProgramAndOptions() async throws {
    let uri =
      "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388"
      + "/?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3Dexample.com"
    _ = await workflow.importServers(from: [.clipboardText(uri)], into: nil)
    let id = try XCTUnwrap(workflow.tree.roots.first?.id)
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .named(program: "v2ray-plugin"))
    XCTAssertTrue(plugin.optionsPresent)
    // NoManagedPluginProvider:程序引用保留但可执行文件缺失(集外点名事实)。
    XCTAssertEqual(plugin.programs.first { $0.program == "v2ray-plugin" }?.availability, .missing)
    XCTAssertEqual(plugin.options, "mode=websocket;host=example.com")
  }

  func testImportUnsupportedMethodKeepsServerAsInvalidCandidate() async throws {
    let uri = SsUri(
      method: "future-cipher", password: "password", host: "203.0.113.7", port: 8388
    ).encode()

    let outcome = await workflow.importServers(from: [.clipboardText(uri)], into: nil)

    XCTAssertEqual(outcome.sources.first?.result.importedCount, 1)
    let node = try XCTUnwrap(workflow.tree.roots.first)
    XCTAssertEqual(
      node.invalidReasons, [.unsupportedEncryptionMethod("future-cipher")],
      "不支持的方法保留并明确标记为无效(story 9)")
  }

  func testImportIntoSelectedManualGroup() async throws {
    let groupID = try await workflow.createGroup(named: "手动组", into: nil)
    let target = try XCTUnwrap(workflow.importTargetParent(for: groupID))
    XCTAssertEqual(target, groupID)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: target)
    XCTAssertEqual(workflow.tree.node(withID: groupID)?.childCount, 1)
    // 选中服务器时落到其手动父组；无选中落到根。
    let serverID = try XCTUnwrap(workflow.tree.node(withID: groupID)?.children?.first?.id)
    XCTAssertEqual(workflow.importTargetParent(for: serverID), groupID)
    XCTAssertNil(workflow.importTargetParent(for: nil))
  }

  func testImportTargetSkipsSubscriptionSubtree() async throws {
    try makeSubscriptionCatalog()
    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    XCTAssertEqual(workflow.importTargetParent(for: fixture.groupID), nil)
    XCTAssertEqual(workflow.importTargetParent(for: fixture.serverIDs[0]), nil)
  }

  // MARK: - 树 projection

  func testTreeSnapshotMirrorsStructureCountsAndParents() async throws {
    let groupID = try await workflow.createGroup(named: "组A", into: nil)
    let nestedID = try await workflow.createGroup(named: "嵌套", into: groupID)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: nestedID)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.8:8388")],
      into: nil)

    let group = try XCTUnwrap(workflow.tree.node(withID: groupID))
    XCTAssertTrue(group.isGroup)
    XCTAssertTrue(group.isManual)
    XCTAssertEqual(group.parentID, nil)
    XCTAssertEqual(group.childCount, 1)
    XCTAssertEqual(group.subtreeNodeCount, 2, "嵌套分组 + 服务器叶子")
    let nested = try XCTUnwrap(group.children?.first)
    XCTAssertEqual(nested.id, nestedID)
    XCTAssertEqual(nested.parentID, groupID)
    let rootServer = try XCTUnwrap(workflow.tree.roots.last)
    XCTAssertFalse(rootServer.isGroup)
    XCTAssertFalse(rootServer.isInvalid)
    XCTAssertNil(rootServer.children)
    XCTAssertTrue(workflow.tree.containsNode(groupID))
  }

  // MARK: - 活动目标路径摘要（代理控制窄缝取用）

  func testPathSummaryResolvesRootToLeafNames() async throws {
    let groupID = try await workflow.createGroup(named: "组A", into: nil)
    let nestedID = try await workflow.createGroup(named: "嵌套", into: groupID)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: nestedID)
    let leafID = try XCTUnwrap(workflow.tree.node(withID: nestedID)?.childNodes.first?.id)

    XCTAssertEqual(workflow.tree.pathSummary(for: groupID), "组A")
    XCTAssertEqual(workflow.tree.pathSummary(for: nestedID), "组A / 嵌套")
    XCTAssertEqual(workflow.tree.pathSummary(for: leafID), "组A / 嵌套 / 203.0.113.7:8388")
  }

  func testPathSummaryIsNilForMissingTarget() {
    XCTAssertNil(workflow.tree.pathSummary(for: NodeID(rawValue: "gone")))
  }

  // MARK: - 表单编辑与凭据生命周期

  func testUpdateServerPersistsFieldsAndPassword() async throws {
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: nil)
    let id = try XCTUnwrap(workflow.tree.roots.first?.id)
    try await workflow.updateServer(
      id,
      draft: ServerEditDraft(
        address: "198.51.100.9", port: 9999,
        encryptionMethod: "chacha20-ietf-poly1305", password: "新密码",
        remark: "改过的", plugin: .none, pluginOptions: nil))
    let form = try XCTUnwrap(try workflow.serverEditForm(for: id))
    XCTAssertEqual(form.address, "198.51.100.9")
    XCTAssertEqual(form.port, 9999)
    XCTAssertEqual(form.remark, "改过的")
    XCTAssertEqual(form.password, "新密码", "同一引用始终对应最新秘密")
    XCTAssertEqual(form.encryptionMethod, "chacha20-ietf-poly1305")
    // 连续提交合并为最新代次的收敛：旧代次在启动前被取代，
    // 最终结果必为最新提交快照。
    await waitUntilRuntimeSettles(workflow.runtimeSync != .syncing(generation: 2))
    XCTAssertEqual(
      workflow.runtimeSync,
      .finished(generation: 2, outcome: .converged(skippedServers: [])),
      "目录提交与运行时收敛分离呈现(story 38)")
  }

  func testUpdateServerRejectsInvalidAddressAndPort() async throws {
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: nil)
    let id = try XCTUnwrap(workflow.tree.roots.first?.id)
    await expectThrowsAsync(
      {
        try await workflow.updateServer(
          id,
          draft: ServerEditDraft(
            address: "  ", port: 8388, encryptionMethod: "aes-256-gcm", password: "p",
            remark: "", plugin: .none, pluginOptions: nil))
      },
      onThrow: { error in
        XCTAssertEqual(error as? ServerFormError, .invalidAddress)
      })
    await expectThrowsAsync(
      {
        try await workflow.updateServer(
          id,
          draft: ServerEditDraft(
            address: "203.0.113.7", port: 0, encryptionMethod: "aes-256-gcm", password: "p",
            remark: "", plugin: .none, pluginOptions: nil))
      },
      onThrow: { error in
        XCTAssertEqual(error as? ServerFormError, .invalidPort)
      })
  }

  func testRemoveServerCleansCredentials() async throws {
    // 已知凭据引用直建目录（模块投影不含引用；身份经文件夹具固定）。
    var catalog = ConfigurationCatalog()
    let fields = ServerFields(
      address: "203.0.113.7", port: 8388, encryptionMethod: "aes-256-gcm",
      passwordRef: CredentialReference(rawValue: "ref-pw"), remark: "删除我",
      pluginProgram: "v2ray-plugin",
      pluginOptionsRef: CredentialReference(rawValue: "ref-opts"))
    try credentials.save("pw", for: fields.passwordRef)
    try credentials.save("opts", for: try XCTUnwrap(fields.pluginOptionsRef))
    try catalog.addServer(fields)
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: catalog))
    workflow = makeWorkflow()

    let id = try XCTUnwrap(workflow.tree.roots.first?.id)
    let outcome = try await workflow.remove(id)

    XCTAssertEqual(outcome.removedNodeIDs, [id], "删除返回 selection invalidation(story 18)")
    XCTAssertTrue(workflow.tree.isEmpty)
    XCTAssertNil(try credentials.secret(for: fields.passwordRef), "密码秘密已清理")
    XCTAssertNil(
      try credentials.secret(for: try XCTUnwrap(fields.pluginOptionsRef)), "插件参数秘密已清理")
  }

  func testRemoveNonEmptyGroupRemovesWholeSubtree() async throws {
    let groupID = try await workflow.createGroup(named: "组", into: nil)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: groupID)
    let serverID = try XCTUnwrap(workflow.tree.node(withID: groupID)?.children?.first?.id)
    let outcome = try await workflow.remove(groupID)
    XCTAssertEqual(outcome.removedNodeIDs, [groupID, serverID])
    XCTAssertTrue(workflow.tree.isEmpty)
  }

  // MARK: - 分享（与添加互逆）

  func testShareSsUriRoundTripsBackThroughImport() async throws {
    let source =
      "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388"
      + "/?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3Dexample.com#分享节点"
    _ = await workflow.importServers(from: [.clipboardText(source)], into: nil)
    let id = try XCTUnwrap(workflow.tree.roots.first?.id)
    let shared = try workflow.shareURI(for: id)
    let decoded = try SsUri.decode(shared)
    XCTAssertEqual(decoded.method, "aes-256-gcm")
    XCTAssertEqual(decoded.password, "password123")
    XCTAssertEqual(decoded.host, "203.0.113.7")
    XCTAssertEqual(decoded.port, 8388)
    XCTAssertEqual(decoded.pluginProgram, "v2ray-plugin")
    XCTAssertEqual(decoded.pluginOptions, "mode=websocket;host=example.com")
    XCTAssertEqual(decoded.remark, "分享节点")
  }

  func testShareFailsWhenCredentialMissing() async throws {
    var catalog = ConfigurationCatalog()
    var fields = CatalogFixtures.serverFields(remark: "无凭据")
    fields.passwordRef = CredentialReference.fresh()
    try catalog.addServer(fields)
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: catalog))
    workflow = makeWorkflow()
    let id = try XCTUnwrap(workflow.tree.roots.first?.id)
    await expectThrowsAsync { _ = try workflow.shareURI(for: id) }
  }

  // MARK: - 持久化

  func testChangesPersistAcrossWorkflowInstances() async throws {
    let groupID = try await workflow.createGroup(named: "持久组", into: nil)
    let reloaded = makeWorkflow()
    XCTAssertTrue(reloaded.tree.containsNode(groupID))
    XCTAssertEqual(reloaded.displayName(for: groupID), "持久组")
  }
}

/// 组合根 fakes 装配覆盖：工作流可以完全经依赖束以
/// hermetic fake 组装——init 的发现状态、目录命令、激活命令与 Legacy 导入
/// 全部命中注入替身，不触碰生产 Keychain、app 数据、LaunchAgent、代理进程
/// 或 SystemConfiguration。
@MainActor
final class CatalogWorkflowHermeticAssemblyTests: XCTestCase {
  private var workDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-assembly-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  func testWorkflowAssemblesFromFakesWithoutProductionSideEffects() async throws {
    let fileURL = workDir.appendingPathComponent("catalog.json")
    let credentials = InMemoryCredentialStore()
    let runtime = FakeCatalogRuntime()
    let marker = InMemoryLegacyImportMarker()
    let dependencies = CatalogWorkflowDependencies(
      coordinator: CatalogCommitCoordinator(
        fileStore: CatalogFileStore(fileURL: fileURL), runtime: runtime),
      credentials: credentials,
      plugins: NoManagedPluginProvider(),
      subscriptionFetcher: FakeSubscriptionFetcher(behavior: .success(Data())),
      legacyImportService: LegacyImportService(
        source: FixedLegacySnapshotProvider(snapshot: try makeLegacySnapshot()),
        catalogStore: CatalogFileStore(fileURL: fileURL),
        credentials: credentials,
        marker: marker),
      postLegacyImport: nil,
      activator: RejectingActivator())

    let workflow = CatalogWorkflow(dependencies: dependencies)

    // init 的发现状态来自注入的 Legacy 服务，而非生产缺省实现。
    XCTAssertEqual(
      workflow.legacyImportState,
      LegacyImportAvailability(snapshotFound: true, completed: false))

    // 目录命令落在注入的内存凭据与文件存储上；激活命令命中注入替身。
    let groupID = try await workflow.createGroup(named: "组装组", into: nil)
    XCTAssertTrue(workflow.tree.containsNode(groupID))
    let activation = try await workflow.activate(groupID)
    XCTAssertEqual(activation, .rejectedActivation(.noActiveTarget))

    // Legacy 导入走注入服务：报告、完成标记与凭据写入都落在注入的 fake 上；
    // 不经提交管线触发运行时收敛。
    let outcome = try await workflow.importLegacy()
    XCTAssertEqual(outcome.report.importedServerCount, 1)
    XCTAssertEqual(try marker.isCompleted(), true)
    XCTAssertEqual(
      credentials.storageSnapshot.values.contains("legacy-pw"), true,
      "导入凭据写入注入的内存存储，而非生产 Keychain")
    XCTAssertEqual(runtime.convergeCount, 0, "导入不经提交管线触发运行时收敛")
  }

  private func makeLegacySnapshot() throws -> LegacySnapshot {
    let profile: [String: Any] = [
      "Id": "11111111-2222-4333-8444-555555555555",
      "ServerHost": "203.0.113.9",
      "ServerPort": 8388,
      "Method": "aes-256-gcm",
      "Password": "legacy-pw",
      "Remark": "旧服务器",
    ]
    return try LegacySnapshot(
      propertyList: ["ServerProfiles": [profile], "ShadowsocksRunningMode": "manual"])
  }
}
