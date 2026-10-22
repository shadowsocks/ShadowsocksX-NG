import AppKit
import UniformTypeIdentifiers

/// 原生 Table 拖放使用系统字符串表示；接收方仍校验本表拖动的节点身份。
@MainActor
final class ServerTableDropState {
  private(set) var draggedID: NodeID?

  func provider(for id: NodeID, payload: String) -> NSItemProvider {
    draggedID = id
    return NSItemProvider(object: payload as NSString)
  }

  func loadPayload(_ providers: [NSItemProvider], action: @escaping @MainActor ([String]) -> Void) {
    guard providers.count == 1, let provider = providers.first, let expected = draggedID else {
      return
    }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
      guard let data, String(data: data, encoding: .utf8) == expected.rawValue else { return }
      Task { @MainActor in
        guard self.draggedID == expected else { return }
        action([expected.rawValue])
      }
    }
  }

  /// 分组行接收到自身；服务器行接收到其所属分组（根层服务器对应根层）。
  static func rowParent(for node: CatalogTreeNode) -> NodeID? {
    node.isGroup ? node.id : node.parentID
  }

  /// 插入线位于下一行的同级容器内；顶部和表尾空白表示根层。
  static func insertionParent(at index: Int, in rows: [CatalogTreeRow]) -> NodeID? {
    guard rows.indices.contains(index) else { return nil }
    return rows[index].node.parentID
  }

  func finishDrop() { draggedID = nil }
}
