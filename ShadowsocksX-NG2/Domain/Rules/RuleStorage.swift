import Foundation

/// Wire records are independent of domain values. Both file adapters convert
/// through the validated RuleMatch constructors before publishing any rules.
struct StoredProxyRule: Codable {
  let action: String
  let match: StoredRuleMatch

  init(_ rule: ProxyRule) {
    action = rule.action.rawValue
    match = StoredRuleMatch(rule.match)
  }

  func domain() throws -> ProxyRule {
    guard let action = RuleAction(rawValue: action) else {
      throw RuleStorageDecodingError.invalidAction(action)
    }
    return ProxyRule(action: action, match: try match.domain())
  }
}

struct StoredRuleMatch: Codable {
  let kind: String
  let value: String

  init(_ match: RuleMatch) {
    switch match.pattern {
    case .domainExact(let raw): (kind, value) = ("domainExact", raw)
    case .domainSuffix(let raw): (kind, value) = ("domainSuffix", raw)
    case .ipv4CIDR(let raw): (kind, value) = ("ipv4CIDR", raw)
    case .ipv6CIDR(let raw): (kind, value) = ("ipv6CIDR", raw)
    }
  }

  func domain() throws -> RuleMatch {
    switch kind {
    case "domainExact": return try RuleMatch(domainExact: value)
    case "domainSuffix":
      if value == "local" { return .localSuffix }
      if value == "localhost" { return .localhostSuffix }
      return try RuleMatch(nationalDomainSuffix: value)
    case "ipv4CIDR": return try RuleMatch(ipv4CIDR: value)
    case "ipv6CIDR": return try RuleMatch(ipv6CIDR: value)
    default: throw RuleStorageDecodingError.invalidMatchKind(kind)
    }
  }
}

enum RuleStorageDecodingError: Error {
  case invalidAction(String)
  case invalidMatchKind(String)
  case invalidSource(String)
}
