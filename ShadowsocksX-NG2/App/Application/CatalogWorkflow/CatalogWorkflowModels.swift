import Foundation
import Security

// MARK: - 目录树 projection（非敏感）

/// 目录树节点快照（目录工作流 module 的 UI-facing projection）：
/// 名称、来源、形态、渲染原子与子树计数；不含凭据引用、密码、插件参数等
/// 秘密值。身份为不透明 `NodeID`，重命名、移动或刷新后保持稳定。
/// 门禁/关系型事实（删除档位、移动资格、激活资格）走 module 查询方法，
/// 不在节点上堆政策字段。
struct CatalogTreeNode: Identifiable, Equatable {
  let id: NodeID
  let name: String
  let isGroup: Bool
  let source: NodeSource
  /// 父节点身份；目录根层节点为 `nil`。
  let parentID: NodeID?
  let createdAt: Date?
  let updatedAt: Date?
  /// 服务器叶子的已知阻塞原因（typed，无成句文案）；分组为空。
  let invalidReasons: [LeafInvalidationReason]
  /// 直接子节点数（分组）。
  let childCount: Int
  /// 子树全部后代节点数（分组；不含自身；删除确认的递归规模）。
  let subtreeNodeCount: Int
  /// 子树中已知无效的服务器数量（不含当前叶子自身；仅供 tooltip 展示）。
  let invalidDescendantCount: Int
  /// 分组持有子树快照；服务器叶子为 `nil`。
  let children: [CatalogTreeNode]?

  var isInvalid: Bool { !invalidReasons.isEmpty }
  var isManual: Bool { source == .manual }
  /// 子树快照；服务器叶子为空（与 `children` 的 nil 区分叶子语义并存）。
  var childNodes: [CatalogTreeNode] { children ?? [] }

  /// 子树服务器配置数，包含存在已知激活阻塞的服务器。
  var serverConfigurationCount: Int {
    isGroup ? childNodes.reduce(0) { $0 + $1.serverConfigurationCount } : 1
  }

  /// 是否包含服务器配置（含当前节点本身）；激活资格与结构性可导出性分离。
  var containsServerConfiguration: Bool {
    if !isGroup { return true }
    return childNodes.contains(where: \.containsServerConfiguration)
  }
}

extension CatalogTreeNode {
  /// 深度优先查找子树中的节点（含自身）。
  func find(_ id: NodeID) -> CatalogTreeNode? {
    if id == self.id { return self }
    for child in children ?? [] {
      if let found = child.find(id) { return found }
    }
    return nil
  }

  /// 子树全部节点身份（含自身）。
  var subtreeIDs: Set<NodeID> {
    var ids: Set<NodeID> = [id]
    for child in children ?? [] { ids.formUnion(child.subtreeIDs) }
    return ids
  }

  /// 子树内已知无效服务器总数（含自身叶子）。
  var subtreeInvalidServerCount: Int {
    (isInvalid ? 1 : 0) + invalidDescendantCount
  }
}

/// 侧栏树的可见行投影：节点 + 呈现深度；身份即节点身份（折叠只影响可见
/// 集合，不影响行身份与选中）。服务器管理侧栏与首页目标树共用同一类型，
/// 折叠集合由各自的浏览状态 owner 给出。
struct CatalogTreeRow: Identifiable {
  let node: CatalogTreeNode
  let depth: Int
  var id: NodeID { node.id }
}

/// 目录树快照：侧栏、活动目标级联、移动目的地与删除确认共用的同一份
/// 非敏感 projection；UI 不再持有原始目录副本。
struct CatalogTreeSnapshot: Equatable {
  let roots: [CatalogTreeNode]

  var isEmpty: Bool { roots.isEmpty }

  /// 深度优先查找节点（含子树）。
  func node(withID id: NodeID) -> CatalogTreeNode? {
    for node in roots {
      if let found = node.find(id) { return found }
    }
    return nil
  }

  /// 节点是否在树中（拖拽负载存在性校验）。
  func containsNode(_ id: NodeID) -> Bool { node(withID: id) != nil }

