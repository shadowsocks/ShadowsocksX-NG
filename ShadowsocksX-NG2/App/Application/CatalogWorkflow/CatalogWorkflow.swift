import Combine
import Foundation

/// 目录工作流 module（深化为 application module）：主窗口与
/// 配置 UI 的唯一 UI-facing seam。隐藏配置目录、秘密值、订阅快照、Legacy
/// 导入细节、持久化协调与运行时收敛，向 UI 提供不含秘密值的树/详情/订阅
/// projection、opaque 节点身份查询、typed command、typed error 与 structured
/// outcome。选择、pane、sheet、alert 等窗口状态仍由 UI 持有；本类不生成
/// 用户可见文案。
///
/// 内部沿用既有深 module：`ConfigurationCatalog` 的结构约束、
/// `ActivationStateMachine` 经 `CatalogCommitCoordinator` 的激活语义与目录
/// 持久化/runtime sync 协调，以及既有订阅获取与 Legacy 导入缝。
/// 「目录已提交」与「运行时已收敛」是分离的观察面：提交在
/// 持久化成功即完成，`runtimeSync` 单独呈现收敛阶段，失败不回滚目录。
/// 实现 adapter 全部经组合根注入的 `CatalogWorkflowDependencies` 装配；
/// 本类不自行创建生产默认实现。
@MainActor
final class CatalogWorkflow: ObservableObject {
  @Published private(set) var libraryFailure: ServerLibraryFailure?

  /// 目录树 projection（侧栏、级联、移动目的地、删除确认共用）。
  @Published private(set) var tree: CatalogTreeSnapshot
  @Published private(set) var favoriteIDs: [NodeID]
  /// 订阅卡片 projection（非敏感）。
  @Published private(set) var subscriptions: [SubscriptionSummary] = []
  /// 正在刷新的订阅身份（并发守卫的只读观察面）。
  @Published private(set) var refreshingSubscriptionIDs: Set<NodeID> = []
  /// 当前会话的刷新结果；不从持久化状态重建，供各入口共用结束时间。
  @Published private(set) var subscriptionRefreshCompletions:
    [NodeID: SubscriptionRefreshCompletion] = [:]
  /// 最近一次订阅刷新失败的安全事实，包括无法持久化失败状态的情况。
  @Published private(set) var subscriptionRefreshFailures: [NodeID: SubscriptionRefreshFailure] =
    [:]
  /// 最近一次提交的运行时收敛阶段（与目录提交成功分离）。存储与
  /// 发布单点在提交协调器，此处只透传读面；需要实时更新的表面订阅
  /// `runtimeSyncChanges`（`.onReceive` 消费），不经本类 objectWillChange——
  /// App 侧目前无视图消费者，避免每次提交徒劳失效全部目录观察者。
  var runtimeSync: RuntimeSyncStatus { dependencies.coordinator.syncStatus }

  /// 收敛阶段变化通道（didChange 语义，值即当前阶段）。
  var runtimeSyncChanges: AnyPublisher<RuntimeSyncStatus, Never> {
    dependencies.coordinator.syncStatusChanges.eraseToAnyPublisher()
  }
  /// Legacy 快照发现与一次性完成标记。
  @Published private(set) var legacyImportState = LegacyImportAvailability(
    snapshotFound: false, completed: false)

  /// 组合根与测试装配的全部实现 adapter：coordinator、
  /// 插件、订阅获取、Legacy 导入服务、导入后回调与激活缝只经此束持有，
  /// 不再作为 workflow 属性暴露。仅供组合根与测试构造；视图不得访问——
  /// 独立 target 拆分前由 architecture deletion check 守护残余可见性。
  var connectivity: ServerConnectivity?

  let dependencies: CatalogWorkflowDependencies
  /// 启动时发现的 Legacy 快照（导入编排用；秘密值不进 projection）。
  var discoveredLegacySnapshot: LegacySnapshot?
  var subscriptionRequests: [NodeID: (token: UUID, task: Task<Void, Never>)] = [:]
  var automaticUpdatesRunning = false
  var automaticUpdateTimer: Task<Void, Never>?
  var automaticUpdateBatch: Task<Void, Never>?
  var checkingDueSubscriptions = false

  /// 组合根注入依赖束；workflow 不自行创建任何生产 adapter。
  init(dependencies: CatalogWorkflowDependencies) {
    self.dependencies = dependencies
    let coordinator = dependencies.coordinator
    libraryFailure = coordinator.loadError.map(ServerLibraryFailure.init)
    favoriteIDs = coordinator.committedFavoriteIDs
    tree = .build(
      from: coordinator.committedCatalog,
      plugins: dependencies.plugins)
    subscriptions = Self.subscriptionSummaries(
      coordinator.committedSubscriptions, catalog: coordinator.committedCatalog)
    refreshLegacyImportState()
  }

