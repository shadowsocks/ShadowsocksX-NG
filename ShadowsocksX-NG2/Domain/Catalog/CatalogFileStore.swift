import Foundation

/// 服务器库文件存储；生产和测试均通过整体加密存储写盘。
struct CatalogFileStore {
  enum PersistenceError: Error, Equatable {
    /// 文件存在但不是本模型可接受的目录文档：JSON 损坏、版本未知、结构不一致。
    case corrupt(detail: String)
    /// 读取或写入时的文件系统错误。
    case ioFailure(detail: String)
  }

  private static let currentVersion = 7
  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  let fileURL: URL
  private let library: ServerLibraryStorage

  init(fileURL: URL, library: ServerLibraryStorage = ServerLibraryStorage()) {
    self.fileURL = fileURL
    self.library = library
  }

  func reset() throws -> CatalogDocument {
    try library.reset(at: fileURL)
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
    try library.load(at: fileURL, allowingInteraction: allowingInteraction)
  }

  /// 整体加密后原子替换，失败时保留原文件。
  func save(_ document: CatalogDocument) throws {
    try library.save(document, at: fileURL)
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
    guard payload.version == Self.currentVersion else {
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
    let subscriptions = payload.subscriptions
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
    let favoriteIDs = payload.favoriteIDs
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

/// 当前服务器库明文载荷；只能在内存中编解码，由整体加密存储写盘。
private struct CatalogFilePayload: Codable {
  var version: Int
  var rootChildren: [NodeID]
  var entries: [CatalogEntry]
  var subscriptions: [SubscriptionRecord]
  var favoriteIDs: [NodeID]
}
