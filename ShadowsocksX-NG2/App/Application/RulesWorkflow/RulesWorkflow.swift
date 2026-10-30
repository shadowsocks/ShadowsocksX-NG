import Combine
import Foundation

/// File reads and collection preparation run outside the UI actor; queries use
/// the prepared collection and do not rebuild semantic analysis on each keypress.
/// Operations that await capture a `RulesIntentTicket` at entry and recheck it
/// once after every await.
@MainActor
final class RulesWorkflow: ObservableObject {
  let preset: RulePreset
  @Published private(set) var snapshot = RulesPageSnapshot()
  @Published private(set) var reportSource: RulesSourceSnapshot?
  private let loadCustom: @Sendable () throws -> [CustomRule]
  private let builtinSnapshots: BuiltinRuleSnapshots
  private let loadDocument: (@MainActor () throws -> CustomRuleDocument)?
  private let commitDocument: (@MainActor (CustomRuleDocument) async -> RuleDocumentCommit)?
  private var collection: RulesCollection?
  private var refreshGeneration = 0
  private let feedbackDelay: @Sendable () async throws -> Void
  private var feedbackTask: Task<Void, Never>?
  private(set) var analysisTask: Task<Void, Never>?
  private var analysisGeneration = 0
  private let analysisDelay: @Sendable () async throws -> Void

