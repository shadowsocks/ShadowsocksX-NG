import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct EncryptedServerLibraryTests {
  @Test func savedLibraryHidesServerMetadata() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: ServerLibraryCredentials(),
        keys: TestLibraryKeys(), legacyCredentials: InMemoryCredentialStore()))
    _ = try store.load()
    var catalog = ConfigurationCatalog()
    _ = try catalog.addGroup("PRIVATE-GROUP-NAME")
    try store.save(CatalogDocument(catalog: catalog))
    let data = try Data(contentsOf: url)
    #expect(data.range(of: Data("PRIVATE-GROUP-NAME".utf8)) == nil)
    #expect(try store.load().catalog == catalog)
  }
  @Test func migrationRestoresAllSecretsAfterRestartAndCleansOnlyLibraryCredentials() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try CatalogFixtures.makeSubscriptionFixture(prefix: "private-subscription")
    let record = SubscriptionRecord(
      id: NodeID(rawValue: "subscription"), groupID: fixture.groupID,
      urlRef: CredentialReference.fresh(), status: .never)
    let document = CatalogDocument(
      catalog: fixture.catalog, subscriptions: [record],
      favoriteIDs: [fixture.groupID])
    let legacyCredentials = InMemoryCredentialStore()
    let outside = CredentialReference.fresh()
    try legacyCredentials.save("listener-secret", for: outside)
    for reference in document.libraryCredentialReferences {
      try legacyCredentials.save("sample-secret-" + reference.rawValue, for: reference)
    }
    let legacyURL = directory.appendingPathComponent("catalog.json")
    try CatalogFileStore(fileURL: legacyURL).save(document)
    let keys = TestLibraryKeys()
    let credentials = ServerLibraryCredentials()
    let url = directory.appendingPathComponent("catalog.enc")
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: credentials, keys: keys, legacyCredentials: legacyCredentials))
    #expect(try store.load() == document)
    #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    let data = try Data(contentsOf: url)
    #expect(data.range(of: Data("sample-secret-".utf8)) == nil)
    #expect(data.range(of: Data("private-subscription".utf8)) == nil)
    let restartedCredentials = ServerLibraryCredentials()
    let restarted = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: restartedCredentials, keys: keys, legacyCredentials: legacyCredentials))
    #expect(try restarted.load() == document)
    for reference in document.libraryCredentialReferences {
      #expect(
        try restartedCredentials.secret(for: reference) == "sample-secret-" + reference.rawValue)
      #expect(try legacyCredentials.secret(for: reference) == nil)
    }
    #expect(try legacyCredentials.secret(for: outside) == "listener-secret")
    try restarted.save(document)
    #expect(try Data(contentsOf: url) != data)
  }

  @Test(arguments: [0, 8, 9, 45, -1])
  func alteredFileIsRejectedWithoutFallback(offset: Int) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let storage = ServerLibraryStorage(
      credentials: ServerLibraryCredentials(), keys: keys,
      legacyCredentials: InMemoryCredentialStore())
    let store = CatalogFileStore(fileURL: url, library: storage)
    _ = try store.load()
    var data = try Data(contentsOf: url)
    data[offset == -1 ? data.count - 1 : offset] ^= 1
    try data.write(to: url)
    try CatalogFileStore(fileURL: directory.appendingPathComponent("catalog.json"))
      .save(CatalogDocument())
    let restarted = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: ServerLibraryCredentials(), keys: keys,
        legacyCredentials: InMemoryCredentialStore()))
    #expect(throws: (any Error).self) { try restarted.load() }
    #expect(try Data(contentsOf: url) == data)
  }

  @Test func missingLegacyCredentialKeepsOriginalFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("catalog.json")
    var catalog = ConfigurationCatalog()
    _ = try catalog.addTestServer("missing-secret")
    try CatalogFileStore(fileURL: legacyURL).save(CatalogDocument(catalog: catalog))
    let original = try Data(contentsOf: legacyURL)
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: ServerLibraryCredentials(), keys: keys,
        legacyCredentials: InMemoryCredentialStore()))
    #expect(throws: ServerLibraryError.missingCredential) { try store.load() }
    #expect(try Data(contentsOf: legacyURL) == original)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(keys.values.isEmpty)
  }

  @Test func unavailableOrWrongKeyDoesNotReplaceCiphertext() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("catalog.enc")
    let keys = TestLibraryKeys()
    let store = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: ServerLibraryCredentials(), keys: keys,
        legacyCredentials: InMemoryCredentialStore()))
    _ = try store.load()
    let ciphertext = try Data(contentsOf: url)
    let restarted = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: ServerLibraryCredentials(), keys: TestLibraryKeys(),
        legacyCredentials: InMemoryCredentialStore()))
    #expect(throws: ServerLibraryError.keyUnavailable) { try restarted.load() }
    keys.values = keys.values.mapValues { _ in Data(repeating: 0, count: 32) }
    let wrongKey = CatalogFileStore(
      fileURL: url,
      library: ServerLibraryStorage(
        credentials: ServerLibraryCredentials(), keys: keys,
        legacyCredentials: InMemoryCredentialStore()))
    #expect(throws: ServerLibraryError.authenticationFailed) { try wrongKey.load() }
    #expect(try Data(contentsOf: url) == ciphertext)
  }

}

final class TestLibraryKeys: LibraryMasterKeyStoring {
  var values: [UUID: Data] = [:]
  var requiresInteraction = false
  var createFails = false
  func read(_ id: UUID, allowingInteraction: Bool) throws -> Data? {
    if requiresInteraction && !allowingInteraction {
      throw CredentialStoreError.keychainStatus(-25308)
    }
    return values[id]
  }
  func create(_ data: Data, id: UUID, allowingInteraction: Bool) throws {
    if createFails { throw CredentialStoreError.keychainStatus(-25308) }
    values[id] = data
  }
}
