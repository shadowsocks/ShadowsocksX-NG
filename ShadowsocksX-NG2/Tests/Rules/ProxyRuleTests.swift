import Foundation
import Testing
import XCTest

@testable import ShadowsocksX_NG2

/// 规则领域模型：动作与匹配条件独立于
/// PAC、ACL 文本和系统代理设置。
final class ProxyRuleTests: XCTestCase {
  // MARK: - 动作与匹配

  func testActionsAreProxyAndDirect() throws {
    XCTAssertEqual(RuleAction.proxy.rawValue, "proxy")
    XCTAssertEqual(RuleAction.direct.rawValue, "direct")
  }

  func testMatchKindsCoverDomainAndCIDR() throws {
    let exact = try RuleMatch(domainExact: "api.example.com")
    let suffix = try RuleMatch(domainSuffix: "example.com")
    // swiftlint:disable:next identifier_name
    let v4 = try RuleMatch(ipv4CIDR: "203.0.113.0/24")
    // swiftlint:disable:next identifier_name
    let v6 = try RuleMatch(ipv6CIDR: "2001:db8::/32")

    XCTAssertEqual(exact.pattern, .domainExact("api.example.com"))
    XCTAssertEqual(suffix.pattern, .domainSuffix("example.com"))
    XCTAssertEqual(v4.pattern, .ipv4CIDR("203.0.113.0/24"))
    XCTAssertEqual(v6.pattern, .ipv6CIDR("2001:db8::/32"))
  }

  func testDomainExactRejectsSuffixSemantics() throws {
    XCTAssertThrowsError(try RuleMatch(domainExact: "example.com."))
    XCTAssertThrowsError(try RuleMatch(domainExact: ".example.com"))
    XCTAssertThrowsError(try RuleMatch(domainExact: "*.example.com"))
    XCTAssertThrowsError(try RuleMatch(domainExact: ""))
    XCTAssertThrowsError(try RuleMatch(domainExact: "exa mple.com"))
    XCTAssertThrowsError(try RuleMatch(domainExact: "例子.com"))
  }

  func testDomainSuffixNormalizesAndRejectsInvalid() throws {
    XCTAssertEqual(try RuleMatch(domainSuffix: "Example.COM").pattern, .domainSuffix("example.com"))
    XCTAssertEqual(
      try RuleMatch(domainSuffix: ".example.com").pattern, .domainSuffix("example.com"))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "example.com."))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "*.example.com"))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: ""))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "localhost"))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "com"), "单标签后缀不允许，避免过宽匹配")
  }

  func testIPv4CIDRNormalizesHostAddressesAndRejectsInvalid() throws {
    XCTAssertEqual(try RuleMatch(ipv4CIDR: "203.0.113.7").pattern, .ipv4CIDR("203.0.113.7/32"))
    XCTAssertEqual(try RuleMatch(ipv4CIDR: "203.0.113.0/24").pattern, .ipv4CIDR("203.0.113.0/24"))
    // 主机位非零的前缀按网络地址规范化。
    XCTAssertEqual(try RuleMatch(ipv4CIDR: "203.0.113.15/24").pattern, .ipv4CIDR("203.0.113.0/24"))
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "203.0.113.0/33"))
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "203.0.113.256/24"))
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "2001:db8::/32"), "IPv6 不得进入 IPv4 匹配")
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "not-an-ip"))
  }

  func testIPv6CIDRNormalizesAndRejectsInvalid() throws {
    XCTAssertEqual(try RuleMatch(ipv6CIDR: "2001:db8::/32").pattern, .ipv6CIDR("2001:db8::/32"))
    XCTAssertEqual(
      try RuleMatch(ipv6CIDR: "2001:DB8:0:0:0:0:0:0/32").pattern, .ipv6CIDR("2001:db8::/32"))
    XCTAssertThrowsError(try RuleMatch(ipv6CIDR: "2001:db8::/129"))
    XCTAssertThrowsError(try RuleMatch(ipv6CIDR: "203.0.113.0/24"), "IPv4 不得进入 IPv6 匹配")
    XCTAssertThrowsError(try RuleMatch(ipv6CIDR: "gggg::/32"))
  }

  // MARK: - 规则序列化

  func testCustomRuleStorageKeepsFlatActionAndMatch() throws {
    let rule = ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
    let document = CustomRuleDocument(rules: [CustomRule(action: rule.action, match: rule.match)])
    let data = try CustomRuleStore.encode(document)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entry = try XCTUnwrap((json["rules"] as? [[String: Any]])?.first)
    XCTAssertEqual(Set(entry.keys), ["id", "action", "match"])
    XCTAssertEqual(try CustomRuleStore.decode(data).rules.first?.rule, rule)
  }
}

struct NormalizedRuleValueTests {
  @Test func equivalentInputsShareIdentityTokensAndACL() throws {
    let first = ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.15/24"))
    let second = ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24"))
    #expect(first == second)
    #expect(Set([first, second]).count == 1)
    #expect(first.contentToken == "direct|ipv4CIDR(\"203.0.113.0/24\")")
    #expect(first.aclLine == "203.0.113.0/24")
    #expect(first.match.pattern == .ipv4CIDR("203.0.113.0/24"))
    let mapped = ProxyRule(
      action: .direct, match: try RuleMatch(ipv6CIDR: "::ffff:203.0.113.0/120"))
    #expect(first != mapped)
  }

  @Test func historicalTokensAndACLRenderingSurviveRepresentationChange() throws {
    let cases: [(RuleMatch, String, String)] = [
      (
        try RuleMatch(domainExact: " API.Example.COM "), "proxy|domainExact(\"api.example.com\")",
        "|api.example.com"
      ),
      (
        try RuleMatch(domainSuffix: ".Example.COM"), "proxy|domainSuffix(\"example.com\")",
        "||example.com"
      ),
      (
        try RuleMatch(ipv6CIDR: "2001:DB8::8/32"), "proxy|ipv6CIDR(\"2001:db8::/32\")",
        "2001:db8::/32"
      ),
    ]
    for (match, token, acl) in cases {
      let rule = ProxyRule(action: .proxy, match: match)
      #expect(rule.contentToken == token)
      #expect(rule.aclLine == acl)
    }
  }

  @Test func fixedSuffixesRoundTripThroughSnapshotButRemainUnavailableToCustomRules() throws {
    let fixed = [RuleMatch.localSuffix, .localhostSuffix]
    let rules = fixed.map { ProxyRule(action: .direct, match: $0) }
    let snapshot = rulesFixture(.geolocationCN, rules: rules)
    let decoded = try RuleSnapshotStore.decode(RuleSnapshotStore.encode(snapshot))
    #expect(decoded == snapshot)
    for match in fixed {
      let custom = CustomRule(action: .direct, match: match)
      let data = try CustomRuleStore.encode(CustomRuleDocument(rules: [custom]))
      #expect(throws: (any Error).self) { try CustomRuleStore.decode(data) }
    }
    for value in ["local", "localhost", "com"] {
      #expect(throws: RuleMatchError.self) { try RuleMatch(nationalDomainSuffix: value) }
    }
  }
}
