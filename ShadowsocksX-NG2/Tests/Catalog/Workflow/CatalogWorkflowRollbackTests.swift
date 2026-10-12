import XCTest

@testable import ShadowsocksX_NG2

/// 目录工作流 module 的失败语义与阶段分离：
/// 目录持久化失败时旧配置与旧凭据都保持有效；目录提交完成与运行时收敛是分离
/// 的观察面且收敛失败不回滚目录；Legacy 导入不驱动运行时收敛、不自动重复。
@MainActor
final class CatalogWorkflowRollbackTests: XCTestCase {
  private var workDir: URL!
  private var fileURL: URL!
  private var settingsURL: URL!
  private var activationURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var runtime: FakeCatalogRuntime!
  private var bootstrap: CatalogCommitBootstrap!
  private var rootsSeenByLegacyPostImport: [NodeID]?

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-rollback-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    // 目录文件置于 gate 子目录:破坏持久化时把 gate 目录替换为同名文件,
    // 临时文件创建必失败(比替换目标更确定的失败注入)。
    fileURL = workDir.appendingPathComponent("gate/catalog.json")
    settingsURL = workDir.appendingPathComponent("settings.json")
    activationURL = workDir.appendingPathComponent("activation.json")
    credentials = InMemoryCredentialStore()
    runtime = FakeCatalogRuntime()
  }

  /// 让下一次目录持久化必然失败:gate 目录替换为同名文件后,临时文件无法
  /// 在其中创建。
  private func breakPersistence() throws {
    let gateDir = workDir.appendingPathComponent("gate")
    try FileManager.default.removeItem(at: gateDir)
    try Data().write(to: gateDir)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  private func makeWorkflow(
    legacyImportService: LegacyImportService? = nil,
    postLegacyImport: ((LegacyImportOutcome) async -> Void)? = nil
  ) -> CatalogWorkflow {
    runtime.hasActiveTarget = true
    let fileStore = CatalogFileStore(fileURL: fileURL)
    bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: fileStore)
    let coordinator = CatalogCommitCoordinator(
      fileStore: fileStore, runtime: runtime, bootstrap: bootstrap)
    return makeCatalogWorkflow(
      coordinator: coordinator,
      credentials: credentials,
      plugins: NoManagedPluginProvider(),
      legacyImportService: legacyImportService,
      postLegacyImport: postLegacyImport)
  }

  /// 直建一条服务器（凭据引用固定，便于观察回滚），返回其身份。
  private func seedServer(password: String) async throws -> NodeID {
    var catalog = ConfigurationCatalog()
    let fields = ServerFields(
      address: "203.0.113.7", port: 8388, encryptionMethod: "aes-256-gcm",
      passwordRef: CredentialReference(rawValue: "ref-pw"), remark: "夹具")
    try credentials.save(password, for: fields.passwordRef)
    try catalog.addServer(fields)
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: catalog))
    let workflow = makeWorkflow()
    self.workflow = workflow
    return try XCTUnwrap(workflow.tree.roots.first?.id)
  }

  private var workflow: CatalogWorkflow!

  private func isFinished(_ status: RuntimeSyncStatus) -> Bool {
    if case .finished = status { return true }
    return false
  }

  // MARK: - 持久化失败 → 旧配置与旧凭据都保持有效

  func testUpdateServerRollsBackCredentialWhenPersistenceFails() async throws {
    let id = try await seedServer(password: "旧密码")

    try breakPersistence()

    await expectThrowsAsync {
      try await workflow.updateServer(
        id,
        draft: ServerEditDraft(
          address: "198.51.100.9", port: 9999, encryptionMethod: "aes-256-gcm",
          password: "新密码", remark: "新名称", plugin: .none, pluginOptions: nil))
    } onThrow: { error in
      guard let commitError = error as? CommitError else {
        XCTFail("预期 CommitError，收到 \(error)")
        return
      }
      XCTAssertEqual(
        commitError.credentialRollback,
        .restored([CredentialReference(rawValue: "ref-pw")]),
        "journal 回滚经 typed outcome 报出（story 13）")
    }

    let form = try XCTUnwrap(try workflow.serverEditForm(for: id))
    XCTAssertEqual(form.address, "203.0.113.7", "目录提交失败则已发布状态不动")
    XCTAssertEqual(form.password, "旧密码", "旧凭据继续生效（journal 回滚，story 13）")
  }

  func testUpdateServerRollsBackPluginOptionsDeletionWhenPersistenceFails() async throws {
    // 带参数引用的服务器；把参数改为空触发 journal delete，再让持久化失败。
    var catalog = ConfigurationCatalog()
    let fields = ServerFields(
      address: "203.0.113.7", port: 8388, encryptionMethod: "aes-256-gcm",
      passwordRef: CredentialReference(rawValue: "ref-pw"), remark: "夹具",
      pluginProgram: "v2ray-plugin",
      pluginOptionsRef: CredentialReference(rawValue: "ref-opts"))
    try credentials.save("旧密码", for: fields.passwordRef)
    try credentials.save("mode=websocket", for: try XCTUnwrap(fields.pluginOptionsRef))
    try catalog.addServer(fields)
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: catalog))
    workflow = makeWorkflow()
    let id = try XCTUnwrap(workflow.tree.roots.first?.id)

    try breakPersistence()

    await expectThrowsAsync {
      try await workflow.updateServer(
        id,
        draft: ServerEditDraft(
          address: "203.0.113.7", port: 8388, encryptionMethod: "aes-256-gcm",
          password: "旧密码", remark: "新名称", plugin: .none, pluginOptions: nil))
    } onThrow: { error in
      guard let commitError = error as? CommitError else {
        XCTFail("预期 CommitError，收到 \(error)")
        return
      }
      XCTAssertEqual(
        commitError.credentialRollback,
        .restored([
          CredentialReference(rawValue: "ref-pw"),
          CredentialReference(rawValue: "ref-opts"),
        ]),
        "密码覆盖写与参数删除都被回滚（story 13）")
    }

    let form = try XCTUnwrap(try workflow.serverEditForm(for: id))
    XCTAssertEqual(form.plugin.selection, .named(program: "v2ray-plugin"), "插件引用保留")
    XCTAssertEqual(form.plugin.options, "mode=websocket", "被删除的参数秘密已恢复")
  }

  func testCommitFailureWithoutCredentialTouchReportsNothingToRestore() async throws {
    _ = try await seedServer(password: "旧密码")

    // 节点不存在时提交在写凭据之前失败：无触碰即 nothingToRestore。
    await expectThrowsAsync {
      try await workflow.updateServer(
        NodeID(rawValue: "missing"),
        draft: ServerEditDraft(
          address: "198.51.100.9", port: 9999, encryptionMethod: "aes-256-gcm",
          password: "新密码", remark: "新名称", plugin: .none, pluginOptions: nil))
    } onThrow: { error in
      guard let commitError = error as? CommitError else {
        XCTFail("预期 CommitError，收到 \(error)")
        return
      }
      XCTAssertEqual(commitError.credentialRollback, .nothingToRestore)
    }
  }

  // MARK: - 表单新建持久化失败 → 新写凭据回滚为不存在

  func testCreateServerRollsBackFreshCredentialWhenPersistenceFails() async throws {
    let workflow = makeWorkflow()
    // 先落一份空目录建立 gate 存储（写入器才会创建父目录），再破坏持久化。
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: ConfigurationCatalog()))

    try breakPersistence()

    await expectThrowsAsync {
      try await workflow.createServer(
        ServerEditDraft(
          address: "198.51.100.9", port: 8388, encryptionMethod: "aes-256-gcm",
          password: "新密码", remark: "新名称", plugin: .none, pluginOptions: nil),
        into: nil)
    } onThrow: { error in
      guard let commitError = error as? CommitError else {
        XCTFail("预期 CommitError，收到 \(error)")
        return
      }
      guard case .restored(let refs) = commitError.credentialRollback, refs.count == 1 else {
        return XCTFail("预期恰有一个全新引用回滚为删除，实际 \(commitError.credentialRollback)")
      }
    }

    XCTAssertTrue(workflow.tree.isEmpty, "目录提交失败则已发布状态不动")
    XCTAssertTrue(credentials.storageSnapshot.isEmpty, "新写秘密已删除，不留孤儿")
  }

  // MARK: - 提交完成与运行时收敛是分离的观察面

  func testCommitCompletesWhileRuntimeConvergenceIsStillSyncing() async throws {
    let workflow = makeWorkflow()
    runtime.hasActiveTarget = true
    runtime.armGate(count: 1)

    let groupID = try await workflow.createGroup(named: "组", into: nil)

    // 目录提交已完成（树已发布），运行时仍在收敛中。
    XCTAssertNotNil(workflow.tree.node(withID: groupID))
    XCTAssertEqual(workflow.runtimeSync, .syncing(generation: 1))
    runtime.openGate()
    await waitUntilRuntimeSettles(isFinished(workflow.runtimeSync))
    guard case .finished(1, .converged(skippedServers: [])) = workflow.runtimeSync else {
      return XCTFail("收敛应正常结束，实际 \(workflow.runtimeSync)")
    }
  }

  // MARK: - 运行时收敛失败不回滚已提交目录

  func testRuntimeConvergenceFailureDoesNotRollbackCatalog() async throws {
    let workflow = makeWorkflow()
    runtime.hasActiveTarget = true
    runtime.enqueueOutcomes([.failed(failure: .launch(.missingRuntimeDocument))])

    let groupID = try await workflow.createGroup(named: "组", into: nil)

    await waitUntilRuntimeSettles(isFinished(workflow.runtimeSync))
    XCTAssertNotNil(workflow.tree.node(withID: groupID), "收敛失败不回滚已提交目录")
    XCTAssertEqual(
      workflow.runtimeSync,
      .finished(generation: 1, outcome: .failed(failure: .launch(.missingRuntimeDocument))))
  }

  // MARK: - Legacy 导入不驱动运行时，不自动重复

  func testLegacyImportCommitsGroupWithoutRuntimeSyncOrRepeat() async throws {
    var existingSettings = ProxySettings()
    existingSettings.listen.socksPort = 2086
    existingSettings.listen.httpPort = 2087
    existingSettings.preferredMode = .global
    let settingsStore = ProxySettingsFileStore(
      fileURL: settingsURL)
    try settingsStore.save(existingSettings)
    let existingTarget = NodeID(rawValue: "existing-target")
    let activationStore = ActivationStateFileStore(fileURL: activationURL)
    try activationStore.save(activeTargetID: existingTarget)

    let service = try makeLegacyService()
    var postCalls = 0
    rootsSeenByLegacyPostImport = nil
    let workflow = makeWorkflow(legacyImportService: service) { [weak self] _ in
      postCalls += 1
      self?.rootsSeenByLegacyPostImport =
        self?.bootstrap.catalogSnapshotReader
        .catalogSnapshot.rootChildren
    }
    XCTAssertTrue(
      workflow.legacyImportState.snapshotFound, "发现快照后统一导入面板提供 Legacy 入口")
    XCTAssertFalse(workflow.legacyImportState.completed)
    // 有活动目标也不得触发运行时收敛（导入不启动代理、不写系统代理）。
    XCTAssertTrue(runtime.hasActiveTarget)

    let outcome = try await workflow.importLegacy()

    XCTAssertEqual(outcome.report.importedServerCount, 1)
    XCTAssertEqual(workflow.tree.roots.count, 1)
    let group = try XCTUnwrap(workflow.tree.roots.first)
    XCTAssertTrue(group.isGroup)
    XCTAssertTrue(group.isManual)
    XCTAssertEqual(group.childCount, 1)
    XCTAssertEqual(
      rootsSeenByLegacyPostImport, [group.id],
      "独立导入先 reload 并发布共享目录快照，再进入运行时清理回调")
    XCTAssertEqual(runtime.convergeCount, 0, "导入不经提交管线触发运行时收敛")
    XCTAssertEqual(postCalls, 1, "导入后的运行时边界只经注入闭包（独立于普通提交）")
    XCTAssertEqual(workflow.legacyImportState.completed, true, "成功导入写完成标记")
    XCTAssertNotNil(workflow.tree.node(withID: outcome.groupID), "返回新建分组身份供选中")
    XCTAssertEqual(try settingsStore.load(), existingSettings, "工作流导入不得写入 2.0 偏好")
    XCTAssertEqual(
      try activationStore.loadActiveTargetID(), existingTarget,
      "工作流导入不得写入或清除活动目标")

    // 首次导入成功后不再自动重复；显式再导入创建独立分组。
    workflow.refreshLegacyImportState()
    XCTAssertTrue(workflow.legacyImportState.snapshotFound, "发现状态与完成标记独立")
    XCTAssertTrue(workflow.legacyImportState.completed)
    _ = try await workflow.importLegacy(reimport: true)
    XCTAssertEqual(workflow.tree.roots.count, 2, "再导入创建新的独立手动分组")
    XCTAssertEqual(runtime.convergeCount, 0)
  }

  // MARK: - 夹具

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

  private func makeLegacyService() throws -> LegacyImportService {
    let snapshot = try makeLegacySnapshot()
    return LegacyImportService(
      source: FixedLegacySnapshotProvider(snapshot: snapshot),
      catalogStore: CatalogFileStore(fileURL: fileURL),
      credentials: credentials,
      marker: InMemoryLegacyImportMarker())
  }
}