  init(
    preset: RulePreset = .gfwlist,
    loadCustom: (@Sendable () throws -> [CustomRule])? = nil,
    loadDocument: (@MainActor () throws -> CustomRuleDocument)? = nil,
    commitDocument: (@MainActor (CustomRuleDocument) async -> RuleDocumentCommit)? = nil,
    feedbackDelay: @escaping @Sendable () async throws -> Void = {
      try await Task.sleep(for: .seconds(3))
    },
    analysisDelay: @escaping @Sendable () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(150))
    },
    builtinSnapshots: BuiltinRuleSnapshots = BuiltinRuleSnapshots()
  ) {
    self.preset = preset
    if let loadDocument {
      self.loadDocument = loadDocument
    } else if loadCustom == nil {
      self.loadDocument = { try CustomRuleStore(preset: preset).loadDocument() }
    } else {
      self.loadDocument = nil
    }
    self.commitDocument = commitDocument
    self.feedbackDelay = feedbackDelay
    self.analysisDelay = analysisDelay
    self.loadCustom = loadCustom ?? { try CustomRuleStore(preset: preset).load() }
    self.builtinSnapshots = builtinSnapshots
    snapshot.query.source = .custom
  }

  func refresh(retryFailedSources: Bool = false) async {
    guard !snapshot.isCommitting else { return }
    if snapshot.commitOutcome?.isSuccess == true && !snapshot.issues.isEmpty {
      dismissFeedback()
    }
    await refreshCollection(retryFailedSources: retryFailedSources)
  }

  private func refreshCollection(retryFailedSources: Bool) async {
    analysisGeneration += 1
    refreshGeneration += 1
    let generation = refreshGeneration
    invalidateAddressTest()
    snapshot.isLoading = true
    let custom = loadCustom
    let preset = preset
    let sources = await builtinSnapshots.browsingSources(
      sources: preset.sources, retryFailures: retryFailedSources)
    let document: Result<CustomRuleDocument, Error>?
    if let loadDocument {
      do { document = .success(try loadDocument()) } catch { document = .failure(error) }
    } else {
      document = nil
    }
    let result = await Task.detached(priority: .userInitiated) {
      RulesCollection.load(
        preset: preset, custom: custom,
        builtin: { source in try sources[source, default: .failure(RuleSnapshotError.missing)].get()
        },
        document: document.map { saved in { try saved.get() } })
    }.value
    guard generation == refreshGeneration else { return }
    if !result.issues.isEmpty, collection != nil {
      snapshot.issues = result.issues
      snapshot.isLoading = false
      return
    }
    collection = result
    var next = snapshot
    next.version = result.version
    next.sources = result.sources
    next.issues = result.issues
    next.isLoading = false
    snapshot = applyingQuery(to: next)
  }

  var actionableSelection: Set<ProxyRule> {
    Set(
      snapshot.rows.filter { snapshot.selection.contains($0.id) && !$0.isFixed }
        .compactMap(\.identity))
  }

  func setEnabled(_ enabled: Bool, identities: Set<ProxyRule>) async {
    guard let ticket = intentTicket(), let old = ticket.document else { return }
    let allowed = Set(snapshot.rows.filter { !$0.isFixed }.compactMap(\.identity))
    let targets = identities.intersection(allowed)
    guard !targets.isEmpty else { return }
    var disabled = old.disabledIdentities
    let changedCount =
      enabled
      ? targets.intersection(disabled).count : targets.subtracting(disabled).count
    if enabled { disabled.subtract(targets) } else { disabled.formUnion(targets) }
    guard disabled != old.disabledIdentities else { return }
    _ = await commit(
      CustomRuleDocument(rules: old.rules, disabledIdentities: disabled),
      operation: .enablement(enabled), changedCount: changedCount)
  }

  private func commit(
    _ document: CustomRuleDocument, operation: RulesCommitFeedback.Operation, changedCount: Int = 1
  ) async -> CustomRuleUpdateOutcome {
    guard let commitDocument else { return .busy }
    snapshot.isCommitting = true
    dismissFeedback()
    invalidateAddressTest()
    let result = await commitDocument(document)
    var next = snapshot
    if let document = result.document, let previous = collection,
      document != previous.userDocument
    {
      let updated = previous.replacingUserDocument(document, analyzing: false)
      collection = updated
      next = snapshot
      next.version = updated.version
      next.sources = updated.sources
      next.issues = updated.issues
      next = applyingQuery(to: next)
      scheduleAnalysis()
    } else if result.document == nil {
      next.issues = [.userDocument("Saved rule document is unavailable")]
    }
    next.isCommitting = false
    publishFeedback(result.outcome, operation: operation, changedCount: changedCount, page: next)
    return result.outcome
  }

  /// Saved facts stay interactive while explanatory relationships catch up.
  /// One worker coalesces saves and never publishes analysis for an older version.
  private func scheduleAnalysis() {
    analysisGeneration += 1
    guard analysisTask == nil else { return }
    analysisTask = Task { [weak self] in
      guard let self else { return }
      defer { self.analysisTask = nil }
      while !Task.isCancelled {
        let generation = self.analysisGeneration
        do { try await self.analysisDelay() } catch { return }
        guard generation == self.analysisGeneration else { continue }
        guard !self.snapshot.isLoading, let captured = self.collection,
          let document = captured.userDocument
        else { return }
        let updated = await Task.detached(priority: .userInitiated) {
          captured.replacingUserDocument(document)
        }.value
        guard generation == self.analysisGeneration else { continue }
        guard self.collection?.version == captured.version else { return }
        self.collection = updated
        self.snapshot = self.applyingQuery(to: self.snapshot)
        return
      }
    }
  }

  func dismissFeedback() {
    feedbackTask?.cancel()
    feedbackTask = nil
    snapshot.commitFeedback = nil
  }

  private func publishFeedback(
    _ outcome: CustomRuleUpdateOutcome, operation: RulesCommitFeedback.Operation, changedCount: Int,
    page: RulesPageSnapshot
  ) {
    let feedback = RulesCommitFeedback(
      outcome: outcome, operation: operation, changedCount: changedCount)
    var next = page
    next.commitFeedback = feedback
    snapshot = next
    guard outcome.isSuccess, snapshot.issues.isEmpty else { return }
    let delay = feedbackDelay
    feedbackTask = Task { [weak self] in
      do { try await delay() } catch { return }
      guard !Task.isCancelled, self?.snapshot.commitFeedback?.id == feedback.id else { return }
      self?.dismissFeedback()
    }
  }

  func setTestTarget(_ target: String) {
    guard target != snapshot.addressTest.target else { return }
    invalidateAddressTest()
    snapshot.addressTest.target = target
  }

  func testAddress() async {
    invalidateAddressTest()
    guard snapshot.isComplete, let collection else {
      snapshot.addressTest.failure = .incompleteCollection
      return
    }
    let ticket = RulesIntentTicket(collection: collection)
    snapshot.addressTest.isTesting = true
    // 捕获整份测试状态：任何失效（目标编辑回原值、新测试进入、刷新/提交
    // 重置）都会改动它，迟到的结果不得发布。
    let intent = snapshot.addressTest
    let result = await Task.detached(priority: .userInitiated) {
      do {
        return Result<OfflineRuleMatcher.Result, OfflineRuleMatcher.Failure>.success(
          try OfflineRuleMatcher.test(collection: collection, address: intent.target))
      } catch {
        return .failure(error as? OfflineRuleMatcher.Failure ?? .invalidTarget)
      }
    }.value
    guard snapshot.addressTest == intent, intentTicketIsCurrent(ticket) else { return }
    snapshot.addressTest.isTesting = false
    switch result {
    case .success(let result): snapshot.addressTest.result = result
    case .failure(let failure): snapshot.addressTest.failure = failure
    }
  }

  private func invalidateAddressTest() {
    snapshot.addressTest = RulesAddressTest(target: snapshot.addressTest.target)
  }

  func query(_ query: RulesQuery) {
    guard query != snapshot.query else { return }
    var next = snapshot
    next.query = query
    snapshot = applyingQuery(to: next)
  }

  func select(_ ids: Set<RulesRow.SelectionID>) {
    let selection = ids.intersection(Set(snapshot.rows.map(\.id)))
    guard selection != snapshot.selection else { return }
    snapshot.selection = selection
  }

  /// Capture only on an explicit open request, independently of browsing and refresh.
  @discardableResult
  func openSourceReport(_ source: RulesSource) -> Bool {
    guard let loaded = snapshot.sources.first(where: { $0.id == source }),
      loaded.metadata != nil, loaded.conversionReport != nil
    else { return false }
    reportSource = loaded
    return true
  }

  private func applyingQuery(to page: RulesPageSnapshot) -> RulesPageSnapshot {
    guard let collection else { return page }
    let query = page.query
    let search = query.search.lowercased()
    let rows = collection.rows.filter { row in
      (query.action == nil || row.action == query.action)
        && (query.source.map {
          row.sources.contains($0)
            || ($0 == .custom && !row.hasCurrentSource && query.enabled == false)
        } ?? true)
        && (query.enabled.map { row.isEnabled == $0 } ?? true)
        && (row.hasCurrentSource || query.enabled == false)
        && (search.isEmpty || row.content.lowercased().contains(search))
    }
    var next = page
    next.rows = rows
    next.selection.formIntersection(Set(rows.map(\.id)))
    return next
  }
}

