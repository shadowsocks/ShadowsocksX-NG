import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class RulesPresentationTests: XCTestCase {
  func testReportIsAnExplicitSnapshotUnaffectedByQueryOrRefresh() async throws {
    let loader = ReportFixtureLoader()
    let workflow = RulesWorkflow(
      preset: .chinaDirect, loadCustom: { [] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { loader.load($0) }))
    await workflow.refresh()
    XCTAssertTrue(workflow.openSourceReport(.geolocationCN))
    let opened = try XCTUnwrap(workflow.reportSource)
    workflow.query(RulesQuery(source: .chinaIPv4))
    loader.advance()
    await workflow.refresh()
    XCTAssertEqual(workflow.reportSource, opened)
    XCTAssertTrue(workflow.openSourceReport(.geolocationCN))
    XCTAssertEqual(workflow.reportSource, opened)
    XCTAssertTrue(workflow.openSourceReport(.chinaIPv4))
    XCTAssertEqual(workflow.reportSource?.id, .chinaIPv4)
    XCTAssertFalse(workflow.openSourceReport(.custom))
    XCTAssertEqual(workflow.reportSource?.id, .chinaIPv4)
  }
  func testRelationshipExplanationRequiresExactlyOneRelatedSelection() async throws {
    let broad = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let narrow = CustomRule(action: .direct, match: try RuleMatch(domainExact: "a.example.com"))
    let independent = CustomRule(action: .direct, match: try RuleMatch(domainExact: "other.net"))
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadCustom: { [broad, narrow, independent] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    XCTAssertNil(workflow.selectedRelationshipRow)
    workflow.select([.rule(narrow.identity)])
    let row = try XCTUnwrap(workflow.selectedRelationshipRow)
    XCTAssertEqual(row.identity, narrow.identity)
    XCTAssertEqual(row.relationships.first?.kind, .shadowing)
    XCTAssertEqual(row.relationships.first?.covering, [broad.identity])
    workflow.select([.rule(narrow.identity), .rule(independent.identity)])
    XCTAssertNil(workflow.selectedRelationshipRow)
    workflow.select([.rule(independent.identity)])
    XCTAssertNil(workflow.selectedRelationshipRow)
  }

  func testSameActionAndFixedCoverageRemainExplainable() async throws {
    let broad = CustomRule(action: .direct, match: try RuleMatch(domainSuffix: "example.net"))
    let narrow = CustomRule(action: .direct, match: try RuleMatch(domainExact: "a.example.net"))
    let local = CustomRule(action: .direct, match: try RuleMatch(domainExact: "device.local"))
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadCustom: { [broad, narrow, local] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select([.rule(narrow.identity)])
    let absorbed = try XCTUnwrap(workflow.selectedRelationshipRow)
    XCTAssertEqual(absorbed.relationships.first?.kind, .absorption)
    XCTAssertEqual(absorbed.relationships.first?.covering, [broad.identity])
    workflow.select([.rule(local.identity)])
    let fixed = try XCTUnwrap(workflow.selectedRelationshipRow?.fixedCoverage)
    XCTAssertEqual(fixed.matches, [.localSuffix])
    workflow.select([.noDotHostname])
    XCTAssertNil(workflow.selectedRelationshipRow)
  }

  func testOutcomeCopyMappingCoversEveryCase() throws {
    XCTAssertEqual(CustomRuleUpdateOutcome.saved.rulesMessage, RulesCopy.text("已保存"))
    XCTAssertEqual(
      CustomRuleUpdateOutcome.persistenceFailed.rulesMessage, RulesCopy.text("保存失败，规则未更改"))
    XCTAssertEqual(
      CustomRuleUpdateOutcome.persistenceFailed.nextStep, RulesCopy.text("请重试规则操作。"))
    XCTAssertNil(CustomRuleUpdateOutcome.persistenceFailed.failureDetail)
    XCTAssertEqual(CustomRuleUpdateOutcome.busy.rulesMessage, RulesCopy.text("正在更新规则…"))
    XCTAssertEqual(
      CustomRuleUpdateOutcome.superseded.rulesMessage, RulesCopy.text("规则集合已变化，操作未执行。"))
    XCTAssertEqual(CustomRuleUpdateOutcome.superseded.nextStep, RulesCopy.text("请重试规则操作。"))
    XCTAssertNil(CustomRuleUpdateOutcome.superseded.failureDetail)
    let invalid = CustomRuleUpdateOutcome.invalidDocument(detail: "detail-1")
    XCTAssertEqual(invalid.rulesMessage, RulesCopy.text("无法更新规则"))
    XCTAssertEqual(invalid.failureDetail, "detail-1")
    XCTAssertEqual(invalid.nextStep, RulesCopy.text("请检查规则数据后再操作。"))
    let rejected = CustomRuleUpdateOutcome.rejected([
      RejectedCustomRule(
        rule: CustomRule(action: .direct, match: try RuleMatch(domainExact: "a.test")),
        reason: .duplicate, explanation: "r1"),
      RejectedCustomRule(
        rule: CustomRule(action: .direct, match: try RuleMatch(domainExact: "b.test")),
        reason: .duplicate, explanation: "r2"),
    ])
    XCTAssertEqual(rejected.failureDetail, "r1\nr2")
    XCTAssertEqual(rejected.nextStep, RulesCopy.text("请检查规则数据后再操作。"))
    XCTAssertNil(CustomRuleUpdateOutcome.saved.failureDetail)
    XCTAssertNil(CustomRuleUpdateOutcome.saved.nextStep)
    let success = RulesCommitFeedback(
      outcome: .saved, operation: .enablement(true), changedCount: 3)
    XCTAssertEqual(
      success.summary,
      RulesCopy.text("已启用 3 条规则") + " · " + RulesCopy.text("已保存"))
    let failure = RulesCommitFeedback(outcome: .busy, operation: .delete, changedCount: 1)
    XCTAssertEqual(failure.summary, RulesCopy.text("正在更新规则…"))
  }

}

private final class ReportFixtureLoader: @unchecked Sendable {
  private let lock = NSLock()
  private var version = 1

  func advance() { lock.withLock { version += 1 } }

  func load(_ source: RulesSource) -> RuleSnapshot {
    let version = lock.withLock { version }
    let fixture = rulesFixture(source)
    let metadata = fixture.metadata
    return RuleSnapshot(
      metadata: RuleSnapshotMetadata(
        source: RuleSourceIdentity(
          kind: metadata.source.kind, upstreamVersion: "v\(version)", label: metadata.source.label),
        upstreamReference: metadata.upstreamReference, inputDigest: "digest-\(version)",
        fetchedAt: metadata.fetchedAt, converterVersion: metadata.converterVersion,
        license: metadata.license, attribution: metadata.attribution),
      rules: fixture.rules, lossReport: RuleConversionLossReport(absorbedCount: version))
  }
}
