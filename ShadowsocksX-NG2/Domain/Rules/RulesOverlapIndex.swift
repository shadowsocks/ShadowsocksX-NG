import Foundation

/// Prefix trees restrict explanatory analysis to intersecting rules. Domain
/// labels and IP bits share the same tree mechanics; RuleCoverage remains the
/// authority for intersection, containment, and mapped-address semantics.
struct RulesOverlapIndex {
  private final class Node {
    var rules: [ProxyRule] = []
    var children: [String: Node] = [:]
    func descendants() -> [ProxyRule] { rules + children.values.flatMap { $0.descendants() } }
  }
  private let root = Node()

  init(rules: [ProxyRule]) {
    for rule in rules {
      var node = root
      for component in Self.path(rule.match) {
        if node.children[component] == nil { node.children[component] = Node() }
        node = node.children[component]!
      }
      node.rules.append(rule)
    }
  }

  func overlapping(_ match: RuleMatch) -> [ProxyRule] {
    var node = root
    var candidates = node.rules
    for component in Self.path(match) {
      guard let next = node.children[component] else {
        return candidates.filter { RuleCoverage.intersects($0.match, match) }
      }
      node = next
      candidates += node.rules
    }
    candidates += node.children.values.flatMap { $0.descendants() }
    return candidates.filter { RuleCoverage.intersects($0.match, match) }
  }

  private static func path(_ match: RuleMatch) -> [String] {
    switch match.pattern {
    case .domainExact(let value), .domainSuffix(let value):
      return ["domain"] + value.split(separator: ".").reversed().map(String.init)
    case .ipv4CIDR, .ipv6CIDR:
      guard let cidr = RuleCoverage.parseCIDR(match) else { return [] }
      let bytes =
        cidr.family == .ipv4
        ? Array(repeating: UInt8(0), count: 10) + [255, 255] + cidr.bytes : cidr.bytes
      let prefix = cidr.prefixLength + (cidr.family == .ipv4 ? 96 : 0)
      return ["ip"]
        + (0..<prefix).map { bit in
          bytes[bit / 8] & (UInt8(1) << (7 - bit % 8)) == 0 ? "0" : "1"
        }
    }
  }
}
