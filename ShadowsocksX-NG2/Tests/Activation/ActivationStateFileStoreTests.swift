import XCTest

@testable import ShadowsocksX_NG2

/// 活动目标持久化缝：往返无损、缺失/损坏按安全侧恢复、权限基线。
final class ActivationStateFileStoreTests: XCTestCase {
  private var workDir: URL!
  private var store: ActivationStateFileStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("activation-file-store-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    store = ActivationStateFileStore(fileURL: workDir.appendingPathComponent("activation.json"))
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: workDir)
    try super.tearDownWithError()
  }

  // MARK: 缺失与损坏

  func testMissingFileLoadsAsNoActiveTarget() throws {
    XCTAssertNil(try store.loadActiveTargetID(), "文件缺失按从未激活处理")
  }

  func testBrokenJSONLoadsAsNoActiveTargetOnTheSafeSide() throws {
    try "{ not json {{{".write(to: store.fileURL, atomically: true, encoding: .utf8)

    XCTAssertNil(
      try store.loadActiveTargetID(), "损坏按安全侧恢复：无活动目标，代理保持停止")
  }

  func testUnknownSchemaVersionLoadsAsNoActiveTarget() throws {
    let payload = """
      {"version": 99, "activeTargetID": "s1"}
      """
    try payload.write(to: store.fileURL, atomically: true, encoding: .utf8)

    XCTAssertNil(try store.loadActiveTargetID())
  }

  // MARK: 往返无损

  func testRoundTripPreservesTargetIdentity() throws {
    let target = NodeID(rawValue: "manual:group-1")

    try store.save(activeTargetID: target)

    XCTAssertEqual(try store.loadActiveTargetID(), target, "目标身份跨持久化无损")
  }

  func testSavingNilClearsPersistedTarget() throws {
    try store.save(activeTargetID: NodeID(rawValue: "s1"))

    try store.save(activeTargetID: nil)

    XCTAssertNil(try store.loadActiveTargetID(), "清除即整文件替换，不再残留旧目标")
  }

  func testDefaultFileURLMatchesRuntimeDirectoryContract() {
    XCTAssertTrue(
      ActivationStateFileStore.defaultFileURL().path.hasSuffix(
        "ShadowsocksX-NG2/configuration/activation.json")
    )
  }

  // MARK: 与状态机的生命周期往返

  func testActivationLifecycleRoundTripThroughFileStore() throws {
    var catalog = ConfigurationCatalog()
    let leaf = try ActivationFixture.addPlainServer("a", in: &catalog)
    var machine = ActivationStateMachine()
    _ = try ActivationFixture.activate(&machine, leaf, in: catalog)
    try store.save(activeTargetID: machine.activeTargetID)

    // 下次启动：从文件恢复目标，载入目录后立即重校验（「重新校验同步」）。
    var restored = ActivationStateMachine(activeTargetID: try store.loadActiveTargetID())
    let configuration = try ActivationFixture.requireDeployed(
      ActivationFixture.commit(&restored, catalog))
    XCTAssertEqual(configuration.targetID, leaf, "恢复的目标重放派生")

    // 目标随后失效：清除并停止，持久化同步清空。
    try catalog.remove(leaf)
    let failure = try ActivationFixture.requireCleared(
      ActivationFixture.commit(&restored, catalog))
    XCTAssertEqual(failure, .targetNotFound(leaf))
    try store.save(activeTargetID: restored.activeTargetID)
    XCTAssertNil(try store.loadActiveTargetID(), "清除随持久化落盘，重启不再复活旧目标")
  }
}
