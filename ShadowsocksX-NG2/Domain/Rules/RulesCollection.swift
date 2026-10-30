import Foundation

/// Browsing uses the preset’s effective actions and saved custom entries.
struct RulesCollection: Sendable {
  let preset: RulePreset
  let version: String
  let rows: [RulesRow]
  let sources: [RulesSourceSnapshot]
  let issues: [RulesPageSnapshot.Issue]
  let userDocument: CustomRuleDocument?
  fileprivate let builtinInput: RulesCollectionInput
  fileprivate let builtinVersion: String

  static func load(
    preset: RulePreset,
    custom loadCustom: () throws -> [CustomRule],
    builtin loadBuiltin: (RulesSource) throws -> RuleSnapshot,
    document loadDocument: (() throws -> CustomRuleDocument)? = nil
  ) -> RulesCollection {
    var builtin = RulesCollectionInput(preset: preset)
    for source in preset.sources {
      builtin.readBuiltin(source, using: loadBuiltin)
    }
    var input = builtin
    input.readCustom { try loadDocument?() ?? CustomRuleDocument(rules: loadCustom()) }
    return input.collection(builtinInput: builtin, builtinVersion: builtin.contentVersion)
  }

  /// A single prospective row uses the same analysis as browsing without sorting
  /// or recomputing every saved row on each editor keystroke.
  func previewRow(identity: ProxyRule, document: CustomRuleDocument) -> RulesRow? {
    var input = builtinInput
    input.readCustom { document }
    return input.previewRow(identity: identity)
  }

  func replacingUserDocument(
    _ document: CustomRuleDocument, analyzing: Bool = true
  ) -> RulesCollection {
    var input = builtinInput
    input.readCustom { document }
    return input.collection(
      builtinInput: builtinInput, builtinVersion: builtinVersion,
      cachedRows: analyzing ? nil : Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }))
  }
}

private struct RulesCandidate: Sendable {
  let rule: ProxyRule
  var identity: ProxyRule { rule }
  let source: RulesSource
  let customID: UUID?

  init(rule: ProxyRule, source: RulesSource, customID: UUID?) {
    self.rule = rule
    self.source = source
    self.customID = customID
  }
}

private struct RulesCollectionInput: Sendable {
  var preset: RulePreset
  var userDocument: CustomRuleDocument?
  var disabled: Set<ProxyRule> = []
  var entries: [RulesCandidate] = []
  var sources: [RulesSourceSnapshot] = []
  var issues: [RulesPageSnapshot.Issue] = []
  var metadataTokens: [String] = []

  mutating func readCustom(_ loadCustom: () throws -> CustomRuleDocument) {
    do {
      let loaded = try loadCustom()
      let validation = CustomRuleValidator.hardValidation(custom: loaded.rules)
      guard validation.rejected.isEmpty else {
        throw CustomRuleStoreError.corrupt(detail: "Invalid custom rule collection")
      }
      let custom = loaded.rules.filter { $0.action == preset.matchedAction }
      let document = CustomRuleDocument(
        rules: custom, disabledIdentities: loaded.disabledIdentities)
      disabled = document.disabledIdentities
      userDocument = document
      entries += custom.map { RulesCandidate(rule: $0.proxyRule, source: .custom, customID: $0.id) }
      sources.insert(
        RulesSourceSnapshot(id: .custom, count: custom.count, metadata: nil, conversionReport: nil),
        at: 0)
    } catch {
      issues.insert(.userDocument(String(describing: error)), at: 0)
    }
  }

  mutating func readBuiltin(
    _ source: RulesSource, using loadBuiltin: (RulesSource) throws -> RuleSnapshot
  ) {
    do {
      let snapshot = try loadBuiltin(source)
      guard let expected = source.sourceKind else { throw RuleSnapshotError.missing }
      guard snapshot.metadata.source.kind == expected
      else { throw RuleSnapshotError.corrupt(detail: "Unexpected rule source") }
      let candidates = preset.rules(from: snapshot)
      entries += candidates.map { RulesCandidate(rule: $0, source: source, customID: nil) }
      sources.append(
        RulesSourceSnapshot(
          id: source, count: candidates.count,
          metadata: snapshot.metadata, conversionReport: snapshot.lossReport))
      // Metadata changes invalidate details even when rule content is unchanged.
      metadataTokens += try RuleSnapshotStore.metadataTokens(for: snapshot)
    } catch {
      issues.append(.builtin(source, String(describing: error)))
    }
  }

  private mutating func appendFixedPolicy() {
    let fixedMatches = RuleCoverage.fixedLocalMatches
    entries += fixedMatches.map {
      RulesCandidate(
        rule: ProxyRule(action: .direct, match: $0), source: .fixed,
        customID: nil)
    }
    sources.append(
      RulesSourceSnapshot(
        id: .fixed, count: fixedMatches.count + 1, metadata: nil, conversionReport: nil))
  }

  mutating func previewRow(identity: ProxyRule) -> RulesRow? {
    appendFixedPolicy()
    let memberships = entries.filter { $0.identity == identity }
    guard !memberships.isEmpty else { return nil }
    let overlapping = entries.compactMap { candidate -> ProxyRule? in
      let rule = candidate.rule
      guard !disabled.contains(rule), preset.defaultAction.expresses(rule.action),
        RuleCoverage.intersects(rule.match, identity.match),
        rule.action != .proxy
          || RuleCoverage.fixedLocalCoverage(of: rule.match)?.extent != .full
      else { return nil }
      return rule
    }
    return row(identity: identity, entries: memberships, overlapping: overlapping)
  }

