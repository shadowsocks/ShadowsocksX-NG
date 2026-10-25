import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class RuleEnablementWorkflowTests: XCTestCase {
  func testSavedTogglesStayInteractiveAndOfflineMatchingUsesLatestFactsDuringAnalysis() async throws
  {
    let broad = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "pending.example"))
    let narrow = CustomRule(action: .direct, match: try RuleMatch(domainExact: "x.pending.example"))
    let started = expectation(description: "analysis debounce paused")
    let gate = RulesAnalysisGate(started: started)
    var documents: [CustomRuleDocument] = []
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: [broad, narrow]) },
      commitDocument: {
        documents.append($0)
        return RuleDocumentCommit(outcome: .saved, document: $0)
      },
      analysisDelay: { await gate.wait() },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(source: .custom))
    let originalOrder = workflow.snapshot.rows.map(\.id)
    let oldRelationships = try XCTUnwrap(
      workflow.snapshot.rows.first { $0.identity == narrow.identity }
    ).relationships
    XCTAssertFalse(oldRelationships.isEmpty)
    await workflow.setEnabled(false, identities: [broad.identity])
    await fulfillment(of: [started], timeout: 3)
    XCTAssertTrue(workflow.snapshot.isComplete)
    XCTAssertFalse(workflow.snapshot.isCommitting)
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == broad.identity }!.isEnabled)
    XCTAssertEqual(
      workflow.snapshot.rows.first { $0.identity == narrow.identity }!.relationships,
      oldRelationships)
    workflow.setTestTarget("other.pending.example")
    await workflow.testAddress()
    XCTAssertEqual(workflow.snapshot.addressTest.result?.outcome, .direct)
    await workflow.setEnabled(true, identities: [broad.identity])
    await workflow.setEnabled(false, identities: [broad.identity])
    XCTAssertEqual(documents.count, 3)
    let version = workflow.snapshot.version
    await gate.resume()
    await workflow.analysisTask?.value
    XCTAssertEqual(workflow.snapshot.version, version)
    XCTAssertEqual(workflow.snapshot.rows.map(\.id), originalOrder)
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == broad.identity }!.isEnabled)
    XCTAssertTrue(
      workflow.snapshot.rows.first { $0.identity == narrow.identity }!.relationships.isEmpty)
  }

  func testCollectionSaveKeepsRowOrderAndFixedFactsWithoutWaitingForAnalysis() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let session = RuleDocumentSession(store: store)
    let started = expectation(description: "analysis paused")
    let gate = RulesAnalysisGate(started: started)
    let workflow = RulesWorkflow(
      preset: .chinaDirect,
      loadDocument: { try session.load() },
      commitDocument: { document in
        do {
          try session.save(document)
          return RuleDocumentCommit(outcome: .saved, document: session.current)
        } catch {
          XCTFail("Fixture save failed: \(error)")
          return RuleDocumentCommit(outcome: .persistenceFailed, document: session.current)
        }
      },
      analysisDelay: { await gate.wait() },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { source in
        if source == .geolocationCN {
          return rulesFixture(
            source,
            rules: [
              ProxyRule(action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn")),
              ProxyRule(action: .direct, match: try RuleMatch(domainExact: "fixture.example")),
            ])
        }
        return rulesFixture(source)
      }))
    await workflow.refresh()
    XCTAssertTrue(workflow.snapshot.isComplete)
    XCTAssertTrue(workflow.snapshot.sources.contains { $0.id == .geolocationCN })
    workflow.query(RulesQuery())
    let rowIDs = workflow.snapshot.rows.map(\.id)
    let fixed = workflow.snapshot.rows.filter(\.isFixed)
    XCTAssertFalse(fixed.isEmpty)
    let nationalSuffix = ProxyRule(
      action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))
    await workflow.setEnabled(false, identities: [nationalSuffix])
    XCTAssertTrue(try store.loadDocument().disabledIdentities.contains(nationalSuffix))
    XCTAssertEqual(workflow.snapshot.rows.map(\.id), rowIDs)
    XCTAssertEqual(workflow.snapshot.rows.filter(\.isFixed), fixed)
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == nationalSuffix }!.isEnabled)
    XCTAssertTrue(workflow.snapshot.isComplete)
    await fulfillment(of: [started], timeout: 3)
    await gate.resume()
    await workflow.analysisTask?.value
    XCTAssertEqual(workflow.snapshot.rows.map(\.id), rowIDs)
    XCTAssertEqual(workflow.snapshot.rows.filter(\.isFixed), fixed)
  }

  func testSuccessfulCommitDoesNotReadSourcesOrUserDocumentAgain() async throws {
    let reads = RulesReadCounts()
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "saved.example"))
    let workflow = RulesWorkflow(
      preset: .chinaDirect,
      loadDocument: {
        reads.recordDocument()
        return CustomRuleDocument(rules: [rule])
      },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { source in
        reads.recordSource()
        return rulesFixture(source)
      }))
    await workflow.refresh()
    await workflow.setEnabled(false, identities: [rule.identity])
    XCTAssertEqual(reads.documentCount, 1)
    XCTAssertEqual(reads.sourceCount, 2)
    XCTAssertFalse(
      try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == rule.identity }).isEnabled)
  }

  func testInFlightBatchRejectsRepeatedCommandAndPublishesProgress() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "example.net"))
    try store.save([rule])
    let started = expectation(description: "commit started")
    var continuation: CheckedContinuation<Void, Never>?
    var commits = 0
    let workflow = RulesWorkflow(
      loadDocument: { try store.loadDocument() },
      commitDocument: { document in
        commits += 1
        await withCheckedContinuation {
          continuation = $0
          started.fulfill()
        }
        do {
          try store.saveDocument(document)
          return RuleDocumentCommit(outcome: .saved, document: document)
        } catch {
          XCTFail("Fixture save failed: \(error)")
          return RuleDocumentCommit(
            outcome: .persistenceFailed, document: try? store.loadDocument())
        }
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let pending = Task { await workflow.setEnabled(false, identities: [rule.identity]) }
    await fulfillment(of: [started], timeout: 3)
    XCTAssertTrue(workflow.snapshot.isCommitting)
    XCTAssertEqual(workflow.snapshot.operationStatus, .updating)
    XCTAssertNil(workflow.snapshot.commitFeedback)
    await workflow.setEnabled(false, identities: [rule.identity])
    await workflow.refresh()
    XCTAssertEqual(commits, 1)
    continuation?.resume()
    await pending.value
    XCTAssertFalse(workflow.snapshot.isCommitting)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    let feedback = try XCTUnwrap(workflow.snapshot.commitFeedback)
    XCTAssertEqual(feedback.changedCount, 1)
    XCTAssertEqual(feedback.operation, .enablement(false))
    XCTAssertEqual(workflow.snapshot.operationStatus, .feedback(feedback))
    XCTAssertFalse(workflow.snapshot.rows.first { $0.identity == rule.identity }!.isEnabled)
  }

  func testFailedSaveKeepsSnapshotWithoutReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let rule = CustomRule(action: .direct, match: try RuleMatch(domainExact: "kept.example"))
    try store.save([rule])
    var commits = 0
    let workflow = RulesWorkflow(
      loadDocument: { try store.loadDocument() },
      commitDocument: { _ in
        commits += 1
        return RuleDocumentCommit(outcome: .persistenceFailed, document: try? store.loadDocument())
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let version = workflow.snapshot.version
    await workflow.setEnabled(false, identities: [rule.identity])
    XCTAssertEqual(workflow.snapshot.commitOutcome, .persistenceFailed)
    XCTAssertEqual(workflow.snapshot.version, version)
    XCTAssertTrue(workflow.snapshot.rows.first { $0.identity == rule.identity }!.isEnabled)
    XCTAssertEqual(commits, 1)
  }
}

private final class RulesReadCounts: @unchecked Sendable {
  private let lock = NSLock()
  private var documents = 0
  private var sources = 0
  func recordDocument() { lock.withLock { documents += 1 } }
  func recordSource() { lock.withLock { sources += 1 } }
  var documentCount: Int { lock.withLock { documents } }
  var sourceCount: Int { lock.withLock { sources } }
}

private actor RulesAnalysisGate {
  let started: XCTestExpectation
  private var continuation: CheckedContinuation<Void, Never>?
  private var first = true
  init(started: XCTestExpectation) { self.started = started }
  func wait() async {
    guard first else { return }
    first = false
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
