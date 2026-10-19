import CryptoKit
import Foundation

enum EncryptedFileError: Error, Equatable {
  case malformedFile
  case unsupportedVersion
  case authenticationFailed
  case keyUnavailable
  case notLoaded
}

/// 加密文件的密钥、封装与原子提交；每个实例独立持有已加载密钥。
final class EncryptedFileStorage<Value> {
  private let keys: MasterKeyStoring
  private var currentKey: (id: UUID, data: Data)?
  private var loaded = false

  // 固定头：8 字节 magic + 1 字节版本 + 36 字节 UUID。整段原始头字节参与认证。
  private let magic: Data
  private let version: UInt8
  private let maximumSize: Int
  private let legacyFileName: String
  private let makeDefault: () -> Value
  private let encode: (Value) throws -> Data
  private let decode: (Data) throws -> Value
  private var headerSize: Int { 45 }
  var isLoaded: Bool { loaded }

  init(
    keys: MasterKeyStoring, magic: String, version: UInt8, maximumSize: Int,
    legacyFileName: String, makeDefault: @escaping () -> Value,
    encode: @escaping (Value) throws -> Data, decode: @escaping (Data) throws -> Value
  ) {
    precondition(magic.utf8.count == 8)
    self.keys = keys
    self.magic = Data(magic.utf8)
    self.version = version
    self.maximumSize = maximumSize
    self.legacyFileName = legacyFileName
    self.makeDefault = makeDefault
    self.encode = encode
    self.decode = decode
  }

  func load(at url: URL, allowingInteraction: Bool) throws -> Value {
    if loaded, !FileManager.default.fileExists(atPath: url.path) {
      throw EncryptedFileError.notLoaded
    }
    if FileManager.default.fileExists(atPath: url.path) {
      let (document, key) = try read(at: url, allowingInteraction: allowingInteraction)
      currentKey = key
      loaded = true
      return document
    }
    let legacyURL = url.deletingLastPathComponent().appendingPathComponent(legacyFileName)
    guard !FileManager.default.fileExists(atPath: legacyURL.path) else {
      throw EncryptedFileError.unsupportedVersion
    }
    let document = makeDefault()
    let key = try createKey(allowingInteraction: allowingInteraction)
    try write(document, key: key, to: url)
    currentKey = key
    loaded = true
    return document
  }

  func save(_ document: Value, at url: URL) throws {
    guard loaded, let key = currentKey else { throw EncryptedFileError.notLoaded }
    try write(document, key: key, to: url)
  }

  /// 调用方先取得用户的破坏性操作确认；成功写盘前不发布新状态。
  func reset(at url: URL) throws -> Value {
    let key = try createKey(allowingInteraction: true)
    let document = makeDefault()
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
      throw EncryptedFileError.keyUnavailable
    }
    return (id, data)
  }

  private func write(
    _ document: Value,
    key: (id: UUID, data: Data), to url: URL
  ) throws {
    let payload = try encode(document)
    guard payload.count <= maximumSize else { throw EncryptedFileError.malformedFile }
    let header = magic + Data([version]) + Data(key.id.uuidString.utf8)
    let sealed = try AES.GCM.seal(
      payload, using: SymmetricKey(data: key.data), authenticating: header)
    guard let combined = sealed.combined else { throw EncryptedFileError.malformedFile }
    try AtomicFileWriter.write(header + combined, to: url)
  }

  private func read(
    at url: URL, allowingInteraction: Bool
  ) throws -> (Value, (id: UUID, data: Data)) {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size >= headerSize + 28, size <= maximumSize + headerSize + 28 else {
      throw EncryptedFileError.malformedFile
    }
    let data = try Data(contentsOf: url)
    guard data.starts(with: magic) else { throw EncryptedFileError.malformedFile }
    guard data[8] == version else { throw EncryptedFileError.unsupportedVersion }
    guard let idText = String(data: data[9..<headerSize], encoding: .utf8),
      let id = UUID(uuidString: idText)
    else { throw EncryptedFileError.malformedFile }
    let cached = currentKey
    let keyData: Data?
    if cached?.id == id {
      keyData = cached?.data
    } else {
      keyData = try keys.read(id, allowingInteraction: allowingInteraction)
    }
    guard let keyData, keyData.count == 32 else { throw EncryptedFileError.keyUnavailable }
    let plain: Data
    do {
      plain = try AES.GCM.open(
        AES.GCM.SealedBox(combined: data.dropFirst(headerSize)),
        using: SymmetricKey(data: keyData), authenticating: data.prefix(headerSize))
    } catch { throw EncryptedFileError.authenticationFailed }
    let document = try decode(plain)
    return (document, (id, keyData))
  }
}
