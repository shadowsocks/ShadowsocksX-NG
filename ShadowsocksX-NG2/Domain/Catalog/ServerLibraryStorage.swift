import CryptoKit
import Foundation

enum ServerLibraryError: Error, Equatable {
  case malformedFile
  case unsupportedVersion
  case authenticationFailed
  case keyUnavailable
  case notLoaded
}

/// 服务器库整体加密存储；成功写盘前不替换当前主密钥。
final class ServerLibraryStorage {
  private let keys: LibraryMasterKeyStoring
  private var currentKey: (id: UUID, data: Data)?
  private var loaded = false

  // 固定头：8 字节 magic + 1 字节版本 + 36 字节 UUID。整段原始头字节参与认证。
  private static let magic = Data("SSXNG2LB".utf8)
  private static let headerSize = 45
  private static let maximumSize = 64 * 1024 * 1024

  init(keys: LibraryMasterKeyStoring = KeychainLibraryMasterKeyStore()) {
    self.keys = keys
  }

  func load(at url: URL, allowingInteraction: Bool) throws -> CatalogDocument {
    if loaded, !FileManager.default.fileExists(atPath: url.path) {
      throw ServerLibraryError.notLoaded
    }
    if FileManager.default.fileExists(atPath: url.path) {
      let (document, key) = try read(at: url, allowingInteraction: allowingInteraction)
      currentKey = key
      loaded = true
      return document
    }
    let legacyURL = url.deletingLastPathComponent().appendingPathComponent("catalog.json")
    guard !FileManager.default.fileExists(atPath: legacyURL.path) else {
      throw ServerLibraryError.unsupportedVersion
    }
    let document = CatalogDocument()
    let key = try createKey(allowingInteraction: allowingInteraction)
    try write(document, key: key, to: url)
    currentKey = key
    loaded = true
    return document
  }

  func save(_ document: CatalogDocument, at url: URL) throws {
    guard loaded, let key = currentKey else { throw ServerLibraryError.notLoaded }
    try write(document, key: key, to: url)
  }

  /// 调用方先取得用户的破坏性操作确认；成功写盘前不发布新状态。
  func reset(at url: URL) throws -> CatalogDocument {
    let key = try createKey(allowingInteraction: true)
    let document = CatalogDocument()
    try write(document, key: key, to: url)
    currentKey = key
    loaded = true
    return document
  }

  private func createKey(allowingInteraction: Bool) throws -> (id: UUID, data: Data) {
    let id = UUID()
    let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    try keys.create(data, id: id, allowingInteraction: allowingInteraction)
    guard try keys.read(id, allowingInteraction: allowingInteraction) == data else {
      throw ServerLibraryError.keyUnavailable
    }
    return (id, data)
  }

  private func write(
    _ document: CatalogDocument,
    key: (id: UUID, data: Data), to url: URL
  ) throws {
    let payload = try CatalogFileStore.encode(document)
    guard payload.count <= Self.maximumSize else { throw ServerLibraryError.malformedFile }
    let header = Self.magic + Data([2]) + Data(key.id.uuidString.utf8)
    let sealed = try AES.GCM.seal(
      payload, using: SymmetricKey(data: key.data), authenticating: header)
    guard let combined = sealed.combined else { throw ServerLibraryError.malformedFile }
    try AtomicFileWriter.write(header + combined, to: url)
  }

  private func read(
    at url: URL, allowingInteraction: Bool
  ) throws -> (CatalogDocument, (id: UUID, data: Data)) {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size >= Self.headerSize + 28, size <= Self.maximumSize + Self.headerSize + 28 else {
      throw ServerLibraryError.malformedFile
    }
    let data = try Data(contentsOf: url)
    guard data.starts(with: Self.magic) else { throw ServerLibraryError.malformedFile }
    guard data[8] == 2 else { throw ServerLibraryError.unsupportedVersion }
    guard let idText = String(data: data[9..<Self.headerSize], encoding: .utf8),
      let id = UUID(uuidString: idText)
    else { throw ServerLibraryError.malformedFile }
    let cached = currentKey
    let keyData: Data?
    if cached?.id == id {
      keyData = cached?.data
    } else {
      keyData = try keys.read(id, allowingInteraction: allowingInteraction)
    }
    guard let keyData, keyData.count == 32 else { throw ServerLibraryError.keyUnavailable }
    let plain: Data
    do {
      plain = try AES.GCM.open(
        AES.GCM.SealedBox(combined: data.dropFirst(Self.headerSize)),
        using: SymmetricKey(data: keyData), authenticating: data.prefix(Self.headerSize))
    } catch { throw ServerLibraryError.authenticationFailed }
    let document = try CatalogFileStore.decode(plain)
    return (document, (id, keyData))
  }
}
