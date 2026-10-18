import Foundation

extension CatalogWorkflow {
  /// 手动节点和根层订阅组可复制；订阅子组不能将手动副本放入订阅父组。
  func canDuplicate(_ id: NodeID) -> Bool {
    guard let node = tree.node(withID: id) else { return false }
    return node.isManual || (node.isGroup && node.parentID == nil)
  }

  /// 同级快照复制：名称后缀由 UI 本地化，重名序号与事务由 module 处理。
  /// 目录提交后才返回新身份；运行时收敛沿用普通目录变更语义。
  func duplicate(_ id: NodeID, nameSuffix: String) async throws -> NodeID {
    let source = dependencies.coordinator.committedCatalog
    guard let entry = source.entry(for: id) else { throw CatalogError.nodeNotFound(id) }
    guard canDuplicate(id) else { throw CatalogError.subscriptionNodeImmutable(id) }
    let parent = try source.parentID(of: id)
    let siblings = try source.children(of: parent)
    guard let position = siblings.firstIndex(of: id) else { throw CatalogError.nodeNotFound(id) }
    let names = Set(siblings.compactMap { source.entry(for: $0)?.displayName })
    var base = "\(entry.displayName) \(nameSuffix)"
    var name = base
    var number = 2
    // 两种语言的已保存后缀都识别，切换语言后仍沿用原名称的复制序列。
    if let suffixRange = entry.displayName.range(
      of: #" (?:副本|Copy)(?: [0-9]+)?$"#, options: .regularExpression)
    {
      let suffix = entry.displayName[suffixRange].split(separator: " ")[0]
      base = "\(entry.displayName[..<suffixRange.lowerBound]) \(suffix)"
      name = "\(base) 2"
      number = 3
    }
    while names.contains(name) {
      name = "\(base) \(number)"
      number += 1
    }
    return try commit { catalog in
      try copyEntry(
        entry, from: source, into: &catalog, parent: parent,
        index: position + 1, name: name, now: Date())
    }
  }

  /// 副本节点获得全新身份与全新时间戳（创建时间 = 复制时刻，ADR-0031）；
  /// 每个新建节点的落点分组按结构敏感语义更新修改时间。
  private func copyEntry(
    _ entry: CatalogEntry, from source: ConfigurationCatalog,
    into catalog: inout ConfigurationCatalog, parent: NodeID?, index: Int? = nil,
    name: String, now: Date
  ) throws -> NodeID {
    switch entry.kind {
    case .server(var fields):
      fields.remark = name
      return try catalog.addServer(fields, to: parent, index: index, now: now)
    case .group(let fields):
      let copy = try catalog.addGroup(name, to: parent, index: index, now: now)
      for child in fields.children {
        guard let childEntry = source.entry(for: child) else {
          throw CatalogError.nodeNotFound(child)
        }
        _ = try copyEntry(
          childEntry, from: source, into: &catalog, parent: copy,
          name: childEntry.displayName, now: now)
      }
      return copy
    }
  }

}