  /// 活动目标的显示名路径（根 → 节点，" / " 连接）；目标不在树中为 nil。
  /// 代理控制窄缝经此取安全路径摘要，树结构不出目录 module。
  func pathSummary(for id: NodeID) -> String? {
    pathComponents(for: id)?.joined(separator: " / ")
  }

  /// 节点的名称路径；分隔符与来源标签由呈现层决定。
  func pathComponents(for id: NodeID) -> [String]? {
    guard var node = self.node(withID: id) else { return nil }
    var names = [node.name]
    while let parentID = node.parentID, let parent = self.node(withID: parentID) {
      names.insert(parent.name, at: 0)
      node = parent
    }
    return names
  }

  /// 全树已知无效服务器总数（诊断计数）。
  var invalidServerCount: Int {
    roots.reduce(0) { $0 + $1.subtreeInvalidServerCount }
  }
}

extension CatalogTreeSnapshot {
  /// 折叠投影后的可见行（深度优先）：收起分组的子树不出现，其余保持目录
  /// 序。行序与深度是纯树事实；折叠集合由调用方按自己的持久化策略持有。
  func visibleRows(collapsed: Set<NodeID>) -> [CatalogTreeRow] {
    var rows: [CatalogTreeRow] = []
    func walk(_ nodes: [CatalogTreeNode], depth: Int) {
      for node in nodes {
        rows.append(CatalogTreeRow(node: node, depth: depth))
        if node.isGroup, !collapsed.contains(node.id) {
          walk(node.childNodes, depth: depth + 1)
        }
      }
    }
    walk(roots, depth: 0)
    return rows
  }

  /// 全树服务器叶子数（工作区侧栏角标）。
  var serverLeafCount: Int {
    func leaves(_ nodes: [CatalogTreeNode]) -> Int {
      nodes.reduce(0) { $0 + ($1.isGroup ? leaves($1.childNodes) : 1) }
    }
    return leaves(roots)
  }
}

extension CatalogTreeSnapshot {
  /// 从已提交目录构建 projection（module 内部推导；测试同 target 可直接调用）。
  /// 每个服务器叶子求值一次激活校验（与既有口径一致，读凭据存储）。
  static func build(
    from catalog: ConfigurationCatalog,
    credentials: CredentialStoring,
    plugins: PluginExecutableResolving
  ) -> CatalogTreeSnapshot {
    let plugins = plugins.catalogSnapshot()
    func buildNode(_ id: NodeID, entry: CatalogEntry, parentID: NodeID?) -> CatalogTreeNode {
      switch entry.kind {
      case .group(let fields):
        let children = fields.children.compactMap { childID -> CatalogTreeNode? in
          guard let childEntry = catalog.entry(for: childID) else { return nil }
          return buildNode(childID, entry: childEntry, parentID: id)
        }
        return CatalogTreeNode(
          id: id,
          name: entry.displayName,
          isGroup: true,
          source: entry.source,
          parentID: parentID,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          invalidReasons: [],
          childCount: children.count,
          subtreeNodeCount: children.reduce(0) { $0 + 1 + $1.subtreeNodeCount },
          invalidDescendantCount: children.reduce(0) { $0 + $1.subtreeInvalidServerCount },
          children: children)
      case .server(let fields):
        let validation = ServerValidation.evaluate(
          fields, credentials: credentials, plugins: plugins)
        return CatalogTreeNode(
          id: id,
          name: entry.displayName,
          isGroup: false,
          source: entry.source,
          parentID: parentID,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          invalidReasons: validation.issues,
          childCount: 0,
          subtreeNodeCount: 0,
          invalidDescendantCount: 0,
          children: nil)
      }
    }
    let roots = catalog.rootChildren.compactMap { id -> CatalogTreeNode? in
      guard let entry = catalog.entry(for: id) else { return nil }
      return buildNode(id, entry: entry, parentID: nil)
    }
    return CatalogTreeSnapshot(roots: roots)
  }
}

// MARK: - 目录政策事实（UI 写句子；本 module 不产成句文案）

