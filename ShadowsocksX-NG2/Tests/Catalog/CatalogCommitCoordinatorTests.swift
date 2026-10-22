import XCTest

@testable import ShadowsocksX_NG2

/// 确定性运行时同步替身（测试缝）：记录 converge 快照与次序，
/// 可编程每次结果；门闩让同步在收敛中挂起，用于验证提交代次语义。
@MainActor
final class FakeCatalogRuntime: CatalogRuntimeSyncing {
  var hasActiveTarget = false
  var onNextConverge: (() -> Void)?
  /// 未编程结果时的默认返回。
  var defaultOutcome: RuntimeSyncOutcome = .converged(skippedServers: [])
  private var outcomeQueue: [RuntimeSyncOutcome] = []
  private(set) var convergeSnapshots: [CommittedCatalogSnapshot] = []

  /// 门闩：武装后接下来的 converge 在记录调用后挂起，直到 openGate。
  private var armedGateCount = 0
  private var gateWaiters: [CheckedContinuation<Void, Never>] = []

  var convergeCount: Int { convergeSnapshots.count }

  /// 预编程按次序返回的结果（耗尽后回退 `defaultOutcome`）。
  func enqueueOutcomes(_ outcomes: [RuntimeSyncOutcome]) {
    outcomeQueue.append(contentsOf: outcomes)
  }

  func armGate(count: Int = 1) {
    armedGateCount = count
  }

  func openGate() {
    armedGateCount = 0
    for waiter in gateWaiters {
      waiter.resume()
    }
    gateWaiters.removeAll()
  }

  func converge(to snapshot: CommittedCatalogSnapshot) async -> RuntimeSyncOutcome {
    convergeSnapshots.append(snapshot)
    let callback = onNextConverge
    onNextConverge = nil
    callback?()
    let result = outcomeQueue.isEmpty ? defaultOutcome : outcomeQueue.removeFirst()
    if armedGateCount > 0 {
      armedGateCount -= 1
      await withCheckedContinuation { gateWaiters.append($0) }
    }
    return result
  }
}

/// 让出 MainActor 直到条件成立（被测同步任务在同一线程上排队执行）。供
/// 协调器与视图模型测试共享：提交后的运行时收敛不再内联等待。
@MainActor
func waitUntilRuntimeSettles(
  _ condition: @autoclosure () -> Bool,
  timeout: TimeInterval = 2,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    await Task.yield()
  }
  XCTAssertTrue(condition(), "等待条件超时", file: file, line: line)
}

/// 目录提交—运行时同步协调器：只断言外部行为——持久化与发布、
/// 运行时是否被调用及使用的快照、阶段与失败结果、并发提交的最终赢家、无效
/// 活动目标的停止语义。全部走临时目录文件存储，不触碰真实运行时。
@MainActor
final class CatalogCommitCoordinatorTests: XCTestCase {
  private var workDir: URL!
  private var fileURL: URL!
  private var runtime: FakeCatalogRuntime!
  private var coordinator: CatalogCommitCoordinator!
  private var bootstrap: CatalogCommitBootstrap!

