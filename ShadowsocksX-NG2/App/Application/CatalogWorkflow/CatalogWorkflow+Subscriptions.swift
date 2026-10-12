import Foundation

/// 订阅生命周期：粘贴 HTTPS URL 创建、单个/全部
/// 立即更新、编辑 URL（保留身份）、删除（递归清除）。刷新 = 完整获取、解析、
/// 校验后同文档原子提交快照与刷新状态；任何失败保留最后成功快照、活动目标与
/// 运行状态，仅标记来源失败。每次提交都经目录提交协调器异步
/// 触发运行时收敛（订阅子树变更 → 活动目标原子跟随或清除停止）。
extension CatalogWorkflow {
  /// 当前会话中最近一次失败的完整结果；不会把凭据引用暴露到 durable catalog。
  func subscriptionRefreshFailure(for id: NodeID) -> SubscriptionRefreshFailureResult? {
    subscriptionRefreshFailures[id]
  }

  /// 创建订阅：校验 HTTPS URL → 落订阅记录与空固定分组 → 立即
  /// 首次刷新。首次刷新失败留空分组加错误态（状态在刷新内标记，创建本身总是
  /// 成功）。返回订阅 summary（状态在首次刷新中落定）。
  @discardableResult
  func createSubscription(urlString: String) async throws -> SubscriptionSummary {
    let url = try Self.validatedSubscriptionURL(urlString)
    let record = SubscriptionRecord(
      id: .fresh(),
      groupID: .fresh(),
      urlRef: .fresh(),
      status: .never)
    try dependencies.credentials.save(url.absoluteString, for: record.urlRef)
    do {
      try commitSubscriptionDocument { catalog, subscriptions in
        // 固定分组挂在目录根（GLOSSARY.md「Subscription group」）；名称以 host
        // 兜底，首次成功刷新后跟随远端。
        try catalog.addGroup(url.host ?? "", source: .subscription, id: record.groupID, now: Date())
        subscriptions.append(record)
      }
    } catch {
      try? dependencies.credentials.delete(record.urlRef)
      throw error
    }
    await refreshSubscription(record.id)
    return subscriptions.first(where: { $0.id == record.id })
      ?? SubscriptionSummary(
        id: record.id, groupID: record.groupID, name: url.host ?? "",
        host: url.host ?? "", status: .never, serverCount: 0)
  }

  /// 立即更新单个订阅。不抛错：失败标记到订阅状态（无静默，
  /// 有结构化状态可呈现）。同一订阅不重入：进行中的刷新期间重复触发直接跳过。
  func refreshSubscription(_ id: NodeID) async {
    guard !refreshingSubscriptionIDs.contains(id),
      subscriptions.contains(where: { $0.id == id })
    else { return }
    setRefreshInFlight(id, true)
    defer { setRefreshInFlight(id, false) }
    do {
      try await performRefresh(id)
      setSubscriptionRefreshFailure(nil, for: id)
      publishSubscriptionServerRefresh(id)
    } catch is CancellationError {
      // 取消不构成失败：快照与状态都不动。
    } catch {
      guard !Task.isCancelled else { return }
      let result = Self.refreshFailureResult(from: error)
      setSubscriptionRefreshFailure(result, for: id)
      await markRefreshFailed(subscriptionID: id, failure: result.failure)
    }
  }

  /// 立即更新全部订阅（逐个顺序执行；单个失败不影响其余）。
  func refreshAllSubscriptions() async {
    for record in subscriptions {
      await refreshSubscription(record.id)
    }
  }

  /// 编辑订阅 URL：同一凭据引用覆盖写，订阅/固定分组/远端身份
  /// 命名空间全部保留；最后成功快照保留到新 URL 刷新成功，随后立即刷新。
  func editSubscriptionURL(_ id: NodeID, urlString: String) async throws {
    guard let record = subscriptionRecord(withID: id) else {
      throw SubscriptionFormError.notFound
    }
    let url = try Self.validatedSubscriptionURL(urlString)
    // 覆盖写同一引用；URL 编辑不落目录文档（引用与身份不变），新地址刷新
    // 成功才有新快照——写入失败不触碰目录状态。
    try dependencies.credentials.save(url.absoluteString, for: record.urlRef)
    await refreshSubscription(record.id)
  }