/// 删除确认档位（GLOSSARY.md 删除不变量的结构化事实）。
enum DeleteConfirmKind: Equatable, Sendable {
  /// 服务器叶子：单次确认。
  case leaf
  /// 空手动分组：单次确认。
  case emptyGroup
  /// 非空手动分组：二次确认，点名子树规模与凭据移除。
  case subtree(count: Int, includesCredentials: Bool)
}

/// 激活资格事实（点前门禁；与 `ActivationCommandOutcome` 的点后结果区分）。
struct ActivationEligibility: Equatable, Sendable {
  enum Ineligibility: Equatable, Sendable {
    case emptyGroup
    case noCandidates
  }

  let canActivate: Bool
  let candidateCount: Int
  let skippedInvalidCount: Int
  let ineligibility: Ineligibility?
}

/// 激活命令的结构化结果（意外错误仍 throws）。
enum ActivationCommandOutcome: Equatable, Sendable {
  /// 成功；组展开时跳过的已知无效叶子数。
  case activated(skippedInvalid: Int)
  /// 原子拒绝（无 activation candidate / 目标失效）；携带 typed 点名原因，
  /// 状态完全不动。结果自含全部事实，调用方不必回读运行时发布事实拼原因。
  case rejectedActivation(ActivationFailure)
}

/// 激活缝：目录命令面经此发出激活意图。生产 adapter 为
/// `ProxyRuntimeController`；测试注入假 adapter 观察目标传递。
@MainActor
protocol Activating: AnyObject {
  func activate(_ target: NodeID) async throws -> ActivationCommandOutcome
}

// MARK: - 服务器详情与编辑

/// 服务器编辑面状态：用户打开编辑器时经显式命令解析，凭据明文只在此出现，
/// 不属于普通 projection。
struct ServerEditForm: Equatable {
  let address: String
  let port: Int
  let encryptionMethod: String
  let password: String
  let remark: String
  let plugin: PluginSectionState
  let isEditable: Bool
}

/// 服务器编辑的提交载荷（typed command）：配置与凭据字段作为一个逻辑变更
/// 提交；任一持久化步骤失败时旧配置与旧凭据继续生效。
struct ServerEditDraft: Equatable {
  var address: String
  var port: Int
  var encryptionMethod: String
  var password: String
  var remark: String
  var plugin: PluginSelection
  var pluginOptions: String?
}

/// 提交失败的结构化抛错：配置与凭据是一个逻辑变更，表单校验通过后提交
/// 管线的任一步失败都已触碰（或可能触碰）凭据，凭据半边的恢复结果随错
/// 报出。不含用户可见文案（文案归 presentation edge，从
/// `underlying` 生成）；表单校验在建 journal 之前失败，保持裸 `ServerFormError`。
struct CommitError: Error {
  let underlying: any Error
  let credentialRollback: CredentialRollbackOutcome
}

/// 插件选择器选中态：无、目录中的名称引用、未解析的导入引用。
/// 托管或用户来源由有效目录解释，不参与选中值身份。
/// Hashable 以直接充当 SwiftUI Picker 的选中值。
enum PluginSelection: Hashable {
  case none
  case named(program: String)
  case unknown(program: String)
}

/// 表单所需的目录事实，不包含本机路径或托管发布信息。
struct PluginSectionState: Equatable {
  struct Program: Equatable {
    let program: String
    let source: PluginCatalogSnapshot.Source
    let availability: PluginCatalogSnapshot.Availability
  }

  let selection: PluginSelection
  let programs: [Program]
  let mappingsUnreadable: Bool
  let optionsPresent: Bool
  var options: String

  /// 当前草稿引用可能与已保存选择不同，目录移除不能让它从表单消失。
  func unresolvedProgram(for selection: PluginSelection) -> String? {
    switch selection {
    case .none: return nil
    case .named(let program), .unknown(let program):
      return programs.contains { $0.program == program } ? nil : program
    }
  }
}

// MARK: - 订阅 projection

/// 订阅卡片 projection（非敏感）：完整 URL 不出现，只含 host；
/// 状态为结构化值，本地化文案与日期格式由 UI 呈现层派生。
struct SubscriptionSummary: Identifiable, Equatable {
  let id: NodeID
  let groupID: NodeID
  let name: String
  let host: String
  let status: SubscriptionRefreshStatus
  let serverCount: Int
  var information: SubscriptionInformation?
  var lastSucceededAt: Date?
}

