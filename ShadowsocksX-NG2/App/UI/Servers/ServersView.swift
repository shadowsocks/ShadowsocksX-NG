import SwiftUI

/// 服务器目录、只读详情与分组命令；本视图持有新建／编辑 sheet 和确认弹窗。
/// selection 由主窗口绑定，订阅删除可清除失效选择。
struct ServersView: View {

  @ObservedObject var workflow: CatalogWorkflow
  /// 激活反馈共享状态（三激活入口共用，单飞互斥）：侧栏右键与分组详情的
  /// 激活命令都经它发出。
  let activation: ActivationFeedbackState
  /// 活动目标标记：父视图传入的运行时事实，不进目录 projection（与
  /// ServerTableNameCell/ServerDetailView 的传参先例同法）。
  let activeTargetID: NodeID?
  @Binding var selection: NodeID?
  @Binding var section: ServerListSection
  @Binding var sortOrder: [ServerTableSort]
  /// 服务器管理的展开状态跨工作区页面切换保留，不落盘。
  @ObservedObject var expansion: CatalogExpansionState
  let clipboard: any TextClipboard
  let imageClipboard: any ImageClipboard
  let configurationGroupFileExporter: any ConfigurationGroupFileExporter
  let qrImageSaver: any QrImageSaver

  /// 共享错误弹窗呈现（UI 持有；typed error → 本地化文案的呈现边缘）。
  /// 非 private：ServersView+Share.swift 扩展经它呈现分享失败。
  @StateObject var errors = ErrorAlertPresenter()

  // 纯窗口状态：selection/sheet/alert 不进目录 module。
  @State private var renameTarget: NodeID?
  @State private var newGroupParent: NodeID?
  @State private var isPresentingNewGroup = false
  @State private var serverFormOperation: ServerFormSheet.Operation?
  @State private var subscriptionEditTarget: SubscriptionSummary?
  @State private var deleteTarget: DeleteTarget?
  @State private var dropState = ServerTableDropState()
  @FocusState private var isServerTableFocused: Bool
  // 分享 popover 打开时冻结载荷、顶部资料与建议文件名。
  @State var shareContext: ShareContext?

