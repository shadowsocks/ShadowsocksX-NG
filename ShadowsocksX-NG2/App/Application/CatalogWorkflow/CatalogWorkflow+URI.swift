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

  /// 服务器 → ss://（SIP002）：凭据从存储解析；无凭据即点名失败
  /// （不分享空档）。仅在用户明确请求分享时调用。
  func shareURI(for id: NodeID) throws -> String {
    guard let entry = dependencies.coordinator.committedCatalog.entry(for: id),
      case .server(let fields) = entry.kind
    else { throw CatalogError.notAServer(id) }
    guard let password = try dependencies.credentials.secret(for: fields.passwordRef) else {
      throw CredentialStoreError.keychainStatus(errSecItemNotFound)
    }
    var pluginOptions: String?
    if let optionsRef = fields.pluginOptionsRef {
      pluginOptions = try dependencies.credentials.secret(for: optionsRef) ?? ""
    }
    return SsUri(
      method: fields.encryptionMethod,
      password: password,
      host: fields.address,
      port: fields.port,
      pluginProgram: fields.pluginProgram,
      pluginOptions: pluginOptions,
      remark: fields.remark.isEmpty ? nil : fields.remark
    ).encode()
  }

  // MARK: - URI → 服务器叶子字段

  /// URI → 服务器叶子字段：密码与插件参数经 journal 写入凭据存储、目录只持
  /// 引用。回滚由调用方持有 journal 统一处理（统一导入管线）。
  static func serverFields(
    from uri: SsUri, journal: inout CredentialWriteJournal
  ) throws -> ServerFields {
    let passwordRef = CredentialReference.fresh()
    try journal.save(uri.password, for: passwordRef)
    var pluginOptionsRef: CredentialReference?
    if uri.pluginProgram != nil, let options = uri.pluginOptions {
      let ref = CredentialReference.fresh()
      try journal.save(options, for: ref)
      pluginOptionsRef = ref
    }
    return ServerFields(
      address: uri.host,
      port: uri.port,
      encryptionMethod: uri.method,
      passwordRef: passwordRef,
      remark: uri.remark ?? "",
      pluginProgram: uri.pluginProgram,
      pluginOptionsRef: pluginOptionsRef)
  }

  static func serverFields(of entry: CatalogEntry) -> ServerFields? {
    if case .server(let fields) = entry.kind { return fields }
    return nil
  }

  /// 条目集合 → 待清理凭据引用（密码 + 可选插件参数）。
  static func credentialRefs(of entries: [CatalogEntry]) -> [CredentialReference] {
    entries.flatMap { entry -> [CredentialReference] in
      guard let fields = serverFields(of: entry) else { return [] }
      return [fields.passwordRef] + (fields.pluginOptionsRef.map { [$0] } ?? [])
    }
  }

  /// 插件选择落盘（GLOSSARY.md 不变量）：「无」整体清除引用与
  /// 参数秘密；受管程序写引用、参数按空/非空经 journal 写删钥匙串；集外引用
  /// 原样保留（不因打开或保存表单而漂移，激活语义由状态机点名拒绝）。
  /// 受管集校验已由 `updateServer` 的表单校验完成。
  static func applyPluginSelection(
    _ selection: PluginSelection,
    options: String?,
    to fields: inout ServerFields,
    credentials: CredentialStoring,
    journal: inout CredentialWriteJournal
  ) throws {
    switch selection {
    case .none:
      if let reference = fields.pluginOptionsRef {
        journal.delete(reference)
      }
      fields.pluginProgram = nil
      fields.pluginOptionsRef = nil
    case .named(let program):
      fields.pluginProgram = program
      let trimmedOptions = (options ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedOptions.isEmpty {
        if let reference = fields.pluginOptionsRef {
          journal.delete(reference)
        }
        fields.pluginOptionsRef = nil
      } else if let reference = fields.pluginOptionsRef {
        try journal.save(trimmedOptions, for: reference)
      } else {
        let reference = CredentialReference.fresh()
        try journal.save(trimmedOptions, for: reference)
        fields.pluginOptionsRef = reference
      }
    case .unknown:
      // Imported manual records may contain an unsupported plugin. Keep the opaque
      // reference unchanged while the user repairs another field or selects a
      // supported plugin explicitly.
      break
    }
  }
}
