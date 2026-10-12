import XCTest

@testable import ShadowsocksX_NG2

/// 目录政策 seam 的 interface 测试：删除确认档位、
/// 拖放/移动资格、激活资格与激活命令经假 adapter 的目标传递。只观察结构化
/// fact 与 typed command outcome，不锁定 SwiftUI。
@MainActor
final class CatalogWorkflowPolicyTests: XCTestCase {
  private var workDir: URL!
  private var fileURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var runtime: FakeCatalogRuntime!
  private var activator: FakeActivator!
  private var workflow: CatalogWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-policy-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    fileURL = workDir.appendingPathComponent("catalog.json")
    credentials = InMemoryCredentialStore()
    runtime = FakeCatalogRuntime()
    activator = FakeActivator()
    workflow = makeWorkflow()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  private func makeWorkflow() -> CatalogWorkflow {
    runtime.hasActiveTarget = true
    let coordinator = CatalogCommitCoordinator(
      fileStore: CatalogFileStore(fileURL: fileURL), runtime: runtime)
    return makeCatalogWorkflow(
      coordinator: coordinator,
      credentials: credentials,
      plugins: NoManagedPluginProvider(),
      activator: activator)
  }

  private func importServer(into parent: NodeID? = nil) async throws -> NodeID {
    let before = Set(workflow.tree.roots.flatMap(\.subtreeIDs))
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: parent)
    if let parent {
      let node = try XCTUnwrap(workflow.tree.node(withID: parent))
      return try XCTUnwrap(node.childNodes.last?.id)
    }
    let added = workflow.tree.roots.map(\.id).filter { !before.contains($0) }
    return try XCTUnwrap(added.last)
  }

  // MARK: - 删除确认档位

  func testDeleteFactsLeafIsEmptySingleConfirm() async throws {
    let serverID = try await importServer()
    XCTAssertEqual(workflow.deleteFacts(for: serverID), .leaf)
  }

  func testDeleteFactsEmptyManualGroupIsSingleConfirm() async throws {
    let groupID = try await workflow.createGroup(named: "空组", into: nil)
    XCTAssertEqual(workflow.deleteFacts(for: groupID), .emptyGroup)
  }

  func testDeleteFactsNonEmptyGroupNamesSubtreeAndCredentials() async throws {
    let groupID = try await workflow.createGroup(named: "组", into: nil)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: groupID)
    let nestedID = try await workflow.createGroup(named: "嵌套", into: groupID)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.8:8388")],
      into: nestedID)
    // 组内：服务器 + 嵌套组 + 嵌套服务器 = 3 个后代节点（不含自身）。
    XCTAssertEqual(
      workflow.deleteFacts(for: groupID),
      .subtree(count: 3, includesCredentials: true))
  }

  // MARK: - 删除资格

  func testCanDeleteManualLeafAndGroupButNotSubscriptionOrMissing() async throws {
    let serverID = try await importServer()
    let groupID = try await workflow.createGroup(named: "组", into: nil)
    XCTAssertTrue(workflow.canDelete(serverID), "手动叶子可删")
    XCTAssertTrue(workflow.canDelete(groupID), "手动分组可删（空组同理）")

    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: fixture.catalog))
    workflow = makeWorkflow()
    XCTAssertFalse(workflow.canDelete(fixture.serverIDs[0]), "订阅成员结构只读")
    XCTAssertFalse(workflow.canDelete(fixture.groupID), "订阅分组结构只读")
    XCTAssertFalse(workflow.canDelete(NodeID(rawValue: "ghost")), "节点不存在")
  }

  // MARK: - 移动/拖放资格

  func testCanMoveRejectsSelfCycleAndSubscriptionTarget() async throws {
    let groupID = try await workflow.createGroup(named: "组", into: nil)
    let nestedID = try await workflow.createGroup(named: "嵌套", into: groupID)
    let serverID = try await importServer(into: groupID)

    XCTAssertFalse(workflow.canMove(groupID, to: groupID), "非自身")
    XCTAssertFalse(workflow.canMove(groupID, to: nil), "根层节点不得同父重排")
    XCTAssertFalse(workflow.canMove(groupID, to: nestedID), "目标在被拖子树内")
    XCTAssertTrue(workflow.canMove(nestedID, to: nil))
    XCTAssertFalse(workflow.canMove(nestedID, to: nestedID))
    XCTAssertTrue(workflow.canMove(serverID, to: nestedID))
    XCTAssertFalse(workflow.canMove(serverID, to: groupID), "已有父组不得同父重排")

    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: fixture.catalog))
    workflow = makeWorkflow()
    XCTAssertFalse(workflow.canMove(fixture.serverIDs[0], to: nil), "订阅节点不可拖")
    XCTAssertFalse(workflow.canMove(serverID, to: fixture.groupID), "目标非手动组")
    XCTAssertFalse(workflow.canMove(NodeID(rawValue: "ghost"), to: nil), "不存在")
  }

  func testDragPayloadManualHasIDSubscriptionNil() async throws {
    let serverID = try await importServer()
    XCTAssertEqual(workflow.dragPayload(for: serverID), serverID.rawValue)

    let fixture = try CatalogFixtures.makeSubscriptionFixture()
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: fixture.catalog))
    workflow = makeWorkflow()
    XCTAssertNil(workflow.dragPayload(for: fixture.serverIDs[0]))
    XCTAssertNil(workflow.dragPayload(for: fixture.groupID))
  }

  // MARK: - 激活资格

  func testActivationEligibilityEmptyGroup() async throws {
    let groupID = try await workflow.createGroup(named: "空组", into: nil)
    XCTAssertEqual(
      workflow.activationEligibility(for: groupID),
      ActivationEligibility(
        canActivate: false, candidateCount: 0, skippedInvalidCount: 0,
        ineligibility: .emptyGroup))
  }

  func testActivationEligibilityCountsCandidatesAndSkips() async throws {
    let groupID = try await workflow.createGroup(named: "组", into: nil)
    _ = await workflow.importServers(
      from: [.clipboardText("ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")],
      into: groupID)
    // 无效叶子（不支持的加密方法）。
    _ = await workflow.importServers(
      from: [.clipboardText("ss://ZnV0dXJlLWNpcGhlcjp4eHg=@203.0.113.9:8388")],
      into: groupID)
    let eligibility = try XCTUnwrap(workflow.activationEligibility(for: groupID))
    XCTAssertTrue(eligibility.canActivate)
    XCTAssertEqual(eligibility.candidateCount, 1)
    XCTAssertEqual(eligibility.skippedInvalidCount, 1)
    XCTAssertNil(eligibility.ineligibility)
  }

  func testActivationEligibilityAllInvalidIsNoCandidates() async throws {
    _ = await workflow.importServers(
      from: [.clipboardText("ss://ZnV0dXJlLWNpcGhlcjp4eHg=@203.0.113.9:8388")],
      into: nil)
    let serverID = try XCTUnwrap(workflow.tree.roots.first?.id)
    let eligibility = try XCTUnwrap(workflow.activationEligibility(for: serverID))
    XCTAssertEqual(eligibility.ineligibility, .noCandidates)
    XCTAssertFalse(eligibility.canActivate)
    XCTAssertEqual(eligibility.skippedInvalidCount, 1)
  }

  // MARK: - 激活命令经假 adapter

  func testActivateForwardsTargetThroughActivatingPort() async throws {
    let serverID = try await importServer()
    activator.result = .activated(skippedInvalid: 2)
    let outcome = try await workflow.activate(serverID)
    XCTAssertEqual(outcome, .activated(skippedInvalid: 2))
    XCTAssertEqual(activator.activated, [serverID])
  }

  func testActivateRejectedOutcomeIsNotThrown() async throws {
    let serverID = try await importServer()
    activator.result = .rejectedActivation(.targetNotFound(serverID))
    let outcome = try await workflow.activate(serverID)
    XCTAssertEqual(outcome, .rejectedActivation(.targetNotFound(serverID)))
  }
}

private final class FakeActivator: Activating {
  var activated: [NodeID] = []
  var result: ActivationCommandOutcome = .activated(skippedInvalid: 0)
  var error: Error?

  func activate(_ target: NodeID) async throws -> ActivationCommandOutcome {
    activated.append(target)
    if let error { throw error }
    return result
  }
}
