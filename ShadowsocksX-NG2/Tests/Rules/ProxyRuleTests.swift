import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 规则领域模型：动作与匹配条件独立于
/// PAC、ACL 文本和系统代理设置。
final class ProxyRuleTests: XCTestCase {
  // MARK: - 动作与匹配

  func testActionsAreProxyAndDirect() {
    XCTAssertEqual(RuleAction.allCases, [.proxy, .direct])
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

    XCTAssertEqual(exact, .domainExact("api.example.com"))
    XCTAssertEqual(suffix, .domainSuffix("example.com"))
    XCTAssertEqual(v4, .ipv4CIDR("203.0.113.0/24"))
    XCTAssertEqual(v6, .ipv6CIDR("2001:db8::/32"))
  }

  func testDomainExactRejectsSuffixSemantics() {
    XCTAssertThrowsError(try RuleMatch(domainExact: "example.com."))
    XCTAssertThrowsError(try RuleMatch(domainExact: ".example.com"))
    XCTAssertThrowsError(try RuleMatch(domainExact: "*.example.com"))
    XCTAssertThrowsError(try RuleMatch(domainExact: ""))
    XCTAssertThrowsError(try RuleMatch(domainExact: "exa mple.com"))
    XCTAssertThrowsError(try RuleMatch(domainExact: "例子.com"))
  }

  func testDomainSuffixNormalizesAndRejectsInvalid() throws {
    XCTAssertEqual(try RuleMatch(domainSuffix: "Example.COM"), .domainSuffix("example.com"))
    XCTAssertEqual(try RuleMatch(domainSuffix: ".example.com"), .domainSuffix("example.com"))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "example.com."))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "*.example.com"))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: ""))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "localhost"))
    XCTAssertThrowsError(try RuleMatch(domainSuffix: "com"), "单标签后缀不允许，避免过宽匹配")
  }

  func testIPv4CIDRNormalizesHostAddressesAndRejectsInvalid() throws {
    XCTAssertEqual(try RuleMatch(ipv4CIDR: "203.0.113.7"), .ipv4CIDR("203.0.113.7/32"))
    XCTAssertEqual(try RuleMatch(ipv4CIDR: "203.0.113.0/24"), .ipv4CIDR("203.0.113.0/24"))
    // 主机位非零的前缀按网络地址规范化。
    XCTAssertEqual(try RuleMatch(ipv4CIDR: "203.0.113.15/24"), .ipv4CIDR("203.0.113.0/24"))
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "203.0.113.0/33"))
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "203.0.113.256/24"))
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "2001:db8::/32"), "IPv6 不得进入 IPv4 匹配")
    XCTAssertThrowsError(try RuleMatch(ipv4CIDR: "not-an-ip"))
  }

  func testIPv6CIDRNormalizesAndRejectsInvalid() throws {
    XCTAssertEqual(try RuleMatch(ipv6CIDR: "2001:db8::/32"), .ipv6CIDR("2001:db8::/32"))
    XCTAssertEqual(
      try RuleMatch(ipv6CIDR: "2001:DB8:0:0:0:0:0:0/32"), .ipv6CIDR("2001:db8::/32"))
    XCTAssertThrowsError(try RuleMatch(ipv6CIDR: "2001:db8::/129"))
    XCTAssertThrowsError(try RuleMatch(ipv6CIDR: "203.0.113.0/24"), "IPv4 不得进入 IPv6 匹配")
    XCTAssertThrowsError(try RuleMatch(ipv6CIDR: "gggg::/32"))
  }

  // MARK: - 来源身份

  func testSourceIdentityCapturesKindAndUpstream() {
    let source = RuleSourceIdentity(
      kind: .geolocationCN,
      upstreamVersion: "20260925234224",
      label: "geolocation-cn")
    XCTAssertEqual(source.kind, .geolocationCN)
    XCTAssertEqual(source.upstreamVersion, "20260925234224")
    XCTAssertEqual(source.id, "geolocation-cn")
  }

  func testSourceKindsCoverBuiltInAndCustom() {
    XCTAssertEqual(
      RuleSourceKind.allCases,
      [.geolocationCN, .chinaIPv4, .gfwlist, .custom])
  }

  // MARK: - 规则序列化

  func testRuleEncodesOnlyActionAndMatch() throws {
    let rule = ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
    let data = try JSONEncoder().encode(rule)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["action", "match"])
    XCTAssertEqual(try JSONDecoder().decode(ProxyRule.self, from: data), rule)
  }
}
