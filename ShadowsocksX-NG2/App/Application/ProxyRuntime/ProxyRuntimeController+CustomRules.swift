import Foundation

// MARK: - 结果呈现文案

// outcome→文案映射供状态行与编辑器两个视图共享。

extension RulesCommitFeedback {
  var summary: String {
    guard outcome.isSuccess else { return outcome.rulesMessage }
    let count: String
    switch operation {
    case .enablement(let enabled):
      count = String.localizedStringWithFormat(
        RulesCopy.text(enabled ? "已启用 %lld 条规则" : "已禁用 %lld 条规则"), Int64(changedCount))
    case .add: count = RulesCopy.text("已新增规则")
    case .edit: count = RulesCopy.text("已编辑规则")
    case .delete:
      count = String.localizedStringWithFormat(
        RulesCopy.text("已删除 %lld 条自定义规则"), Int64(changedCount))
    }
    return count + " · " + RulesCopy.text("已保存")
  }
}

extension CustomRuleUpdateOutcome {
  var rulesMessage: String {
    switch self {
    case .saved: RulesCopy.text("已保存")
    case .persistenceFailed: RulesCopy.text("保存失败，规则未更改")
    case .busy: RulesCopy.text("正在更新规则…")
    case .superseded: RulesCopy.text("规则集合已变化，操作未执行。")
    case .invalidDocument, .rejected: RulesCopy.text("无法更新规则")
    }
  }

  var failureDetail: String? {
    switch self {
    case .invalidDocument(let detail): detail
    case .rejected(let rejected): rejected.map(\.explanation).joined(separator: "\n")
    default: nil
    }
  }

  var nextStep: String? {
    switch self {
    case .persistenceFailed, .busy, .superseded: String(localized: "请重试规则操作。")
    case .invalidDocument, .rejected: String(localized: "请检查规则数据后再操作。")
    default: nil
    }
  }
}

// MARK: - 自定义规则命令面

extension ProxyRuntimeController {
  /// Validate and atomically save intent; runtime application is a separate worker.
  /// Deployment failure never restores an older saved rule document.
  /// 全局和直连模式不加载自定义规则，但持久化仍然进行（切换到规则模式后生效）。
  func commitRuleDocument(_ document: CustomRuleDocument, preset: RulePreset? = nil) async
    -> RuleDocumentCommit
  {
    let preset = preset ?? settings.rulePreset
    let result = documents(for: preset).commit(document)
    if result.outcome.isSuccess && preset == settings.rulePreset { scheduleRuleApplication() }
    return result
  }

  /// One worker owns rule deployments. Saves never cancel an in-flight restart;
  /// another saved revision is coalesced and applied after that restart finishes.
  func scheduleRuleApplication() {
    ruleApplicationGeneration += 1
    guard ruleApplicationTask == nil else { return }
    ruleApplicationTask = Task { [weak self] in
      guard let self else { return }
      defer { self.ruleApplicationTask = nil }
      while !Task.isCancelled {
        let generation = self.ruleApplicationGeneration
        do { try await self.ruleApplicationDelay() } catch { return }
        guard generation == self.ruleApplicationGeneration else { continue }
        await self.convergeRuntime(.savedRules)
        if generation == self.ruleApplicationGeneration { return }
      }
    }
  }

  /// 自定义规则安全摘要：数量 + 内容版本，不含原始域名。
  func readCustomRuleSummary() -> CustomRuleSummary? {
    try? CustomRuleSummary.summarizing(ruleDocuments.load())
  }
}
