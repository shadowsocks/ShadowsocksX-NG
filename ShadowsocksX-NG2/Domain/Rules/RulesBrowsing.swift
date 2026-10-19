import Foundation

/// Session browsing state belongs to the workflow, so navigation never discards it.
struct RulesQuery: Equatable, Sendable {
  var search = ""
  var action: RuleAction?
  var source: RulesSource?
  var enabled: Bool?
}

enum RulesSource: String, CaseIterable, Identifiable, Sendable {
  case custom, geolocationCN, chinaIPv4, gfwlist, fixed
  var id: Self { self }

  /// Fixed policy has no snapshot metadata kind.
  var sourceKind: RuleSourceKind? {
    switch self {
    case .custom: .custom
    case .geolocationCN: .geolocationCN
    case .chinaIPv4: .chinaIPv4
    case .gfwlist: .gfwlist
    case .fixed: nil
    }
  }
}

struct RulesSourceSnapshot: Equatable, Identifiable, Sendable {
  let id: RulesSource
  let count: Int
  let metadata: RuleSnapshotMetadata?
  let conversionReport: RuleConversionLossReport?
}

struct RulesRow: Equatable, Identifiable, Sendable {
  enum SelectionID: Hashable, Sendable {
    case rule(ProxyRule)
    case noDotHostname
  }
  let id: SelectionID
  let identity: ProxyRule?
  let content: String
  let sources: Set<RulesSource>
  let customIDs: Set<UUID>
  let relationships: [RuleRelationship]
  let fixedCoverage: FixedRuleCoverage?
  var isEnabled = true
  var hasCurrentSource: Bool { !sources.isEmpty }
  var isFixed: Bool { sources.contains(.fixed) }
  var action: RuleAction { identity?.action ?? .direct }
}

struct RulesPageSnapshot: Equatable, Sendable {
  enum Issue: Equatable, Hashable, Sendable {
    case userDocument(String)
    case builtin(RulesSource, String)
  }
  var version = ""
  var isLoading = false
  var isCommitting = false
  var commitFeedback: RulesCommitFeedback?
  var commitOutcome: CustomRuleUpdateOutcome? { commitFeedback?.outcome }
  var issues: [Issue] = []
  var sources: [RulesSourceSnapshot] = []
  var rows: [RulesRow] = []
  var selection: Set<RulesRow.SelectionID> = []
  var query = RulesQuery()
  var addressTest = RulesAddressTest()
  var isComplete: Bool { !isLoading && !isCommitting && issues.isEmpty && !version.isEmpty }
  var operationStatus: RulesOperationStatus {
    if isCommitting { return .updating }
    if isLoading { return version.isEmpty ? .initialLoading : .refreshing }
    if !issues.isEmpty && commitFeedback?.outcome.isSuccess != false {
      return .collectionIncomplete
    }
    if let commitFeedback { return .feedback(commitFeedback) }
    return issues.isEmpty ? .idle : .collectionIncomplete
  }
}

enum RulesOperationStatus: Equatable, Sendable {
  case idle, initialLoading, refreshing, updating, collectionIncomplete
  case feedback(RulesCommitFeedback)
}

struct RulesCommitFeedback: Equatable, Sendable, Identifiable {
  enum Operation: Equatable, Sendable {
    case enablement(Bool)
    case add, edit, delete
  }
  let id = UUID()
  let outcome: CustomRuleUpdateOutcome
  let operation: Operation
  let changedCount: Int
}
