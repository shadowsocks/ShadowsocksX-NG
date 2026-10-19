import XCTest

@testable import ShadowsocksX_NG2

final class OfflineRuleMatcherTests: XCTestCase {
  func testURLAndLiteralIPNormalizationSelectOnlyTheHostBranch() throws {
    let rules = [
      CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com")),
      CustomRule(action: .proxy, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
      CustomRule(action: .direct, match: try RuleMatch(ipv6CIDR: "2001:db8::/32")),
    ]
    let collection = RulesCollection.load(custom: { rules }, builtin: { rulesFixture($0) })
    for input in [" A.Example.COM. \n", "https://A.Example.COM.:8443/path?q=203.0.113.8#fragment"] {
      let result = try OfflineRuleMatcher.test(collection: collection, address: input)
      XCTAssertEqual(result.target, "a.example.com")
      XCTAssertEqual(result.outcome, .proxy)
      XCTAssertTrue(result.domainWithoutDNS)
    }
    for input in ["203.0.113.8", "https://203.0.113.8:443/path"] {
      let result = try OfflineRuleMatcher.test(collection: collection, address: input)
      XCTAssertEqual(result.target, "203.0.113.8")
      XCTAssertEqual(result.outcome, .proxy)
      XCTAssertFalse(result.domainWithoutDNS)
    }
    let ipv6 = try OfflineRuleMatcher.test(
      collection: collection, address: "https://[2001:DB8::8]:8443/path")
    XCTAssertEqual(ipv6.target, "2001:db8::8")
    XCTAssertEqual(ipv6.outcome, .direct)
    XCTAssertFalse(ipv6.domainWithoutDNS)
  }
  func testDomainOverlapAndSuffixBoundariesKeepAllCommonEvidence() throws {
    let suffix = CustomRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
    let exact = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "a.example.com"))
    let secondProxy = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
    let rules = [suffix, exact, secondProxy]
    for entries in [rules, Array(rules.reversed())] {
      let collection = RulesCollection.load(custom: { entries }, builtin: { rulesFixture($0) })
      let result = try OfflineRuleMatcher.test(collection: collection, address: "a.example.com")
      XCTAssertEqual(result.outcome, .proxy)
      XCTAssertEqual(result.explanation, .domainProxy)
      XCTAssertEqual(
        Set(result.deciding.compactMap(\.identity)), [exact.identity, secondProxy.identity])
      XCTAssertEqual(result.otherMatches.map(\.identity), [suffix.identity])
      XCTAssertEqual(
        try OfflineRuleMatcher.test(collection: collection, address: "notexample.com").outcome,
        .unmatched)
    }
    let collection = RulesCollection.load(
      custom: { [suffix, exact] }, builtin: { rulesFixture($0) })
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "example.com").outcome, .direct)
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "b.example.com").outcome, .direct
    )
    let exactOnly = RulesCollection.load(custom: { [exact] }, builtin: { rulesFixture($0) })
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: exactOnly, address: "sub.a.example.com").outcome,
      .unmatched)
  }

  func testIPOverlapAndMappedAddressesPreferDirectWithoutLosingOtherRanges() throws {
    for reverseActions in [false, true] {
      let broad = CustomRule(
        action: reverseActions ? .direct : .proxy,
        match: try RuleMatch(ipv4CIDR: "203.0.113.0/24"))
      let narrow = CustomRule(
        action: reverseActions ? .proxy : .direct,
        match: try RuleMatch(ipv6CIDR: "::ffff:203.0.113.8/128"))
      let collection = RulesCollection.load(
        custom: { [broad, narrow] }, builtin: { rulesFixture($0) })
      for address in ["203.0.113.8", "::ffff:203.0.113.8"] {
        let result = try OfflineRuleMatcher.test(collection: collection, address: address)
        XCTAssertEqual(result.outcome, .direct)
        XCTAssertEqual(result.explanation, .ipDirect)
        XCTAssertEqual(
          result.deciding.map(\.identity), [reverseActions ? broad.identity : narrow.identity])
        XCTAssertEqual(
          result.otherMatches.map(\.identity), [reverseActions ? narrow.identity : broad.identity])
      }
      XCTAssertEqual(
        try OfflineRuleMatcher.test(collection: collection, address: "203.0.113.9").outcome,
        reverseActions ? .direct : .proxy)
      XCTAssertEqual(
        try OfflineRuleMatcher.test(collection: collection, address: "198.51.100.8").outcome,
        .unmatched)
      XCTAssertEqual(
        try OfflineRuleMatcher.test(collection: collection, address: "unresolved.example").outcome,
        .unmatched)
    }
  }

  func testFixedPolicyWinsAndSourceMembershipsRemainComplete() throws {
    let proxy = ProxyRule(action: .proxy, match: .localSuffix)
    let collection = RulesCollection.load(
      custom: { [] },
      builtin: {
        rulesFixture($0, rules: $0 == .gfwlist ? [proxy] : [])
      })
    for address in [
      "printer", "localhost", "a.localhost", "host.local", "127.0.0.1", "192.168.1.2",
      "::1", "::ffff:192.168.1.2", "fe80::1",
    ] {
      let result = try OfflineRuleMatcher.test(collection: collection, address: address)
      XCTAssertEqual(result.outcome, .direct, address)
      XCTAssertEqual(result.explanation, .fixedLocal, address)
      XCTAssertTrue(result.deciding.allSatisfy(\.isFixed))
    }
    let local = try OfflineRuleMatcher.test(collection: collection, address: "host.local")
    XCTAssertEqual(local.otherMatches.map(\.identity), [proxy])
    let match = try RuleMatch(domainExact: "example.com")
    let custom = CustomRule(action: .proxy, match: match)
    let duplicate = ProxyRule(action: .proxy, match: match)
    let merged = RulesCollection.load(
      custom: { [custom] },
      builtin: {
        rulesFixture($0, rules: $0 == .gfwlist ? [duplicate] : [])
      })
    let result = try OfflineRuleMatcher.test(collection: merged, address: "example.com")
    XCTAssertEqual(result.deciding.count, 1)
    XCTAssertEqual(result.deciding[0].sources, [.custom, .gfwlist])
    XCTAssertEqual(result.deciding[0].customIDs, [custom.id])
  }

  func testInvalidInputsAreOperationErrorsRatherThanUnmatched() throws {
    let collection = RulesCollection.load(custom: { [] }, builtin: { rulesFixture($0) })
    for input in [
      "", " ", "example..com", "example.com..", "-example.com", "example-.com",
      "https:///path", "https://", "file:///tmp/test", "203.0.113.999", "203.0.113.8/32",
      "2001:db8::xyz", "example.com:443", "a example.com", "*.example.com",
      "https://example.com:99999",
      "https://ex%61mple.com", "例子.com", "https://例子.com",
    ] {
      XCTAssertThrowsError(
        try OfflineRuleMatcher.test(collection: collection, address: input), input
      ) {
        XCTAssertEqual($0 as? OfflineRuleMatcher.Failure, .invalidTarget, input)
      }
    }
    let valid = try OfflineRuleMatcher.test(
      collection: collection, address: "XN--BCHER-KVA.example.")
    XCTAssertEqual(valid.target, "xn--bcher-kva.example")
    XCTAssertEqual(valid.outcome, .unmatched)
  }

}
