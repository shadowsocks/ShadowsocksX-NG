import Combine

/// 目录树折叠状态（纯窗口呈现状态）：组合根持有的长寿命对象。destination 切换
/// 会销毁分区子树里的 `@State`，折叠状态因此必须活在视图层级之外；服务器管理分区
/// 侧栏专用，首页另行持久化自己的状态。语义=收起的分组身份集合，
/// 缺省全部展开；不落盘，进程重启回全展开基线。
@MainActor
final class CatalogExpansionState: ObservableObject {
  @Published private(set) var collapsedGroupIDs: Set<NodeID> = []

  func isCollapsed(_ id: NodeID) -> Bool {
    collapsedGroupIDs.contains(id)
  }

  func toggleCollapsed(_ id: NodeID) {
    if collapsedGroupIDs.contains(id) {
      collapsedGroupIDs.remove(id)
    } else {
      collapsedGroupIDs.insert(id)
    }
  }

  /// 收起包含选中节点的组时，选择该组，避免详情指向隐藏的后代。
  func setExpanded(_ expanded: Bool, for group: CatalogTreeNode, selection: NodeID?) -> NodeID? {
    if expanded {
      collapsedGroupIDs.remove(group.id)
    } else {
      collapsedGroupIDs.insert(group.id)
      if let selection, selection != group.id, group.find(selection) != nil {
        return group.id
      }
    }
    return selection
  }

  /// 创建成功后仅展开祖先，保留其他分组的折叠状态。
  func reveal(_ id: NodeID, in tree: CatalogTreeSnapshot) {
    var parent = tree.node(withID: id)?.parentID
    while let current = parent {
      collapsedGroupIDs.remove(current)
      parent = tree.node(withID: current)?.parentID
    }
  }
}
