import Darwin
import Foundation

// MARK: - CIDR 解析

enum AddressFamily: Equatable, Sendable {
  case ipv4
  case ipv6
}

struct ParsedCIDR: Equatable, Sendable {
  let family: AddressFamily
  let bytes: [UInt8]
  let prefixLength: Int
}

// MARK: - 拒绝原因

/// Blocking custom-rule validation errors. Shadowing is a relationship, not an error.
enum CustomRuleRejection: Equatable, Sendable {
  /// 代理动作覆盖固定本地范围（回环/私有/链路本地/localhost/*.local/无点主机名）。
  /// 应用固定的本地绕过规则始终优先于用户代理规则；冲突规则不会生效。
  case conflictsWithFixedLocalScope
  /// 同动作+同匹配条件重复。
  case duplicate

  var label: String {
    switch self {
    case .conflictsWithFixedLocalScope:
      return "与固定本地范围冲突"
    case .duplicate:
      return "重复规则"
    }
  }
}

/// 被拒绝的自定义规则及其可解释原因。
struct RejectedCustomRule: Equatable, Sendable {
  let rule: CustomRule
  let reason: CustomRuleRejection
  /// 可解释说明：覆盖/遮蔽方的匹配条件描述，不含无关来源内容。
  let explanation: String
}

/// Valid candidates, blocking errors, and nonblocking coverage explanations.
struct CustomRuleValidationResult: Equatable, Sendable {
  let accepted: [ProxyRule]
  let rejected: [RejectedCustomRule]
  var relationships: [RuleRelationship] = []
}

// MARK: - 覆盖判定

/// 匹配条件的覆盖/相交判定：用于固定本地冲突与 ACL 优先级遮蔽检查。
enum RuleCoverage {
  // MARK: 域名

  /// `covering` 的域名目标集合是否包含 `covered` 的域名目标集合。
  static func domainCovers(_ covering: RuleMatch, _ covered: RuleMatch) -> Bool {
    guard let coveringDomain = domainValue(covering), let coveredDomain = domainValue(covered)
    else { return false }
    let coveringIsSuffix = isDomainSuffix(covering)
    let coveredIsSuffix = isDomainSuffix(covered)
    switch (coveringIsSuffix, coveredIsSuffix) {
    case (true, _):
      // 后缀覆盖：目标域等于后缀，或是后缀的子域。
      return coveredDomain == coveringDomain
        || coveredDomain.hasSuffix("." + coveringDomain)
    case (false, true):
      // 精确规则无法覆盖后缀规则（后缀还含子域）。
      return false
    case (false, false):
      return coveredDomain == coveringDomain
    }
  }

  /// 域名目标集合是否相交（用于固定本地冲突）。
  static func domainIntersects(_ lhs: RuleMatch, _ rhs: RuleMatch) -> Bool {
    // 任一覆盖另一即相交；后缀的点分隔边界确保互不覆盖的两个后缀不相交。
    domainCovers(lhs, rhs) || domainCovers(rhs, lhs)
  }

  /// 是否命中固定本地主机模式：`localhost`、`*.local`、无点主机名。
  static func matchesFixedLocalHost(_ match: RuleMatch) -> Bool {
    guard let domain = domainValue(match) else { return false }
    let isSuffix = isDomainSuffix(match)
    // 无点主机名（含 `local` 本身）。
    if !domain.contains(".") {
      return true
    }
    // `*.local` / `local` 后缀。
    if isSuffix {
      return domain == "local" || domain.hasSuffix(".local")
    }
    return domain == "localhost" || domain.hasSuffix(".local") || domain.hasSuffix(".localhost")
  }

  /// 代理动作的域名规则是否与固定本地主机范围冲突。
  static func domainConflictsWithFixedLocal(_ match: RuleMatch) -> Bool {
    // 固定本地 ACL 主机规则：||localhost、||local、^[^.]+$。
    let fixedLocalHostMatches: [RuleMatch] = [
      .localhostSuffix,
      .localSuffix,
    ]
    if matchesFixedLocalHost(match) { return true }
    for fixed in fixedLocalHostMatches where domainIntersects(match, fixed) {
      return true
    }
    return false
  }

