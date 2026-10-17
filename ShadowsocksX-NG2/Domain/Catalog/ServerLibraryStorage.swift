import CryptoKit
import Foundation

/// 服务器秘密只在当前进程内按引用查询；唯一持久副本随服务器库整体加密。
final class ServerLibraryCredentials: CredentialStoring {
  fileprivate var values: [String: String] = [:]

  func save(_ secret: String, for reference: CredentialReference) throws {
    values[reference.rawValue] = secret
  }

  func secret(for reference: CredentialReference) throws -> String? {
    values[reference.rawValue]
  }

  func delete(_ reference: CredentialReference) throws {
    values.removeValue(forKey: reference.rawValue)
  }
}

enum ServerLibraryError: Error, Equatable {
  case malformedFile
  case unsupportedVersion
  case authenticationFailed
  case keyUnavailable
  case missingCredential
  case notLoaded
}

/// 文件、主密钥与进程内凭据的单进程持久化边界。
final class ServerLibraryStorage {
  private struct Payload: Codable {
    let catalog: Data
    let secrets: [String: String]
  }

  let credentials: ServerLibraryCredentials
  private let keys: LibraryMasterKeyStoring
  private let legacyCredentials: CredentialStoring
  private var currentKey: (id: UUID, data: Data)?
  private var loaded = false
  private(set) var cleanupFailed = false

  // 固定头：8 字节 magic + 1 字节版本 + 36 字节 UUID。整段原始头字节参与认证。
  private static let magic = Data("SSXNG2LB".utf8)
  private static let headerSize = 45
  private static let maximumSize = 64 * 1024 * 1024

  init(
    credentials: ServerLibraryCredentials,
    keys: LibraryMasterKeyStoring,
    legacyCredentials: CredentialStoring
  ) {
    self.credentials = credentials
    self.keys = keys
    self.legacyCredentials = legacyCredentials
  }

  func load(at url: URL, allowingInteraction: Bool) throws -> CatalogDocument {
    if loaded, !FileManager.default.fileExists(atPath: url.path) {
      throw ServerLibraryError.notLoaded
    }
    if FileManager.default.fileExists(atPath: url.path) {
      let (document, secrets, key) = try read(at: url, allowingInteraction: allowingInteraction)
      credentials.values = secrets
      currentKey = key
      loaded = true
      return document
    }
    let legacyURL = url.deletingLastPathComponent().appendingPathComponent("catalog.json")
    let legacy = CatalogFileStore(fileURL: legacyURL)
    let document = try legacy.load()
    var secrets: [String: String] = [:]
    for reference in document.libraryCredentialReferences {
      let value: String?
      if let keychain = legacyCredentials as? KeychainCredentialStore {
        value = try keychain.librarySecret(for: reference, allowingInteraction: allowingInteraction)
      } else {
        value = try legacyCredentials.secret(for: reference)
      }
      guard let value else { throw ServerLibraryError.missingCredential }
      secrets[reference.rawValue] = value
    }
    let key = try createKey(allowingInteraction: allowingInteraction)
    try write(document, secrets: secrets, key: key, to: url)
    let reopened = try read(at: url, allowingInteraction: allowingInteraction, cachedKey: key)
    guard reopened.0 == document, reopened.1 == secrets else {
      throw ServerLibraryError.authenticationFailed
    }
    credentials.values = secrets
    currentKey = key
    loaded = true
    cleanupFailed = false
    if FileManager.default.fileExists(atPath: legacyURL.path) {
      do { try FileManager.default.removeItem(at: legacyURL) } catch { cleanupFailed = true }
      for reference in document.libraryCredentialReferences {
        do {
          if let keychain = legacyCredentials as? KeychainCredentialStore {
            try keychain.deleteLibrarySecret(reference, allowingInteraction: allowingInteraction)
          } else {
            try legacyCredentials.delete(reference)
          }
        } catch { cleanupFailed = true }
      }
    }
    return document
  }

  func save(_ document: CatalogDocument, at url: URL) throws {
    guard loaded, let key = currentKey else { throw ServerLibraryError.notLoaded }
    let secrets = try resolvedSecrets(for: document)
    try write(document, secrets: secrets, key: key, to: url)
  }

  /// 调用方先取得用户的破坏性操作确认；成功写盘前不发布新状态。
  func reset(at url: URL) throws -> CatalogDocument {
    let key = try createKey(allowingInteraction: true)
    let document = CatalogDocument()
    try write(document, secrets: [:], key: key, to: url)
    credentials.values = [:]
    currentKey = key
    loaded = true
    cleanupFailed = false
    let oldURL = url.deletingLastPathComponent().appendingPathComponent("catalog.json")
    if FileManager.default.fileExists(atPath: oldURL.path) {
      do { try FileManager.default.removeItem(at: oldURL) } catch { cleanupFailed = true }
    }
    return document
  }

  private func resolvedSecrets(for document: CatalogDocument) throws -> [String: String] {
    var result: [String: String] = [:]
    for reference in document.libraryCredentialReferences {
      guard let value = credentials.values[reference.rawValue] else {
        throw ServerLibraryError.missingCredential
      }
      result[reference.rawValue] = value
    }
    return result
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
    _ document: CatalogDocument, secrets: [String: String],
    key: (id: UUID, data: Data), to url: URL
  ) throws {
    let catalog = try CatalogFileStore.encode(document)
    let payload = try JSONEncoder().encode(Payload(catalog: catalog, secrets: secrets))
    guard payload.count <= Self.maximumSize else { throw ServerLibraryError.malformedFile }
    let header = Self.magic + Data([1]) + Data(key.id.uuidString.utf8)
    let sealed = try AES.GCM.seal(
      payload, using: SymmetricKey(data: key.data), authenticating: header)
    guard let combined = sealed.combined else { throw ServerLibraryError.malformedFile }
    try AtomicFileWriter.write(header + combined, to: url)
  }

  private func read(
    at url: URL, allowingInteraction: Bool, cachedKey: (id: UUID, data: Data)? = nil
  ) throws -> (CatalogDocument, [String: String], (id: UUID, data: Data)) {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size >= Self.headerSize + 28, size <= Self.maximumSize + Self.headerSize + 28 else {
      throw ServerLibraryError.malformedFile
    }
    let data = try Data(contentsOf: url)
    guard data.starts(with: Self.magic) else { throw ServerLibraryError.malformedFile }
    guard data[8] == 1 else { throw ServerLibraryError.unsupportedVersion }
    guard let idText = String(data: data[9..<Self.headerSize], encoding: .utf8),
      let id = UUID(uuidString: idText)
    else { throw ServerLibraryError.malformedFile }
    let cached = cachedKey ?? currentKey
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
    let payload: Payload
    do { payload = try JSONDecoder().decode(Payload.self, from: plain) } catch {
      throw ServerLibraryError.malformedFile
    }
    let document = try CatalogFileStore.decode(payload.catalog)
    guard Set(payload.secrets.keys) == Set(document.libraryCredentialReferences.map(\.rawValue))
    else {
      throw ServerLibraryError.missingCredential
    }
    return (document, payload.secrets, (id, keyData))
  }
}

extension CatalogDocument {
  var libraryCredentialReferences: Set<CredentialReference> {
    var result = Set(subscriptions.map(\.urlRef))
    for entry in catalog.entries.values {
      guard case .server(let fields) = entry.kind else { continue }
      result.insert(fields.passwordRef)
      if let reference = fields.pluginOptionsRef { result.insert(reference) }
    }
    return result
  }
}
