import AgeSwift
import Foundation

enum EncryptedFileError: Error, Equatable {
  case malformedFile
  case unsupportedVersion
  case authenticationFailed
  case keyUnavailable
  case notLoaded
}

/// age 文件的密钥选择与原子提交；每个实例独立持有已匹配的 identity。
final class EncryptedFileStorage<Value> {
  private let keys: CredentialKeyStoring
  private var currentIdentity: AgeIdentity?
  private var loaded = false
  private let maximumSize: Int
  private let legacyFileNames: [String]
  private let makeDefault: () -> Value
  private let encode: (Value) throws -> Data
  private let decode: (Data) throws -> Value
  var isLoaded: Bool { loaded }

  // 为 age 分块标签、文件头和 armor 换行预留空间；明文仍单独检查原有上限。
  private var maximumFileSize: Int {
    let binary = maximumSize + (maximumSize / 65536 + 1) * 16 + 16384
    let base64 = (binary + 2) / 3 * 4
    return base64 + base64 / 64 * 2 + 1024
  }

  init(
    keys: CredentialKeyStoring, maximumSize: Int,
    legacyFileNames: [String], makeDefault: @escaping () -> Value,
    encode: @escaping (Value) throws -> Data, decode: @escaping (Data) throws -> Value
  ) {
    self.keys = keys
    self.maximumSize = maximumSize
    self.legacyFileNames = legacyFileNames
    self.makeDefault = makeDefault
    self.encode = encode
    self.decode = decode
  }

  func load(at url: URL, allowingInteraction: Bool) throws -> Value {
    if loaded, !FileManager.default.fileExists(atPath: url.path) {
      throw EncryptedFileError.notLoaded
    }
    if FileManager.default.fileExists(atPath: url.path) {
      let (document, identity) = try read(at: url, allowingInteraction: allowingInteraction)
      currentIdentity = identity
      loaded = true
      return document
    }
    let directory = url.deletingLastPathComponent()
    guard
      !legacyFileNames.contains(where: {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
      })
    else { throw EncryptedFileError.unsupportedVersion }
    let document = makeDefault()
    let identity = try createIdentity(allowingInteraction: allowingInteraction)
    try write(document, identity: identity, to: url)
    currentIdentity = identity
    loaded = true
    return document
  }

  func save(_ document: Value, at url: URL) throws {
    guard loaded, let identity = currentIdentity else { throw EncryptedFileError.notLoaded }
    try write(document, identity: identity, to: url)
  }

  /// 调用方先取得用户的破坏性操作确认；成功写盘前不发布新状态。
  func reset(at url: URL) throws -> Value {
    let identity = try createIdentity(allowingInteraction: true)
    let document = makeDefault()
    try write(document, identity: identity, to: url)
    currentIdentity = identity
    loaded = true
    return document
  }

  private func createIdentity(allowingInteraction: Bool) throws -> AgeIdentity {
    let id = UUID()
    let identity = try AgeIdentity.generate()
    let data = Data(identity.serialized.utf8)
    try keys.create(data, id: id, allowingInteraction: allowingInteraction)
    guard try keys.read(id, allowingInteraction: allowingInteraction) == data else {
      throw EncryptedFileError.keyUnavailable
    }
    return identity
  }

  private func write(_ document: Value, identity: AgeIdentity, to url: URL) throws {
    let payload = try encode(document)
    guard payload.count <= maximumSize else { throw EncryptedFileError.malformedFile }
    let ciphertext = try Age.encrypt(payload, recipients: [identity.recipient])
    try AtomicFileWriter.write(ciphertext, to: url)
  }

  private func read(at url: URL, allowingInteraction: Bool) throws -> (Value, AgeIdentity) {
    let data = try readBoundedFile(at: url)
    if data.starts(with: Data("SSXNG2".utf8)) {
      throw EncryptedFileError.unsupportedVersion
    }
    if let identity = currentIdentity {
      return (try decodePayload(data, identity: identity), identity)
    }
    var accessError: (any Error)?
    var triedIdentity = false
    for id in try keys.ids() {
      let identity: AgeIdentity
      do {
        guard let keyData = try keys.read(id, allowingInteraction: allowingInteraction),
          let text = String(data: keyData, encoding: .utf8)
        else { continue }
        identity = try AgeIdentity(string: text)
      } catch {
        if accessError == nil { accessError = error }
        continue
      }
      triedIdentity = true
      let plain: Data
      do {
        plain = try Age.decrypt(data, identities: [identity])
      } catch AgeError.noMatchingKey {
        continue
      } catch AgeError.invalidFormat {
        throw EncryptedFileError.malformedFile
      } catch {
        throw EncryptedFileError.authenticationFailed
      }
      return (try decodeCheckedPayload(plain), identity)
    }
    if let accessError { throw accessError }
    throw triedIdentity ? EncryptedFileError.authenticationFailed : .keyUnavailable
  }

  private func decodePayload(_ data: Data, identity: AgeIdentity) throws -> Value {
    let plain: Data
    do {
      plain = try Age.decrypt(data, identities: [identity])
    } catch AgeError.invalidFormat {
      throw EncryptedFileError.malformedFile
    } catch {
      throw EncryptedFileError.authenticationFailed
    }
    return try decodeCheckedPayload(plain)
  }

  private func decodeCheckedPayload(_ plain: Data) throws -> Value {
    guard plain.count <= maximumSize else { throw EncryptedFileError.malformedFile }
    return try decode(plain)
  }

  private func readBoundedFile(at url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while let chunk = try handle.read(upToCount: min(65536, maximumFileSize + 1 - data.count)),
      !chunk.isEmpty
    {
      data.append(chunk)
      guard data.count <= maximumFileSize else { throw EncryptedFileError.malformedFile }
    }
    guard !data.isEmpty else { throw EncryptedFileError.malformedFile }
    return data
  }
}