/// 规则意图票据：一次规则操作意图在入口捕获的事实快照。改写意图（草稿/
/// 预览/保存/启停/删除）经 `intentTicket()` 入口捕获——页完整、无进行中
/// 事务、提交缝在场且用户文档已加载；只读意图（地址测试）直接以已加载
/// 集合构造。每个 await 之后用 `intentTicketIsCurrent` 一查：页不再完整
/// （刷新落地带来 issues、事务或加载开始）或集合版本前进（刷新/提交落地），
/// 本次意图超期——按调用方口径退出，不得发布结果或提交文档。
struct RulesIntentTicket {
  /// 捕获时刻的集合；版本与页版本在写入点同步前进（分析置换除外）。
  let collection: RulesCollection
  var version: String { collection.version }
  /// 捕获时刻的用户文档（改写入口保证非空；浏览态集合可为空）。
  var document: CustomRuleDocument? { collection.userDocument }
}

extension RulesWorkflow {
  /// 改写意图的入口捕获；nil = 此刻不容许改写（页不完整 / 事务进行中 /
  /// 提交缝缺失 / 用户文档未加载）。
  func intentTicket() -> RulesIntentTicket? {
    guard commitDocument != nil, snapshot.isComplete, !snapshot.isCommitting,
      let collection, collection.userDocument != nil
    else { return nil }
    return RulesIntentTicket(collection: collection)
  }

