import Foundation

/// 目录政策查询与激活命令：删除确认档位、拖放资格
/// 与激活资格/命令的唯一 UI-facing 出口。视图不得重推 ownership、删除确认或
/// ADR-0001 激活预检；领域拒绝仍是不变量防线。
extension CatalogWorkflow {
  // MARK: - 删除确认事实

  /// 删除资格（命令入口的统一 disable 判据，如分区工具栏删除钮）：节点存在
  /// 且来源为 manual。订阅节点结构只读（GLOSSARY.md），其移除属订阅分区流程，
  /// 不经此口径。
  func canDelete(_ id: NodeID) -> Bool {
    guard let node = tree.node(withID: id) else { return false }
    return node.isManual
  }

  /// 删除确认档位（GLOSSARY.md：空手动组/服务器单次；非空手动组二次并点名规模）。
  /// 节点不存在时为 `nil`。
  func deleteFacts(for id: NodeID) -> DeleteConfirmKind? {
    guard let node = tree.node(withID: id) else { return nil }
    guard node.isGroup, node.isManual else { return .leaf }
    if node.childNodes.isEmpty { return .emptyGroup }
    return .subtree(
      count: node.subtreeNodeCount,
      includesCredentials: subtreeHasServers(node))
  }

  private func subtreeHasServers(_ node: CatalogTreeNode) -> Bool {
    if !node.isGroup { return true }
    return node.childNodes.contains { subtreeHasServers($0) }
  }

  // MARK: - 拖放资格

  /// 移动/落点资格：存在性、非自身、被拖节点可拖、目标为根或不在被拖子树内
  /// 的手动组；同父落点不提供重排。跨来源与成环仍由领域拒绝。
  func canMove(_ id: NodeID, to parent: NodeID?) -> Bool {
    guard let node = tree.node(withID: id) else { return false }
    guard id != parent, node.parentID != parent else { return false }
    guard node.isManual else { return false }
    guard let parent else { return true }
    guard let parentNode = tree.node(withID: parent), parentNode.isGroup, parentNode.isManual else {
      return false
    }
    return !node.subtreeIDs.contains(parent)
  }

  /// 拖拽载荷：手动节点携带身份；订阅节点结构只读，返回 `nil`（空载荷）。
  func dragPayload(for id: NodeID) -> String? {
    guard let node = tree.node(withID: id), node.isManual else { return nil }
    return id.rawValue
  }

  // MARK: - 激活资格与命令

  /// 激活资格（点前门禁，ADR-0001）：空组与无 candidate 原子不可激活；
  /// 组内已知无效叶子计入跳过数。
  func activationEligibility(for id: NodeID) -> ActivationEligibility? {
    guard let node = tree.node(withID: id) else { return nil }
    if node.isGroup {
      if node.childNodes.isEmpty {
        return ActivationEligibility(
          canActivate: false, candidateCount: 0, skippedInvalidCount: 0,
          ineligibility: .emptyGroup)
      }
      var candidateCount = 0
      var skipped = 0
      countEligibility(of: node, candidates: &candidateCount, skipped: &skipped)
      if candidateCount == 0 {
        return ActivationEligibility(
          canActivate: false, candidateCount: 0, skippedInvalidCount: skipped,
          ineligibility: .noCandidates)
      }
      return ActivationEligibility(
        canActivate: true, candidateCount: candidateCount, skippedInvalidCount: skipped,
        ineligibility: nil)
    }
    if node.isInvalid {
      return ActivationEligibility(
        canActivate: false, candidateCount: 0, skippedInvalidCount: 1,
        ineligibility: .noCandidates)
    }
    return ActivationEligibility(
      canActivate: true, candidateCount: 1, skippedInvalidCount: 0, ineligibility: nil)
  }

  private func countEligibility(
    of node: CatalogTreeNode,
    candidates: inout Int,
    skipped: inout Int
  ) {
    if !node.isGroup {
      if node.isInvalid {
        skipped += 1
      } else {
        candidates += 1
      }
      return
    }
    for child in node.childNodes {
      countEligibility(of: child, candidates: &candidates, skipped: &skipped)
    }
  }

  /// 激活命令（typed command surface）：经 `Activating` port 发出；编排与
  /// 运行时收敛留在 port 背后。意外错误 throws。
  func activate(_ id: NodeID) async throws -> ActivationCommandOutcome {
    try await dependencies.activator.activate(id)
  }
}
