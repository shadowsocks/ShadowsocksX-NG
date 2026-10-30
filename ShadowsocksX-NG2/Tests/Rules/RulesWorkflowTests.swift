import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class RulesWorkflowTests: XCTestCase {
  func testDisableAcrossSourcesRestoresCoverageAndOrphanCanBeEnabled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let broad = CustomRule(
      action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let narrow = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "safe.example.com"))
    let orphan = ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "gone.example"))
    try store.saveDocument(
      CustomRuleDocument(rules: [broad, narrow], disabledIdentities: [orphan]))
    var commits = 0
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadDocument: { try store.loadDocument() },
      commitDocument: { document in
        commits += 1
        do {
          try store.saveDocument(document)
          return RuleDocumentCommit(outcome: .saved, document: document)
        } catch {
          XCTFail("Fixture save failed: \(error)")
          return RuleDocumentCommit(
            outcome: .persistenceFailed, document: try? store.loadDocument())
        }
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { source in
        guard source == .gfwlist else { return rulesFixture(source) }
        return rulesFixture(
          source,
          rules: [
            ProxyRule(action: .proxy, match: broad.match)
          ])
      }))
    await workflow.refresh()
    let version = workflow.snapshot.version
    let covered = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == narrow.identity })
    XCTAssertTrue(covered.relationships.contains { $0.kind == .absorption && $0.extent == .full })
    workflow.select([.rule(broad.identity), .noDotHostname])
    XCTAssertEqual(workflow.actionableSelection, [broad.identity])
    await workflow.setEnabled(false, identities: workflow.actionableSelection)
    XCTAssertEqual(commits, 1)
    XCTAssertNotEqual(workflow.snapshot.version, version)
    try await assertDisabledRowsAndOrphanCanBeEnabled(
      workflow: workflow, store: store, broad: broad, narrow: narrow, orphan: orphan)
  }

  private func assertDisabledRowsAndOrphanCanBeEnabled(
    workflow: RulesWorkflow, store: CustomRuleStore, broad: CustomRule,
    narrow: CustomRule, orphan: ProxyRule
  ) async throws {
    let disabled = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == broad.identity })
    XCTAssertFalse(disabled.isEnabled)
    XCTAssertEqual(disabled.sources, [.custom, .gfwlist])
    await workflow.analysisTask?.value
    XCTAssertTrue(
      workflow.snapshot.rows.first { $0.identity == narrow.identity }!.relationships.isEmpty)
    workflow.setTestTarget("safe.example.com")
    await workflow.testAddress()
    XCTAssertEqual(workflow.snapshot.addressTest.result?.outcome, .proxy)
    workflow.query(RulesQuery(enabled: false))
    XCTAssertTrue(workflow.snapshot.rows.contains { $0.identity == orphan && !$0.hasCurrentSource })
    await workflow.setEnabled(true, identities: [orphan])
    XCTAssertFalse(workflow.snapshot.rows.contains { $0.identity == orphan })
    XCTAssertNil(workflow.snapshot.addressTest.result)
    XCTAssertFalse(try store.loadDocument().disabledIdentities.contains(orphan))
  }

  func testEquivalentSourcesMergeForShippedRules() async throws {
    let match = try RuleMatch(domainExact: "Example.COM")
    let custom = CustomRule(action: .direct, match: match)
    let source = RuleSourceIdentity(kind: .geolocationCN, upstreamVersion: "fixture", label: "geo")
    let snapshot = RuleSnapshot(
      metadata: RuleSnapshotMetadata(
        source: source, upstreamReference: "upstream", inputDigest: "digest",
        fetchedAt: Date(timeIntervalSince1970: 0), converterVersion: "2.0.0", license: "MIT",
        attribution: "author"),
      rules: [ProxyRule(action: .direct, match: match)])
    let workflow = RulesWorkflow(
      preset: .chinaDirect,
      loadCustom: { [custom] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { source in
        source == .geolocationCN ? snapshot : rulesFixture(source)
      }))
    await workflow.refresh()
    workflow.query(RulesQuery(search: "EXAMPLE", action: .direct, source: .geolocationCN))
    let row = try XCTUnwrap(workflow.snapshot.rows.first)
    XCTAssertEqual(workflow.snapshot.rows.count, 1)
    XCTAssertTrue(row.sources.contains(.custom))
    XCTAssertTrue(row.sources.contains(.geolocationCN))
    XCTAssertEqual(row.customIDs, [custom.id])
    XCTAssertEqual(row.identity, custom.identity)
  }
  func testWrongBuiltinSourceIsAnIncompleteCollectionRatherThanMislabeledRules() async throws {
    let workflow = RulesWorkflow(
      loadCustom: { [] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { _ in
        rulesFixture(.geolocationCN)
      }))
    await workflow.refresh()
    XCTAssertFalse(workflow.snapshot.isComplete)
    XCTAssertEqual(workflow.snapshot.issues.count, 1)
  }

  func testSearchActionAndSourceIntersectAndHiddenSelectionIsCleared() async throws {
    let direct = CustomRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
    let other = CustomRule(action: .direct, match: try RuleMatch(domainExact: "outside.net"))
    let workflow = RulesWorkflow(
      preset: .chinaDirect, loadCustom: { [direct, other] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select([.rule(direct.identity), .rule(other.identity), .noDotHostname])
    workflow.query(RulesQuery(search: "EXAMPLE", action: .direct, source: .custom))
    XCTAssertEqual(workflow.snapshot.rows.map(\.identity), [direct.identity])
    XCTAssertEqual(workflow.snapshot.selection, [.rule(direct.identity)])
    workflow.query(RulesQuery(search: "EXAMPLE", action: .proxy, source: .custom))
    XCTAssertTrue(workflow.snapshot.rows.isEmpty)
    XCTAssertTrue(workflow.snapshot.selection.isEmpty)
    XCTAssertTrue(workflow.snapshot.isComplete)
  }

  func testStableInputOrderAndNavigationPreserveVersionAndSessionQuery() async throws {
    let entries = [
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: "z.net")),
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: "a.net")),
    ]
    let workflow = RulesWorkflow(
      loadCustom: { entries }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let version = workflow.snapshot.version
    workflow.query(RulesQuery(source: .custom))
    workflow.select([.rule(entries[0].identity)])
    let route = WorkspaceRoute()
    route.navigate(to: .rules)
    route.navigate(to: .home)
    route.navigate(to: .rules)
    XCTAssertEqual(workflow.snapshot.rows.map(\.content), ["z.net", "a.net"])
    XCTAssertEqual(workflow.snapshot.query.source, .custom)
    XCTAssertEqual(workflow.snapshot.selection, [.rule(entries[0].identity)])
    await workflow.refresh()
    XCTAssertEqual(workflow.snapshot.version, version)
    XCTAssertEqual(workflow.snapshot.selection, [.rule(entries[0].identity)])
  }

  func testCorruptUserDocumentAndMissingBuiltinStayDistinctFromEmptySearch() async throws {
    let workflow = RulesWorkflow(
      preset: .chinaDirect,
      loadCustom: { throw CustomRuleStoreError.corrupt(detail: "fixture") },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { source in
        if source == .chinaIPv4 { throw RuleSnapshotError.missing }
        return rulesFixture(source)
      }))
    await workflow.refresh()
    XCTAssertFalse(workflow.snapshot.isComplete)
    XCTAssertEqual(
      workflow.snapshot.issues,
      [.userDocument("corrupt(detail: \"fixture\")"), .builtin(.chinaIPv4, "missing")])
    workflow.query(RulesQuery(source: .fixed))
    XCTAssertTrue(workflow.snapshot.rows.contains { $0.isFixed })
    workflow.query(RulesQuery(search: "no-result.example"))
    XCTAssertTrue(workflow.snapshot.rows.isEmpty)
    XCTAssertFalse(workflow.snapshot.isComplete)
    XCTAssertEqual(workflow.snapshot.issues.count, 2)
  }

  func testPackagedCollectionLoadsMetadataShippedRulesAndFixedSemanticPolicy() async throws {
    let bundle = AppArtifact.bundle
    let workflow = RulesWorkflow(
      preset: .chinaDirect,
      loadCustom: { [] },
      builtinSnapshots: BuiltinRuleSnapshots(bundle: bundle))
    await workflow.refresh()
    XCTAssertTrue(workflow.snapshot.isComplete, "\(workflow.snapshot.issues)")
    XCTAssertEqual(workflow.snapshot.sources.count, 4)
    workflow.query(RulesQuery(source: .fixed))
    XCTAssertTrue(workflow.snapshot.rows.contains { $0.id == .noDotHostname && $0.isFixed })
    let geo = try XCTUnwrap(workflow.snapshot.sources.first { $0.id == .geolocationCN })
    XCTAssertEqual(geo.count, 4241)
    XCTAssertEqual(geo.metadata?.source.upstreamVersion, "20260925234224")
    XCTAssertNotNil(geo.conversionReport)
    let rows = workflow.snapshot.rows
    XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    workflow.query(RulesQuery(source: .geolocationCN))
    XCTAssertTrue(workflow.snapshot.rows.contains { $0.content == "cn" })
    XCTAssertEqual(workflow.snapshot.rows.count, 4241)
  }

  func testRefreshPublishesVersionAndRowsTogetherAndInvalidatesRemovedSelection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let old = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "old.net"))
    let new = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "new.net"))
    try store.save([old])
    let workflow = RulesWorkflow(
      loadCustom: { try store.load() },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(source: .custom))
    workflow.select([.rule(old.identity)])
    let oldVersion = workflow.snapshot.version
    try store.save([new])
    let observation = workflow.$snapshot.sink { snapshot in
      if snapshot.version != oldVersion {
        XCTAssertEqual(snapshot.rows.map(\.content), ["new.net"])
        XCTAssertTrue(snapshot.selection.isEmpty)
      }
    }
    await workflow.refresh()
    observation.cancel()
    XCTAssertNotEqual(workflow.snapshot.version, oldVersion)
    XCTAssertEqual(workflow.snapshot.rows.map(\.identity), [new.identity])
    let loadedVersion = workflow.snapshot.version
    try Data("broken".utf8).write(to: store.fileURL)
    await workflow.refresh()
    XCTAssertFalse(workflow.snapshot.isComplete)
    XCTAssertEqual(workflow.snapshot.issues.count, 1)
    XCTAssertEqual(workflow.snapshot.rows.map(\.identity), [new.identity])
    XCTAssertEqual(workflow.snapshot.version, loadedVersion)
    XCTAssertEqual(workflow.snapshot.operationStatus, .collectionIncomplete)
  }

  func testLateOldRefreshCannotReplaceTheNewCollection() async throws {
    let firstRead = XCTestExpectation(description: "first read")
    let barrier = RulesReadBarrier(firstRead: firstRead)
    let workflow = RulesWorkflow(
      loadCustom: { try barrier.read() },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    let older = Task { await workflow.refresh() }
    await fulfillment(of: [firstRead], timeout: 3)
    defer { barrier.release.signal() }
    XCTAssertTrue(workflow.snapshot.isLoading)
    await workflow.refresh()
    workflow.query(RulesQuery(source: .custom))
    XCTAssertEqual(workflow.snapshot.rows.map(\.content), ["new.net"])
    let version = workflow.snapshot.version
    barrier.release.signal()
    await older.value
    XCTAssertEqual(workflow.snapshot.rows.map(\.content), ["new.net"])
    XCTAssertEqual(workflow.snapshot.version, version)
    XCTAssertFalse(workflow.snapshot.isLoading)
  }

}

