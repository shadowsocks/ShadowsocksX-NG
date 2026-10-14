import SwiftUI

/// Table 名称列：名称占剩余宽度，活动目标在列尾。
struct ServerTableNameCell: View {
  let node: CatalogTreeNode
  let activeTargetID: NodeID?

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: node.isGroup ? "folder" : "server.rack")
      Text(node.name)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(node.isInvalid ? .secondary : .primary)
      if node.isInvalid {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .help(
            node.invalidReasons.first.map {
              AppPresentation.message(
                for: ActivationFailure.invalidLeaf(node: node.id, reason: $0))
            } ?? "服务器存在已知阻塞问题")
      } else if node.invalidDescendantCount > 0 {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .help("包含 \(node.invalidDescendantCount) 个存在已知阻塞问题的服务器")
      }
      if activeTargetID == node.id {
        Image(systemName: "bolt.fill")
          .foregroundStyle(.orange)
          .help("活动目标")
      }
    }
    .frame(minHeight: 28)
  }

}

/// 行级右键菜单沿用目录工作流的命令与资格事实。
struct ServerNodeContextMenu: View {
  let node: CatalogTreeNode
  let workflow: CatalogWorkflow
  let allowsSubscriptionManagement: Bool
  /// 激活反馈共享状态：命令经它发出（单飞互斥、结果记录在会话反馈里）。
  let activation: ActivationFeedbackState
  let errors: ErrorAlertPresenter
  let onEdit: (NodeID) -> Void
  let onRename: (NodeID) -> Void
  let onNewGroup: (NodeID?) -> Void
  let onDuplicate: (NodeID) -> Void
  let onDelete: (NodeID) -> Void
  let onExport: (NodeID) -> Void

  private var isSubscription: Bool { node.source == .subscription }

  @ViewBuilder
  var body: some View {
    if let module = workflow.connectivity {
      ConnectivityTestButton(module: module, node: node)
    }
    Button("激活") {
      Task { @MainActor in
        do {
          let outcome = try await activation.activate(node.id, via: workflow)
          // 右键菜单即关、无内联反馈面：原子拒绝点名弹窗（typed 原因随
          // 结果返回）；单飞忽略（nil）不呈现。
          if case .rejectedActivation(let failure)? = outcome {
            errors.present(failure)
          }
        } catch {
          errors.present(error)
        }
      }
    }
    if node.isGroup {
      Divider()
      Button("导出为 SIP-008 JSON…") { onExport(node.id) }
        .disabled(!node.containsServerConfiguration)
    }
    Divider()
    Button {
      onDuplicate(node.id)
    } label: {
      Label("复制", systemImage: "plus.square.on.square")
    }
    .disabled(!workflow.canDuplicate(node.id))
    if !isSubscription {
      Divider()
      if node.isGroup {
        Button("重命名…") { onRename(node.id) }
      } else {
        Button("编辑…") { onEdit(node.id) }
      }
      Button("新建分组…") {
        onNewGroup(node.isGroup ? node.id : node.parentID)
      }
      Divider()
      Button("删除…", role: .destructive) {
        onDelete(node.id)
      }
    } else if allowsSubscriptionManagement, node.isRootSubscriptionGroup {
      Divider()
      Button("编辑 URL…") { onEdit(node.id) }
      Button("删除…", role: .destructive) {
        onDelete(node.id)
      }
    }
  }
}