  override func setUp() async throws {
    try await super.setUp()
    // 专用工作目录：写入器会把父目录强制 0700（不得指向临时根）。
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-commit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    fileURL = workDir.appendingPathComponent("catalog.json")
    runtime = FakeCatalogRuntime()
    coordinator = makeCoordinator()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  private func makeCoordinator() -> CatalogCommitCoordinator {
    let fileStore = makeTestCatalogStore(fileURL: fileURL)
    bootstrap = CatalogCommitCoordinator.bootstrap(fileStore: fileStore)
    return CatalogCommitCoordinator(fileStore: fileStore, runtime: runtime, bootstrap: bootstrap)
  }

  /// 预置目录后重建协调器（模拟已落盘的既有状态）。
  private func seedCatalog(_ mutate: (inout ConfigurationCatalog) throws -> Void) throws {
    var catalog = ConfigurationCatalog()
    try mutate(&catalog)
    try makeTestCatalogStore(fileURL: fileURL).save(CatalogDocument(catalog: catalog))
    coordinator = makeCoordinator()
  }

  private func persistedCatalog() throws -> ConfigurationCatalog {
    try makeTestCatalogStore(fileURL: fileURL).load().catalog
  }

  // MARK: - 无活动目标

  func testCommitWithoutActiveTargetPersistsAndPublishesWithoutRuntimeCall() throws {
    runtime.hasActiveTarget = false

    let added = try coordinator.commit { catalog, _ in
      try catalog.addTestServer("香港 01")
    }

    XCTAssertTrue(coordinator.committedCatalog.contains(added), "提交后已发布新状态")
    XCTAssertTrue(
      bootstrap.catalogSnapshotReader.catalogSnapshot.contains(added),
      "controller reader 与 coordinator 观察同一已提交目录")
    XCTAssertEqual(try persistedCatalog().rootChildren, [added], "变更已原子持久化")
    XCTAssertEqual(runtime.convergeCount, 0, "无活动目标不驱动运行时")
    XCTAssertEqual(coordinator.syncStatus, .idle)
  }

  // MARK: - 活动目标提交

  func testCommitWithActiveServerTargetConvergesToCommittedSnapshot() async throws {
    try seedCatalog { try $0.addTestServer("已有节点") }
    runtime.hasActiveTarget = true

    let added = try coordinator.commit { catalog, _ in
      try catalog.addTestServer("新节点")
    }

    // 一次提交恰好一次同步。
    await waitUntilRuntimeSettles(runtime.convergeCount == 1)
    let snapshot = try XCTUnwrap(runtime.convergeSnapshots.first)
    XCTAssertTrue(snapshot.catalog.contains(added), "同步使用刚提交的内存快照")
    XCTAssertEqual(snapshot.subscriptions, [])
    XCTAssertEqual(
      coordinator.syncStatus,
      .finished(generation: 1, outcome: .converged(skippedServers: [])))
  }

  func testCommitWithActiveGroupTargetUsesSamePipeline() async throws {
    try seedCatalog { catalog in
      let group = try catalog.addGroup("手动组")
      _ = try catalog.addTestServer("成员", to: group)
    }
    runtime.hasActiveTarget = true
    let groupID = try XCTUnwrap(coordinator.committedCatalog.rootChildren.first)

    _ = try coordinator.commit { catalog, _ in
      try catalog.addTestServer("新成员", to: groupID)
    }

    await waitUntilRuntimeSettles(runtime.convergeCount == 1)
    XCTAssertEqual(runtime.convergeCount, 1, "分组目标与服务器目标共用同一提交语义")
    let snapshot = try XCTUnwrap(runtime.convergeSnapshots.first)
    let group = try XCTUnwrap(snapshot.catalog.entry(for: groupID))
    guard case .group(let fields) = group.kind else {
      return XCTFail("快照中的目标应为分组")
    }
    XCTAssertEqual(fields.children.count, 2, "同步快照携带刚提交的新子树")
  }

  func testMoveRemoveAndRenameShareCommitSemantics() async throws {
    try seedCatalog { catalog in
      let group = try catalog.addGroup("组")
      _ = try catalog.addTestServer("成员", to: group)
    }
    runtime.hasActiveTarget = true
    let groupID = try XCTUnwrap(coordinator.committedCatalog.rootChildren.first)
    let serverID = try XCTUnwrap(coordinator.committedCatalog.children(of: groupID).first)

    try coordinator.commit { catalog, _ in try catalog.move(serverID, to: nil) }
    await waitUntilRuntimeSettles(runtime.convergeCount == 1)
    try coordinator.commit { catalog, _ in try catalog.renameGroup(groupID, to: "改名") }
    await waitUntilRuntimeSettles(runtime.convergeCount == 2)
    _ = try coordinator.commit { catalog, _ in try catalog.remove(serverID) }
    // 移动、改名、删除各触发一次同步。
    await waitUntilRuntimeSettles(runtime.convergeCount == 3)

    XCTAssertEqual(
      coordinator.syncStatus,
      .finished(generation: 3, outcome: .converged(skippedServers: [])),
      "最新代次的收敛结果是最终状态")
  }

  // MARK: - 无效活动目标

  func testRemovedActiveTargetClearsAndStopsWithoutSilentFallback() async throws {
    try seedCatalog { try $0.addTestServer("活动节点") }
    let targetID = try XCTUnwrap(coordinator.committedCatalog.rootChildren.first)
    runtime.hasActiveTarget = true
    runtime.enqueueOutcomes([.clearedAndStopped(.targetNotFound(targetID))])

    _ = try coordinator.commit { catalog, _ in try catalog.remove(targetID) }

    await waitUntilRuntimeSettles(coordinator.syncStatus != .syncing(generation: 1))
    XCTAssertEqual(runtime.convergeCount, 1)
    XCTAssertEqual(
      coordinator.syncStatus,
      .finished(generation: 1, outcome: .clearedAndStopped(.targetNotFound(targetID))),
      "清除停止以结构化结果呈现")
    XCTAssertFalse(try persistedCatalog().contains(targetID), "运行时失败不回滚目录")
  }

  // MARK: - 目录与运行时结果区分

  func testRuntimeFailureKeepsCommittedCatalogAndDistinguishesResult() async throws {
    runtime.hasActiveTarget = true
    runtime.defaultOutcome = .failed(failure: .service(.agent))

    let added = try coordinator.commit { catalog, _ in
      try catalog.addTestServer("香港 01")
    }

    await waitUntilRuntimeSettles(coordinator.syncStatus != .syncing(generation: 1))
    XCTAssertTrue(try persistedCatalog().contains(added), "运行时失败不回滚已提交目录")
    XCTAssertEqual(
      coordinator.syncStatus,
      .finished(generation: 1, outcome: .failed(failure: .service(.agent))),
      "结果明确区分目录已提交与运行时未收敛")
  }

  // MARK: - 提交代次

  func testSupersededSyncBeforeStartNeverCallsRuntime() async throws {
    runtime.hasActiveTarget = true

    _ = try coordinator.commit { catalog, _ in try catalog.addTestServer("第一台") }
    _ = try coordinator.commit { catalog, _ in try catalog.addTestServer("第二台") }
    // 同一 MainActor 回合内的两次提交：旧代次同步尚未启动即被取代。
    await waitUntilRuntimeSettles(runtime.convergeCount == 1)

    let snapshot = try XCTUnwrap(runtime.convergeSnapshots.first)
    XCTAssertEqual(snapshot.catalog.rootChildren.count, 2, "最终同步采用最新提交快照")
    XCTAssertEqual(
      coordinator.syncStatus,
      .finished(generation: 2, outcome: .converged(skippedServers: [])))
  }

  func testDelayedSyncCannotOverrideLatestSnapshotOrResult() async throws {
    runtime.hasActiveTarget = true
    runtime.enqueueOutcomes([
      .converged(skippedServers: []),
      .failed(failure: .service(.unknown)),
    ])
    runtime.armGate()

    _ = try coordinator.commit { catalog, _ in try catalog.addTestServer("第一台") }
    await waitUntilRuntimeSettles(runtime.convergeCount == 1)

    _ = try coordinator.commit { catalog, _ in try catalog.addTestServer("第二台") }
    runtime.openGate()
    await waitUntilRuntimeSettles(runtime.convergeCount == 2)
    await waitUntilRuntimeSettles(coordinator.syncStatus != .syncing(generation: 2))

    XCTAssertEqual(runtime.convergeCount, 2)
    XCTAssertEqual(
      runtime.convergeSnapshots[1].catalog.rootChildren.count, 2, "最新代次使用最新快照")
    XCTAssertEqual(
      coordinator.syncStatus,
      .finished(generation: 2, outcome: .failed(failure: .service(.unknown))),
      "迟到的旧代次结果不得覆盖最新代次")
  }

  // MARK: - 独立路径对齐

  func testReloadCommittedStateAdoptsExternalWritesWithoutRuntimeCall() throws {
    runtime.hasActiveTarget = true

    // Legacy 导入等独立路径绕过协调器直接落盘（订阅固定分组须在目录内）。
    var external = ConfigurationCatalog()
    let groupID = NodeID(rawValue: "import:group")
    try external.addGroup("导入订阅组", source: .subscription, id: groupID)
    try makeTestCatalogStore(fileURL: fileURL).save(
      CatalogDocument(
        catalog: external,
        subscriptions: [
          SubscriptionRecord(
            id: .fresh(), groupID: groupID, url: "https://provider.example/sub", status: .never)
        ]))

    coordinator.reloadCommittedStateFromStore()

    XCTAssertEqual(coordinator.committedCatalog.rootChildren, [groupID], "已提交状态对齐磁盘")
    XCTAssertEqual(
      bootstrap.catalogSnapshotReader.catalogSnapshot.rootChildren, [groupID],
      "独立导入 reload 发布到共享目录来源")
    XCTAssertEqual(coordinator.committedSubscriptions.count, 1)
    XCTAssertEqual(runtime.convergeCount, 0, "对齐不触发运行时收敛")
  }

  func testFailedPersistenceDoesNotPublishSharedCatalog() throws {
    let blocker = workDir.appendingPathComponent("not-a-directory")
    try Data().write(to: blocker)
    let blockedStore = makeTestCatalogStore(fileURL: blocker.appendingPathComponent("catalog.json"))
    let blockedBootstrap = CatalogCommitCoordinator.bootstrap(fileStore: blockedStore)
    let blockedCoordinator = CatalogCommitCoordinator(
      fileStore: blockedStore, runtime: runtime, bootstrap: blockedBootstrap)
    let original = blockedBootstrap.catalogSnapshotReader.catalogSnapshot

    XCTAssertThrowsError(
      try blockedCoordinator.commit { catalog, _ in
        try catalog.addTestServer("不能发布")
      })

    XCTAssertEqual(blockedBootstrap.catalogSnapshotReader.catalogSnapshot, original)
    XCTAssertEqual(blockedCoordinator.committedCatalog, original)
    XCTAssertEqual(runtime.convergeCount, 0, "持久化失败不驱动运行时")
  }
}