extension RulesWorkflowTests {
  func testCandidatePermutationKeepsVersionAndCoverageWhilePreservingInputOrder() async throws {
    let broad = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let narrow = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "www.example.com"))
    let forward = RulesWorkflow(
      loadCustom: { [broad, narrow] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    let reverse = RulesWorkflow(
      loadCustom: { [narrow, broad] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await forward.refresh()
    await reverse.refresh()
    XCTAssertEqual(forward.snapshot.version, reverse.snapshot.version)
    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: forward.snapshot.rows.map { ($0.id, $0) }),
      Dictionary(uniqueKeysWithValues: reverse.snapshot.rows.map { ($0.id, $0) }))
    XCTAssertEqual(
      forward.snapshot.rows.prefix(2).compactMap(\.identity), [broad.identity, narrow.identity])
    XCTAssertEqual(
      reverse.snapshot.rows.prefix(2).compactMap(\.identity), [narrow.identity, broad.identity])
  }

  func testSameNamedExactAndSuffixHaveStableVersionsAcrossRefreshes() async throws {
    let exact = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "example.com"))
    let suffix = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let workflow = RulesWorkflow(
      loadCustom: { [suffix, exact] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let version = workflow.snapshot.version
    let identities = workflow.snapshot.rows.map(\.identity)
    for _ in 0..<12 {
      await workflow.refresh()
      XCTAssertEqual(workflow.snapshot.version, version)
      XCTAssertEqual(workflow.snapshot.rows.map(\.identity), identities)
    }
  }

}

