import Foundation
import XCTest

@testable import ShadowsocksX_NG2

final class ProxyACLTests: XCTestCase {
  func testDirectACLUsesBypassAllAndFixedLocalSafetyRules() {
    let acl = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"))

    XCTAssertTrue(acl.isWellFormed)
    XCTAssertTrue(acl.content.hasPrefix("[bypass_all]\n[bypass_list]\n"))
    XCTAssertFalse(acl.content.contains("[proxy_list]"))
    XCTAssertTrue(acl.content.contains("127.0.0.0/8\n"))
    XCTAssertTrue(acl.content.contains("10.0.0.0/8\n"))
    XCTAssertTrue(acl.content.contains("172.16.0.0/12\n"))
    XCTAssertTrue(acl.content.contains("192.168.0.0/16\n"))
    XCTAssertTrue(acl.content.contains("169.254.0.0/16\n"))
    XCTAssertTrue(acl.content.contains("::1/128\n"))
    XCTAssertTrue(acl.content.contains("fe80::/10\n"))
    XCTAssertTrue(acl.content.contains("fc00::/7\n"))
    XCTAssertTrue(acl.content.contains("||localhost\n"))
    XCTAssertTrue(acl.content.contains("||local\n"))
    XCTAssertTrue(acl.content.contains("^[^.]+$\n"))
    XCTAssertFalse(acl.content.contains("100.64.0.0/10"))
  }

  /// 全局模式：只含固定本地绕过的最小 ACL；不混入中国列表、
  /// GFWList 或自定义规则。公网目标默认代理，本地目标固定直连。
  func testGlobalACLUsesProxyAllAndOnlyFixedLocalSafetyRules() {
    let acl = ProxyACLDocument.global(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"))

    XCTAssertTrue(acl.isWellFormed)
    XCTAssertEqual(acl.summary, "global")
    XCTAssertTrue(acl.content.hasPrefix("[proxy_all]\n[bypass_list]\n"))
    XCTAssertFalse(acl.content.contains("[proxy_list]"))
    XCTAssertFalse(acl.content.contains("[bypass_all]"))
    XCTAssertTrue(acl.content.contains("127.0.0.0/8\n"))
    XCTAssertTrue(acl.content.contains("10.0.0.0/8\n"))
    XCTAssertTrue(acl.content.contains("172.16.0.0/12\n"))
    XCTAssertTrue(acl.content.contains("192.168.0.0/16\n"))
    XCTAssertTrue(acl.content.contains("169.254.0.0/16\n"))
    XCTAssertTrue(acl.content.contains("::1/128\n"))
    XCTAssertTrue(acl.content.contains("fe80::/10\n"))
    XCTAssertTrue(acl.content.contains("fc00::/7\n"))
    XCTAssertTrue(acl.content.contains("||localhost\n"))
    XCTAssertTrue(acl.content.contains("||local\n"))
    XCTAssertTrue(acl.content.contains("^[^.]+$\n"))
    XCTAssertFalse(acl.content.contains("100.64.0.0/10"), "不加入 CGNAT")
    // 仅固定本地绕过：不携带任何来源规则或用户规则痕迹。
    let rules = Array(acl.content.split(separator: "\n").map(String.init).dropFirst(2))
    XCTAssertEqual(
      rules, FixedLocalProxyRanges.aclBypassRules,
      "全局 ACL 的规则区应与固定本地绕过完全一致")
  }

  func testACLRejectsChangedDigestAndNonAbsolutePath() {
    let valid = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/acl-active.ini"))
    let badDigest = ProxyACLDocument(
      path: valid.path,
      summary: valid.summary,
      content: valid.content,
      sha256: String(repeating: "0", count: 64))
    let relativePath = ProxyACLDocument(
      path: "acl-active.ini",
      summary: valid.summary,
      content: valid.content,
      sha256: valid.sha256)

    XCTAssertFalse(badDigest.isWellFormed)
    XCTAssertFalse(relativePath.isWellFormed)
  }

  /// ADR-0011：契约只传身份字段。解码后的文档没有 content，等式与 well-formed
  /// 校验只看 path/summary/sha256；生成侧 content 存在时仍自证摘要。
  func testACLIdentityEqualityIgnoresContentPresence() {
    let generated = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/acl-active.ini"))
    let decodedShape = ProxyACLDocument(
      path: generated.path,
      summary: generated.summary,
      content: "",
      sha256: generated.sha256)

    XCTAssertEqual(generated, decodedShape, "content 不参与身份等式")
    XCTAssertTrue(decodedShape.isWellFormed, "无 content 时按身份形状校验")
    XCTAssertFalse(
      ProxyACLDocument(
        path: generated.path, summary: "", content: "", sha256: generated.sha256
      ).isWellFormed,
      "summary 为空仍拒绝")
    XCTAssertFalse(
      ProxyACLDocument(
        path: generated.path, summary: generated.summary, content: "",
        sha256: "not-a-digest"
      ).isWellFormed,
      "摘要形状无效仍拒绝")
    let mismatchedContent = ProxyACLDocument(
      path: generated.path, summary: generated.summary, content: "[proxy_all]\n",
      sha256: generated.sha256)
    XCTAssertFalse(mismatchedContent.isWellFormed, "携带 content 时仍自证摘要")
  }

  func testACLIdentityChangeBreaksEquality() {
    let base = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/acl-active.ini"))
    let otherPath = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/other/acl-active.ini"))
    let otherSummary = ProxyACLDocument.global(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/acl-active.ini"))

    XCTAssertNotEqual(base, otherPath)
    XCTAssertNotEqual(base, otherSummary)
  }

  // MARK: - 规则模式

  /// 规则＋未匹配时代理：proxy_all + 固定本地绕过 + 中国域名直连候选。
  func testRuleProxyDefaultACLUsesProxyAllAndChinaDirectCandidates() throws {
    let rules = [
      ProxyRule(action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn")),
      ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "qq.com")),
      ProxyRule(
        action: .direct, match: try RuleMatch(domainExact: "api.example.cn")),
    ]
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .proxyWhenUnmatched,
      rules: rules)

    XCTAssertTrue(acl.isWellFormed)
    XCTAssertEqual(acl.summary, "rule-proxy-default")
    XCTAssertTrue(acl.content.hasPrefix("[proxy_all]\n[bypass_list]\n"))
    XCTAssertFalse(acl.content.contains("[bypass_all]"))
    XCTAssertFalse(acl.content.contains("[proxy_list]"))
    // 固定本地绕过仍在。
    XCTAssertTrue(acl.content.contains("127.0.0.0/8\n"))
    XCTAssertTrue(acl.content.contains("||localhost\n"))
    // 中国域名直连候选。
    XCTAssertTrue(acl.content.contains("||cn\n"))
    XCTAssertTrue(acl.content.contains("||qq.com\n"))
    XCTAssertTrue(acl.content.contains("|api.example.cn\n"))
    XCTAssertFalse(acl.content.contains("100.64.0.0/10"), "不加入 CGNAT")
  }