  var contentVersion: String {
    let tokens =
      entries.map { $0.identity.contentToken + "|" + $0.source.rawValue }
      + metadataTokens + issues.map { String(describing: $0) }
    return ProxyACLDocument.digest(tokens.sorted().joined(separator: "\n"))
  }

  private func documentVersion(builtinVersion: String) -> String {
    let tokens =
      (userDocument?.rules ?? []).map { $0.identity.contentToken + "|" + $0.id.uuidString }
      + disabled.map { "disabled:" + $0.contentToken }
    return String(
      ProxyACLDocument.digest(
        preset.rawValue + builtinVersion + "\n" + tokens.sorted().joined(separator: "\n")
      ).prefix(16))
  }

  mutating func collection(
    builtinInput: RulesCollectionInput, builtinVersion: String,
    cachedRows: [RulesRow.SelectionID: RulesRow]? = nil
  ) -> RulesCollection {
    appendFixedPolicy()
    let grouped = Dictionary(grouping: entries, by: { $0.identity })
    // Completely fixed-protected proxy candidates remain browsable but cannot
    // cover or shadow another candidate in the effective collection.
    let index =
      cachedRows == nil
      ? RulesOverlapIndex(
        rules: grouped.values.compactMap { $0.first?.rule }.filter {
          !disabled.contains($0) && preset.defaultAction.expresses($0.action)
            && ($0.action != .proxy
              || RuleCoverage.fixedLocalCoverage(of: $0.match)?.extent != .full)
        }) : nil
    var rows = orderedRows(grouped: grouped, index: index, cachedRows: cachedRows)
    let orphans = disabled.filter { grouped[$0] == nil }.map { ($0, $0.contentToken) }
      .sorted { $0.1 < $1.1 }.map(\.0)
    for identity in orphans {
      rows.append(
        RulesRow(
          id: .rule(identity), identity: identity,
          content: identity.match.browsingContent, sources: [], customIDs: [],
          relationships: [], fixedCoverage: nil, isEnabled: false))
    }
    rows.append(
      RulesRow(
        id: .noDotHostname, identity: nil, content: "^[^.]+$", sources: [.fixed], customIDs: [],
        relationships: [], fixedCoverage: nil))
    return RulesCollection(
      preset: preset, version: documentVersion(builtinVersion: builtinVersion),
      rows: rows, sources: sources, issues: issues, userDocument: userDocument,
      builtinInput: builtinInput, builtinVersion: builtinVersion)
  }
  private func cachedCoverage(
    identity: ProxyRule, old: RulesRow?, entries: [RulesCandidate]
  ) -> FixedRuleCoverage? {
    if let old { return old.fixedCoverage }
    return entries.contains { $0.source == .fixed }
      ? nil : RuleCoverage.fixedLocalCoverage(of: identity.match)
  }

  private func orderedRows(
    grouped: [ProxyRule: [RulesCandidate]], index: RulesOverlapIndex?,
    cachedRows: [RulesRow.SelectionID: RulesRow]?
  ) -> [RulesRow] {
    // Preserve the first source occurrence, rather than Dictionary iteration order.
    var seen: Set<ProxyRule> = []
    var rows: [RulesRow] = []
    for entry in entries {
      let identity = entry.identity
      guard seen.insert(identity).inserted else { continue }
      let memberships = grouped[identity, default: []]
      if let cachedRows {
        let old = cachedRows[.rule(identity)]
        rows.append(
          RulesRow(
            id: .rule(identity), identity: identity, content: identity.match.browsingContent,
            sources: Set(memberships.map(\.source)),
            customIDs: Set(memberships.compactMap(\.customID)),
            relationships: old?.relationships ?? [],
            fixedCoverage: cachedCoverage(identity: identity, old: old, entries: memberships),
            isEnabled: memberships.contains { $0.source == .fixed } || !disabled.contains(identity))
        )
      } else {
        rows.append(
          row(
            identity: identity, entries: memberships,
            overlapping: disabled.contains(identity) ? [] : index!.overlapping(identity.match)))
      }
    }
    return rows
  }

  private func row(
    identity: ProxyRule, entries: [RulesCandidate], overlapping: [ProxyRule]
  ) -> RulesRow {
    let memberships = Set(entries.map { $0.source })
    let representative = entries[0].rule
    var relationships =
      memberships.contains(.fixed)
      ? [] : RuleAnalysis(rules: overlapping, subjects: [representative]).relationships
    let fixedCoverage =
      memberships.contains(.fixed) ? nil : RuleCoverage.fixedLocalCoverage(of: identity.match)
    if identity.action == .direct, let fixedCoverage {
      relationships = relationships.compactMap { relationship in
        guard relationship.kind == .shadowing else { return relationship }
        guard fixedCoverage.extent == .partial else { return nil }
        return RuleRelationship(
          rule: identity, kind: .shadowing, extent: .partial,
          covering: relationship.covering)
      }
    }
    return RulesRow(
      id: .rule(identity), identity: identity, content: identity.match.browsingContent,
      sources: memberships, customIDs: Set(entries.compactMap { $0.customID }),
      relationships: disabled.contains(identity) ? [] : relationships, fixedCoverage: fixedCoverage,
      isEnabled: memberships.contains(.fixed) || !disabled.contains(identity))
  }

}

extension RuleMatch {
  var browsingContent: String {
    switch pattern {
    case .domainExact(let value), .domainSuffix(let value), .ipv4CIDR(let value),
      .ipv6CIDR(let value):
      value
    }
  }
}
