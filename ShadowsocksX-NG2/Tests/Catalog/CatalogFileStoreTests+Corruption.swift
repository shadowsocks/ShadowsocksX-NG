import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct ServerLibraryCorruptionTests {
  @Test func damagedFileIsPreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("catalog.age")
    let original = Data("damaged-ciphertext".utf8)
    try original.write(to: url)
    let store = makeTestCatalogStore(fileURL: url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: url) == original)
  }
}