  // MARK: IP

  /// `covering` 的 IP 目标集合是否包含 `covered` 的 IP 目标集合（含 mapped 跨家族匹配）。
  static func ipCovers(_ covering: RuleMatch, _ covered: RuleMatch) -> Bool {
    guard let outer = matchingCIDR(covering), let inner = matchingCIDR(covered)
    else { return false }
    return outer.prefixLength <= inner.prefixLength
      && networkContains(outer: outer, inner: inner)
  }

  /// IP 目标集合是否相交。
  static func ipIntersects(_ lhs: RuleMatch, _ rhs: RuleMatch) -> Bool {
    guard let left = matchingCIDR(lhs), let right = matchingCIDR(rhs)
    else { return false }
    return networkContains(outer: left, inner: right) || networkContains(outer: right, inner: left)
  }

  /// 代理动作的 IP 规则是否与固定本地 IP 范围冲突。
  static func ipConflictsWithFixedLocal(_ match: RuleMatch) -> Bool {
    for range in FixedLocalProxyRanges.ipRanges {
      if let fixed = parseFixedLocalCIDR(range), ipIntersects(match, fixed) {
        return true
      }
    }
    return false
  }

  static func winningAction(for match: RuleMatch) -> RuleAction {
    switch match.pattern {
    case .domainExact, .domainSuffix: .proxy
    case .ipv4CIDR, .ipv6CIDR: .direct
    }
  }

  static func intersects(_ lhs: RuleMatch, _ rhs: RuleMatch) -> Bool {
    domainIntersects(lhs, rhs) || ipIntersects(lhs, rhs)
  }

  static func fullyCovered(_ target: RuleMatch, by matches: [RuleMatch]) -> Bool {
    if matches.contains(where: { domainCovers($0, target) }) { return true }
    guard let range = matchingCIDR(target) else { return false }
    return fullyCovered(range, by: matches.compactMap { matchingCIDR($0) })
  }

  /// IPv4 and its mapped IPv6 image match the same addresses in sslocal v1.25.0.
  /// Identity keeps the original family; coverage uses the common IPv6 space.
  private static func matchingCIDR(_ match: RuleMatch) -> ParsedCIDR? {
    guard let range = parseCIDR(match) else { return nil }
    guard range.family == .ipv4 else { return range }
    return ParsedCIDR(
      family: .ipv6, bytes: Array(repeating: 0, count: 10) + [255, 255] + range.bytes,
      prefixLength: 96 + range.prefixLength)
  }

  /// Several disjoint narrower CIDRs can together cover a whole range.
  private static func fullyCovered(_ target: ParsedCIDR, by ranges: [ParsedCIDR]) -> Bool {
    let overlapping = ranges.filter {
      networkContains(outer: $0, inner: target) || networkContains(outer: target, inner: $0)
    }
    if overlapping.contains(where: {
      $0.prefixLength <= target.prefixLength && networkContains(outer: $0, inner: target)
    }) {
      return true
    }
    guard !overlapping.isEmpty, target.prefixLength < 128 else { return false }
    let nextPrefix = target.prefixLength + 1
    var upperBytes = target.bytes
    upperBytes[target.prefixLength / 8] |= UInt8(1) << (7 - target.prefixLength % 8)
    let lower = ParsedCIDR(family: .ipv6, bytes: target.bytes, prefixLength: nextPrefix)
    let upper = ParsedCIDR(family: .ipv6, bytes: upperBytes, prefixLength: nextPrefix)
    return fullyCovered(lower, by: overlapping) && fullyCovered(upper, by: overlapping)
  }

  // MARK: 解析

