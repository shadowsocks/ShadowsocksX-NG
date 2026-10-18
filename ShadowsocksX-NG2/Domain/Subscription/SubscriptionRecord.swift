import Foundation

/// 订阅源记录：持久不透明的订阅 UUID + 固定分组
/// 身份 + 订阅 URL + 最近刷新状态。URL 随服务器库整体加密；
/// 编辑 URL 保留订阅与固定分组身份。
struct SubscriptionRecord: Codable, Equatable, Sendable, Identifiable {
  /// 订阅源身份；删除后新建即新身份（GLOSSARY.md「Subscription」）。
  let id: NodeID
  /// 固定订阅分组的稳定身份（客户端所有，跨刷新与 URL 编辑不变）。
  let groupID: NodeID
  var url: String
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

/// 已解析为目录形态的订阅快照：身份已按订阅作用域限定，记录携带凭据值。
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
