import Foundation

typealias ServerLibraryError = EncryptedFileError

/// 服务器库专用载荷与密钥空间；封装格式保持不变。
final class ServerLibraryStorage {
  private let encrypted: EncryptedFileStorage<CatalogDocument>

  init(keys: MasterKeyStoring = KeychainMasterKeyStore(namespace: "server-library")) {
    encrypted = EncryptedFileStorage(
      keys: keys, magic: "SSXNG2LB", version: 2, maximumSize: 64 * 1024 * 1024,
      legacyFileName: "catalog.json", makeDefault: { CatalogDocument() },
      encode: CatalogFileStore.encode, decode: CatalogFileStore.decode)
  }

  func load(at url: URL, allowingInteraction: Bool) throws -> CatalogDocument {
    try encrypted.load(at: url, allowingInteraction: allowingInteraction)
  }

  func save(_ document: CatalogDocument, at url: URL) throws {
    try encrypted.save(document, at: url)
  }

  func reset(at url: URL) throws -> CatalogDocument {
    try encrypted.reset(at: url)
  }
}