  static func parseCIDR(_ match: RuleMatch) -> ParsedCIDR? {
    switch match.pattern {
    case .ipv4CIDR(let cidr):
      return parseCIDRString(cidr, family: .ipv4, maxPrefix: 32)
    case .ipv6CIDR(let cidr):
      return parseCIDRString(cidr, family: .ipv6, maxPrefix: 128)
    case .domainExact, .domainSuffix:
      return nil
    }
  }

  private static func parseFixedLocalCIDR(_ raw: String) -> RuleMatch? {
    if raw.contains(":") {
      return try? RuleMatch(ipv6CIDR: raw)
    }
    return try? RuleMatch(ipv4CIDR: raw)
  }

  private static func parseCIDRString(
    _ cidr: String, family: AddressFamily, maxPrefix: Int
  ) -> ParsedCIDR? {
    let parts = cidr.split(separator: "/", maxSplits: 1)
    guard !parts.isEmpty else { return nil }
    let addressPart = String(parts[0])
    let prefixLength: Int
    if parts.count == 2 {
      guard let parsed = Int(parts[1]), (0...maxPrefix).contains(parsed) else { return nil }
      prefixLength = parsed
    } else {
      prefixLength = maxPrefix
    }
    switch family {
    case .ipv4:
      var address = in_addr()
      guard addressPart.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return nil }
      let host = UInt32(bigEndian: address.s_addr)
      let mask: UInt32 = prefixLength == 0 ? 0 : UInt32.max << (32 - prefixLength)
      let network = host & mask
      let bytes = withUnsafeBytes(of: network.bigEndian) { Array($0) }
      return ParsedCIDR(family: .ipv4, bytes: bytes, prefixLength: prefixLength)
    case .ipv6:
      var address = in6_addr()
      guard addressPart.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
      var bytes = withUnsafeBytes(of: address) { Array($0) }
      for index in 0..<16 {
        let bitStart = index * 8
        if prefixLength >= bitStart + 8 { continue }
        if prefixLength <= bitStart {
          bytes[index] = 0
        } else {
          let keep = prefixLength - bitStart
          bytes[index] &= UInt8.max << (8 - keep)
        }
      }
      return ParsedCIDR(family: .ipv6, bytes: bytes, prefixLength: prefixLength)
    }
  }

  private static func networkContains(outer: ParsedCIDR, inner: ParsedCIDR) -> Bool {
    let fullBytes = outer.prefixLength / 8
    let remainderBits = outer.prefixLength % 8
    guard outer.bytes.count == inner.bytes.count else { return false }
    for index in 0..<fullBytes where outer.bytes[index] != inner.bytes[index] {
      return false
    }
    if remainderBits > 0 {
      let mask = UInt8.max << (8 - remainderBits)
      guard (outer.bytes[fullBytes] & mask) == (inner.bytes[fullBytes] & mask) else {
        return false
      }
    }
    return true
  }

  private static func domainValue(_ match: RuleMatch) -> String? {
    switch match.pattern {
    case .domainExact(let domain), .domainSuffix(let domain):
      return domain
    case .ipv4CIDR, .ipv6CIDR:
      return nil
    }
  }

  private static func isDomainSuffix(_ match: RuleMatch) -> Bool {
    if case .domainSuffix = match.pattern { return true }
    return false
  }
}

// MARK: - 校验器

/// Reject only duplicate custom identities and fixed-local conflicts. Analyze
/// coverage against the complete valid set using the runtime's expressed actions.
/// Accepted candidates retain saved intent; relationships never remove entries.
enum CustomRuleValidator {
  static func validate(
    custom: [CustomRule],
    builtIn: [ProxyRule] = [],
    defaultAction: RuleDefaultAction
  ) -> CustomRuleValidationResult {
    let validated = hardValidation(custom: custom)
    let candidates = builtIn + validated.accepted
    let expressed =
      defaultAction == .proxyWhenUnmatched
      ? candidates.filter { $0.action == .direct } : candidates
    let analysis = RuleAnalysis(rules: expressed, subjects: validated.accepted)
    return CustomRuleValidationResult(
      accepted: validated.accepted, rejected: validated.rejected,
      relationships: analysis.relationships)
  }

