import Foundation
import ImageIO

// MARK: - 统一服务器导入（docs/design/unified-server-import.md）

/// 服务器导入深模块：UI 只认识 `importServers(from:into:)` 一个入口与
/// `ImportRunOutcome` 一个结果类型。来源分派按内容嗅探（图片→二维码、
/// JSON 对象→SIP-008、其余→ss:// 文本行），解码全部复用 Domain 既有实现，
/// 每来源独立事务（凭据经 journal）独立结果，来源之间互不影响。
extension CatalogWorkflow {
  /// 逐来源独立导入。不抛错：任何失败都折进对应来源的
  /// `ImportSourceResult.failed`，其他来源不受影响。落点对全部来源一致。
  func importServers(from sources: [ImportSource], into parent: NodeID?) async
    -> ImportRunOutcome
  {
    var outcomes: [ImportSourceOutcome] = []
    var newSelection: NodeID?
    for source in sources {
      let previousIDs = Set(importChildren(of: parent).map(\.id))
      let result: ImportSourceResult
      switch source {
      case .clipboardText(let text):
        result = importURIText(
          text, into: parent, credentials: dependencies.credentials)
      case .file(let name, let data):
        result = await importFile(
          name: name, data: data, into: parent, credentials: dependencies.credentials)
      }
      outcomes.append(ImportSourceOutcome(source: source, result: result))
      if let created = importChildren(of: parent).last(where: { !previousIDs.contains($0.id) }) {
        newSelection = created.id
      }
    }
    return ImportRunOutcome(sources: outcomes, newNodeSelectionCandidate: newSelection)
  }

  private func importChildren(of parent: NodeID?) -> [CatalogTreeNode] {
    if let parent { return tree.node(withID: parent)?.childNodes ?? [] }
    return tree.roots
  }

  /// 单文件分派：内容优先嗅探。可解码位图（ImageIO 事实）走二维码；内容为
  /// JSON 对象走 SIP-008（解析失败按整份拒绝报出，不降级文本行）；其余按
  /// 文本逐行。
  private func importFile(
    name: String, data: Data, into parent: NodeID?, credentials: CredentialStoring
  ) async -> ImportSourceResult {
    if Self.isDecodableImage(data) {
      return await importQRImage(name: name, data: data, into: parent, credentials: credentials)
    }
    if Self.looksLikeJSONObject(data) {
      return importSIP008(fileName: name, data: data, into: parent, credentials: credentials)
    }
    // 非 UTF-8 文本按 UTF-8 有损解读：文本路径宁可逐行点名失败也不整份丢弃。
    return importURIText(
      // swiftlint:disable:next optional_data_string_conversion
      String(decoding: data, as: UTF8.self), into: parent, credentials: credentials)
  }

  // MARK: - ss:// 文本行

  /// ss:// 文本行导入（剪贴板与文本文件的共同落点）：逐行解码，可解析行
  /// 全部添加（每次新建身份，不按内容去重）；空白行跳过不报，失败行以原始
  /// 切分下标（含空行）+ 类型化原因点名，已成功行不被局部失败回滚。空文本
  /// 是来源级失败。
  private func importURIText(
    _ text: String, into parent: NodeID?, credentials: CredentialStoring
  ) -> ImportSourceResult {
    var journal = CredentialWriteJournal(credentials: credentials)
    var prepared: [ServerFields] = []
    var failures: [ImportLineFailure] = []
    let lines = text.split(
      omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (index, rawLine) in lines.enumerated() {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }
      do {
        let uri = try SsUri.decode(line)
        prepared.append(try Self.serverFields(from: uri, journal: &journal))
      } catch let error as SsUriError {
        failures.append(ImportLineFailure(lineIndex: index, reason: .decode(error)))
      } catch let error as CredentialStoreError {
        failures.append(ImportLineFailure(lineIndex: index, reason: .credential(error)))
      } catch {
        failures.append(
          ImportLineFailure(
            lineIndex: index, reason: .decode(.malformed(detail: String(describing: error)))))
      }
    }
    guard !prepared.isEmpty else {
      return failures.isEmpty
        ? .failed(.noImportableLines) : .partial(addedCount: 0, failures: failures)
    }
    do {
      try commit { catalog in
        let now = Date()
        for fields in prepared {
          try catalog.addServer(fields, to: parent, now: now)
        }
      }
    } catch {
      return .failed(
        .commit(CommitError(underlying: error, credentialRollback: journal.rollback())))
    }
    return failures.isEmpty
      ? .imported(count: prepared.count, groupID: parent)
      : .partial(addedCount: prepared.count, failures: failures)
  }

  // MARK: - 二维码图片

  /// 二维码图片一步导入：识别全部负载、仅保留 ss:// 行后按文本行语义导入。
  /// 识别在主线程外执行（Vision 位图处理），无预览确认态。
  private func importQRImage(
    name: String, data: Data, into parent: NodeID?, credentials: CredentialStoring
  ) async -> ImportSourceResult {
    let payloads: [String]
    do {
      payloads = try await Task.detached(priority: .userInitiated) {
        try QrCodeCodec.detectPayloads(in: data)
      }.value
    } catch {
      return .failed(.undecodableImage)
    }
    let uris = payloads.filter { $0.lowercased().hasPrefix("ss://") }
    guard !uris.isEmpty else { return .failed(.qrPayloadNotFound) }
    return importURIText(
      uris.joined(separator: "\n"), into: parent, credentials: credentials)
  }