  /// 任何意图 await 后的一查：页仍完整且集合版本未前进。
  func intentTicketIsCurrent(_ ticket: RulesIntentTicket) -> Bool {
    snapshot.isComplete && ticket.version == snapshot.version
  }
}

extension RulesWorkflow {
  func makeCustomRuleDraft(editing id: UUID? = nil) -> CustomRuleDraft? {
    guard let ticket = intentTicket(), let document = ticket.document else { return nil }
    if let id {
      guard let rule = document.rules.first(where: { $0.id == id }) else { return nil }
      return CustomRuleDraft(
        id: id, editingID: id, version: ticket.version,
        kind: rule.identity.match.editingKind, content: rule.identity.match.editingContent,
        action: preset.matchedAction)
    }
    return CustomRuleDraft(
      id: UUID(), editingID: nil, version: ticket.version, action: preset.matchedAction)
  }

  func previewCustomRule(_ draft: CustomRuleDraft) async -> CustomRulePreview {
    guard !snapshot.isCommitting else { return CustomRulePreview(failure: .busy) }
    guard let ticket = intentTicket() else {
      return CustomRulePreview(failure: .incompleteCollection)
    }
    guard draft.version == ticket.version else { return CustomRulePreview(failure: .staleDraft) }
    let prepared = await Task.detached(priority: .userInitiated) {
      ticket.collection.previewCustomRule(draft)
    }.value
    guard intentTicketIsCurrent(ticket) else { return CustomRulePreview(failure: .staleDraft) }
    return prepared
  }

  func saveCustomRule(_ draft: CustomRuleDraft) async -> CustomRuleSaveResult {
    let preview = await previewCustomRule(draft)
    if let failure = preview.failure { return .unavailable(failure) }
    guard snapshot.isComplete, let document = preview.document else { return .unavailable(.busy) }
    return .committed(await commit(document, operation: draft.editingID == nil ? .add : .edit))
  }
}

/// Deletion targets custom memberships, never the shared match-and-action identity.
extension RulesWorkflow {
  var deletableSelection: Set<UUID> {
    Set(snapshot.rows.filter { snapshot.selection.contains($0.id) }.flatMap(\.customIDs))
  }

  func prepareCustomRuleDeletion() -> CustomRuleDeletion? {
    guard let ticket = intentTicket(), !deletableSelection.isEmpty else { return nil }
    return CustomRuleDeletion(customIDs: deletableSelection, version: ticket.version)
  }

  /// 删除的事务门拒绝（忙碌/超期）与提交失败走同一条 commitFeedback 呈现，
  /// 不另设返回词汇：确认手势的所有失败口径一致。
  func deleteCustomRules(_ confirmation: CustomRuleDeletion) async {
    guard !snapshot.isCommitting else {
      publishFeedback(.busy, operation: .delete, changedCount: 0, page: snapshot)
      return
    }
    guard let ticket = intentTicket(), let old = ticket.document,
      !confirmation.customIDs.isEmpty,
      confirmation.version == ticket.version,
      confirmation.customIDs.isSubset(of: Set(old.rules.map(\.id)))
    else {
      publishFeedback(.superseded, operation: .delete, changedCount: 0, page: snapshot)
      return
    }
    let document = CustomRuleDocument(
      rules: old.rules.filter { !confirmation.customIDs.contains($0.id) },
      disabledIdentities: old.disabledIdentities)
    _ = await commit(
      document, operation: .delete, changedCount: confirmation.customIDs.count)
  }
}

struct CustomRuleDeletion: Equatable, Sendable {
  let customIDs: Set<UUID>
  let version: String

  fileprivate init(customIDs: Set<UUID>, version: String) {
    self.customIDs = customIDs
    self.version = version
  }
}

extension RulesWorkflow {
  var selectedRelationshipRow: RulesRow? {
    guard snapshot.selection.count == 1,
      let row = snapshot.rows.first(where: { snapshot.selection.contains($0.id) }),
      !row.relationships.isEmpty || row.fixedCoverage != nil
    else { return nil }
    return row
  }

}
