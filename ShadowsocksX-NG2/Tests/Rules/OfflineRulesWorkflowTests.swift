import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class OfflineRulesWorkflowTests: XCTestCase {
  func testAddressTestUsesCompleteSavedCollectionDespiteBrowsingFilters() async throws {
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let workflow = RulesWorkflow(
      loadCustom: { [rule] }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(search: "hidden", action: .direct, source: .chinaIPv4))
    XCTAssertTrue(workflow.snapshot.rows.isEmpty)
    workflow.setTestTarget("a.example.com")
    await workflow.testAddress()
    let result = try XCTUnwrap(workflow.snapshot.addressTest.result)
    XCTAssertEqual(result.outcome, .proxy)
    XCTAssertEqual(result.version, workflow.snapshot.version)
    XCTAssertEqual(result.deciding.map(\.identity), [rule.identity])
    XCTAssertTrue(result.domainWithoutDNS)
  }
  func testInvalidAndIncompleteCollectionsExposeOperationErrors() async throws {
    let workflow = RulesWorkflow(
      loadCustom: { [] }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    workflow.setTestTarget("example.com")
    await workflow.testAddress()
    XCTAssertEqual(workflow.snapshot.addressTest.failure, .incompleteCollection)
    await workflow.refresh()
    workflow.setTestTarget("https://")
    await workflow.testAddress()
    XCTAssertEqual(workflow.snapshot.addressTest.failure, .invalidTarget)
    XCTAssertNil(workflow.snapshot.addressTest.result)
    let incomplete = RulesWorkflow(
      loadCustom: { [] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { _ in throw RuleSnapshotError.missing }))
    await incomplete.refresh()
    incomplete.setTestTarget("localhost")
    await incomplete.testAddress()
    XCTAssertEqual(incomplete.snapshot.addressTest.failure, .incompleteCollection)
    XCTAssertNil(incomplete.snapshot.addressTest.result)
  }

  func testPublicRefreshClearsOldResultAndUsesNewSavedVersion() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let proxy = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "example.com"))
    try store.save([proxy])
    let workflow = RulesWorkflow(
      loadCustom: { try store.load() },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.setTestTarget("example.com")
    await workflow.testAddress()
    let version = workflow.snapshot.addressTest.result?.version
    try store.save([CustomRule(action: .direct, match: proxy.match)])
    await workflow.refresh()
    XCTAssertNil(workflow.snapshot.addressTest.result)
    XCTAssertFalse(workflow.snapshot.addressTest.isTesting)
    XCTAssertNotEqual(workflow.snapshot.version, version)
    XCTAssertEqual(workflow.snapshot.addressTest.target, "example.com")
    await workflow.testAddress()
    XCTAssertEqual(workflow.snapshot.addressTest.result?.outcome, .direct)
    try Data("broken".utf8).write(to: store.fileURL)
    await workflow.refresh()
    await workflow.testAddress()
    XCTAssertEqual(workflow.snapshot.addressTest.failure, .incompleteCollection)
    XCTAssertNil(workflow.snapshot.addressTest.result)
  }

  func testClearingTargetOrStartingRefreshPreventsLateTestPublication() async throws {
    let rule = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let workflow = RulesWorkflow(
      loadCustom: { [rule] }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.setTestTarget("example.com")
    await workflow.testAddress()
    workflow.setTestTarget("")
    XCTAssertNil(workflow.snapshot.addressTest.result)
    XCTAssertNil(workflow.snapshot.addressTest.failure)

    // Queue a new public command as soon as the old test starts. The old
    // detached task must not publish after that command invalidates its intent.
    for refresh in [false, true] {
      workflow.setTestTarget("example.com")
      var invalidation: Task<Void, Never>?
      let observation = workflow.$snapshot.sink { page in
        guard page.addressTest.isTesting, invalidation == nil else { return }
        invalidation = Task { @MainActor in
          if refresh { await workflow.refresh() } else { workflow.setTestTarget("") }
        }
      }
      await workflow.testAddress()
      await invalidation?.value
      observation.cancel()
      XCTAssertNil(workflow.snapshot.addressTest.result)
      XCTAssertFalse(workflow.snapshot.addressTest.isTesting)
    }
  }

  func testExternalSettingsChangesNeverSupplyAFallbackOrAlterThreeStateResults() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let preferences = makeTestProxyControlPreferences()
    let rules = [
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: "proxy.example")),
      CustomRule(action: .direct, match: try RuleMatch(domainExact: "direct.example")),
    ]
    let workflow = RulesWorkflow(
      loadCustom: { rules }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    for mode in [ProxyModeKind.rule, .global, .direct] {
      for defaultAction in RuleDefaultAction.allCases {
        for enabled in [false, true] {
          preferences.preferredMode = mode
          preferences.ruleDefaultAction = defaultAction
          preferences.agentEnabled = enabled
          preferences.systemProxyEnabled = enabled
          workflow.query(RulesQuery(search: "hidden", source: .fixed))
          for (target, outcome) in [
            ("proxy.example", OfflineRuleMatcher.Outcome.proxy),
            ("direct.example", .direct), ("unresolved.example", .unmatched),
            ("198.51.100.8", .unmatched),
          ] {
            workflow.setTestTarget(target)
            await workflow.testAddress()
            XCTAssertEqual(workflow.snapshot.addressTest.result?.outcome, outcome)
          }
        }
      }
    }
  }

}