  /// Successful subscription commits, including credential-only record changes.
  private let subscriptionServerRefreshSubject = PassthroughSubject<Set<NodeID>, Never>()

  var subscriptionServerRefreshes: AnyPublisher<Set<NodeID>, Never> {
    subscriptionServerRefreshSubject.eraseToAnyPublisher()
  }

  private let serverUpdateSubject = PassthroughSubject<Set<NodeID>, Never>()

  /// 成功保存或订阅刷新后装载详情参数，包括只改变凭据而树值不变的提交。
  var serverDetailChanges: AnyPublisher<Set<NodeID>, Never> {
    subscriptionServerRefreshSubject.merge(with: serverUpdateSubject).eraseToAnyPublisher()
  }

  func publishSubscriptionServerRefresh(_ id: NodeID) {
    guard let summary = subscriptions.first(where: { $0.id == id }),
      let group = tree.node(withID: summary.groupID)
    else { return }
    subscriptionServerRefreshSubject.send(group.subtreeIDs)
  }

  /// 只有用户主动操作才允许钥匙串请求交互授权。
  func unlockLibrary() {
    do {
      try dependencies.coordinator.reload(allowingInteraction: true)
      libraryFailure = nil
      republishCommittedState()
    } catch { libraryFailure = ServerLibraryFailure(error) }
  }

  /// UI 必须先取得用户放弃原配置的明确确认。
  func resetLibrary() {
    do {
      try dependencies.coordinator.resetLibrary()
      libraryFailure = nil
      republishCommittedState()
    } catch { libraryFailure = ServerLibraryFailure(error) }
  }

  // MARK: - 查询面

  func setFavorite(_ id: NodeID, isFavorite: Bool) throws {
    guard tree.containsNode(id) else { throw CatalogError.nodeNotFound(id) }
    var updated = favoriteIDs
    if isFavorite {
      if !updated.contains(id) { updated.append(id) }
    } else {
      updated.removeAll { $0 == id }
    }
    try dependencies.coordinator.commitFavorites(updated)
    favoriteIDs = dependencies.coordinator.committedFavoriteIDs
  }

  /// 将收藏移至指定收藏前；nil 表示末尾，不接受未收藏的节点。
  func moveFavorite(_ id: NodeID, before target: NodeID?) throws {
    guard favoriteIDs.contains(id) else { throw CatalogError.nodeNotFound(id) }
    if let target, !favoriteIDs.contains(target) { throw CatalogError.nodeNotFound(target) }
    guard id != target else { return }
    var updated = favoriteIDs.filter { $0 != id }
    let index = target.flatMap { updated.firstIndex(of: $0) } ?? updated.endIndex
    updated.insert(id, at: index)
    try dependencies.coordinator.commitFavorites(updated)
    favoriteIDs = dependencies.coordinator.committedFavoriteIDs
  }

  // MARK: - 手动服务器/分组命令

  /// 密码、插件参数与连接字段在同一工作副本中提交，失败不发布任何变更。
  @discardableResult
  func createServer(_ draft: ServerEditDraft, into parent: NodeID?) async throws -> NodeID {
    let draft = try prepareServerDraft(draft)
    return try commit { catalog in
      var fields = ServerFields(
        address: draft.address, port: draft.port, encryptionMethod: draft.encryptionMethod,
        password: draft.password, remark: draft.remark)
      Self.applyPluginSelection(draft.plugin, options: draft.pluginOptions, to: &fields)
      return try catalog.addServer(fields, to: parent, now: Date())
    }
  }

