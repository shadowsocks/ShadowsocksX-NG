import XCTest

@testable import ShadowsocksX_NG2

/// 激活反馈状态模块单测：单飞互斥、反馈映射与意外错误的双通道（记录
/// `.failed` + 原样上抛）。命令经 `makeCatalogWorkflow` 假 seam 发出；
/// pending 态经命令进行中钩子在同任务内观察（不跨任务轮询）。
@MainActor
final class ActivationFeedbackStateTests: XCTestCase {
  private var workDir: URL!
  private var activator: InFlightObservingActivator!
  private var workflow: CatalogWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("activation-feedback-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    activator = InFlightObservingActivator()
    let runtime = FakeCatalogRuntime()
    runtime.hasActiveTarget = true
    workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: CatalogFileStore(fileURL: workDir.appendingPathComponent("catalog.json")),
        runtime: runtime),
      credentials: InMemoryCredentialStore(),
      activator: activator)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  func testActivatedOutcomeRecordsSkippedFeedbackAndClearsPending() async throws {
    let model = ActivationFeedbackState()
    activator.result = .activated(skippedInvalid: 2)
    let outcome = try await model.activate(NodeID(rawValue: "a"), via: workflow)
    XCTAssertEqual(outcome, .activated(skippedInvalid: 2))
    XCTAssertEqual(model.feedback, .activated(skippedInvalid: 2))
    XCTAssertNil(model.pendingTargetID)
    XCTAssertFalse(model.isPending)
  }

  func testRejectedOutcomeFeedbackCarriesTypedReason() async throws {
    let model = ActivationFeedbackState()
    let id = NodeID(rawValue: "a")
    activator.result = .rejectedActivation(.targetNotFound(id))
    let outcome = try await model.activate(id, via: workflow)
    XCTAssertEqual(outcome, .rejectedActivation(.targetNotFound(id)))
    XCTAssertEqual(model.feedback, .rejected(.targetNotFound(id)))
  }

  func testUnexpectedErrorRecordsFailedMessageAndRethrows() async throws {
    let model = ActivationFeedbackState()
    let id = NodeID(rawValue: "a")
    activator.error = CatalogError.nodeNotFound(id)
    do {
      _ = try await model.activate(id, via: workflow)
      XCTFail("意外错误应原样上抛")
    } catch {
      XCTAssertEqual(error as? CatalogError, .nodeNotFound(id))
    }
    XCTAssertEqual(model.feedback, .failed(message: "节点不存在（可能已被删除）"))
    XCTAssertNil(model.pendingTargetID)
  }

  func testPendingVisibleInFlightAndSingleFlightIgnoresNewCommand() async throws {
    let model = ActivationFeedbackState()
    let id = NodeID(rawValue: "a")
    var observedPending: NodeID?
    var observedFeedbackCleared = false
    var ignoredOutcome: ActivationCommandOutcome??
    activator.whileInFlight = {
      observedPending = model.pendingTargetID
      observedFeedbackCleared = model.feedback == nil
      // 首命令 pending 中的再入：单飞忽略，同步返回 nil。
      do {
        ignoredOutcome = .some(
          try await model.activate(NodeID(rawValue: "b"), via: self.workflow))
      } catch {
        XCTFail("单飞忽略路径不应抛错：\(error)")
      }
    }
    activator.result = .activated(skippedInvalid: 0)
    let outcome = try await model.activate(id, via: workflow)
    XCTAssertEqual(outcome, .activated(skippedInvalid: 0))
    XCTAssertEqual(observedPending, id, "命令进行中应可见 pending 目标")
    XCTAssertTrue(observedFeedbackCleared, "新命令开始即清空旧反馈")
    XCTAssertEqual(ignoredOutcome, .some(nil), "pending 中的新命令被单飞忽略")
    XCTAssertNil(model.pendingTargetID)
  }

  func testFeedbackClearsWhenNextCommandStarts() async throws {
    let model = ActivationFeedbackState()
    activator.result = .rejectedActivation(.noActiveTarget)
    _ = try await model.activate(NodeID(rawValue: "a"), via: workflow)
    XCTAssertEqual(model.feedback, .rejected(.noActiveTarget))

    var feedbackAtSecondCommandStart: ActivationFeedbackState.Feedback? = .activated(
      skippedInvalid: 0)
    activator.whileInFlight = { feedbackAtSecondCommandStart = model.feedback }
    activator.result = .activated(skippedInvalid: 1)
    _ = try await model.activate(NodeID(rawValue: "b"), via: workflow)
    XCTAssertNil(feedbackAtSecondCommandStart, "第二命令开始时应已清空旧反馈")
    XCTAssertEqual(model.feedback, .activated(skippedInvalid: 1))
  }
}

/// 命令进行中可挂钩的激活替身：钩子在命令返回结果前同任务执行，用于
/// 观察 pending 态与再入单飞；错误在钩子前抛出。
@MainActor
private final class InFlightObservingActivator: Activating {
  var result: ActivationCommandOutcome = .activated(skippedInvalid: 0)
  var error: Error?
  var whileInFlight: (@MainActor () async -> Void)?

  func activate(_ target: NodeID) async throws -> ActivationCommandOutcome {
    if let error { throw error }
    await whileInFlight?()
    whileInFlight = nil
    return result
  }
}
