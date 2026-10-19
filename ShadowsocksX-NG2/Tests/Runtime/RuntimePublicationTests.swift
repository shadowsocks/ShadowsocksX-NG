import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct RuntimePublicationTests {
  @Test func publicationDoesNotSelectActiveLinks() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let source = ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL))
    try store.write(source)
    #expect(
      (try? FileManager.default.destinationOfSymbolicLink(atPath: store.aclFileURL.path)) == nil)
    #expect(!FileManager.default.fileExists(atPath: runtime.contract.path))
    #expect(store.loadDocument() == source)
  }
}

extension RuntimePublicationTests {
  @Test func supervisionContainsNoCredentialsAndAuthenticationUsesOpaqueIdentity() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    var listen = ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces)
    listen.lan.authenticationEnabled = true
    listen.lan.username = "sample-lan-user"
    listen.lan.passwordReference = "sample-keychain-reference"
    let auth = RuntimeListenerAuthentication(
      username: listen.lan.username,
      password: "sample-lan-password", directory: runtime.directory.path)
    let document = SslocalRuntimeDocument(
      servers: [
        .init(
          id: "server", server: "127.0.0.1", serverPort: 8388,
          password: "sample-server-password", method: "aes-256-gcm",
          plugin: "plugin", pluginOpts: "sample-plugin-secret")
      ], listen: listen
    ).authenticatingLAN(auth)
    try store.write(document)
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let bytes = try String(contentsOf: store.supervisionFileURL, encoding: .utf8)
    for secret in [
      auth.username, auth.password, "sample-keychain-reference", "sample-server-password",
      "sample-plugin-secret", ProxyACLDocument.digest(auth.username + ":" + auth.password),
    ] {
      #expect(!bytes.contains(secret))
    }
    #expect(snapshot.authenticationID.flatMap(UUID.init(uuidString:)) != nil)
    #expect(snapshot.authenticationFiles.count == 2)
    try store.write(document)
    let next = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(next.generation > snapshot.generation)
    #expect(next.authenticationID == snapshot.authenticationID)
    #expect(next.authenticationFiles == snapshot.authenticationFiles)
    #expect(next.configuration != snapshot.configuration)
    let rotated = document.authenticatingLAN(
      .init(
        username: auth.username,
        password: "new-password", directory: runtime.directory.path))
    try store.write(rotated)
    let last = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(last.requiresRestart(from: next))
    #expect(last.authenticationID != next.authenticationID)
  }

  @Test func invalidVersionsAndEscapingReferencesAreRejected() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    try store.write(ProxyRuntimeFixture.makeDocument())
    let bytes = try Data(contentsOf: store.supervisionFileURL)
    for (key, value) in [("version", 99 as Any), ("configuration", "../outside.json" as Any)] {
      var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
      object[key] = value
      try AtomicFileWriter.write(
        JSONSerialization.data(withJSONObject: object), to: store.supervisionFileURL)
      #expect(RuntimePublication.load(at: store.supervisionFileURL) == nil)
    }
    try AtomicFileWriter.write(bytes, to: store.supervisionFileURL)
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let url = runtime.directory.appendingPathComponent(snapshot.configuration)
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/etc/hosts")
    #expect(RuntimePublication.load(at: store.supervisionFileURL) == nil)
  }

  @Test func generationOverflowAndCorruptionNeverReplacePublication() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    try store.write(ProxyRuntimeFixture.makeDocument())
    let before = try Data(contentsOf: store.supervisionFileURL)
    for value in [String(UInt64.max), "broken"] {
      try AtomicFileWriter.write(
        Data(value.utf8), to: runtime.directory.appendingPathComponent("runtime-generation"))
      #expect(throws: (any Error).self) { try store.write(ProxyRuntimeFixture.makeDocument()) }
      #expect(try Data(contentsOf: store.supervisionFileURL) == before)
    }
  }
}