  var body: some View {
    HSplitView {
      sourceSidebar
        .frame(minWidth: 120, idealWidth: 150, maxWidth: 200)
      // 保持分栏容器身份稳定，切换来源时只替换内部表格。
      ZStack(alignment: .topLeading) {
        if section == .favorites {
          FavoriteServersTable(
            workflow: workflow, activeTargetID: activeTargetID,
            selection: $selection, errors: errors, contextMenu: nodeContextMenu)
        } else {
          serverTable
        }
      }
      .toolbar { toolbarContent }
      .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity)
      // 分栏身份必须稳定；节点身份只重建内部详情会话，保留用户拖动后的宽度。
      ZStack(alignment: .topLeading) {
        serverDetailPane
      }
      .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minHeight: 420)
    .sheet(
      item: Binding(
        get: { renameTarget.map(NodeContext.init) },
        set: { renameTarget = $0?.nodeID })
    ) { context in
      RenameGroupSheet(workflow: workflow, errors: errors, nodeID: context.nodeID)
    }
    .sheet(isPresented: $isPresentingNewGroup) {
      NewGroupSheet(
        workflow: workflow, errors: errors, parent: newGroupParent,
        onCreated: selectCreatedNode)
    }
    .sheet(item: $subscriptionEditTarget) { summary in
      EditSubscriptionURLSheet(workflow: workflow, errors: errors, summary: summary)
    }
    .presentingErrors(errors)
    .confirmationDialog(
      deleteTitle,
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }),
      titleVisibility: .visible
    ) {
      Button(deleteConfirmationActionTitle, role: .destructive) { commitDelete() }
      Button("取消", role: .cancel) { deleteTarget = nil }
    } message: {
      Text(deleteMessage)
    }
    .sheet(item: $serverFormOperation) { operation in
      ServerFormSheet(
        workflow: workflow, operation: operation,
        onCreated: selectCreatedNode)
    }
    // 切换选中项时立即收起分享，避免显示旧服务器。
    .onChange(of: selection) {
      shareContext = nil
    }
    .onChange(of: workflow.favoriteIDs) {
      if section == .favorites, let selection, !workflow.isFavorite(selection) {
        self.selection = nil
      }
    }
    .onChange(of: workflow.tree) {
      if let selection, !workflow.tree.containsNode(selection) {
        self.selection = nil
      }
    }
  }

  private var sourceSidebar: some View {
    List(
      selection: Binding<ServerListSection?>(
        get: { section },
        set: { value in
          guard let value, value != section else { return }
          selection = nil
          section = value
        })
    ) {
      Label("收藏", systemImage: "star").tag(ServerListSection.favorites)
      Label("本地", systemImage: "internaldrive").tag(ServerListSection.manual)
      Label("订阅", systemImage: "arrow.triangle.2.circlepath").tag(ServerListSection.subscription)
    }
    .listStyle(.sidebar)
  }

  private var serverTable: some View {
    let rows = workflow.tree.visibleRows(
      source: section.source ?? .manual, sortedBy: sortOrder, collapsed: expansion.collapsedGroupIDs
    )
    let depths = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.depth) })
    return Table(
      of: CatalogTreeNode.self, selection: $selection,
      sortOrder: Binding(get: { sortOrder }, set: { sortOrder = Array($0.prefix(1)) })
    ) {
      TableColumn("名称", sortUsing: ServerTableSort(.name)) { node in
        HStack(spacing: 4) {
          if node.isGroup && !node.childNodes.isEmpty {
            Button {
              selection = expansion.setExpanded(
                expansion.isCollapsed(node.id), for: node, selection: selection)
            } label: {
              Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(expansion.isCollapsed(node.id) ? 0 : 90))
                .frame(minWidth: 24, minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expansion.isCollapsed(node.id) ? "展开" : "收起")
          } else {
            Color.clear.frame(width: 24, height: 28)
          }
          ServerTableNameCell(node: node, activeTargetID: activeTargetID)
        }
        .padding(.leading, CGFloat(depths[node.id] ?? 0) * 14)
      }
      .width(min: 160, ideal: 180)
      TableColumn("收藏") { node in
        Image(systemName: workflow.isFavorite(node.id) ? "star.fill" : "star")
          .accessibilityLabel(Text("收藏"))
          .accessibilityValue(Text(workflow.isFavorite(node.id) ? "收藏" : "—"))
      }
      .width(36)
      TableColumn(ConnectivityCopy.text("响应延迟")) { node in
        if let module = workflow.connectivity {
          ConnectivityCell(module: module, node: node, workflow: workflow)
        }
      }
      .width(min: 50, ideal: 60)
    } rows: {
      ForEach(rows) { row in
        TableRow(row.node)
          .contextMenu {
            nodeContextMenu(for: row.node, allowsSubscriptionManagement: section == .subscription)
          }
          .itemProvider {
            guard let payload = workflow.dragPayload(for: row.id) else { return nil }
            return dropState.provider(for: row.id, payload: payload)
          }
          .dropDestination(for: String.self) { payload in
            _ = handleDrop(payload, onto: ServerTableDropState.rowParent(for: row.node))
          }
      }
      .onInsert(of: [.plainText]) { index, providers in
        guard section == .manual, (0...rows.count).contains(index) else { return }
        let parent = ServerTableDropState.insertionParent(at: index, in: rows)
        dropState.loadPayload(providers) { _ = handleDrop($0, onto: parent) }
      }
    }
    .focused($isServerTableFocused)
    .simultaneousGesture(
      TapGesture().onEnded {
        if !isServerTableFocused { isServerTableFocused = true }
      }
    )
    .onKeyPress(.escape) {
      guard selection != nil else { return .ignored }
      selection = nil
      return .handled
    }
    .overlay {
      if rows.isEmpty {
        ContentUnavailableView(
          "暂无服务器", systemImage: "server.rack",
          description: Text("用工具栏的「新建服务器」按钮手动录入，或用「导入」菜单导入")
        )
        .allowsHitTesting(false)
      }
    }
  }

  @ViewBuilder
  private func nodeContextMenu(_ ids: Set<NodeID>) -> some View {
    if let id = ids.first, let node = workflow.tree.node(withID: id) {
      nodeContextMenu(for: node, allowsSubscriptionManagement: false)
    }
  }

  @ViewBuilder
  private func nodeContextMenu(
    for node: CatalogTreeNode, allowsSubscriptionManagement: Bool
  ) -> some View {
    ServerNodeContextMenu(
      node: node, workflow: workflow, allowsSubscriptionManagement: allowsSubscriptionManagement,
      activation: activation, errors: errors,
      onEdit: presentEditNode, onRename: { renameTarget = $0 },
      onNewGroup: presentNewGroup, onDuplicate: duplicateNode,
      onDelete: {
        requestDelete($0, allowsSubscriptionManagement: allowsSubscriptionManagement)
      }, onExport: exportConfigurationGroup)
  }

  /// 删除结果 → selection invalidation：仅清除失效选择，不自动
  /// 改选相邻节点。
  private func clearSelectionIfInvalidated(_ removed: Set<NodeID>) {
    if let selection, removed.contains(selection) {
      self.selection = nil
    }
  }

  /// 落点语义：分组行接收到自身，服务器行接收到所属组；行间接收到下一行所属组。
  /// 顶部/表尾空白接收到根。
  /// 资格事实由 seam 提供；跨来源/成环仍由领域拒绝（不变量防线）。
  private func handleDrop(_ payload: [String], onto target: NodeID?) -> Bool {
    guard section == .manual, payload.count == 1, let raw = payload.first,
      let dragged = dropState.draggedID, raw == dragged.rawValue,
      workflow.canMove(dragged, to: target)
    else { return false }
    dropState.finishDrop()
    Task {
      do {
        try await workflow.move(dragged, to: target)
        selectCreatedNode(dragged)
      } catch {
        errors.present(error)
      }
    }
    return true
  }

  private func exportConfigurationGroup(_ id: NodeID) {
    switch ConfigurationGroupExportAction(
      workflow: workflow, exporter: configurationGroupFileExporter
    ).perform(for: id) {
    case .preparationFailed(let failure):
      errors.present(failure)
    case .cancelled, .saved:
      break
    case .exportFailed(let failure):
      errors.present(failure)
    }
  }
}

