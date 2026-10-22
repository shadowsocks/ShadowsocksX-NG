import SwiftUI

extension ServersView {
  // MARK: - 详情区

  @ViewBuilder
  var serverDetailPane: some View {
    if let id = selection, let node = workflow.tree.node(withID: id) {
      CatalogNodeDetailView(
        workflow: workflow, activation: activation, nodeID: node.id,
        isActiveTarget: activeTargetID == id,
        containsActiveTarget: activeAncestorIDs.contains(id),
        errors: errors
      )
      .id(id)
    } else {
      ContentUnavailableView(
        "未选择节点", systemImage: "sidebar.left",
        description: Text("在左侧选择服务器或分组查看详情"))
    }
  }

  // MARK: - 工具栏（新建服务器 / 新建分组 / 分享）

  @ToolbarContentBuilder
  var toolbarContent: some ToolbarContent {
    if section == .manual {
      ToolbarItem(placement: .primaryAction) {
        Button {
          presentNewServer(in: workflow.importTargetParent(for: selection))
        } label: {
          Label("新建服务器", systemImage: "plus")
        }
        .help("新建服务器")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          presentNewGroup(in: workflow.importTargetParent(for: selection))
        } label: {
          Label("新建分组", systemImage: "folder.badge.plus")
        }
        .help("新建分组")
      }
    } else if section == .subscription {
      ToolbarItem(placement: .primaryAction) {
        Button("添加订阅", systemImage: "plus") {
          isPresentingAddSubscription = true
        }
        .help("添加订阅")
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        if let selection { presentEditNode(selection) }
      } label: {
        Label(toolbarEditTitle, systemImage: "pencil")
      }
      .labelStyle(.iconOnly)
      .help(toolbarEditTitle)
      .disabled(!canEditSelection)
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        if let selection { duplicateNode(selection) }
      } label: {
        Label("复制", systemImage: "plus.square.on.square")
      }
      .help("复制")
      .disabled(selection.map(workflow.canDuplicate) != true)
    }
    // 删除：手动节点走目录政策；订阅根组走订阅管理。
    ToolbarItem(placement: .primaryAction) {
      Button {
        if let selection {
          requestDelete(selection, allowsSubscriptionManagement: section == .subscription)
        }
      } label: {
        Label("删除", systemImage: "trash")
      }
      .help("删除")
      .disabled(!canDeleteSelection)
    }
    // 分享选中的服务器或非空配置组，分别显示二维码或文件/URI 列表操作。
    ToolbarItem(placement: .primaryAction) {
      Button {
        presentShare()
      } label: {
        Label("分享", systemImage: "square.and.arrow.up")
      }
      .help("分享")
      .disabled(!canShareSelection)
      .popover(item: $shareContext, arrowEdge: .top) { context in
        switch context {
        case .server(let server):
          ShareServerPopover(
            payload: server.payload,
            presentation: server.presentation,
            suggestedFileName: server.suggestedFileName,
            imageClipboard: imageClipboard,
            textClipboard: clipboard,
            saver: qrImageSaver,
            errors: errors)
        case .group(let group):
          ShareGroupPopover(
            context: group, exporter: configurationGroupFileExporter,
            clipboard: clipboard, errors: errors)
        }
      }
    }
  }

  // MARK: - 告警动作

  /// 工具栏删除钮仅对手动节点和订阅根组启用。
  var canDeleteSelection: Bool {
    guard let selection, let node = workflow.tree.node(withID: selection) else { return false }
    if section == .subscription, node.isRootSubscriptionGroup {
      return subscriptionSummary(forRootGroup: selection) != nil
    }
    return workflow.canDelete(selection)
  }

  var canEditSelection: Bool {
    guard let selection, let node = workflow.tree.node(withID: selection) else { return false }
    if section == .subscription, node.isRootSubscriptionGroup {
      return subscriptionSummary(forRootGroup: selection) != nil
    }
    return workflow.serverFormPresentation(for: selection)?.isEditable == true
  }

  var toolbarEditTitle: String {
    guard section == .subscription, let selection,
      workflow.tree.node(withID: selection)?.isRootSubscriptionGroup == true
    else { return String(localized: "编辑服务器") }
    return String(localized: "编辑 URL…")
  }

  func subscriptionSummary(forRootGroup id: NodeID) -> SubscriptionSummary? {
    workflow.subscriptions.first { $0.groupID == id }
  }

  func requestDelete(_ id: NodeID, allowsSubscriptionManagement: Bool) {
    guard let node = workflow.tree.node(withID: id) else { return }
    if allowsSubscriptionManagement, node.isRootSubscriptionGroup,
      let summary = subscriptionSummary(forRootGroup: id)
    {
      deleteTarget = .subscription(summary)
    } else if workflow.canDelete(id) {
      deleteTarget = .node(id)
    }
  }

  func presentNewGroup(in parent: NodeID?) {
    newGroupParent = parent
    isPresentingNewGroup = true
  }

  func presentNewServer(in parent: NodeID?) {
    serverFormOperation = .create(parent: parent)
  }

  func presentEditServer(_ id: NodeID) {
    guard workflow.serverFormPresentation(for: id)?.isEditable == true else { return }
    serverFormOperation = .edit(id)
  }

  func presentEditNode(_ id: NodeID) {
    guard let node = workflow.tree.node(withID: id) else { return }
    if node.isRootSubscriptionGroup,
      let summary = subscriptionSummary(forRootGroup: id)
    {
      subscriptionEditTarget = summary
    } else {
      presentEditServer(id)
    }
  }

  func selectCreatedNode(_ id: NodeID) {
    section = .manual
    expansion.reveal(id, in: workflow.tree)
    selection = id
  }

  func duplicateNode(_ id: NodeID) {
    Task {
      do {
        let copy = try await workflow.duplicate(id, nameSuffix: String(localized: "副本"))
        selectCreatedNode(copy)
      } catch {
        errors.present(error)
      }
    }
  }

  /// 删除确认文案：档位与规模事实来自 seam；句子由 UI 拼（Q3-A）。
  var deleteTitle: String {
    switch deleteTarget {
    case .some(.subscription(let summary)):
      return SubscriptionDeletionConfirmation.title(for: summary.name)
    case .some(.node(let id)):
      let name = workflow.displayName(for: id)
      switch workflow.deleteFacts(for: id) {
      case .subtree:
        return String(localized: "删除分组「\(name)」及其整棵子树？")
      case .leaf, .emptyGroup, nil:
        return String(localized: "删除「\(name)」？")
      }
    case .none:
      return ""
    }
  }

  var deleteMessage: String {
    switch deleteTarget {
    case .some(.subscription):
      return SubscriptionDeletionConfirmation.message
    case .some(.node(let id)):
      switch workflow.deleteFacts(for: id) {
      case .subtree(let count, let includesCredentials):
        if includesCredentials {
          return String(localized: "将递归删除 \(count) 个节点（含其中的服务器与凭据），此操作不可撤销。")
        }
        return String(localized: "将递归删除 \(count) 个节点，此操作不可撤销。")
      case .leaf, .emptyGroup, nil:
        return String(localized: "此操作不可撤销。")
      }
    case .none:
      return ""
    }
  }

  var deleteConfirmationActionTitle: String {
    if case .some(.subscription) = deleteTarget {
      return SubscriptionDeletionConfirmation.actionTitle
    }
    return String(localized: "删除")
  }

  func commitDelete() {
    guard let target = deleteTarget else { return }
    deleteTarget = nil
    Task {
      do {
        let outcome: RemovalOutcome
        switch target {
        case .node(let id):
          outcome = try await workflow.remove(id)
        case .subscription(let summary):
          outcome = try await workflow.removeSubscription(summary.id)
        }
        clearSelectionIfInvalidated(outcome.removedNodeIDs)
      } catch {
        errors.present(error)
      }
    }
  }
}

/// renameTarget 的 sheet(item:) 适配壳。
