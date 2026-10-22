import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct ProxyListeningStoreRecoveryTests {
  @Test func completeListeningIdentitySurvivesRestartWithoutPlaintextOnDisk() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("proxy-listening.age")
    let keys = TestLibraryKeys()
    let store = ProxyListeningFileStore(fileURL: file, keys: keys)
    var configuration = try store.load()
    configuration.lan.username = "PRIVATE-LAN-USERNAME"
    configuration.lan.password = "PRIVATE-LAN-PASSWORD"
    try store.save(configuration)
    let data = try Data(contentsOf: file)
    for secret in ["PRIVATE-LAN-USERNAME", "PRIVATE-LAN-PASSWORD"] {
      #expect(data.range(of: Data(secret.utf8)) == nil)
    }
    #expect(try ProxyListeningFileStore(fileURL: file, keys: keys).load() == configuration)
  }

  @Test func unavailableKeyBlocksOrdinarySaveAndResetCreatesIndependentDefaults() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = TestLibraryKeys()
    let file = directory.appendingPathComponent("proxy-listening.age")
    let store = ProxyListeningFileStore(fileURL: file, keys: keys)
    var configuration = try store.load()
    configuration.lan.isEnabled = true
    configuration.lan.authenticationEnabled = true
    configuration.lan.password = "secret"
    try store.save(configuration)
    let original = try Data(contentsOf: file)
    keys.values.removeAll()
    let restarted = ProxyListeningFileStore(fileURL: file, keys: keys)
    #expect(throws: ProxyListeningStoreError.encryptedFile(.keyUnavailable)) {
      try restarted.load()
    }
    #expect(throws: ProxyListeningStoreError.encryptedFile(.keyUnavailable)) {
      try restarted.save(ProxyListeningConfiguration())
    }
    #expect(try Data(contentsOf: file) == original)
    keys.createFails = true
    #expect(throws: (any Error).self) { try restarted.reset() }
    #expect(try Data(contentsOf: file) == original)
    keys.createFails = false
    #expect(try restarted.reset() == ProxyListeningConfiguration())
    #expect(
      try ProxyListeningFileStore(fileURL: file, keys: keys).load() == ProxyListeningConfiguration()
    )
  }

  @Test func resettingOneStoreDoesNotInvalidateTheOtherStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = TestLibraryKeys()
    let library = CatalogFileStore(
      fileURL: directory.appendingPathComponent("catalog.age"),
      library: ServerLibraryStorage(keys: keys))
    let store = ProxyListeningFileStore(
      fileURL: directory.appendingPathComponent("proxy-listening.age"), keys: keys)
    _ = try library.load()
    var configuration = try store.load()
    configuration.local.socksPort = 12000
    configuration.lan.password = "retained-password"
    try store.save(configuration)
    _ = try library.reset()
    #expect(try ProxyListeningFileStore(fileURL: store.fileURL, keys: keys).load() == configuration)
    let libraryBytes = try Data(contentsOf: library.fileURL)
    _ = try store.reset()
    #expect(try Data(contentsOf: library.fileURL) == libraryBytes)
    #expect(
      try CatalogFileStore(fileURL: library.fileURL, library: ServerLibraryStorage(keys: keys))
        .load().catalog.isEmpty)
  }
}