  /// 删除订阅：递归清除订阅源、固定分组与远端成员并清理凭据；
  /// 活动目标的清除与代理停止由 postCommit 的既有激活语义处理（无静默回退）。
  /// 返回被删身份集合供 UI 清除失效选择。
  func removeSubscription(_ id: NodeID) async throws -> RemovalOutcome {
    guard let record = subscriptionRecord(withID: id) else {
      throw SubscriptionFormError.notFound
    }
    var removedEntries: [CatalogEntry] = []
    try commitSubscriptionDocument { catalog, subscriptions in
      removedEntries = try catalog.removeSubscriptionSubtree(of: record.groupID)
      subscriptions.removeAll { $0.id == id }
    }
    for ref in [record.urlRef] + Self.credentialRefs(of: removedEntries) {
      try? dependencies.credentials.delete(ref)
    }
    return RemovalOutcome(removedNodeIDs: Set(removedEntries.map(\.id)))
  }

  /// 编辑面预填用：读取订阅 URL 明文（仅用户显式编辑动作触发）。
  func subscriptionURL(for id: NodeID) throws -> String {
    guard let record = subscriptionRecord(withID: id) else {
      throw SubscriptionFormError.notFound
    }
    guard let stored = try dependencies.credentials.secret(for: record.urlRef) else {
      throw CredentialStoreError.keychainStatus(errSecItemNotFound)
    }
    return stored
  }

  // MARK: - 刷新内核

  /// 完整获取 → 解析校验 → 凭据解析 → 原子提交快照与成功状态。
  private func performRefresh(_ id: NodeID) async throws {
    guard let record = subscriptionRecord(withID: id) else { return }
    // 缺凭据是命名失败（区别于地址格式无效），不静默当作空 URL。
    let urlString = try subscriptionURL(for: record.id)
    let url = try Self.validatedSubscriptionURL(urlString)
    let data = try await dependencies.subscriptionFetcher.fetch(url)
    try Task.checkCancellation()
    let snapshot = try SubscriptionDocumentParser.parse(data, subscriptionID: record.id)
    let summary =
      subscriptions.first(where: { $0.id == record.id })
      ?? SubscriptionSummary(
        id: record.id, groupID: record.groupID, name: "", host: "",
        status: record.status, serverCount: 0)
    try await commitSnapshot(snapshot, summary: summary, fallbackName: url.host ?? "")
  }

  private func commitSnapshot(
    _ snapshot: SubscriptionSnapshot, summary: SubscriptionSummary, fallbackName: String
  ) async throws {
    try Task.checkCancellation()
    var obsoleteCredentialRefs: Set<CredentialReference> = []
    var credentialJournal = CredentialWriteJournal(credentials: dependencies.credentials)
    do {
      try commitSubscriptionDocument { catalog, subscriptions in
        let now = Date()
        // 凭据引用按节点身份复用：延续节点覆盖写秘密，不新增孤儿引用；
        // journal 保证快照提交失败时恢复旧秘密。
        var reusedRefs: [NodeID: ServerCredentialRefs] = [:]
        for entry in (try? catalog.subscriptionSubtree(of: summary.groupID)) ?? [] {
          if case .server(let fields) = entry.kind {
            reusedRefs[entry.id] = ServerCredentialRefs(
              password: fields.passwordRef, options: fields.pluginOptionsRef)
          }
        }
        let resolved = try Self.resolveCredentials(
          snapshot.root, catalogGroupID: summary.groupID, reuse: reusedRefs,
          journal: &credentialJournal)
        try Task.checkCancellation()
        let name = snapshot.root.name.isEmpty ? fallbackName : snapshot.root.name
        let document = CatalogSubscriptionSnapshot(name: name, root: resolved)
        let replacedServers = try catalog.applySubscriptionSnapshot(
          document, into: summary.groupID, now: now)
        // 快照应用返回整个旧树；延续节点仍复用引用，不能按旧树直接删除秘密。
        let retainedRefs = Set(Self.credentialRefs(of: Array(catalog.entries.values)))
        obsoleteCredentialRefs = Set(Self.credentialRefs(of: replacedServers))
          .subtracting(retainedRefs)
        if let index = subscriptions.firstIndex(where: { $0.id == summary.id }) {
          subscriptions[index].status = .succeeded(at: now)
          subscriptions[index].information =
            snapshot.information.isEmpty ? nil : snapshot.information
          subscriptions[index].lastSucceededAt = now
        }
      }
    } catch {
      // 尽力恢复旧秘密；完整 outcome 只随 transient error 留在
      // 内存，durable status 只会保存粗粒度 rollback 状态。
      let rollback = credentialJournal.rollback()
      if error is CancellationError { throw error }
      let category: SubscriptionRefreshFailure.CommitCategory =
        error is CredentialStoreError ? .credentials : .persistence
      throw SubscriptionRefreshCommitError(category: category, rollback: rollback)
    }
    // 只清理已提交目录不再引用的旧秘密，包括延续节点撤销的插件参数。
    for ref in obsoleteCredentialRefs {
      try? dependencies.credentials.delete(ref)
    }
  }

