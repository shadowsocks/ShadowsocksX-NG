import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 自定义规则合并进 ACL：两种规则子模式按各自内置来源与
/// 自定义规则合并；全局和直连模式不加载自定义规则。
final class CustomRuleMergeTests: XCTestCase {

  private func custom(_ action: RuleAction, _ match: RuleMatch) -> CustomRule {
    CustomRule(action: action, match: match)
  }

  func testACLIdentityDoesNotDependOnRuleOrderOrDuplicates() {
    let first = ProxyRule(action: .direct, match: .domainSuffix("z.example"))
    let equivalent = ProxyRule(
      action: .direct, match: .domainSuffix("z.example"))
    let second = ProxyRule(action: .proxy, match: .domainExact("a.example"))
    let url = URL(fileURLWithPath: "/tmp/rules-order.acl")
    for action in RuleDefaultAction.allCases {
      let expected = ProxyACLDocument.rule(at: url, defaultAction: action, rules: [first, second])
      let reordered = ProxyACLDocument.rule(
        at: url, defaultAction: action, rules: [second, equivalent, first])
      XCTAssertEqual(expected.content, reordered.content)
      XCTAssertEqual(expected.sha256, reordered.sha256)
    }
  }

  /// 「未匹配时代理」：中国直连候选 + 自定义直连进 bypass_list；自定义代理
  /// 不写 proxy_list（默认已代理）。
  func testProxyWhenUnmatchedMergesChinaDirectAndCustomDirect() throws {
    let builtIn = [
      ProxyRule(
        action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn")),
      ProxyRule(
        action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
    ]
    let customRules = [
      custom(.direct, try RuleMatch(domainSuffix: "internal.example")),
      custom(.proxy, try RuleMatch(domainSuffix: "always-proxy.example")),
    ]

    let result = CustomRuleValidator.validate(
      custom: customRules, builtIn: builtIn, defaultAction: .proxyWhenUnmatched)
    let merged = builtIn + result.accepted

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(merged.count, 4)
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .proxyWhenUnmatched,
      rules: merged)
    XCTAssertTrue(acl.content.contains("||cn\n"))
    XCTAssertTrue(acl.content.contains("203.0.113.0/24\n"))
    XCTAssertTrue(acl.content.contains("||internal.example\n"))
    XCTAssertFalse(
      acl.content.contains("||always-proxy.example\n"),
      "未匹配时代理骨架不写 proxy_list；代理动作默认已覆盖")
    XCTAssertTrue(acl.content.hasPrefix("[proxy_all]"))
  }

  /// 「未匹配时直连」：GFWList 代理候选 + 自定义代理进 proxy_list；自定义
  /// 未遮蔽直连进 bypass_list。
  func testDirectWhenUnmatchedMergesGFWListAndCustomRules() throws {
    let builtIn = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let customRules = [
      custom(.proxy, try RuleMatch(domainSuffix: "also-blocked.example")),
      custom(.direct, try RuleMatch(domainSuffix: "unshadowed.example")),
    ]

    let result = CustomRuleValidator.validate(
      custom: customRules, builtIn: builtIn, defaultAction: .directWhenUnmatched)
    let merged = builtIn + result.accepted

    XCTAssertTrue(result.rejected.isEmpty)
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .directWhenUnmatched,
      rules: merged)
    XCTAssertTrue(acl.content.contains("[proxy_list]\n"))
    XCTAssertTrue(acl.content.contains("||blocked.example\n"))
    XCTAssertTrue(acl.content.contains("||also-blocked.example\n"))
    XCTAssertTrue(acl.content.contains("||unshadowed.example\n"))
    XCTAssertTrue(acl.content.hasPrefix("[bypass_all]"))
  }

  /// 被遮蔽条目保留；ACL 优先级决定其实际作用。
  func testShadowedCustomDirectIsRetainedAndExplained() throws {
    let builtIn = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let customRules = [
      custom(.direct, try RuleMatch(domainExact: "sub.blocked.example"))
    ]

    let result = CustomRuleValidator.validate(
      custom: customRules, builtIn: builtIn, defaultAction: .directWhenUnmatched)
    let merged = builtIn + result.accepted

    XCTAssertTrue(result.rejected.isEmpty)
    XCTAssertEqual(result.relationships.first?.extent, .full)
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"),
      defaultAction: .directWhenUnmatched,
      rules: merged)
    XCTAssertTrue(acl.content.contains("sub.blocked.example"), "保留可表达意图，路由由 sslocal 优先级决定")
  }

  /// 单模式遮蔽：在「未匹配时代理」下有效（不被遮蔽），在「未匹配时直连」下
  /// 被 GFWList 代理遮蔽并返回原因。保存允许（另一模式可生效），编译按当前
  /// 模式解释。
  func testOneModeShadowedRuleIsValidInTheOtherMode() throws {
    let gfwBuiltIn = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let chinaBuiltIn = [
      ProxyRule(
        action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))
    ]
    let customRules = [
      custom(.direct, try RuleMatch(domainExact: "sub.blocked.example"))
    ]

    let proxyDefault = CustomRuleValidator.validate(
      custom: customRules, builtIn: chinaBuiltIn, defaultAction: .proxyWhenUnmatched)
    XCTAssertTrue(
      proxyDefault.rejected.isEmpty,
      "未匹配时代理骨架无域名代理表，自定义直连不被遮蔽")

    let directDefault = CustomRuleValidator.validate(
      custom: customRules, builtIn: gfwBuiltIn, defaultAction: .directWhenUnmatched)
    XCTAssertTrue(directDefault.rejected.isEmpty)
    XCTAssertEqual(directDefault.relationships.first?.kind, .shadowing)
    XCTAssertEqual(directDefault.accepted.count, 1)
  }

  /// 全局模式 ACL 不加载自定义规则。
  func testGlobalACLDoesNotLoadCustomRules() throws {
    let customRules = [
      custom(.direct, try RuleMatch(domainSuffix: "internal.example")),
      custom(.proxy, try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
    ]
    // 全局模式的 runtimeDocument 路径不加载自定义规则集合；此处
    // 验证全局 ACL 文档本身不含自定义痕迹。
    let acl = ProxyACLDocument.global(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"))
    XCTAssertFalse(acl.content.contains("internal.example"))
    XCTAssertFalse(acl.content.contains("203.0.113.0/24"))
    XCTAssertEqual(
      Array(acl.content.split(separator: "\n").map(String.init).dropFirst(2)),
      FixedLocalProxyRanges.aclBypassRules)
    // 自定义规则集合本身不参与全局编译（调用方不传入）。
    XCTAssertTrue(customRules.allSatisfy { $0.source.kind == .custom })
  }

  /// 直连模式 ACL 不加载自定义规则。
  func testDirectACLDoesNotLoadCustomRules() {
    let acl = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-test/sslocal-active.acl"))
    XCTAssertFalse(acl.content.contains("[proxy_list]"))
    XCTAssertEqual(
      Array(acl.content.split(separator: "\n").map(String.init).dropFirst(2)),
      FixedLocalProxyRanges.aclBypassRules)
  }
}