  /// Persistence and ACL compilation need blocking validation, not browsing explanations.
  static func hardValidation(custom: [CustomRule]) -> CustomRuleValidationResult {
    var accepted: [ProxyRule] = []
    var rejected: [RejectedCustomRule] = []
    let counts = Dictionary(grouping: custom, by: \.contentToken).mapValues(\.count)
    for rule in custom.sorted(by: {
      ($0.contentToken, $0.id.uuidString) < ($1.contentToken, $1.id.uuidString)
    }) {
      if counts[rule.contentToken, default: 0] > 1 {
        rejected.append(
          RejectedCustomRule(
            rule: rule, reason: .duplicate, explanation: "同动作同匹配条件的规则已存在"))
      } else if let rejection = fixedLocalRejection(for: rule) {
        rejected.append(rejection)
      } else {
        accepted.append(rule.proxyRule)
      }
    }
    return CustomRuleValidationResult(accepted: accepted, rejected: rejected)
  }

  /// 单条规则的固定本地冲突检查（保存与编译共用）。
  static func fixedLocalRejection(for rule: CustomRule) -> RejectedCustomRule? {
    guard rule.action == .proxy else { return nil }
    let conflicts: Bool
    switch rule.identity.match.pattern {
    case .domainExact, .domainSuffix:
      conflicts = RuleCoverage.domainConflictsWithFixedLocal(rule.identity.match)
    case .ipv4CIDR, .ipv6CIDR:
      conflicts = RuleCoverage.ipConflictsWithFixedLocal(rule.identity.match)
    }
    guard conflicts else { return nil }
    return RejectedCustomRule(
      rule: rule,
      reason: .conflictsWithFixedLocalScope,
      explanation: "应用固定的本地绕过规则优先；这些本地目标不会经代理")
  }

}

/// Pure runtime projection; browsing uses all sources, this projection uses only
/// the source subset expressed by the current ACL skeleton.
enum RuleRuntimeCompiler {
  struct Input: Sendable {
    let source: SslocalRuntimeDocument
    let mode: ProxyMode
    let defaultAction: RuleDefaultAction
    let document: CustomRuleDocument?
    let builtIn: [ProxyRule]
    let aclURL: URL
  }
  static func validation(
    document: CustomRuleDocument, builtIn: [ProxyRule], defaultAction: RuleDefaultAction
  ) -> CustomRuleValidationResult {
    let custom = document.rules.filter { !document.disabledIdentities.contains($0.identity) }
    let enabled = builtIn.filter { !document.disabledIdentities.contains($0) }
    let validated = CustomRuleValidator.validate(
      custom: custom, builtIn: enabled, defaultAction: defaultAction)
    return CustomRuleValidationResult(
      accepted: RuleAnalysis.runtimeCandidates(
        enabled + validated.accepted, defaultAction: defaultAction),
      rejected: validated.rejected, relationships: validated.relationships)
  }

  static func compile(_ input: Input) -> SslocalRuntimeDocument {
    let source = input.source
    let mode = input.mode
    let defaultAction = input.defaultAction
    let document = input.document
    let builtIn = input.builtIn
    let aclURL = input.aclURL
    switch mode {
    case .direct: return source.replacingACL(.direct(at: aclURL))
    case .global: return source.replacingACL(.global(at: aclURL))
    case .rule:
      let document = document ?? CustomRuleDocument(rules: [])
      let custom = document.rules.filter { !document.disabledIdentities.contains($0.identity) }
      let enabled = builtIn.filter { !document.disabledIdentities.contains($0) }
      let validated = CustomRuleValidator.hardValidation(custom: custom)
      let candidates = RuleAnalysis.runtimeCandidates(
        enabled + validated.accepted, defaultAction: defaultAction)
      return source.replacingACL(
        .rule(at: aclURL, defaultAction: defaultAction, rules: candidates))
    }
  }
}
