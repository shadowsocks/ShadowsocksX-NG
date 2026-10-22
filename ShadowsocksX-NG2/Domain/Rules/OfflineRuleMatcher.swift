import Foundation

/// A full saved collection is the only context: no runtime, default action, or network dependencies.
enum OfflineRuleMatcher {
  enum Outcome: Equatable, Sendable { case proxy, direct, unmatched }
  enum Explanation: Equatable, Sendable {
    case fixedLocal, domainProxy, ipDirect, singleAction, noMatch
  }
  enum Failure: Error, Equatable, Sendable { case invalidTarget, incompleteCollection }

  struct Result: Equatable, Sendable {
    let version: String
    let target: String
    let outcome: Outcome
    let domainWithoutDNS: Bool
    let deciding: [RulesRow]
    let otherMatches: [RulesRow]
    let explanation: Explanation
  }

  static func test(collection: RulesCollection, address: String) throws -> Result {
    guard collection.issues.isEmpty else { throw Failure.incompleteCollection }
    let target = try OfflineRuleTarget(address)
    let matches = collection.rows.filter { row in
      guard row.isEnabled else { return false }
      guard let identity = row.identity else { return target.isSimpleHostname }
      return RuleCoverage.domainCovers(identity.match, target.match)
        || RuleCoverage.ipCovers(identity.match, target.match)
    }
    let fixed = matches.filter(\.isFixed)
    let action: RuleAction?
    let explanation: Explanation
    if !fixed.isEmpty {
      action = .direct
      explanation = .fixedLocal
    } else if Set(matches.map(\.action)).count > 1 {
      action = RuleCoverage.winningAction(for: target.match)
      explanation = target.isDomain ? .domainProxy : .ipDirect
    } else {
      action = matches.first?.action
      explanation = action == nil ? .noMatch : .singleAction
    }
    let deciding = matches.filter {
      fixed.isEmpty ? $0.action == action : $0.isFixed
    }
    let decidingIDs = Set(deciding.map(\.id))
    return Result(
      version: collection.version, target: target.display,
      outcome: action.map { $0 == .proxy ? .proxy : .direct } ?? .unmatched,
      domainWithoutDNS: target.isDomain, deciding: deciding,
      otherMatches: matches.filter { !decidingIDs.contains($0.id) }, explanation: explanation)
  }
}

private struct OfflineRuleTarget {
  let match: RuleMatch
  let display: String
  var isDomain: Bool {
    if case .domainExact = match.pattern { return true }
    return false
  }
  var isSimpleHostname: Bool { isDomain && !display.contains(".") }

  init(_ address: String) throws {
    let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { throw OfflineRuleMatcher.Failure.invalidTarget }
    var host = raw
    if raw.contains("://") {
      guard let url = URL(string: raw, encodingInvalidCharacters: false),
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.scheme != nil, let value = components.host, !value.isEmpty,
        components.percentEncodedHost?.contains("%") == false,
        components.port.map({ (0...65535).contains($0) }) ?? true
      else { throw OfflineRuleMatcher.Failure.invalidTarget }
      host = value
      if host.hasPrefix("["), host.hasSuffix("]") {
        host = String(host.dropFirst().dropLast())
      }
    }
    if let addressMatch = try? RuleMatch(ipv4CIDR: host), !host.contains("/") {
      match = addressMatch
      display = String(addressMatch.browsingContent.split(separator: "/")[0])
      return
    }
    if let addressMatch = try? RuleMatch(ipv6CIDR: host), !host.contains("/") {
      match = addressMatch
      display = String(addressMatch.browsingContent.split(separator: "/")[0])
      return
    }
    host = host.lowercased()
    if host.hasSuffix(".") { host.removeLast() }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard !host.isEmpty, host.utf8.count <= 253,
      !host.allSatisfy({ $0.isNumber || $0 == "." }),
      labels.allSatisfy({ label in
        !label.isEmpty && label.utf8.count <= 63
          && label.first != "-" && label.last != "-"
          && label.utf8.allSatisfy { byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
          }
      })
    else { throw OfflineRuleMatcher.Failure.invalidTarget }
    match = try RuleMatch(domainExact: host)
    display = host
  }
}

struct RulesAddressTest: Equatable, Sendable {
  var target = ""
  var isTesting = false
  var result: OfflineRuleMatcher.Result?
  var failure: OfflineRuleMatcher.Failure?
}
