import Foundation

// MARK: - 自定义规则更新结果

/// The result of accepting and saving a rule document, independent of runtime.
/// `busy`/`superseded` are transaction-gate rejections: no save was attempted.
enum CustomRuleUpdateOutcome: Equatable, Sendable {
  /// 规则已保存；运行规则模式时应用。
  case saved
  /// 校验拒绝：整批不落地，旧规则保持不变；附可解释原因。
  case rejected([RejectedCustomRule])
  /// 持久化失败：旧规则保持不变。
  case persistenceFailed
  case busy
  /// 事务门拒绝：意图捕获后事实已前进（集合版本/完整性变化），本次更新未尝试保存。
  case superseded
  case invalidDocument(detail: String)

  var isSuccess: Bool {
    switch self {
    case .saved: true
    default: false
    }
  }
}

/// Final persisted facts, independent of whether runtime application succeeded.
struct RuleDocumentCommit: Sendable {
  let outcome: CustomRuleUpdateOutcome
  let document: CustomRuleDocument?
}

/// One saved-document owner per preset. Only successful atomic saves replace
/// loaded facts; runtime recovery never restores an older rule document.
@MainActor
final class RuleDocumentSession {
  private let store: CustomRuleStore
  private(set) var current: CustomRuleDocument?
  private(set) var revision = 0

  init(store: CustomRuleStore) { self.store = store }

  func load() throws -> CustomRuleDocument {
    if let current { return current }
    let loaded = try store.loadDocument()
    current = loaded
    return loaded
  }

  func commit(_ document: CustomRuleDocument) -> RuleDocumentCommit {
    _ = try? load()
    let rejected = CustomRuleValidator.hardValidation(custom: document.rules).rejected
    guard rejected.isEmpty else {
      return RuleDocumentCommit(outcome: .rejected(rejected), document: current)
    }
    if let preset = store.preset,
      document.rules.contains(where: { $0.action != preset.matchedAction })
    {
      return RuleDocumentCommit(
        outcome: .invalidDocument(detail: "Custom rule action must match its rule scheme"),
        document: current)
    }
    guard
      document.disabledIdentities.isDisjoint(
        with: Set(RuleCoverage.fixedLocalMatches.map { ProxyRule(action: .direct, match: $0) }))
    else {
      return RuleDocumentCommit(
        outcome: .invalidDocument(detail: "Fixed local policy cannot be disabled"),
        document: current)
    }
    do {
      _ = try load()
      try save(document)
      return RuleDocumentCommit(outcome: .saved, document: current)
    } catch {
      RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      return RuleDocumentCommit(outcome: .persistenceFailed, document: current)
    }
  }

  private func save(_ document: CustomRuleDocument) throws {
    try store.saveDocument(document)
    if current != document { revision += 1 }
    current = document
  }
}
