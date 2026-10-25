import SwiftUI

extension ServersView {
  var sourceSidebar: some View {
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

  var serverTable: some View {
    let rows = workflow.tree.visibleRows(
      source: section.source ?? .manual, collapsed: expansion.collapsedGroupIDs
    )
    let depths = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.depth) })
    let activeAncestors = activeAncestorIDs
    return Table(
      of: CatalogTreeNode.self, selection: $selection
    ) {
      TableColumn("名称") { node in
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
            .help(Text(expansion.isCollapsed(node.id) ? LocalizedStringKey("展开") : "收起"))
          } else {
            Color.clear.frame(width: 24, height: 28)
          }
          ServerTableNameCell(
            node: node, activeTargetID: activeTargetID,
            containsActiveTarget: activeAncestors.contains(node.id))
        }
        .padding(.leading, CGFloat(depths[node.id] ?? 0) * 14)
      }
      .width(min: 160, ideal: 180)
      TableColumn("收藏") { node in
        Image(systemName: workflow.isFavorite(node.id) ? "star.fill" : "star")
          .accessibilityLabel(Text("收藏"))
          .accessibilityValue(Text(workflow.isFavorite(node.id) ? String(localized: "收藏") : "—"))
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
          description: section == .subscription
            ? Text("用工具栏的「添加订阅」按钮添加 HTTPS 订阅地址（SIP-008 JSON）")
            : Text("用工具栏的「新建服务器」按钮手动录入，或用「导入」菜单导入")
        )
        .allowsHitTesting(false)
      }
    }
  }

  @ViewBuilder
  func nodeContextMenu(_ ids: Set<NodeID>) -> some View {
    if let id = ids.first, let node = workflow.tree.node(withID: id) {
      nodeContextMenu(for: node, allowsSubscriptionManagement: false)
    }
  }

  @ViewBuilder
  func nodeContextMenu(
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
  func clearSelectionIfInvalidated(_ removed: Set<NodeID>) {
    if let selection, removed.contains(selection) {
      self.selection = nil
    }
  }

  /// 落点语义：分组行接收到自身，服务器行接收到所属组；行间接收到下一行所属组。
  /// 顶部/表尾空白接收到根。
  /// 资格事实由 seam 提供；跨来源/成环仍由领域拒绝（不变量防线）。
  func handleDrop(_ payload: [String], onto target: NodeID?) -> Bool {
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

  func exportConfigurationGroup(_ id: NodeID) {
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
