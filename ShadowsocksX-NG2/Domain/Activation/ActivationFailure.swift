/// 激活失败的点名原因：激活被拒与活动目标清除
/// 停止共用同一套原因：前者状态完全不动，后者清除目标并发出停止意图。
enum ActivationFailure: Error, Equatable, Sendable {
  /// Enable was requested without a selected target.
  case noActiveTarget
  /// 活动目标已被删除（或从未存在）。
  case targetNotFound(NodeID)
  /// 组目标展开后没有可激活的服务器叶子（空组或全部候选无效）。
  case targetExpandsToNothing(NodeID)
  /// 展开结果包含无效叶子；携带叶节点与具体原因，激活整体原子拒绝。
  case invalidLeaf(node: NodeID, reason: LeafInvalidationReason)
}

/// 服务器叶子无效的具体原因（点名到可行动的事实）。
enum LeafInvalidationReason: Error, Equatable, Sendable {
  /// 地址为空或只有空白。
  case invalidAddress
  /// 端口不在 1–65535 范围内。
  case invalidPort(Int)
  /// 加密方式为空。
  case missingEncryptionMethod
  /// 加密方式非空但不在当前 sslocal 能力目录中。
  case unsupportedEncryptionMethod(String)
  /// 引用本版本未提供的插件程序；受管插件集合来自供应链清单。
  case pluginNotProvided(program: String)
  /// 服务器密码为空。
  case missingPassword
}
