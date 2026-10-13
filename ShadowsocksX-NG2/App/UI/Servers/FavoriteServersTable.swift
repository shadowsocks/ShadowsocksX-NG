import SwiftUI
import UniformTypeIdentifiers

/// 浏览位置与节点来源分别表达；收藏可以同时包含两种来源。
enum ServerListSection: Hashable {
  case favorites
  case manual
  case subscription

  init(source: NodeSource) {
    self = source == .manual ? .manual : .subscription
  }

  var source: NodeSource? {
    switch self {
    case .favorites: nil
    case .manual: .manual
    case .subscription: .subscription
    }
  }
}

/// 平面收藏表只重排收藏；详情及节点命令仍使用原目录身份。
struct FavoriteServersTable<MenuContent: View>: View {
  @ObservedObject var workflow: CatalogWorkflow
  let activeTargetID: NodeID?
  @Binding var selection: NodeID?
  let errors: ErrorAlertPresenter
  @ViewBuilder let contextMenu: (Set<NodeID>) -> MenuContent
  @State private var dropState = ServerTableDropState()
  @FocusState private var isTableFocused: Bool

  var body: some View {
    let rows = workflow.favorites
    Table(of: CatalogTreeNode.self, selection: $selection) {
      TableColumn("名称") { node in
        ServerTableNameCell(node: node, activeTargetID: activeTargetID)
      }
      .width(min: 140, ideal: 200)
      TableColumn(ConnectivityCopy.text("响应延迟")) { node in
        if let module = workflow.connectivity {
          ConnectivityCell(module: module, node: node, workflow: workflow)
        }
      }
      .width(min: 90, ideal: 110)
      TableColumn("路径") { node in
        let path = path(for: node)
        Text(path)
          .lineLimit(1)
          .truncationMode(.tail)
          .help(path)
      }
      .width(min: 160, ideal: 300)
    } rows: {
      ForEach(rows) { node in
        TableRow(node)
          .itemProvider {
            dropState.provider(for: node.id, payload: node.id.rawValue)
          }
      }
      .onInsert(of: [.plainText]) { index, providers in
        insert(providers, at: index, in: rows.map(\.id))
      }
    }
    .focused($isTableFocused)
    .simultaneousGesture(TapGesture().onEnded { isTableFocused = true })
    .contextMenu(forSelectionType: NodeID.self, menu: contextMenu)
    .onKeyPress(.escape) {
      guard selection != nil else { return .ignored }
      selection = nil
      return .handled
    }
    .overlay {
      if rows.isEmpty {
        ContentUnavailableView("收藏", systemImage: "star")
          .allowsHitTesting(false)
      }
    }

  }

  private func path(for node: CatalogTreeNode) -> String {
    let source = node.source == .manual ? String(localized: "本地") : String(localized: "订阅")
    return ([source] + (workflow.tree.pathComponents(for: node.id) ?? [node.name]))
      .joined(separator: "/")
  }

  /// 原生 Table 的行间插入回调；仅接受本表发起的单节点拖动。
  private func insert(_ providers: [NSItemProvider], at index: Int, in ids: [NodeID]) {
    guard providers.count == 1, let provider = providers.first,
      let id = dropState.draggedID, ids.contains(id), (0...ids.count).contains(index)
    else { return }
    let target = ids.indices.contains(index) ? ids[index] : nil
    dropState.finishDrop()
    let typeIdentifier = UTType.plainText.identifier
    provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
      guard let data, String(data: data, encoding: .utf8) == id.rawValue else { return }
      Task { @MainActor in
        do {
          try workflow.moveFavorite(id, before: target)
        } catch {
          errors.present(error)
        }
      }
    }
  }
}