extension RulesWorkflowTests {
  func testCollectionRemovesReverseActionsAndPreservesRemainingInputOrder() throws {
    let exact = try RuleMatch(domainExact: "same.example")
    let suffix = try RuleMatch(domainSuffix: "same.example")
    let rules = [
      CustomRule(action: .proxy, match: suffix),
      CustomRule(action: .direct, match: suffix),
      CustomRule(action: .proxy, match: exact),
      CustomRule(action: .direct, match: exact),
    ]
    for input in [rules, Array(rules.reversed())] {
      let collection = RulesCollection.load(
        preset: .gfwlist, custom: { input }, builtin: { rulesFixture($0) })
      XCTAssertTrue(collection.issues.isEmpty)
      XCTAssertEqual(
        collection.rows.filter { $0.content == "same.example" }.compactMap(\.identity),
        input.filter { $0.action == .proxy }.map(\.identity))
      XCTAssertTrue(collection.rows.contains { $0.id == .noDotHostname && $0.isFixed })
    }
  }
}

func rulesFixture(
  _ source: RulesSource, rules: [ProxyRule] = []
) -> RuleSnapshot {
  guard let kind = source.sourceKind else {
    preconditionFailure("Fixed policy has no rule snapshot")
  }
  return RuleSnapshot(
    metadata: RuleSnapshotMetadata(
      source: RuleSourceIdentity(kind: kind, upstreamVersion: "v1", label: source.rawValue),
      upstreamReference: "https://example.com/source", inputDigest: "fixture",
      fetchedAt: Date(timeIntervalSince1970: 0), converterVersion: "2.0.0",
      license: "MIT", attribution: "fixture author"), rules: rules)
}

private final class RulesReadBarrier: @unchecked Sendable {
  let release = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var reads = 0
  private let firstRead: XCTestExpectation

  init(firstRead: XCTestExpectation) { self.firstRead = firstRead }

  func read() throws -> [CustomRule] {
    lock.lock()
    reads += 1
    let first = reads == 1
    lock.unlock()
    if first {
      firstRead.fulfill()
      guard release.wait(timeout: .now() + 5) == .success else { throw RuleSnapshotError.missing }
    }
    return [
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: first ? "old.net" : "new.net"))
    ]
  }
}