/// Transient refresh result retained by the workflow. The durable status stores
/// only `SubscriptionRefreshFailure` and a coarse rollback state; this value
/// keeps the complete journal outcome available to the current UI/session.
struct SubscriptionRefreshFailureResult: Equatable, Sendable {
  let failure: SubscriptionRefreshFailure
  let credentialRollback: CredentialRollbackOutcome?
}

/// 非持久化的刷新回执。每次操作有独立身份，失败事实不含秘密值。
struct SubscriptionRefreshCompletion: Identifiable, Equatable {
  let id: UUID
  let completedAt: Date
  let failure: SubscriptionRefreshFailure?

  init(id: UUID = UUID(), completedAt: Date = Date(), failure: SubscriptionRefreshFailure? = nil) {
    self.id = id
    self.completedAt = completedAt
    self.failure = failure
  }
}

/// Commit failure at the subscription workflow seam. The underlying storage
/// error is intentionally reduced to a safe category, while the complete
/// rollback outcome remains available in memory for the current operation.
struct SubscriptionRefreshCommitError: Error, Equatable, Sendable {
  let category: SubscriptionRefreshFailure.CommitCategory
  let rollback: CredentialRollbackOutcome
}

extension SubscriptionRefreshFailure {
  /// Single workflow conversion point from transient refresh errors to durable
  /// safe facts. Presentation is intentionally not involved here.
  static func from(error: Error) -> Self {
    switch error {
    case let error as SubscriptionFetchError:
      return from(fetchError: error)
    case let error as SubscriptionParseError:
      return from(parseError: error)
    case let error as CredentialStoreError:
      let category: CredentialCategory
      switch error {
      case .keychainStatus(let status) where status == errSecItemNotFound:
        category = .missing
      default:
        category = .read
      }
      return .credential(category: category)
    case let error as SubscriptionFormError:
      if case .invalidURL = error { return .invalidURL }
      return .unknown
    case let error as SubscriptionRefreshCommitError:
      return .commit(
        category: error.category,
        rollback: rollbackStatus(for: error.rollback))
    default:
      return .unknown
    }
  }
}

/// 删除结果：被删节点身份集合。UI 据此清除失效选择（selection invalidation，
/// 不自动改选相邻节点，活动目标语义不受影响。
struct RemovalOutcome: Equatable, Sendable {
  let removedNodeIDs: Set<NodeID>
}

// MARK: - 表单级 typed error（本地化由 UI 呈现层负责）

/// 表单级校验失败（地址/端口/名称）；领域拒绝仍以 `CatalogError` 上抛。
enum ServerFormError: Error, Equatable {
  case invalidAddress
  case invalidPort
  case missingEncryptionMethod
  case unsupportedEncryptionMethod(String)
  case invalidPassword
  case emptyName
  /// 提交了有效目录之外的插件选择；拒绝陈旧或未知的表单选择。
  case pluginUnknown(String)
}

/// 订阅表单级失败（URL 门禁、订阅不存在）；获取/解析失败仍以原错误上抛。
enum SubscriptionFormError: Error, Equatable {
  case invalidURL
  case notFound
}

/// Safe load failure facts; no credential reference or underlying error detail escapes.
enum ServerFormLoadError: Error, Equatable {
  case credentialsUnavailable
  case notFound
}

/// Non-secret facts for rendering; options is always empty in this projection.
struct ServerFormPresentation: Equatable {
  let isEditable: Bool
  let plugin: PluginSectionState

  init(isEditable: Bool, plugin: PluginSectionState) {
    self.isEditable = isEditable
    var facts = plugin
    facts.options = ""
    self.plugin = facts
  }
}

/// 详情的已保存展示事实，参数明文通过独立读取 interface 装载。
struct ServerDetailPresentation {
  let name: String
  let address: String
  let port: Int
  let encryptionMethod: String
  let plugin: PluginSectionState
}
