import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class CustomRuleDeletionWorkflowTests: XCTestCase {
  func testMixedSelectionDeletesOnlyCustomUUIDsAndPreservesDisablementAndBuiltinMembership()
    async throws
  {
    let custom = CustomRule(
      action: .proxy, match: try RuleMatch(domainSuffix: "merged.example"))
    let other = CustomRule(action: .direct, match: try RuleMatch(domainExact: "other.example"))
    let orphan = ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "orphan.example"))
    let builtin = ProxyRule(action: custom.action, match: custom.match)
    var saved = CustomRuleDocument(
      rules: [custom, other], disabledIdentities: [custom.identity, orphan])
    var commits = 0
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadDocument: { saved },
      commitDocument: {
        commits += 1
        saved = $0
        return RuleDocumentCommit(outcome: .saved, document: saved)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: {
        rulesFixture($0, rules: $0 == .gfwlist ? [builtin] : [])
      }))
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    XCTAssertEqual(workflow.deletableSelection, [custom.id, other.id])
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    XCTAssertEqual(confirmation.customIDs, [custom.id, other.id])
    XCTAssertEqual(commits, 0, "Preparing and discarding a confirmation has no side effects")
    let oldVersion = workflow.snapshot.version
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    XCTAssertEqual(commits, 1)
    XCTAssertTrue(saved.rules.isEmpty)
    XCTAssertEqual(saved.disabledIdentities, [custom.identity, orphan])
    workflow.query(RulesQuery(source: .gfwlist))
    let merged = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == custom.identity })
    XCTAssertEqual(merged.sources, [.gfwlist])
    XCTAssertTrue(merged.customIDs.isEmpty)
    XCTAssertFalse(merged.isEnabled)
    XCTAssertNotEqual(workflow.snapshot.version, oldVersion)
    XCTAssertFalse(workflow.snapshot.rows.contains { $0.identity == other.identity })
    XCTAssertTrue(workflow.snapshot.selection.isSubset(of: Set(workflow.snapshot.rows.map(\.id))))
    XCTAssertEqual(workflow.snapshot.commitFeedback?.changedCount, 2)
  }
}

extension CustomRuleDeletionWorkflowTests {
  func testFilteredSelectionCannotEnterConfirmationAndStaleConfirmationCannotExpand() async throws {
    let first = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "first.example"))
    let hidden = CustomRule(action: .direct, match: try RuleMatch(domainExact: "hidden.example"))
    var commits = 0
    var saved = CustomRuleDocument(rules: [first, hidden])
    let workflow = RulesWorkflow(
      loadDocument: { saved },
      commitDocument: {
        commits += 1
        saved = $0
        return RuleDocumentCommit(outcome: .saved, document: saved)
      }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    var query = workflow.snapshot.query
    query.search = "first"
    workflow.query(query)
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    XCTAssertEqual(confirmation.customIDs, [first.id])
    query.search = ""
    workflow.query(query)
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    XCTAssertEqual(saved.rules.map(\.id), [hidden.id], "New selection cannot expand captured UUIDs")
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitFeedback?.outcome, .superseded)
    XCTAssertEqual(commits, 1)
    workflow.select([])
    XCTAssertNil(workflow.prepareCustomRuleDeletion())
  }

  func testVersionChangeRejectsDeletionEvenWhenTheCustomUUIDStillExists() async throws {
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "kept.example"))
    var commits = 0
    let workflow = RulesWorkflow(
      loadDocument: { CustomRuleDocument(rules: [rule]) },
      commitDocument: {
        commits += 1
        return RuleDocumentCommit(outcome: .saved, document: $0)
      }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    await workflow.setEnabled(false, identities: [rule.identity])
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitFeedback?.outcome, .superseded)
    XCTAssertEqual(commits, 1)
    XCTAssertEqual(workflow.deletableSelection, [rule.id])
  }

  func testPendingDeletionBlocksRepeatsAndPersistenceFailureKeepsConfirmationRetryable()
    async throws
  {
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "kept.example"))
    let original = CustomRuleDocument(rules: [rule])
    let started = expectation(description: "delete awaiting commit")
    var continuation: CheckedContinuation<Void, Never>?
    var commits = 0
    let workflow = RulesWorkflow(
      loadDocument: { original },
      commitDocument: { _ in
        commits += 1
        await withCheckedContinuation {
          continuation = $0
          started.fulfill()
        }
        return RuleDocumentCommit(outcome: .persistenceFailed, document: original)
      }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    let pending = Task { await workflow.deleteCustomRules(confirmation) }
    await fulfillment(of: [started], timeout: 3)
    XCTAssertNil(workflow.prepareCustomRuleDeletion())
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitFeedback?.outcome, .busy)
    continuation?.resume()
    await pending.value
    XCTAssertEqual(workflow.snapshot.commitOutcome, .persistenceFailed)
    XCTAssertEqual(commits, 1)
    XCTAssertEqual(workflow.snapshot.version, confirmation.version)
    XCTAssertEqual(workflow.prepareCustomRuleDeletion(), confirmation)
  }

  func testIncompleteCollectionRejectsDeletionFromPreviouslyLoadedFacts() async throws {
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "kept.example"))
    let loadState = DocumentLoadState()
    var commits = 0
    let workflow = RulesWorkflow(
      loadDocument: {
        if loadState.shouldFail { throw CustomRuleStoreError.corrupt(detail: "fixture") }
        return CustomRuleDocument(rules: [rule])
      },
      commitDocument: {
        commits += 1
        return RuleDocumentCommit(outcome: .saved, document: $0)
      }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    loadState.shouldFail = true
    await workflow.refresh()
    XCTAssertNil(workflow.prepareCustomRuleDeletion())
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitFeedback?.outcome, .superseded)
    XCTAssertEqual(commits, 0)
  }
  @MainActor
  private final class DocumentLoadState {
    var shouldFail = false
  }
}
