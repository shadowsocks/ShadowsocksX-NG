import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 自定义规则校验：固定本地冲突、ACL 优先级说明与重复拒绝，
/// 并返回可解释原因。
final class CustomRuleValidatorTests: XCTestCase {

  private func rule(
    _ action: RuleAction,
    _ match: RuleMatch,
    id: UUID = UUID()
  ) -> CustomRule {
    CustomRule(id: id, action: action, match: match)
  }

  func testOppositeActionsAreRetainedRegardlessOfCustomOrder() throws {
    let rules = [
      rule(.direct, try RuleMatch(domainExact: "a.example.com")),
      rule(.proxy, try RuleMatch(domainSuffix: "example.com")),
    ]
    let first = CustomRuleValidator.validate(custom: rules, defaultAction: .directWhenUnmatched)
    let reversed = CustomRuleValidator.validate(
      custom: Array(rules.reversed()), defaultAction: .directWhenUnmatched)
    XCTAssertTrue(first.rejected.isEmpty)
    XCTAssertTrue(reversed.rejected.isEmpty)
    XCTAssertEqual(first, reversed)
    XCTAssertEqual(first.accepted.count, 2)
  }

  // MARK: 有效规则

  func testValidDomainAndCIDRRulesAreAccepted() throws {
    let custom = [
      rule(.proxy, try RuleMatch(domainSuffix: "blocked.example")),
      rule(.direct, try RuleMatch(domainExact: "ok.example.cn")),
      rule(.direct, try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
      rule(.proxy, try RuleMatch(ipv6CIDR: "2001:db8::/32")),
    ]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.accepted.count, 4)
    XCTAssertTrue(
      result.accepted.contains { $0.aclLine == "||blocked.example" && $0.action == .proxy })
  }

  func testMappedIPv6CannotBypassFixedLocalConflictValidation() throws {
    let privateRule = rule(.proxy, try RuleMatch(ipv6CIDR: "::ffff:192.168.1.2"))
    let broadRule = rule(.proxy, try RuleMatch(ipv6CIDR: "::ffff:0.0.0.0/96"))
    let publicRule = rule(.proxy, try RuleMatch(ipv6CIDR: "::ffff:203.0.113.8"))
    let result = CustomRuleValidator.validate(
      custom: [privateRule, publicRule, broadRule], defaultAction: .directWhenUnmatched)
    XCTAssertEqual(result.rejected.count, 2)
    XCTAssertTrue(result.rejected.allSatisfy { $0.reason == .conflictsWithFixedLocalScope })
    XCTAssertEqual(result.accepted, [publicRule.proxyRule])
  }

  // MARK: 固定本地冲突

  func testProxyRuleOverFixedLocalIPRangeIsRejected() throws {
    let custom = [rule(.proxy, try RuleMatch(ipv4CIDR: "10.1.2.3/32"))]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertEqual(result.accepted.count, 0)
    XCTAssertEqual(result.rejected.count, 1)
    XCTAssertEqual(result.rejected[0].reason, .conflictsWithFixedLocalScope)
    XCTAssertFalse(result.rejected[0].explanation.isEmpty)
  }

  func testProxyRuleOverlappingFixedLocalIPRangeIsRejected() throws {
    // 172.0.0.0/8 与固定本地 172.16.0.0/12 相交。
    let custom = [rule(.proxy, try RuleMatch(ipv4CIDR: "172.0.0.0/8"))]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .proxyWhenUnmatched)

