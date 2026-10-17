import Foundation

/// 目录文件边界。生产注入整体加密存储；不带 library 的形态仅用于旧 JSON 迁移与隔离夹具。
struct CatalogFileStore {
  enum PersistenceError: Error, Equatable {
    /// 文件存在但不是本模型可接受的目录文档：JSON 损坏、版本未知、结构不一致。
    case corrupt(detail: String)
    /// 读取或写入时的文件系统错误。
    case ioFailure(detail: String)
  }

  /// v2 起携带订阅记录；v1（无订阅字段）仍可读取。v3 移除节点级 enabled
  /// 语义；v4 把订阅失败字符串替换为 typed facts；v5 增加节点创建/修改时间
  /// （v1–v4 读取为 nil 未知，不回填）；v6 增加有序收藏。读取兼容 v1–v6。
  private static let supportedVersions: Set<Int> = [1, 2, 3, 4, 5, 6]
  private static let currentVersion = 6
  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  let fileURL: URL
  let library: ServerLibraryStorage?

  init(fileURL: URL, library: ServerLibraryStorage? = nil) {
    self.fileURL = fileURL
    self.library = library
  }

  var cleanupFailed: Bool { library?.cleanupFailed ?? false }

  func reset() throws -> CatalogDocument {
    if let library { return try library.reset(at: fileURL) }
    let document = CatalogDocument()
    try save(document)
    return document
  }

  /// 默认密文位置：`~/Library/Application Support/ShadowsocksX-NG2/catalog.enc`。
  static func defaultFileURL() -> URL {
    RuntimePaths.catalogFileURL()
  }

  /// 文件缺失 → 全新空文档；存在但损坏/版本未知/结构不一致 → `.corrupt`。
  func load() throws -> CatalogDocument {
    try load(allowingInteraction: false)
  }

  func load(allowingInteraction: Bool) throws -> CatalogDocument {
    if let library {
      return try library.load(at: fileURL, allowingInteraction: allowingInteraction)
    }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return CatalogDocument()
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
    return try Self.decode(data)
  }

  /// 整体重写并原子替换；失败时保留原文件。目录权限强制为 0700（含自愈）。
  func save(_ document: CatalogDocument) throws {
    if let library { return try library.save(document, at: fileURL) }
    let data = try Self.encode(document)
    do {
      try AtomicFileWriter.write(data, to: fileURL)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
  }

  static func encode(_ document: CatalogDocument) throws -> Data {
    try Self.validateFavorites(document.favoriteIDs, in: document.catalog)
    let payload = CatalogFilePayload(
      version: Self.currentVersion,
      rootChildren: document.catalog.rootChildren,
      entries: document.catalog.entries.values.sorted { $0.id.rawValue < $1.id.rawValue },
      subscriptions: document.subscriptions, favoriteIDs: document.favoriteIDs)
    let data: Data
    do {
      data = try Self.jsonEncoder.encode(payload)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
    return data
  }

  static func decode(_ data: Data) throws -> CatalogDocument {
    let payload: CatalogFilePayload
    do {
      payload = try JSONDecoder().decode(CatalogFilePayload.self, from: data)
    } catch {
      throw PersistenceError.corrupt(detail: String(describing: error))
    }
    guard Self.supportedVersions.contains(payload.version) else {
      throw PersistenceError.corrupt(detail: "unsupported version \(payload.version)")
    }
    var entries: [NodeID: CatalogEntry] = [:]
    for entry in payload.entries {
      guard entries[entry.id] == nil else {
        throw PersistenceError.corrupt(detail: "duplicate node id \(entry.id.rawValue)")
      }
      entries[entry.id] = entry
    }
    let catalog: ConfigurationCatalog
    do {
      catalog = try ConfigurationCatalog.validated(
        rootChildren: payload.rootChildren, entries: entries)
    } catch let error as CatalogError {
      throw PersistenceError.corrupt(detail: String(describing: error))
    }
    let subscriptions = payload.subscriptions ?? []
    var seen = Set<NodeID>()
    for record in subscriptions {
      guard seen.insert(record.id).inserted else {
        throw PersistenceError.corrupt(detail: "duplicate subscription \(record.id.rawValue)")
      }
    }
    // 订阅固定分组必须存在于目录且来源正确；缺失即文档不一致。
    for record in subscriptions {
      guard
        let entry = catalog.entry(for: record.groupID), case .group = entry.kind,
        entry.source == .subscription
      else {
        throw PersistenceError.corrupt(
          detail: "subscription group missing \(record.groupID.rawValue)")
      }
    }
    let favoriteIDs = payload.favoriteIDs ?? []
    try validateFavorites(favoriteIDs, in: catalog)
    return CatalogDocument(
      catalog: catalog, subscriptions: subscriptions, favoriteIDs: favoriteIDs)
  }

  private static func validateFavorites(_ ids: [NodeID], in catalog: ConfigurationCatalog) throws {
    var seen = Set<NodeID>()
    for id in ids {
      guard seen.insert(id).inserted, catalog.entry(for: id) != nil else {
        throw PersistenceError.corrupt(detail: "duplicate or missing favorite node \(id.rawValue)")
      }
    }
  }

}

/// 落盘文档形态：版本号 + 根子序 + 全量节点表（顺序语义在根序与分组显子序中）
/// + 订阅记录（v2 起携带；v1 缺省为空）。v3 节点条目不再写出 `enabled`；
/// v4 的失败状态只写 typed facts，不再写旧 `reason` 字段；v5 节点条目携带
/// 创建/修改时间，未知（历史文档迁移节点）省略键；v6 保存独立的收藏序列。
private struct CatalogFilePayload: Codable {
  var version: Int
  var rootChildren: [NodeID]
  var entries: [CatalogEntry]
  var subscriptions: [SubscriptionRecord]?
  var favoriteIDs: [NodeID]?
}
