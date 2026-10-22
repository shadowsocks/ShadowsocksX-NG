import Combine
import Foundation

/// 首页专用的窗口浏览状态。只持久化模式与展开身份，选择及首次定位属于窗口会话。
@MainActor
final class HomeTargetBrowser: ObservableObject {
  enum Mode: String { case all, favorites }

  @Published private(set) var selection: NodeID?
  @Published private(set) var expandedGroupIDs: Set<NodeID>
  @Published private(set) var mode: Mode
  private var enteredHome = false
  private let defaults: UserDefaults
  private static let expansionKey = "homeTarget.expandedGroups"
  private static let modeKey = "homeTarget.mode"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    expandedGroupIDs = Set(
      (defaults.stringArray(forKey: Self.expansionKey) ?? []).map { NodeID(rawValue: $0) })
    mode = Mode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .all
  }

  func rows(in tree: CatalogTreeSnapshot, favorites: [CatalogTreeNode]) -> [CatalogTreeRow] {
    if mode == .favorites {
      return favorites.map { CatalogTreeRow(node: $0, depth: 0) }
    }
    let groups = Set(tree.visibleRows(collapsed: []).filter(\.node.isGroup).map(\.id))
    return tree.visibleRows(collapsed: groups.subtracting(expandedGroupIDs))
  }

  func select(_ id: NodeID?) { selection = id }

  func reconcile(in tree: CatalogTreeSnapshot, favorites: [CatalogTreeNode]) {
    let groups = Set(tree.visibleRows(collapsed: []).filter(\.node.isGroup).map(\.id))
    expandedGroupIDs.formIntersection(groups)
    persistExpansion()
    clearHiddenSelection(in: tree, favorites: favorites)
  }

  func setMode(_ mode: Mode, in tree: CatalogTreeSnapshot, favorites: [CatalogTreeNode]) {
    self.mode = mode
    defaults.set(mode.rawValue, forKey: Self.modeKey)
    clearHiddenSelection(in: tree, favorites: favorites)
  }

  func toggleGroup(_ id: NodeID, in tree: CatalogTreeSnapshot) {
    guard let group = tree.node(withID: id), group.isGroup else { return }
    if expandedGroupIDs.remove(id) == nil {
      expandedGroupIDs.insert(id)
    } else if let selection, selection != id, group.find(selection) != nil {
      self.selection = id
    }
    persistExpansion()
  }

  /// 仅首次进入自动定位；返回滚动目标，后续切页不改变浏览位置。
  @discardableResult
  func enterHome(
    current: NodeID?, in tree: CatalogTreeSnapshot, favorites: [CatalogTreeNode]
  ) -> NodeID? {
    guard !enteredHome else { return nil }
    enteredHome = true
    return locate(current, in: tree, favorites: favorites)
  }

  @discardableResult
  func locate(
    _ current: NodeID?, in tree: CatalogTreeSnapshot, favorites: [CatalogTreeNode]
  ) -> NodeID? {
    guard let current, tree.containsNode(current) else { return nil }
    if mode == .favorites, !favorites.contains(where: { $0.id == current }) {
      setMode(.all, in: tree, favorites: favorites)
    }
    selection = current
    var parent = tree.node(withID: current)?.parentID
    while let id = parent {
      expandedGroupIDs.insert(id)
      parent = tree.node(withID: id)?.parentID
    }
    persistExpansion()
    return current
  }

  private func clearHiddenSelection(in tree: CatalogTreeSnapshot, favorites: [CatalogTreeNode]) {
    if let selection, !rows(in: tree, favorites: favorites).contains(where: { $0.id == selection })
    {
      self.selection = nil
    }
  }

  private func persistExpansion() {
    defaults.set(expandedGroupIDs.map(\.rawValue).sorted(), forKey: Self.expansionKey)
  }
}