  /// 规则＋未匹配时直连：bypass_all + 固定本地 + GFWList 可生效
  /// 代理规则。两种默认动作不把全部内置来源无条件并集，因此不混入中国直连项。
  func testRuleDirectDefaultACLUsesBypassAllAndGFWListProxyCandidates() throws {
    let rules = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example")),
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "also-blocked.example")),
      ProxyRule(
        action: .direct, match: try RuleMatch(domainSuffix: "unshadowed.example")),
    ]
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .directWhenUnmatched,
      rules: rules)

    XCTAssertTrue(acl.isWellFormed)
    XCTAssertEqual(acl.summary, "rule-direct-default")
    XCTAssertTrue(acl.content.hasPrefix("[bypass_all]\n[bypass_list]\n"))
    XCTAssertEqual(
      acl.content.components(separatedBy: "[proxy_list]\n").last,
      "||also-blocked.example\n||blocked.example\n")
    XCTAssertTrue(acl.content.contains("||unshadowed.example\n"), "未遮蔽例外参与编译进 bypass_list")
    XCTAssertFalse(acl.content.contains("[proxy_all]"))
    // 不无条件并集中国来源。
    XCTAssertFalse(acl.content.contains("||cn\n"))
    // 固定本地绕过仍在。
    XCTAssertTrue(acl.content.contains("127.0.0.0/8\n"))
    XCTAssertTrue(acl.content.contains("||localhost\n"))
    // 未匹配目标走 bypass_all 默认直连。
    XCTAssertTrue(acl.content.hasPrefix("[bypass_all]"))
  }

  /// 规则＋未匹配时直连：IP 字面目标无可用规则命中时直连（无 IP 代理规则时
  /// proxy_list 只有域名项）。
  func testRuleDirectDefaultACLLeavesIPLiteralsUnmatchedDirect() throws {
    let rules = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .directWhenUnmatched,
      rules: rules)

    let proxySection =
      (acl.content.components(separatedBy: "[proxy_list]\n").last ?? "")
      .split(whereSeparator: \.isNewline).map(String.init)
    XCTAssertTrue(
      proxySection.allSatisfy { line in
        line.hasPrefix("||") || line.hasPrefix("|") || line.hasPrefix("^")
      },
      "GFWList 代理候选只含域名规则；IP 字面目标未命中即直连")
  }

  /// 规则＋未匹配时代理：proxy_all 同时含中国域名与 IPv4 CIDR
  /// 直连候选，固定本地绕过仍优先。
  func testRuleProxyDefaultACLIncludesChinaIPv4CIDRCandidates() throws {
    let rules = [
      ProxyRule(
        action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn")),
      ProxyRule(
        action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
      ProxyRule(
        action: .direct, match: try RuleMatch(ipv4CIDR: "198.51.100.0/24")),
    ]
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .proxyWhenUnmatched,
      rules: rules)

    XCTAssertTrue(acl.isWellFormed)
    XCTAssertTrue(acl.content.hasPrefix("[proxy_all]\n[bypass_list]\n"))
    XCTAssertTrue(acl.content.contains("||cn\n"), "中国域名直连候选")
    XCTAssertTrue(acl.content.contains("203.0.113.0/24\n"), "中国 IPv4 CIDR 直连候选")
    XCTAssertTrue(acl.content.contains("198.51.100.0/24\n"), "中国 IPv4 CIDR 直连候选")
    // 固定本地绕过仍排在中国候选之前（优先级）。
    let lines = acl.content.split(separator: "\n").map(String.init)
    let localIndex = lines.firstIndex(of: "127.0.0.0/8") ?? -1
    let cidrIndex = lines.firstIndex(of: "203.0.113.0/24") ?? -1
    XCTAssertTrue(localIndex >= 0 && cidrIndex > localIndex, "固定本地绕过应优先于中国 CIDR")
  }

  /// 冲突元数据不影响 ACL 行；同匹配只输出一行。
  func testRuleACLLineMapping() throws {
    XCTAssertEqual(
      ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com"))
        .aclLine,
      "||example.com")
    XCTAssertEqual(
      ProxyRule(action: .direct, match: try RuleMatch(domainExact: "a.example.com"))
        .aclLine,
      "|a.example.com")
    XCTAssertEqual(
      ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24"))
        .aclLine,
      "203.0.113.0/24")
    XCTAssertEqual(
      ProxyRule(action: .direct, match: try RuleMatch(ipv6CIDR: "2001:db8::/32"))
        .aclLine,
      "2001:db8::/32")
  }
}