    XCTAssertEqual(result.rejected.map(\.reason), [.conflictsWithFixedLocalScope])
  }

  func testProxyRuleOverLocalHostnameIsRejected() throws {
    let custom = [
      rule(.proxy, try RuleMatch(domainExact: "localhost")),
      rule(.proxy, try RuleMatch(domainExact: "printer.local")),
      rule(.proxy, try RuleMatch(domainExact: "myhost")),
      rule(.proxy, try RuleMatch(domainSuffix: "home.local")),
    ]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertEqual(result.accepted.count, 0)
    XCTAssertEqual(result.rejected.count, 4)
    XCTAssertTrue(
      result.rejected.allSatisfy { $0.reason == .conflictsWithFixedLocalScope })
  }

  func testDirectRuleOverFixedLocalIsAllowed() throws {
    let custom = [rule(.direct, try RuleMatch(ipv4CIDR: "127.0.0.0/8"))]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .proxyWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.accepted.count, 1)
  }

  func testProxyRuleOutsideFixedLocalIsAllowed() throws {
    let custom = [
      rule(.proxy, try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
      rule(.proxy, try RuleMatch(domainSuffix: "example.com")),
      rule(.proxy, try RuleMatch(ipv4CIDR: "172.15.0.0/16")),
    ]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.accepted.count, 3)
  }

  // MARK: 遮蔽

  func testDomainDirectShadowedByBroaderDomainProxyIsExplainedWhenProxySideWritten() throws {
    let builtIn = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let custom = [rule(.direct, try RuleMatch(domainExact: "sub.blocked.example"))]

    let result = CustomRuleValidator.validate(
      custom: custom, builtIn: builtIn, defaultAction: .directWhenUnmatched)

    XCTAssertEqual(result.accepted.count, 1)
    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.relationships.first?.extent, .full)
  }

  func testDomainDirectNotShadowedWhenProxySideNotWritten() throws {
    // 「未匹配时代理」骨架不写 proxy_list，域名代理表为空，直连规则不会被遮蔽。
    let builtIn = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let custom = [rule(.direct, try RuleMatch(domainExact: "sub.blocked.example"))]

    let result = CustomRuleValidator.validate(
      custom: custom, builtIn: builtIn, defaultAction: .proxyWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.accepted.count, 1)
  }

  func testIPProxyShadowedByBroaderIPDirectIsExplainedWhenProxySideWritten() throws {
    let builtIn = [
      ProxyRule(
        action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24"))
    ]
    let custom = [rule(.proxy, try RuleMatch(ipv4CIDR: "203.0.113.10/32"))]

    let result = CustomRuleValidator.validate(
      custom: custom, builtIn: builtIn, defaultAction: .directWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.relationships.first?.kind, .shadowing)
    XCTAssertEqual(result.relationships.first?.extent, .full)
  }

  func testIPProxyNotRejectedWhenProxySideNotWritten() throws {
    // 「未匹配时代理」不写 proxy_list；IP 代理规则不参与 bypass 优先判定。
    let builtIn = [
      ProxyRule(
        action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24"))
    ]
    let custom = [rule(.proxy, try RuleMatch(ipv4CIDR: "203.0.113.10/32"))]

    let result = CustomRuleValidator.validate(
      custom: custom, builtIn: builtIn, defaultAction: .proxyWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.accepted.count, 1)
  }

  func testDomainProxyNotShadowedByDomainDirect() throws {
    // 域名 proxy_list 优先于 bypass_list：代理规则不会被直连遮蔽。
    let builtIn = [
      ProxyRule(
        action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
    ]
    let custom = [rule(.proxy, try RuleMatch(domainExact: "a.example.com"))]

    let result = CustomRuleValidator.validate(
      custom: custom, builtIn: builtIn, defaultAction: .directWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
  }

  func testCustomToCustomDomainShadowingIsDetected() throws {
    let custom = [
      rule(.proxy, try RuleMatch(domainSuffix: "example.com")),
      rule(.direct, try RuleMatch(domainExact: "a.example.com")),
    ]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertEqual(result.accepted.count, 2)
    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.relationships.first?.rule.action, .direct)
  }

  func testCustomToCustomIPShadowingIsDetected() throws {
    let custom = [
      rule(.direct, try RuleMatch(ipv4CIDR: "198.51.100.0/24")),
      rule(.proxy, try RuleMatch(ipv4CIDR: "198.51.100.5/32")),
    ]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.relationships.first?.kind, .shadowing)
    XCTAssertEqual(result.relationships.first?.extent, .full)
    XCTAssertEqual(result.relationships.first?.rule.action, .proxy)
  }

  // MARK: 重复

  func testDuplicateContentIsRejected() throws {
    let match = try RuleMatch(domainSuffix: "example.com")
    let custom = [
      rule(.proxy, match),
      rule(.proxy, match),
    ]

    let result = CustomRuleValidator.validate(
      custom: custom, defaultAction: .directWhenUnmatched)

    XCTAssertTrue(result.accepted.isEmpty)
    XCTAssertEqual(result.rejected.map(\.reason), [.duplicate, .duplicate])
  }

  // MARK: 覆盖判定

  func testDomainCoverageMatrix() throws {
    let suffixExample = try RuleMatch(domainSuffix: "example.com")
    let exactA = try RuleMatch(domainExact: "a.example.com")
    let exactExample = try RuleMatch(domainExact: "example.com")
    let suffixA = try RuleMatch(domainSuffix: "a.example.com")
    let suffixOther = try RuleMatch(domainSuffix: "other.example")

    XCTAssertTrue(RuleCoverage.domainCovers(suffixExample, exactA))
    XCTAssertTrue(RuleCoverage.domainCovers(suffixExample, exactExample))
    XCTAssertTrue(RuleCoverage.domainCovers(suffixExample, suffixA))
    XCTAssertFalse(RuleCoverage.domainCovers(exactA, suffixA), "精确不覆盖后缀")
    XCTAssertFalse(RuleCoverage.domainCovers(suffixA, suffixExample), "窄后缀不覆盖宽后缀")
    XCTAssertFalse(RuleCoverage.domainCovers(suffixExample, suffixOther))
    XCTAssertTrue(RuleCoverage.domainCovers(exactA, exactA))
  }

  func testIPCoverageMatrix() throws {
    let slash8 = try RuleMatch(ipv4CIDR: "10.0.0.0/8")
    let slash16 = try RuleMatch(ipv4CIDR: "10.1.0.0/16")
    let host = try RuleMatch(ipv4CIDR: "10.1.2.3/32")
    let other = try RuleMatch(ipv4CIDR: "11.0.0.0/8")

    XCTAssertTrue(RuleCoverage.ipCovers(slash8, slash16))
    XCTAssertTrue(RuleCoverage.ipCovers(slash8, host))
    XCTAssertFalse(RuleCoverage.ipCovers(slash16, slash8))
    XCTAssertFalse(RuleCoverage.ipCovers(slash8, other))
  }
}
