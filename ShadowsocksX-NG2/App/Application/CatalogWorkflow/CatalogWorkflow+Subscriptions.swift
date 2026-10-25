import Foundation

/// 订阅生命周期：粘贴 HTTPS URL 创建、单个/全部
/// 立即更新、编辑 URL（保留身份）、删除（递归清除）。刷新 = 完整获取、解析、
/// 校验后同文档原子提交快照与刷新状态；任何失败保留最后成功快照、活动目标与
/// 运行状态，仅标记来源失败。每次提交都经目录提交协调器异步
/// 触发运行时收敛（订阅子树变更 → 活动目标原子跟随或清除停止）。
extension CatalogWorkflow {
  /// 当前会话最近一次失败的安全事实，保存失败时也可呈现。
  func subscriptionRefreshFailure(for id: NodeID) -> SubscriptionRefreshFailure? {
    subscriptionRefreshFailures[id]
  }

  /// 创建订阅：校验 HTTPS URL → 落订阅记录与空固定分组 → 立即
  /// 首次刷新。首次刷新失败留空分组加错误态（状态在刷新内标记，创建本身总是
  /// 成功）。返回订阅 summary（状态在首次刷新中落定）。
  @discardableResult
  func createSubscription(
    urlString: String, autoUpdate: SubscriptionAutoUpdate = SubscriptionAutoUpdate()
  ) async throws -> SubscriptionSummary {
    let url = try Self.validatedSubscriptionURL(urlString)
    var record = SubscriptionRecord(
      id: .fresh(),
      groupID: .fresh(),
      url: url.absoluteString,
      status: .never)
    record.autoUpdate.userOverride = autoUpdate.userOverride
    record.autoUpdate.interval = autoUpdate.interval == .weekly ? .weekly : .daily
    record.autoUpdate.schedule(
      from: dependencies.subscriptionNow(), jitter: dependencies.subscriptionJitter())
    try commitSubscriptionDocument { catalog, subscriptions in
      try catalog.addGroup(url.host ?? "", source: .subscription, id: record.groupID, now: Date())
      subscriptions.append(record)
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
    guard subscriptionRequests[id] == nil, let source = subscriptionRecord(withID: id),
      !Task.isCancelled
    else { return }
    let token = UUID()
    setSubscriptionRefreshCompletion(nil, for: id)
    setRefreshInFlight(id, true)
    let request = Task { await runSubscriptionRefresh(source, token: token) }
    subscriptionRequests[id] = (token, request)
    await withTaskCancellationHandler {
      await request.value
    } onCancel: {
      request.cancel()
    }
  }

  private func runSubscriptionRefresh(_ source: SubscriptionRecord, token: UUID) async {
    let id = source.id
    defer {
      if subscriptionRequests[id]?.token == token {
        subscriptionRequests[id] = nil
        setRefreshInFlight(id, false)
        scheduleAutomaticUpdateCheck()
      }
    }
    do {
      try await performRefresh(source, token: token)
      setSubscriptionRefreshFailure(nil, for: id)
      publishSubscriptionServerRefresh(id)
      setSubscriptionRefreshCompletion(SubscriptionRefreshCompletion(), for: id)
    } catch is CancellationError {
      // Cancellation preserves the last committed result and plan.
    } catch {
      guard !Task.isCancelled, subscriptionRequests[id]?.token == token,
        subscriptionRecord(withID: id)?.url == source.url
      else { return }
      let failure = SubscriptionRefreshFailure.from(error: error)
      setSubscriptionRefreshFailure(failure, for: id)
      await markRefreshFailed(subscriptionID: id, failure: failure)
      setSubscriptionRefreshCompletion(SubscriptionRefreshCompletion(failure: failure), for: id)
    }
  }

  /// 立即更新全部订阅（逐个顺序执行；单个失败不影响其余）。
  func refreshAllSubscriptions() async {
    for record in subscriptions {
      await refreshSubscription(record.id)
    }
  }

  /// 编辑订阅 URL：订阅/固定分组/远端身份
  /// 命名空间全部保留；最后成功快照保留到新 URL 刷新成功，随后立即刷新。
  func editSubscriptionURL(
    _ id: NodeID, urlString: String, autoUpdate: SubscriptionAutoUpdate? = nil
  ) async throws {
    guard let record = subscriptionRecord(withID: id) else {
      throw SubscriptionFormError.notFound
    }
    let url = try Self.validatedSubscriptionURL(urlString)
    let changedURL = record.url != url.absoluteString
    try dependencies.coordinator.commitSubscriptions { subscriptions in
      guard let index = subscriptions.firstIndex(where: { $0.id == id }) else {
        throw SubscriptionFormError.notFound
      }
      let previousMode = subscriptions[index].autoUpdate.effectiveMode
      if let autoUpdate, subscriptions[index].autoUpdate.allowsUserOverride {
        subscriptions[index].autoUpdate.userOverride = autoUpdate.userOverride
        subscriptions[index].autoUpdate.interval = autoUpdate.interval == .weekly ? .weekly : .daily
      }
      subscriptions[index].url = url.absoluteString
      if changedURL { subscriptions[index].autoUpdate.provider = nil }
      if previousMode != subscriptions[index].autoUpdate.effectiveMode {
        subscriptions[index].autoUpdate.schedule(
          from: dependencies.subscriptionNow(), jitter: dependencies.subscriptionJitter())
      }
    }
    if changedURL { cancelSubscriptionRequest(id) }
    republishCommittedState()
    if changedURL { await refreshSubscription(record.id) }
  }

  /// Settings-only saves never reconcile the proxy runtime or fetch the source.
  func saveSubscriptionAutoUpdate(_ id: NodeID, settings: SubscriptionAutoUpdate) throws {
    guard let record = subscriptionRecord(withID: id) else {
      throw SubscriptionFormError.notFound
    }
    guard record.autoUpdate.allowsUserOverride else { return }
    try dependencies.coordinator.commitSubscriptions { subscriptions in
      guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
      let previousMode = subscriptions[index].autoUpdate.effectiveMode
      subscriptions[index].autoUpdate.userOverride = settings.userOverride
      subscriptions[index].autoUpdate.interval = settings.interval == .weekly ? .weekly : .daily
      if previousMode != subscriptions[index].autoUpdate.effectiveMode {
        subscriptions[index].autoUpdate.schedule(
          from: dependencies.subscriptionNow(), jitter: dependencies.subscriptionJitter())
      }
    }
    republishCommittedState()
  }

  func cancelSubscriptionRequest(_ id: NodeID) {
    subscriptionRequests.removeValue(forKey: id)?.task.cancel()
    setRefreshInFlight(id, false)
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
    cancelSubscriptionRequest(id)
    setSubscriptionRefreshCompletion(nil, for: id)
    return RemovalOutcome(removedNodeIDs: Set(removedEntries.map(\.id)))
  }

  /// 编辑面预填用：读取订阅 URL 明文（仅用户显式编辑动作触发）。
  func subscriptionURL(for id: NodeID) throws -> String {
    guard let record = subscriptionRecord(withID: id) else {
      throw SubscriptionFormError.notFound
    }
    return record.url
  }

  // MARK: - 刷新内核

  /// 完整获取 → 解析校验 → 原子提交快照与成功状态。
  private func performRefresh(_ record: SubscriptionRecord, token: UUID) async throws {
    let urlString = record.url
    let url = try Self.validatedSubscriptionURL(urlString)
    let data = try await dependencies.subscriptionFetcher.fetch(url)
    try Task.checkCancellation()
    guard subscriptionRequests[record.id]?.token == token,
      subscriptionRecord(withID: record.id)?.url == record.url
    else { throw CancellationError() }
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
    do {
      try commitSubscriptionDocument { catalog, subscriptions in
        let now = dependencies.subscriptionNow()
        let resolved = Self.catalogSnapshot(snapshot.root, catalogGroupID: summary.groupID)
        try Task.checkCancellation()
        let name = snapshot.root.name.isEmpty ? fallbackName : snapshot.root.name
        let document = CatalogSubscriptionSnapshot(name: name, root: resolved)
        _ = try catalog.applySubscriptionSnapshot(document, into: summary.groupID, now: now)
        if let index = subscriptions.firstIndex(where: { $0.id == summary.id }) {
          subscriptions[index].status = .succeeded(at: now)
          subscriptions[index].information =
            snapshot.information.isEmpty ? nil : snapshot.information
          subscriptions[index].lastSucceededAt = now
          subscriptions[index].autoUpdate.apply(snapshot.autoUpdatePolicy)
          subscriptions[index].autoUpdate.schedule(
            from: now, jitter: dependencies.subscriptionJitter())
        }
      }
    } catch {
      if error is CancellationError { throw error }
      throw SubscriptionRefreshFailure.commit
    }
  }

  /// 失败点名写入订阅状态。持久化的是 typed durable facts，不是已经渲染的
  /// 用户可见句子。
  private func markRefreshFailed(
    subscriptionID: NodeID, failure: SubscriptionRefreshFailure
  ) async {
    try? commitSubscriptionDocument { _, subscriptions in
      if let index = subscriptions.firstIndex(where: { $0.id == subscriptionID }) {
        let now = dependencies.subscriptionNow()
        subscriptions[index].status = .failed(at: now, failure: failure)
        subscriptions[index].autoUpdate.schedule(
          from: now, jitter: dependencies.subscriptionJitter())
      }
    }
  }

  /// 订阅原始记录查询（module 内部；投影不含完整 URL）。
  func subscriptionRecord(withID id: NodeID) -> SubscriptionRecord? {
    dependencies.coordinator.committedSubscriptions.first { $0.id == id }
  }

  /// 订阅卡片 projection 推导（module 内部）：名称、URL host、结构化状态、
  /// 服务器数。
  static func subscriptionSummaries(
    _ records: [SubscriptionRecord],
    catalog: ConfigurationCatalog
  ) -> [SubscriptionSummary] {
    records.map { record in
      let host = URL(string: record.url)?.host ?? ""
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
        lastSucceededAt: record.lastSucceededAt,
        autoUpdate: record.autoUpdate)
    }
  }

  /// 远端身份保留在订阅作用域中，秘密随服务器记录进入工作副本。
  private static func catalogSnapshot(
    _ group: SubscriptionSnapshot.Group, catalogGroupID: NodeID
  ) -> CatalogSubscriptionSnapshot.Group {
    let children: [CatalogSubscriptionSnapshot.Child] = group.children.map { child in
      switch child {
      case .server(let leaf):
        return .server(.init(id: leaf.id, fields: importServerFields(from: leaf.record)))
      case .group(let nested):
        return .group(catalogSnapshot(nested, catalogGroupID: nested.id))
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
