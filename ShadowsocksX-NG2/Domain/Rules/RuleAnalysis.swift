import Foundation

/// Coverage is explanatory, never a persistence rejection or a routing priority.
struct RuleRelationship: Equatable, Sendable {
  enum Kind: Hashable, Sendable { case absorption, shadowing }
  enum Extent: Sendable { case full, partial }
  let rule: ProxyRule
  let kind: Kind
  let extent: Extent
  let covering: [ProxyRule]
}

/// Analyze the complete candidate set. Optional subjects limit explanation work
/// to custom entries at the existing validation seam without narrowing context.
struct RuleAnalysis: Equatable, Sendable {
  let identities: [ProxyRule]
  let relationships: [RuleRelationship]

  var contentVersion: String {
    String(
      ProxyACLDocument.digest(identities.map(\.contentToken).joined(separator: "\n")).prefix(12))
  }

  init(rules: [ProxyRule], subjects: [ProxyRule]? = nil) {
    let identities = Set(rules).map { ($0, $0.contentToken) }
      .sorted { $0.1 < $1.1 }.map(\.0)
    self.identities = identities
    let targets = Set(subjects ?? rules)
    relationships = identities.filter { targets.contains($0) }.flatMap { target in
      [RuleRelationship.Kind.absorption, .shadowing].compactMap { kind in
        let covering = identities.filter { other in
          guard other != target else { return false }
          switch kind {
          case .absorption:
            guard other.action == target.action else { return false }
          case .shadowing:
            guard other.action != target.action,
              RuleCoverage.winningAction(for: target.match) == other.action
            else { return false }
          }
          return RuleCoverage.intersects(other.match, target.match)
        }
        guard !covering.isEmpty else { return nil }
        return RuleRelationship(
          rule: target, kind: kind,
          extent: RuleCoverage.fullyCovered(target.match, by: covering.map(\.match))
            ? .full : .partial,
          covering: covering)
      }
    }
  }
}

/// Fixed policy includes a semantic simple-hostname condition, not an editable
/// regex identity. Coverage keeps that condition separate from ordinary rules.
struct FixedRuleCoverage: Equatable, Sendable {
  let extent: RuleRelationship.Extent
  let matches: [RuleMatch]
  let includesSimpleHostname: Bool
}

extension RuleCoverage {
  static let fixedLocalMatches: [RuleMatch] = {
    FixedLocalProxyRanges.ipRanges.compactMap { value in
      value.contains(":") ? try? RuleMatch(ipv6CIDR: value) : try? RuleMatch(ipv4CIDR: value)
    } + [.localhostSuffix, .localSuffix]
  }()

  static func fixedLocalCoverage(of match: RuleMatch) -> FixedRuleCoverage? {
    let matches = fixedLocalMatches.filter { intersects($0, match) }
    let simple: Bool
    let simpleIsFull: Bool
    switch match.pattern {
    case .domainExact(let value):
      simple = !value.contains(".")
      simpleIsFull = simple
    case .domainSuffix(let value):
      simple = !value.contains(".")
      simpleIsFull = false
    case .ipv4CIDR, .ipv6CIDR:
      simple = false
      simpleIsFull = false
    }
    guard simple || !matches.isEmpty else { return nil }
    return FixedRuleCoverage(
      extent: simpleIsFull || fullyCovered(match, by: matches) ? .full : .partial,
      matches: matches, includesSimpleHostname: simple)
  }
}

extension RuleAnalysis {
  /// Select the actual ACL skeleton before calculating coverage.
  static func runtimeCandidates(_ rules: [ProxyRule], defaultAction: RuleDefaultAction)
    -> [ProxyRule]
  {
    let expressed = rules.filter { defaultAction.expresses($0.action) }
    let index = RulesOverlapIndex(rules: expressed)
    return expressed.filter { rule in
      let analysis = RuleAnalysis(rules: index.overlapping(rule.match), subjects: [rule])
      return !analysis.relationships.contains {
        $0.extent == .full
          && ($0.kind == .shadowing
            || $0.covering.contains { other in
              RuleCoverage.fullyCovered(rule.match, by: [other.match])
                && (!RuleCoverage.fullyCovered(other.match, by: [rule.match])
                  || other.contentToken < rule.contentToken)
            })
      }
    }
  }
}
