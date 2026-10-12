/// 目录操作失败原因，逐项对应 GLOSSARY.md 的结构不变量（单父、显子序、
/// 无环、手动/订阅严格分离）。
enum CatalogError: Error, Equatable, Sendable {
  /// 目标节点不存在。
  case nodeNotFound(NodeID)
  /// 指定的父容器不存在。
  case parentNotFound(NodeID)
  /// 指定的父容器不是分组（例如把服务器叶子当容器）。
  case parentNotAGroup(NodeID)
  /// 操作目标不是服务器叶子。
  case notAServer(NodeID)
  /// 操作目标不是分组。
  case notAGroup(NodeID)
  /// 目标身份已被挂载的节点占用：身份不复用于另一逻辑节点，否则即共享父。
  case duplicateID(NodeID)
  /// 手动与订阅来源严格分离：不允许把节点放进另一来源的子树。
  case crossSourcePlacement(node: NodeSource, container: NodeSource)
  /// 订阅子树由远端权威所有：本地结构操作（移动/删除/改连接字段/改名）一律拒绝；
  /// 整棵订阅子树只能通过移除订阅源清理。
  case subscriptionNodeImmutable(NodeID)
  /// 订阅服务器叶子必须位于其订阅固定分组内，不得直挂目录根（GLOSSARY.md
  /// 「Subscription group」：根层只允许订阅固定分组本身）。
  case subscriptionServerAtRoot(NodeID)
  /// 把分组移动进它自己的子树会成环。
  case cycleDetected(NodeID)
  /// 插入位置超出目标容器允许范围（0…=子节点数；以摘除移动节点后的子序计）。
  case indexOutOfRange(parent: NodeID?, index: Int?, childCount: Int)
  /// 外部载荷（持久化文件）结构不一致：悬空子引用、共享父、成环或不可达节点。
  case invalidStructure(String)
}
