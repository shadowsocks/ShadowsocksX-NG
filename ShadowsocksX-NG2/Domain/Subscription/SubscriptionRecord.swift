import Foundation

/// 订阅源记录：持久不透明的订阅 UUID + 固定分组
/// 身份 + 订阅 URL 凭据引用 + 最近刷新状态。URL 是敏感信息，权威副本在凭据
/// 存储，目录文档只持引用；编辑 URL 保留订阅与固定分组身份。
struct SubscriptionRecord: Codable, Equatable, Sendable, Identifiable {
  /// 订阅源身份；删除后新建即新身份（GLOSSARY.md「Subscription」）。
  let id: NodeID
  /// 固定订阅分组的稳定身份（客户端所有，跨刷新与 URL 编辑不变）。
  let groupID: NodeID
  var urlRef: CredentialReference
  var status: SubscriptionRefreshStatus
  /// 最近成功提交的白名单资料；成功响应省略时清除，失败或取消保留。
  var information: SubscriptionInformation?
  /// 独立于最近尝试状态，旧文件缺失时不猜测。
  var lastSucceededAt: Date?
}

/// 最近一次刷新结果。失败只保存白名单事实，不保存订阅 URL、秘密、凭据引用
/// 或任意错误 description（均需脱敏）。
enum SubscriptionRefreshStatus: Codable, Equatable, Sendable {
  case never
  // swiftlint:disable:next identifier_name
  case succeeded(at: Date)
  // swiftlint:disable:next identifier_name
  case failed(at: Date, failure: SubscriptionRefreshFailure)

  private enum CodingKeys: String, CodingKey {
    case never
    case succeeded
    case failed
  }

  private struct SucceededPayload: Codable {
    // swiftlint:disable:next identifier_name
    let at: Date
  }

  private struct FailedPayload: Codable {
    // swiftlint:disable:next identifier_name
    let at: Date
    let failure: SubscriptionRefreshFailure?
    let reason: String?
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.never) {
      self = .never
      return
    }
    if let payload = try container.decodeIfPresent(SucceededPayload.self, forKey: .succeeded) {
      self = .succeeded(at: payload.at)
      return
    }
    if let payload = try container.decodeIfPresent(FailedPayload.self, forKey: .failed) {
      // v4 uses typed facts. v1-v3 may contain only a rendered reason; loading it
      // preserves failed status while deliberately discarding the old detail.
      self = .failed(at: payload.at, failure: payload.failure ?? .legacy)
      return
    }
    throw DecodingError.dataCorruptedError(
      forKey: .never, in: container, debugDescription: "unknown refresh status")
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .never:
      try container.encode([String: String](), forKey: .never)
    case .succeeded(let at):  // swiftlint:disable:this identifier_name
      try container.encode(SucceededPayload(at: at), forKey: .succeeded)
    case .failed(let at, let failure):  // swiftlint:disable:this identifier_name
      try container.encode(FailedPayload(at: at, failure: failure, reason: nil), forKey: .failed)
    }
  }
}

/// 配置目录持久化文档：结构树、订阅源记录与有序收藏一次原子落盘，
/// 保证「订阅记录 ↔ 固定分组子树」跨文档一致。
struct CatalogDocument: Equatable, Sendable {
  var catalog: ConfigurationCatalog
  var subscriptions: [SubscriptionRecord]
  var favoriteIDs: [NodeID]

  init(
    catalog: ConfigurationCatalog = ConfigurationCatalog(),
    subscriptions: [SubscriptionRecord] = [],
    favoriteIDs: [NodeID] = []
  ) {
    self.catalog = catalog
    self.subscriptions = subscriptions
    self.favoriteIDs = favoriteIDs
  }
}

/// 已解析为目录形态的订阅快照：身份已按订阅作用域限定、凭据引用已分配
/// （服务层在提交前把明文密码写入凭据存储并构造 `ServerFields`）。
/// `root` 是固定分组的内容来源；固定分组自身身份由应用入口的 `groupID`
/// 决定（客户端所有），`root.id` 不参与挂载。
struct CatalogSubscriptionSnapshot: Equatable, Sendable {
  struct ServerLeaf: Equatable, Sendable {
    let id: NodeID
    var fields: ServerFields
  }

  /// 有序子引用：顺序即快照（远端权威）的用户可见顺序。
  enum Child: Equatable, Sendable {
    case group(Group)
    case server(ServerLeaf)
  }

  struct Group: Equatable, Sendable {
    let id: NodeID
    let name: String
    var children: [Child]
  }

  /// 固定分组显示名：远端根分组名，扩展缺失时为 URL host。
  let name: String
  let root: Group
}
