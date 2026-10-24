import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class RulesWorkflowCoverageTests: XCTestCase {
  func testCoverageUsesAllSourcesAndDistinguishesPartialFromFull() async throws {
    let broad = CustomRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
    let narrow = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "www.example.com"))
    let duplicate = CustomRule(
      action: .direct, match: try RuleMatch(domainExact: "www.example.com"))
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadCustom: { [broad, narrow, duplicate] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(action: .direct, source: .custom))
    let broadRow = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == broad.identity })
    XCTAssertTrue(
      broadRow.relationships.contains {
        $0.kind == .shadowing && $0.extent == .partial && $0.covering == [narrow.identity]
      })
    let narrowRow = try XCTUnwrap(
      workflow.snapshot.rows.first { $0.identity == duplicate.identity })
    XCTAssertTrue(narrowRow.relationships.contains { $0.kind == .shadowing && $0.extent == .full })
    XCTAssertTrue(narrowRow.relationships.contains { $0.kind == .absorption && $0.extent == .full })
    XCTAssertTrue(workflow.snapshot.rows.filter(\.isFixed).allSatisfy { $0.relationships.isEmpty })
  }

  func testMappedIPAndCombinedNarrowRangesExplainCoverageThroughWorkflow() async throws {
    let proxy = CustomRule(action: .proxy, match: try RuleMatch(ipv6CIDR: "::ffff:8.8.8.0/120"))
    let lower = CustomRule(action: .direct, match: try RuleMatch(ipv4CIDR: "8.8.8.0/25"))
    let upper = CustomRule(action: .direct, match: try RuleMatch(ipv4CIDR: "8.8.8.128/25"))
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadCustom: { [proxy, lower, upper] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(action: .proxy, source: .custom))
    let row = try XCTUnwrap(workflow.snapshot.rows.first)
    XCTAssertEqual(row.identity, proxy.identity)
    XCTAssertEqual(row.relationships.count, 1)
    XCTAssertEqual(row.relationships.first?.kind, .shadowing)
    XCTAssertEqual(row.relationships.first?.extent, .full)
    XCTAssertEqual(Set(row.relationships.first?.covering ?? []), [lower.identity, upper.identity])
  }

  func testFixedProtectionExplainsSimpleHostsAndPreventsFalseLocalShadowing() async throws {
    let simple = ProxyRule(
      action: .proxy, match: try RuleMatch(domainExact: "printer"))
    let simpleSuffix = ProxyRule(action: .proxy, match: try RuleMatch(nationalDomainSuffix: "cn"))
    let localProxy = ProxyRule(
      action: .proxy, match: try RuleMatch(domainExact: "device.local"))
    let localDirect = CustomRule(action: .direct, match: try RuleMatch(domainExact: "device.local"))
    let nationalDirect = CustomRule(
      action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadCustom: { [localDirect, nationalDirect] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { requested in
        rulesFixture(
          requested, rules: requested == .gfwlist ? [simple, simpleSuffix, localProxy] : [])
      }))
    await workflow.refresh()
    workflow.query(RulesQuery(source: .gfwlist))
    let simpleRow = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == simple })
    XCTAssertEqual(simpleRow.fixedCoverage?.extent, .full)
    let suffixRow = try XCTUnwrap(
      workflow.snapshot.rows.first { $0.identity == simpleSuffix })
    XCTAssertEqual(suffixRow.fixedCoverage?.extent, .partial)
    workflow.query(RulesQuery(source: .custom))
    let localRow = try XCTUnwrap(
      workflow.snapshot.rows.first { $0.identity == localDirect.identity })
    XCTAssertEqual(localRow.fixedCoverage?.extent, .full)
    XCTAssertFalse(localRow.relationships.contains { $0.kind == .shadowing })
    let nationalRow = try XCTUnwrap(
      workflow.snapshot.rows.first { $0.identity == nationalDirect.identity })
    XCTAssertEqual(nationalRow.fixedCoverage?.extent, .partial)
    XCTAssertTrue(
      nationalRow.relationships.contains { $0.kind == .shadowing && $0.extent == .partial })
  }

  func testFullyFixedProtectedProxyDoesNotShadowAnUnprotectedDirectSuffix() async throws {
    let direct = CustomRule(action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))
    let proxy = ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "cn"))
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadCustom: { [direct] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { requested in
        rulesFixture(requested, rules: requested == .gfwlist ? [proxy] : [])
      }))
    await workflow.refresh()
    workflow.query(RulesQuery(source: .custom))
    let row = try XCTUnwrap(workflow.snapshot.rows.first)
    XCTAssertFalse(row.relationships.contains { $0.kind == .shadowing })
    XCTAssertEqual(row.fixedCoverage?.extent, .partial)
  }
}
