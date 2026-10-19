import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct EncryptedServerLibraryTests {
  @Test func historicalJSONIsRejectedWithoutMigrationOrCleanup() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyURL = directory.appendingPathComponent("catalog.json")
    let original = Data("historical-library".utf8)
    try original.write(to: legacyURL)
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(
      fileURL: directory.appendingPathComponent("catalog.enc"),
      library: ServerLibraryStorage(keys: keys))
    #expect(throws: ServerLibraryError.unsupportedVersion) { try store.load() }
    #expect(try Data(contentsOf: legacyURL) == original)
    #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    #expect(keys.values.isEmpty)
    _ = try store.reset()
    #expect(try store.load().catalog.isEmpty)
    #expect(try Data(contentsOf: legacyURL) == original)
  }

  @Test func completeRecordsSurviveRestartAndOnlyCiphertextIsWritten() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    _ = try store.load()
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("PRIVATE-GROUP", source: .subscription)
    let fields = ServerFields(
      address: "private.example", port: 8388, encryptionMethod: "aes-256-gcm",
      password: "PRIVATE-PASSWORD", remark: "PRIVATE-NAME",
      pluginProgram: "v2ray-plugin", pluginOptions: "host=PRIVATE-PLUGIN")
    _ = try catalog.addServer(fields, source: .subscription, to: group)
    let record = SubscriptionRecord(
      id: .fresh(), groupID: group, url: "https://provider.example/sub?token=PRIVATE-TOKEN",
      status: .never)
    let document = CatalogDocument(catalog: catalog, subscriptions: [record], favoriteIDs: [group])
    try store.save(document)
    let first = try Data(contentsOf: url)
    for secret in ["PRIVATE-", "private.example", "provider.example"] {
      #expect(first.range(of: Data(secret.utf8)) == nil)
    }
    let restarted = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    #expect(try restarted.load() == document)
    try restarted.save(document)
    #expect(try Data(contentsOf: url) != first)
  }

  @Test(arguments: [0, 8, 9, 45, -1])
  func alteredFileIsRejectedWithoutFallback(offset: Int) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    _ = try store.load()
    var data = try Data(contentsOf: url)
    data[offset == -1 ? data.count - 1 : offset] ^= 1
    try data.write(to: url)
    try Data("old-library".utf8).write(to: directory.appendingPathComponent("catalog.json"))
    let restarted = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    #expect(throws: (any Error).self) { try restarted.load() }
    #expect(try Data(contentsOf: url) == data)
  }

  @Test func previousEncryptedEnvelopeIsUnsupportedAndPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    _ = try store.load()
    var old = try Data(contentsOf: url)
    old[8] = 1
    try old.write(to: url)
    let restarted = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    #expect(throws: ServerLibraryError.unsupportedVersion) { try restarted.load() }
    #expect(try Data(contentsOf: url) == old)
  }

  @Test func unavailableOrWrongKeyDoesNotReplaceCiphertext() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    _ = try store.load()
    let ciphertext = try Data(contentsOf: url)
    let restarted = CatalogFileStore(
      fileURL: url, library: ServerLibraryStorage(keys: TestLibraryKeys()))
    #expect(throws: ServerLibraryError.keyUnavailable) { try restarted.load() }
    keys.values = keys.values.mapValues { _ in Data(repeating: 0, count: 32) }
    let wrongKey = CatalogFileStore(fileURL: url, library: ServerLibraryStorage(keys: keys))
    #expect(throws: ServerLibraryError.authenticationFailed) { try wrongKey.load() }
    #expect(try Data(contentsOf: url) == ciphertext)
  }
}

final class TestLibraryKeys: MasterKeyStoring {
  var values: [UUID: Data] = [:]
  var requiresInteraction = false
  var createFails = false
  func read(_ id: UUID, allowingInteraction: Bool) throws -> Data? {
    if requiresInteraction && !allowingInteraction {
      throw MasterKeyStoreError.keychainStatus(-25308)
    }
    return values[id]
  }
  func create(_ data: Data, id: UUID, allowingInteraction: Bool) throws {
    if createFails { throw MasterKeyStoreError.keychainStatus(-25308) }
    values[id] = data
  }
}
