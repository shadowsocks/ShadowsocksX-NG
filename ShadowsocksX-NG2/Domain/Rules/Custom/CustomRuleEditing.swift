import Foundation

/// A sheet-local draft bound to saved facts, never part of the browsing snapshot.
struct CustomRuleDraft: Equatable, Sendable, Identifiable {
  enum Kind: CaseIterable, Sendable { case ipAddress, cidr, domainSuffix, domainExact }
  let id: UUID
  let editingID: UUID?
  let version: String
  var kind: Kind = .domainSuffix
  var content = ""
  var action: RuleAction = .proxy

  func normalizedMatch() throws -> RuleMatch {
    let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .ipAddress, .cidr:
      guard
        kind == .ipAddress
          ? !value.contains("/")
          : value.split(separator: "/", omittingEmptySubsequences: false).count == 2,
        !value.hasPrefix("/"), !value.hasSuffix("/")
      else { throw RuleMatchError.invalidCIDR(value) }
      return try value.contains(":") ? RuleMatch(ipv6CIDR: value) : RuleMatch(ipv4CIDR: value)
    case .domainExact: return try RuleMatch(domainExact: value)
    case .domainSuffix: return try RuleMatch(nationalDomainSuffix: value)
    }
  }
}

struct CustomRulePreview: Equatable, Sendable {
  enum Failure: Equatable, Sendable {
    case incompleteCollection, busy, staleDraft
    case invalidInput(CustomRuleDraft.Kind)
    case duplicate, fixedLocalConflict, fixedPolicyDisablement
  }
  var failure: Failure?
  var rule: CustomRule?
  var row: RulesRow?
  var inheritsDisablement = false
  var document: CustomRuleDocument?
  var displayContent: String? { rule?.identity.match.editingContent }
}

enum CustomRuleSaveResult: Equatable, Sendable {
  case unavailable(CustomRulePreview.Failure)
  case committed(CustomRuleUpdateOutcome)
}

extension RuleMatch {
  var editingKind: CustomRuleDraft.Kind {
    switch pattern {
    case .domainExact: .domainExact
    case .domainSuffix: .domainSuffix
    case .ipv4CIDR(let value): value.hasSuffix("/32") ? .ipAddress : .cidr
    case .ipv6CIDR(let value): value.hasSuffix("/128") ? .ipAddress : .cidr
    }
  }

  var editingContent: String {
    if editingKind == .ipAddress { return String(browsingContent.split(separator: "/")[0]) }
    return browsingContent
  }
}

extension RulesCollection {
  func previewCustomRule(_ draft: CustomRuleDraft) -> CustomRulePreview {
    guard let document = userDocument else {
      return CustomRulePreview(failure: .incompleteCollection)
    }
    let match: RuleMatch
    do { match = try draft.normalizedMatch() } catch {
      return CustomRulePreview(failure: .invalidInput(draft.kind))
    }
    let previous = document.rules.first { $0.id == draft.editingID }
    guard draft.editingID == nil || previous != nil else {
      return CustomRulePreview(failure: .staleDraft)
    }
    let rule = CustomRule(
      id: draft.id, action: draft.action, match: match)
    let others = document.rules.filter { $0.id != draft.editingID }
    guard !others.contains(where: { $0.identity == rule.identity }) else {
      return CustomRulePreview(failure: .duplicate, rule: rule)
    }
    guard CustomRuleValidator.fixedLocalRejection(for: rule) == nil else {
      return CustomRulePreview(failure: .fixedLocalConflict, rule: rule)
    }
    var disabled = document.disabledIdentities
    let inherits = previous.map { disabled.contains($0.identity) } ?? false
    if inherits {
      guard rule.action != .direct || !RuleCoverage.fixedLocalMatches.contains(rule.identity.match)
      else { return CustomRulePreview(failure: .fixedPolicyDisablement, rule: rule) }
      disabled.insert(rule.identity)
    }
    let updated = CustomRuleDocument(rules: others + [rule], disabledIdentities: disabled)
    return CustomRulePreview(
      rule: rule, row: previewRow(identity: rule.identity, document: updated),
      inheritsDisablement: inherits && previous?.identity != rule.identity, document: updated)
  }
}
