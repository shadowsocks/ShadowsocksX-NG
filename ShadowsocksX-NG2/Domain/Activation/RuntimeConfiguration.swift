/// 组激活时因已知本地阻塞问题被跳过的服务器。
struct SkippedServer: Equatable, Sendable {
  let id: NodeID
  let reason: LeafInvalidationReason
}

/// 激活产出：活动目标身份 + 完整派生文档。组目标保持组 UUID（GLOSSARY.md
/// 「Active target」），不被 sslocal 实际选中的后代替换。
struct RuntimeConfiguration: Equatable, Sendable {
  let targetID: NodeID
  let document: SslocalRuntimeDocument
  let skippedServers: [SkippedServer]

  init(
    targetID: NodeID,
    document: SslocalRuntimeDocument,
    skippedServers: [SkippedServer] = []
  ) {
    self.targetID = targetID
    self.document = document
    self.skippedServers = skippedServers
  }
}