extension ServersView {
  // MARK: - 详情区

  @ViewBuilder
  private var serverDetailPane: some View {
    if let id = selection, let node = workflow.tree.node(withID: id) {
      CatalogNodeDetailView(
        workflow: workflow, activation: activation, nodeID: node.id,
        isActiveTarget: activeTargetID == id, errors: errors
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
  private var toolbarContent: some ToolbarContent {
    if let module = workflow.connectivity {
      ToolbarItem(placement: .primaryAction) {
        ConnectivityBatchButton(
          module: module, targets: workflow.connectivityTargets(source: section.source))
      }
    }
    if section != .favorites {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker(
            "排序",
            selection: Binding<ServerTableSort.Field?>(
              get: { sortOrder.first?.field },
              set: { field in sortOrder = field.map { [ServerTableSort($0)] } ?? [] })
          ) {
            Text("无").tag(nil as ServerTableSort.Field?)
            Text("名称").tag(ServerTableSort.Field.name as ServerTableSort.Field?)
            Text("创建时间").tag(ServerTableSort.Field.createdAt as ServerTableSort.Field?)
            Text("修改时间").tag(ServerTableSort.Field.updatedAt as ServerTableSort.Field?)
          }
          .pickerStyle(.inline)
        } label: {
          Label("排序", systemImage: "arrow.up.arrow.down")
        }
        .labelStyle(.iconOnly)
        .help("排序")
      }
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
  private var canDeleteSelection: Bool {
    guard let selection, let node = workflow.tree.node(withID: selection) else { return false }
    if section == .subscription, node.isRootSubscriptionGroup {
      return subscriptionSummary(forRootGroup: selection) != nil
    }
    return workflow.canDelete(selection)
  }

  private var canEditSelection: Bool {
    guard let selection, let node = workflow.tree.node(withID: selection) else { return false }
    if section == .subscription, node.isRootSubscriptionGroup {
      return subscriptionSummary(forRootGroup: selection) != nil
    }
    return workflow.serverFormPresentation(for: selection)?.isEditable == true
  }

  private var toolbarEditTitle: String {
    guard section == .subscription, let selection,
      workflow.tree.node(withID: selection)?.isRootSubscriptionGroup == true
    else { return "编辑服务器" }
    return "编辑 URL…"
  }

  private func subscriptionSummary(forRootGroup id: NodeID) -> SubscriptionSummary? {
    workflow.subscriptions.first { $0.groupID == id }
  }

  private func requestDelete(_ id: NodeID, allowsSubscriptionManagement: Bool) {
    guard let node = workflow.tree.node(withID: id) else { return }
    if allowsSubscriptionManagement, node.isRootSubscriptionGroup,
      let summary = subscriptionSummary(forRootGroup: id)
    {
      deleteTarget = .subscription(summary)
    } else if workflow.canDelete(id) {
      deleteTarget = .node(id)
    }
  }

  private func presentNewGroup(in parent: NodeID?) {
    newGroupParent = parent
    isPresentingNewGroup = true
  }

  private func presentNewServer(in parent: NodeID?) {
    serverFormOperation = .create(parent: parent)
  }

  private func presentEditServer(_ id: NodeID) {
    guard workflow.serverFormPresentation(for: id)?.isEditable == true else { return }
    serverFormOperation = .edit(id)
  }

  private func presentEditNode(_ id: NodeID) {
    guard let node = workflow.tree.node(withID: id) else { return }
    if node.isRootSubscriptionGroup,
      let summary = subscriptionSummary(forRootGroup: id)
    {
      subscriptionEditTarget = summary
    } else {
      presentEditServer(id)
    }
  }

  private func selectCreatedNode(_ id: NodeID) {
    section = .manual
    expansion.reveal(id, in: workflow.tree)
    selection = id
  }

  private func duplicateNode(_ id: NodeID) {
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
  private var deleteTitle: String {
    switch deleteTarget {
    case .some(.subscription(let summary)):
      return SubscriptionDeletionConfirmation.title(for: summary.name)
    case .some(.node(let id)):
      let name = workflow.displayName(for: id)
      switch workflow.deleteFacts(for: id) {
      case .subtree:
        return "删除分组「\(name)」及其整棵子树？"
      case .leaf, .emptyGroup, nil:
        return "删除「\(name)」？"
      }
    case .none:
      return ""
    }
  }

  private var deleteMessage: String {
    switch deleteTarget {
    case .some(.subscription):
      return SubscriptionDeletionConfirmation.message
    case .some(.node(let id)):
      switch workflow.deleteFacts(for: id) {
      case .subtree(let count, let includesCredentials):
        if includesCredentials {
          return "将递归删除 \(count) 个节点（含其中的服务器与凭据），此操作不可撤销。"
        }
        return "将递归删除 \(count) 个节点，此操作不可撤销。"
      case .leaf, .emptyGroup, nil:
        return "此操作不可撤销。"
      }
    case .none:
      return ""
    }
  }

  private var deleteConfirmationActionTitle: String {
    if case .some(.subscription) = deleteTarget {
      return SubscriptionDeletionConfirmation.actionTitle
    }
    return "删除"
  }

  private func commitDelete() {
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
private struct NodeContext: Identifiable {
  let nodeID: NodeID
  var id: NodeID { nodeID }
}

private enum DeleteTarget {
  case node(NodeID)
  case subscription(SubscriptionSummary)
}
