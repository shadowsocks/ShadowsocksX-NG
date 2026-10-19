import Foundation

// MARK: - 自定义规则

/// 自定义条目的持久身份与规范化规则值；编辑身份独立于跨来源规则身份。
struct CustomRule: Equatable, Hashable, Sendable, Identifiable {
  let id: UUID
  let rule: ProxyRule

  init(id: UUID = UUID(), action: RuleAction, match: RuleMatch) {
    self.id = id
    rule = ProxyRule(action: action, match: match)
  }

  var action: RuleAction { rule.action }
  var match: RuleMatch { rule.match }
  var proxyRule: ProxyRule { rule }
  var identity: ProxyRule { rule }

  /// 稳定的内容身份（不含 UUID），用于去重与诊断摘要。
  var contentToken: String {
    identity.contentToken
  }
}

// MARK: - 持久化集合

/// 已保存的自定义条目与跨全部来源的规则停用意图。
struct CustomRuleDocument: Equatable, Sendable {
  let rules: [CustomRule]
  let disabledIdentities: Set<ProxyRule>

  init(rules: [CustomRule], disabledIdentities: Set<ProxyRule> = []) {
    self.rules = rules
    self.disabledIdentities = disabledIdentities
  }
}

// MARK: - 诊断摘要

/// 自定义规则的安全诊断摘要：只含数量与内容版本，
/// 不导出原始自定义域名或来源内容。
struct CustomRuleSummary: Equatable, Sendable {
  /// 规则条数。
  let count: Int
  /// 内容版本：规则内容（动作+匹配）的稳定短摘要。
  let contentVersion: String

  static func summarizing(_ document: CustomRuleDocument) -> CustomRuleSummary {
    let tokens =
      document.rules.map(\.contentToken).sorted()
      + document.disabledIdentities.map { "disabled:" + $0.contentToken }.sorted()
    return CustomRuleSummary(
      count: document.rules.count,
      contentVersion: String(ProxyACLDocument.digest(tokens.joined(separator: "\n")).prefix(12)))
  }

  static func summarizing(_ rules: [CustomRule]) -> CustomRuleSummary {
    CustomRuleSummary(count: rules.count, contentVersion: contentVersion(of: rules))
  }

  /// 内容版本按 (action, match) 排序后摘要；不含 UUID，重排不改版本。
  static func contentVersion(of rules: [CustomRule]) -> String {
    let payload =
      rules
      .map(\.contentToken)
      .sorted()
      .joined(separator: "\n")
    return String(ProxyACLDocument.digest(payload).prefix(12))
  }
}
