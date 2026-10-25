import Combine
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class RuleStatusWorkflowTests: XCTestCase {
  func testUnavailableFinalDocumentKeepsRowsAndRequiresExplicitRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "example.net"))
    try store.save([rule])
    let workflow = RulesWorkflow(
      loadDocument: { try store.loadDocument() },
      commitDocument: { document in
        _ = saveFixture(document, to: store, outcome: .saved)
        return RuleDocumentCommit(outcome: .saved, document: nil)
      },
      feedbackDelay: { XCTFail("An incomplete collection must not start the success timer") },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let rows = workflow.snapshot.rows
    await workflow.setEnabled(false, identities: [rule.identity])
    XCTAssertEqual(workflow.snapshot.operationStatus, .collectionIncomplete)
    XCTAssertEqual(workflow.snapshot.rows, rows)
    XCTAssertFalse(workflow.snapshot.isComplete)
    await workflow.refresh()
    XCTAssertEqual(workflow.snapshot.operationStatus, .idle)
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == rule.identity }!.isEnabled)
  }

  func testSuccessCountsOnlyActualChangesAndExpiresAfterCollectionUpdate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let disabled = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "disabled.example"))
    let enabled = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "enabled.example"))
    try store.saveDocument(
      CustomRuleDocument(rules: [disabled, enabled], disabledIdentities: [disabled.identity]))
    let timerStarted = expectation(description: "success timer started")
    let clock = RuleFeedbackClock(started: timerStarted)
    let workflow = RulesWorkflow(
      loadDocument: { try store.loadDocument() },
      commitDocument: { document in
        saveFixture(document, to: store, outcome: .saved)
      },
      feedbackDelay: { await clock.wait() },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(source: .fixed))
    let fixed = try XCTUnwrap(workflow.snapshot.rows.first { $0.isFixed }?.identity)
    workflow.query(RulesQuery(source: .custom))
    await workflow.setEnabled(true, identities: [disabled.identity, enabled.identity, fixed])
    let feedback = try XCTUnwrap(workflow.snapshot.commitFeedback)
    XCTAssertEqual(feedback.changedCount, 1)
    XCTAssertEqual(feedback.operation, .enablement(true))
    XCTAssertEqual(feedback.outcome, .saved)
    XCTAssertTrue(workflow.snapshot.rows.first { $0.identity == disabled.identity }!.isEnabled)
    await fulfillment(of: [timerStarted], timeout: 3)
    let expired = expectation(description: "success dismissed")
    let observation = workflow.$snapshot.filter { $0.commitFeedback == nil }.sink { _ in
      expired.fulfill()
    }
    await clock.resume()
    await fulfillment(of: [expired], timeout: 3)
    XCTAssertEqual(workflow.snapshot.operationStatus, .idle)
    withExtendedLifetime(observation) {}
  }

  func testCommitRemainsOneBusyOperationAndAllowsBrowsing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "example.net"))
    try store.save([rule])
    let reloadStarted = expectation(description: "collection reload paused")
    let gate = RuleFeedbackClock(started: reloadStarted)
    let workflow = RulesWorkflow(
      loadDocument: { try store.loadDocument() },
      commitDocument: { document in
        await gate.wait()
        return saveFixture(document, to: store, outcome: .saved)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let pending = Task { await workflow.setEnabled(false, identities: [rule.identity]) }
    await fulfillment(of: [reloadStarted], timeout: 3)
    XCTAssertFalse(workflow.snapshot.isLoading)
    XCTAssertEqual(workflow.snapshot.operationStatus, .updating)
    XCTAssertNil(workflow.snapshot.commitFeedback)
    XCTAssertTrue(workflow.snapshot.rows.first { $0.identity == rule.identity }!.isEnabled)
    let query = RulesQuery(search: "example", source: .custom)
    workflow.query(query)
    let row = try XCTUnwrap(workflow.snapshot.rows.first)
    workflow.select([row.id])
    await gate.resume()
    await pending.value
    XCTAssertEqual(workflow.snapshot.query, query)
    XCTAssertEqual(workflow.snapshot.selection, [row.id])
    XCTAssertFalse(workflow.snapshot.rows.first!.isEnabled)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
  }

  func testOldSuccessTimerCannotDismissNewFailureAndClosingDoesNotChangeRules() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "example.net"))
    try store.save([rule])
    let timerStarted = expectation(description: "success timer started")
    let timerReturned = expectation(description: "old timer returned")
    let clock = RuleFeedbackClock(started: timerStarted)
    let commitState = RuleCommitState()
    let workflow = RulesWorkflow(
      loadDocument: { try store.loadDocument() },
      commitDocument: { document in
        commitState.outcome.isSuccess
          ? saveFixture(document, to: store, outcome: commitState.outcome)
          : RuleDocumentCommit(outcome: commitState.outcome, document: try? store.loadDocument())
      },
      feedbackDelay: {
        await clock.wait()
        timerReturned.fulfill()
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    await workflow.setEnabled(false, identities: [rule.identity])
    await fulfillment(of: [timerStarted], timeout: 3)
    commitState.outcome = .persistenceFailed
    await workflow.setEnabled(true, identities: [rule.identity])
    await clock.resume()
    await fulfillment(of: [timerReturned], timeout: 3)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .persistenceFailed)
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == rule.identity }!.isEnabled)
    workflow.dismissFeedback()
    XCTAssertEqual(workflow.snapshot.operationStatus, .idle)
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == rule.identity }!.isEnabled)
  }
}

@MainActor
private final class RuleCommitState {
  var outcome: CustomRuleUpdateOutcome = .saved
}

private actor RuleFeedbackClock {
  let started: XCTestExpectation
  private var continuation: CheckedContinuation<Void, Never>?

  init(started: XCTestExpectation) { self.started = started }

  func wait() async {
    await withCheckedContinuation {
      continuation = $0
      started.fulfill()
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private func saveFixture(
  _ document: CustomRuleDocument, to store: CustomRuleStore, outcome: CustomRuleUpdateOutcome
) -> RuleDocumentCommit {
  do {
    try store.saveDocument(document)
    return RuleDocumentCommit(outcome: outcome, document: document)
  } catch {
    XCTFail("Fixture save failed: \(error)")
    return RuleDocumentCommit(outcome: .persistenceFailed, document: try? store.loadDocument())
  }
}