  // MARK: - SIP-008 文件（ADR-0027）

  /// SIP-008 文档整树导入：解析整份校验（任一记录无效整份拒绝）；快照身份
  /// 只作装配键，目录身份全部新建；根分组挂入选中落点，凭据与目录在同一
  /// 事务提交。
  private func importSIP008(
    fileName: String, data: Data, into parent: NodeID?, credentials: CredentialStoring
  ) -> ImportSourceResult {
    let snapshot: SubscriptionSnapshot
    do {
      // 一次性会话身份只作解析作用域：快照内的 scoped NodeID 不进入目录。
      snapshot = try SubscriptionDocumentParser.parse(data, subscriptionID: .fresh())
    } catch let error as SubscriptionParseError {
      return .failed(.parse(error))
    } catch {
      return .failed(.parse(.decodingFailure))
    }
    var journal = CredentialWriteJournal(credentials: credentials)
    do {
      let rootID = try commit { catalog in
        // 一次导入一个写入时刻：根分组与全部后代节点共用（ADR-0031）。
        let now = Date()
        let base = snapshot.root.name.isEmpty ? Self.fileNameBase(fileName) : snapshot.root.name
        let rootID = try catalog.addGroup(
          Self.uniqueGroupName(base, in: catalog), to: parent, now: now)
        try Self.mountSnapshotChildren(
          of: snapshot.root, into: rootID, catalog: &catalog, journal: &journal, now: now)
        return rootID
      }
      return .imported(count: Self.snapshotServerCount(snapshot.root), groupID: rootID)
    } catch {
      return .failed(
        .commit(CommitError(underlying: error, credentialRollback: journal.rollback())))
    }
  }

  /// 快照后代 → 手动子树：嵌套分组与服务器按快照顺序重建（根分组由调用方
  /// 挂载）。嵌套组缺名以占位名兜底。
  private static func mountSnapshotChildren(
    of group: SubscriptionSnapshot.Group,
    into groupID: NodeID,
    catalog: inout ConfigurationCatalog,
    journal: inout CredentialWriteJournal,
    now: Date
  ) throws {
    for child in group.children {
      switch child {
      case .group(let nested):
        let nestedID = try catalog.addGroup(
          nested.name.isEmpty ? String(localized: "未命名分组") : nested.name, to: groupID, now: now)
        try mountSnapshotChildren(
          of: nested, into: nestedID, catalog: &catalog, journal: &journal, now: now)
      case .server(let leaf):
        try catalog.addServer(
          importServerFields(from: leaf.record, journal: &journal), to: groupID, now: now)
      }
    }
  }

  /// SIP-008 记录 → 手动服务器叶子字段：密码与可选插件参数经 journal 写入
  /// 凭据存储。参数保真：`plugin_opts` 非空即存引用，即使缺插件程序名
  /// （激活语义按 pluginNotProvided 点名，用户可修复）。
  private static func importServerFields(
    from record: RemoteServerRecord, journal: inout CredentialWriteJournal
  ) throws -> ServerFields {
    let passwordRef = CredentialReference.fresh()
    try journal.save(record.password, for: passwordRef)
    var pluginOptionsRef: CredentialReference?
    if let options = record.pluginOptions, !options.isEmpty {
      let reference = CredentialReference.fresh()
      try journal.save(options, for: reference)
      pluginOptionsRef = reference
    }
    return ServerFields(
      address: record.address, port: record.port, encryptionMethod: record.encryptionMethod,
      passwordRef: passwordRef, remark: record.remark,
      pluginProgram: record.pluginProgram, pluginOptionsRef: pluginOptionsRef)
  }

  // MARK: - 命名与嗅探助手

  /// 重名分组加序号后缀（沿用 Legacy 导入命名惯例）：与现有分组同名时追加
  /// 「 2」「 3」…
  private static func uniqueGroupName(_ base: String, in catalog: ConfigurationCatalog) -> String {
    let names = Set(
      catalog.entries.values.compactMap { entry -> String? in
        guard case .group(let fields) = entry.kind else { return nil }
        return fields.name
      })
    guard names.contains(base) else { return base }
    var suffix = 2
    while names.contains("\(base) \(suffix)") { suffix += 1 }
    return "\(base) \(suffix)"
  }

  /// 文件名去扩展名（SIP-008 扁平回退时的根组名兜底，与导出建议文件名对称）。
  private static func fileNameBase(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = trimmed.isEmpty ? "" : (trimmed as NSString).deletingPathExtension
    return base.isEmpty ? String(localized: "导入的服务器") : base
  }

  /// 内容为 JSON 对象（SIP-008 根形态）即走整份拒绝语义；数组或残缺 JSON
  /// 不算，交由文本行路径点名。
  private static func looksLikeJSONObject(_ data: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
    return object is [String: Any]
  }

  /// 数据是可解码位图（ImageIO 事实，PNG/JPEG/HEIC/GIF/TIFF 等）；位图交给
  /// Vision 做条码识别。
  private static func isDecodableImage(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return CGImageSourceGetCount(source) > 0
  }

  private static func snapshotServerCount(_ group: SubscriptionSnapshot.Group) -> Int {
    group.children.reduce(0) { count, child in
      switch child {
      case .server: return count + 1
      case .group(let nested): return count + snapshotServerCount(nested)
      }
    }
  }
}