  /// 新建空手动分组；返回新分组身份。
  @discardableResult
  func createGroup(named name: String, into parent: NodeID?) async throws -> NodeID {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw ServerFormError.emptyName }
    return try commit { catalog in
      try catalog.addGroup(trimmed, to: parent, now: Date())
    }
  }

  /// 重命名手动分组：identity、父级与子项顺序不变。
  func renameGroup(_ id: NodeID, to name: String) async throws {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw ServerFormError.emptyName }
    try commit { catalog in
      try catalog.renameGroup(id, to: trimmed, now: Date())
    }
  }

  /// 拖拽/移动菜单落点：跨来源、共享父级、成环由领域拒绝，
  /// typed error 原样上抛。
  func move(_ id: NodeID, to parent: NodeID?) async throws {
    try commit { catalog in
      try catalog.move(id, to: parent, now: Date())
    }
  }

  /// 删除条目及其后代；凭据随记录一同删除。
  func remove(_ id: NodeID) async throws -> RemovalOutcome {
    let removed = try commit { catalog in
      try catalog.remove(id, now: Date())
    }
    return RemovalOutcome(removedNodeIDs: Set(removed.map(\.id)))
  }

  /// 服务器字段与秘密作为完整值提交，未知插件参数原样保留。
  func updateServer(_ id: NodeID, draft: ServerEditDraft) async throws {
    let draft = try prepareServerDraft(draft)
    try commit { catalog in
      guard let entry = catalog.entry(for: id), case .server(var fields) = entry.kind else {
        throw CatalogError.notAServer(id)
      }
      fields.password = draft.password
      fields.address = draft.address
      fields.port = draft.port
      fields.encryptionMethod = draft.encryptionMethod
      fields.remark = draft.remark
      Self.applyPluginSelection(draft.plugin, options: draft.pluginOptions, to: &fields)
      try catalog.updateServer(id, with: fields, now: Date())
    }
    serverUpdateSubject.send([id])
  }

  /// 新建与编辑共享的草稿准备：校验在目录提交之前完成。
  /// 仅手动表单拒绝空名称；导入通过 ServerFields 的构造规则补名。
  private func prepareServerDraft(_ input: ServerEditDraft) throws -> ServerEditDraft {
    var draft = input
    draft.address = draft.address.trimmingCharacters(in: .whitespaces)
    guard !draft.address.isEmpty else { throw ServerFormError.invalidAddress }
    guard (1...65_535).contains(draft.port) else { throw ServerFormError.invalidPort }
    draft.encryptionMethod = draft.encryptionMethod.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !draft.encryptionMethod.isEmpty else { throw ServerFormError.missingEncryptionMethod }
    guard EncryptionMethodCatalog.isSupported(draft.encryptionMethod) else {
      throw ServerFormError.unsupportedEncryptionMethod(draft.encryptionMethod)
    }
    guard !draft.password.isEmpty else { throw ServerFormError.invalidPassword }
    if case .named(let program) = draft.plugin,
      dependencies.plugins.catalogSnapshot().entry(for: program) == nil
    {
      throw ServerFormError.pluginUnknown(program)
    }
    draft.remark = draft.remark.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !draft.remark.isEmpty else { throw ServerFormError.emptyName }
    return draft
  }

  // MARK: - 提交管线（module 内部；UI 不得调用，独立 target 拆分前靠 deletion check）

  /// 仅目录变更的提交便捷入口（module 内部扩展共用，同 `commitSubscriptionDocument`
  /// 的窄缝口径）。
  func commit<T>(
    _ mutate: (inout ConfigurationCatalog) throws -> T
  ) throws -> T {
    try commitDocument { catalog, _ in
      try mutate(&catalog)
    }
  }

  /// 副本变更 → 协调器落盘 → 重新发布 projection；任一步失败则已发布状态
  /// 不动。运行时收敛由协调器异步调度，不阻塞也不回滚本提交。
  private func commitDocument<T>(
    _ mutate: (inout ConfigurationCatalog, inout [SubscriptionRecord]) throws -> T
  ) throws -> T {
    let result = try dependencies.coordinator.commit(mutate)
    republishCommittedState()
    return result
  }

  /// 订阅扩展的唯一写路径（module 内部窄缝，替代直接摸 `commitDocument`）。
  func commitSubscriptionDocument<T>(
    _ mutate: (inout ConfigurationCatalog, inout [SubscriptionRecord]) throws -> T
  ) throws -> T {
    try commitDocument(mutate)
  }

  /// 提交成功后的 projection 重建（树 + 订阅卡片）。
  func republishCommittedState() {
    connectivity?.configurationsChanged()
    let coordinator = dependencies.coordinator
    favoriteIDs = coordinator.committedFavoriteIDs
    tree = .build(
      from: coordinator.committedCatalog,
      plugins: dependencies.plugins)
    subscriptions = Self.subscriptionSummaries(
      coordinator.committedSubscriptions, catalog: coordinator.committedCatalog)
    scheduleAutomaticUpdateCheck()
  }

  // MARK: - module 内部发布缝（扩展文件经此更新只读投影，setter 保持 private）

  func publishLegacyImportState(_ state: LegacyImportAvailability) {
    legacyImportState = state
  }

  /// 订阅刷新并发守卫的写入口（集合对外只读）。
  func setRefreshInFlight(_ id: NodeID, _ inFlight: Bool) {
    if inFlight {
      refreshingSubscriptionIDs.insert(id)
    } else {
      refreshingSubscriptionIDs.remove(id)
    }
  }

  func setSubscriptionRefreshCompletion(
    _ completion: SubscriptionRefreshCompletion?, for id: NodeID
  ) {
    subscriptionRefreshCompletions[id] = completion
  }

  func setSubscriptionRefreshFailure(
    _ result: SubscriptionRefreshFailure?, for id: NodeID
  ) {
    if let result {
      subscriptionRefreshFailures[id] = result
    } else {
      subscriptionRefreshFailures.removeValue(forKey: id)
    }
  }
}
