import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ProxyListeningStartupTests {
  @Test func unsupportedListeningFileBlocksStartupUntilResetIsConfirmed() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let oldURL = directory.appendingPathComponent("proxy-listening.json")
    let old = Data("old-listening-configuration".utf8)
    try old.write(to: oldURL)
    let keys = TestLibraryKeys()
    let store = ProxyListeningFileStore(
      fileURL: directory.appendingPathComponent("proxy-listening.enc"), keys: keys)
    var prompts = 0
    let configuration = ProxyListeningStartup.load(store: store) { error in
      prompts += 1
      #expect(error == .encryptedFile(.unsupportedVersion))
      #expect(keys.values.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
    #expect(prompts == 1)
    #expect(configuration == ProxyListeningConfiguration())
    #expect(!configuration.lan.isEnabled)
    #expect(try store.load() == configuration)
    #expect(try Data(contentsOf: oldURL) == old)
  }
  @Test func failedResetKeepsOriginalFileAndRequestsConfirmationAgain() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keys = TestLibraryKeys()
    let file = directory.appendingPathComponent("proxy-listening.enc")
    let store = ProxyListeningFileStore(fileURL: file, keys: keys)
    _ = try store.load()
    let original = try Data(contentsOf: file)
    keys.values.removeAll()
    keys.createFails = true
    var prompts = 0
    let restarted = ProxyListeningFileStore(fileURL: file, keys: keys)
    let configuration = ProxyListeningStartup.load(store: restarted) { _ in
      prompts += 1
      #expect((try? Data(contentsOf: file)) == original)
      if prompts >= 2 { keys.createFails = false }
    }
    #expect(prompts == 2)
    #expect(configuration == ProxyListeningConfiguration())
    #expect(try ProxyListeningFileStore(fileURL: file, keys: keys).load() == configuration)
  }
}