  /// 失败点名写入订阅状态。持久化的是 typed durable facts，不是已经渲染的
  /// 用户可见句子。
  private func markRefreshFailed(
    subscriptionID: NodeID, failure: SubscriptionRefreshFailure
  ) async {
    try? commitSubscriptionDocument { _, subscriptions in
      if let index = subscriptions.firstIndex(where: { $0.id == subscriptionID }) {
        subscriptions[index].status = .failed(at: Date(), failure: failure)
      }
    }
  }

  private static func refreshFailureResult(from error: Error) -> SubscriptionRefreshFailureResult {
    if let commit = error as? SubscriptionRefreshCommitError {
      return SubscriptionRefreshFailureResult(
        failure: .commit(
          category: commit.category,
          rollback: SubscriptionRefreshFailure.rollbackStatus(for: commit.rollback)),
        credentialRollback: commit.rollback)
    }
    let failure = SubscriptionRefreshFailure.from(error: error)
    return SubscriptionRefreshFailureResult(failure: failure, credentialRollback: nil)
  }

  /// 订阅原始记录查询（module 内部；投影不含凭据引用等原始形态）。
  private func subscriptionRecord(withID id: NodeID) -> SubscriptionRecord? {
    dependencies.coordinator.committedSubscriptions.first { $0.id == id }
  }

  /// 订阅卡片 projection 推导（module 内部）：名称、URL host、结构化状态、
  /// 服务器数。
  static func subscriptionSummaries(
    _ records: [SubscriptionRecord],
    catalog: ConfigurationCatalog,
    credentials: CredentialStoring
  ) -> [SubscriptionSummary] {
    records.map { record in
      let host =
        (try? credentials.secret(for: record.urlRef))
        .flatMap { $0.flatMap(URL.init(string:)) }?.host ?? ""
      let subtree = (try? catalog.subscriptionSubtree(of: record.groupID)) ?? []
      let serverCount = subtree.reduce(0) { count, entry in
        if case .server = entry.kind { return count + 1 }
        return count
      }
      return SubscriptionSummary(
        id: record.id,
        groupID: record.groupID,
        name: catalog.entry(for: record.groupID)?.displayName ?? "",
        host: host,
        status: record.status,
        serverCount: serverCount,
        information: record.information,
        lastSucceededAt: record.lastSucceededAt)
    }
  }

  /// 明文快照 → 目录形态：密码与插件参数写入凭据存储、目录持引用。
  /// 延续节点复用既有引用（覆盖写），新节点分配新引用。
  private static func resolveCredentials(
    _ group: SubscriptionSnapshot.Group,
    catalogGroupID: NodeID,
    reuse: [NodeID: ServerCredentialRefs],
    journal: inout CredentialWriteJournal
  ) throws -> CatalogSubscriptionSnapshot.Group {
    var children: [CatalogSubscriptionSnapshot.Child] = []
    for child in group.children {
      switch child {
      case .server(let leaf):
        let existing = reuse[leaf.id]
        let passwordRef = existing?.password ?? .fresh()
        try journal.save(leaf.record.password, for: passwordRef)
        var optionsRef: CredentialReference?
        if let options = leaf.record.pluginOptions, !options.isEmpty {
          let ref = existing?.options ?? .fresh()
          try journal.save(options, for: ref)
          optionsRef = ref
        }
        children.append(
          .server(
            CatalogSubscriptionSnapshot.ServerLeaf(
              id: leaf.id,
              fields: ServerFields(
                address: leaf.record.address,
                port: leaf.record.port,
                encryptionMethod: leaf.record.encryptionMethod,
                passwordRef: passwordRef,
                remark: leaf.record.remark,
                pluginProgram: leaf.record.pluginProgram,
                pluginOptionsRef: optionsRef))))
      case .group(let nested):
        children.append(
          .group(
            try resolveCredentials(
              nested, catalogGroupID: nested.id, reuse: reuse, journal: &journal)))
      }
    }
    return CatalogSubscriptionSnapshot.Group(
      id: catalogGroupID, name: group.name, children: children)
  }

  /// 订阅地址门禁：必须是带主机的 HTTPS URL（宽松模式永不提供）。
  private static func validatedSubscriptionURL(_ string: String) throws -> URL {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      url.scheme?.lowercased() == "https",
      url.host != nil
    else {
      throw SubscriptionFormError.invalidURL
    }
    return url
  }
}

/// 一台服务器叶子的凭据引用对（密码 + 可选插件参数；仅本实现文件使用）。
private struct ServerCredentialRefs: Sendable {
  var password: CredentialReference
  var options: CredentialReference?
}
