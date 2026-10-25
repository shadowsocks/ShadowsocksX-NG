import Foundation

extension CatalogWorkflow {
  /// 行显示名（导航标题、重命名预填等）；节点不存在为空串。
  func displayName(for id: NodeID) -> String {
    dependencies.coordinator.committedCatalog.entry(for: id)?.displayName ?? ""
  }

  /// 有序平面收藏；配置组只返回自身，详情仍使用同一个节点身份。
  var favorites: [CatalogTreeNode] {
    favoriteIDs.compactMap { tree.node(withID: $0) }
  }

  func isFavorite(_ id: NodeID) -> Bool { favoriteIDs.contains(id) }

  /// 服务器叶子的已知阻塞原因（typed；编辑面「激活状态」区）。
  func serverInvalidReasons(for id: NodeID) -> [LeafInvalidationReason] {
    tree.node(withID: id)?.invalidReasons ?? []
  }

  /// Rendering returns metadata only, never credentials or form baselines.
  func serverFormPresentation(for id: NodeID) -> ServerFormPresentation? {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { return nil }
    return ServerFormPresentation(
      isEditable: entry.source == .manual, plugin: pluginPresentation(for: fields))
  }

  /// 已保存详情投影；普通渲染不向视图传递密码或参数。
  func serverDetailPresentation(for id: NodeID) -> ServerDetailPresentation? {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { return nil }
    return ServerDetailPresentation(
      name: entry.displayName, address: fields.address, port: fields.port,
      encryptionMethod: fields.encryptionMethod, plugin: pluginPresentation(for: fields))
  }

  /// 详情参数装载独立于密码和插件可用性；未知插件仍可核对原文。
  func serverDetailPluginOptions(for id: NodeID) throws -> String {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { throw ServerFormLoadError.notFound }
    return fields.pluginOptions ?? ""
  }

  /// 服务器编辑面（显式命令）：解析密码与目录中的具名插件参数明文。
  /// 节点不存在或不是服务器叶子为 `nil`。
  func serverEditForm(for id: NodeID) throws -> ServerEditForm? {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { return nil }
    let password = fields.password
    return ServerEditForm(
      address: fields.address,
      port: fields.port,
      encryptionMethod: fields.encryptionMethod,
      password: password,
      remark: fields.remark,
      plugin: try loadedPluginState(for: fields),
      isEditable: entry.source == .manual)
  }

  /// 插件区状态：集内引用给可执行文件存在性事实与参数明文；集外引用
  /// 以显式 unknown 呈现（原样保留，激活语义由状态机点名拒绝）。
  private func pluginPresentation(for fields: ServerFields) -> PluginSectionState {
    let snapshot = dependencies.plugins.catalogSnapshot()
    let selection: PluginSelection
    if let program = fields.pluginProgram {
      selection =
        snapshot.entry(for: program) != nil
        ? .named(program: program) : .unknown(program: program)
    } else {
      selection = .none
    }
    return pluginSection(
      selection: selection, snapshot: snapshot,
      optionsPresent: fields.pluginOptions != nil)
  }

  private func loadedPluginState(for fields: ServerFields) throws -> PluginSectionState {
    var facts = pluginPresentation(for: fields)
    if case .named = facts.selection, let options = fields.pluginOptions {
      facts.options = options
    }
    return facts
  }

  func newFormPluginSection(selection: PluginSelection) -> PluginSectionState {
    pluginSection(
      selection: selection, snapshot: dependencies.plugins.catalogSnapshot(),
      optionsPresent: false)
  }

  private func pluginSection(
    selection: PluginSelection, snapshot: PluginCatalogSnapshot, optionsPresent: Bool
  ) -> PluginSectionState {
    PluginSectionState(
      selection: selection,
      programs: snapshot.entries.map {
        PluginSectionState.Program(
          program: $0.program, source: $0.source,
          availability: $0.availability)
      },
      mappingsUnreadable: snapshot.mappingsUnreadable,
      optionsPresent: optionsPresent, options: "")
  }

  /// 添加落点：选中手动分组 → 组内；选中服务器 → 其父组（仅手动）；其余 → 根。
  func importTargetParent(for selection: NodeID?) -> NodeID? {
    let catalog = dependencies.coordinator.committedCatalog
    guard let selection, let entry = catalog.entry(for: selection) else { return nil }
    switch entry.kind {
    case .group:
      return entry.source == .manual ? selection : nil
    case .server:
      guard let parent = (try? catalog.parentID(of: selection)) ?? nil else { return nil }
      return catalog.entry(for: parent)?.source == .manual ? parent : nil
    }
  }

}
