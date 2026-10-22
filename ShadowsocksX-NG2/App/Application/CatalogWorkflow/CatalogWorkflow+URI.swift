import Foundation

/// 分享顶部的已保存资料，不包含密码或插件参数。
struct ServerSharePresentation {
  let name: String
  let address: String
  let port: Int
  let encryptionMethod: String
  let pluginProgram: String?
}

// MARK: - 分享与 URI → 服务器叶子

extension CatalogWorkflow {
  func serverSharePresentation(for id: NodeID) -> ServerSharePresentation? {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { return nil }
    return ServerSharePresentation(
      name: entry.displayName, address: fields.address, port: fields.port,
      encryptionMethod: fields.encryptionMethod, pluginProgram: fields.pluginProgram)
  }

  /// 仅在用户明确请求分享时生成包含秘密的 URI。
  func shareURI(for id: NodeID) throws -> String {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { throw CatalogError.notAServer(id) }
    guard !fields.password.isEmpty else { throw ServerFormError.invalidPassword }
    return SsUri(
      method: fields.encryptionMethod, password: fields.password,
      host: fields.address, port: fields.port,
      pluginProgram: fields.pluginProgram, pluginOptions: fields.pluginOptions,
      remark: fields.remark.isEmpty ? nil : fields.remark
    ).encode()
  }

  static func serverFields(from uri: SsUri) -> ServerFields {
    ServerFields(
      address: uri.host, port: uri.port, encryptionMethod: uri.method,
      password: uri.password, remark: uri.remark ?? "",
      pluginProgram: uri.pluginProgram,
      pluginOptions: uri.pluginProgram == nil ? nil : uri.pluginOptions)
  }

  static func serverFields(of entry: CatalogEntry) -> ServerFields? {
    if case .server(let fields) = entry.kind { return fields }
    return nil
  }

  /// 无插件时清除参数；未知插件的原始参数在其他字段编辑时保持不变。
  static func applyPluginSelection(
    _ selection: PluginSelection, options: String?, to fields: inout ServerFields
  ) {
    switch selection {
    case .none:
      fields.pluginProgram = nil
      fields.pluginOptions = nil
    case .named(let program):
      fields.pluginProgram = program
      let trimmed = (options ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      fields.pluginOptions = trimmed.isEmpty ? nil : trimmed
    case .unknown:
      break
    }
  }
}
