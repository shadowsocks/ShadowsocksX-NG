import Darwin
import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct RuntimePublicationTests {
  @Test func aclAndServerChangesDoNotRequireRestart() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    try store.write(
      ProxyRuntimeFixture.makeDocument().replacingACL(.global(at: store.aclFileURL)))
    let previous = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try store.write(
      ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9")
        .replacingACL(.direct(at: store.aclFileURL)))
    let next = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(next.acl != previous.acl)
    #expect(next.configurationID != previous.configurationID)
    #expect(next.reloadSignals(from: previous) == [SIGUSR1, SIGUSR2])
    #expect(!next.requiresRestart(from: previous))
  }

  @Test func configurationIdentitySurvivesACLOnlyPublicationAndLegacyReloadIsConservative() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let source = ProxyRuntimeFixture.makeDocument().replacingACL(.global(at: store.aclFileURL))
    try store.write(source)
    let previous = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try store.write(source.replacingACL(.direct(at: store.aclFileURL)))
    let next = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(previous.configurationID != nil)
    #expect(next.configurationID == previous.configurationID)
    #expect(next.configuration != previous.configuration)
    #expect(next.reloadSignals(from: previous) == [SIGUSR2])
    let bytes = try JSONEncoder().encode(next)
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    object.removeValue(forKey: "configurationID")
    let legacy = try JSONDecoder().decode(
      RuntimeSupervision.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(legacy.hasValidStructure)
    #expect(legacy.reloadSignals(from: legacy) == [SIGUSR1])
  }

  @Test func publicationDoesNotSelectActiveLinks() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let source = ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL))
    try store.write(source)
    #expect(
      (try? FileManager.default.destinationOfSymbolicLink(atPath: store.aclFileURL.path)) == nil)
    #expect(!FileManager.default.fileExists(atPath: runtime.contract.path))
    #expect(try store.contains(PreparedRuntimeContract(source)))
  }
}

extension RuntimePublicationTests {
  @Test func opaqueConfigurationUsesExplicitMetadataThroughSelectionAndRetirement() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let document = ProxyRuntimeFixture.makeDocument()
    try store.write(document)
    let original = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let bytes = try Data(contentsOf: store.supervisionFileURL)
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let prefix = String(format: "config-%020llu-", original.generation)
    let configuration = prefix + "payload.bin"
    let metadata = prefix + "gui-metadata.dat"
    try FileManager.default.moveItem(
      at: runtime.directory.appendingPathComponent(original.intentMetadata),
      to: runtime.directory.appendingPathComponent(metadata))
    let payload = Data([0x00, 0xff, 0x80, 0x01])
    try AtomicFileWriter.write(payload, to: runtime.directory.appendingPathComponent(configuration))
    object["configuration"] = configuration
    object["intentMetadata"] = metadata
    try AtomicFileWriter.write(
      JSONSerialization.data(withJSONObject: object), to: store.supervisionFileURL)

    let selected = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(store.publishedSummary()?.contains("servers=1") == true)
    try RuntimePublication.select(
      selected, configurationLink: runtime.contract, aclLink: store.aclFileURL)
    #expect(try Data(contentsOf: runtime.contract) == payload)
    try store.write(document)
    let next = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try RuntimePublication.retire(
      before: next, publishedAt: store.supervisionFileURL, protecting: selected.retainedFiles)
    for name in [configuration, metadata] {
      #expect(
        FileManager.default.fileExists(atPath: runtime.directory.appendingPathComponent(name).path))
    }
    try RuntimePublication.select(
      next, configurationLink: runtime.contract, aclLink: store.aclFileURL)
    try RuntimePublication.retire(
      before: next, publishedAt: store.supervisionFileURL, protecting: [])
    for name in [configuration, metadata] {
      #expect(
        !FileManager.default.fileExists(atPath: runtime.directory.appendingPathComponent(name).path)
      )
    }
    #expect(try store.contains(PreparedRuntimeContract(document)))
  }

  @Test func metadataReferenceIsRequiredAndMustBeDistinctAndFromTheSameGeneration() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    try store.write(ProxyRuntimeFixture.makeDocument())
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let bytes = try Data(contentsOf: store.supervisionFileURL)
    let invalidReferences: [String?] = [
      nil, "../outside.json", snapshot.configuration,
      String(format: "config-%020llu-intent.json", snapshot.generation - 1),
      String(format: "config-%020llu-intent.json", snapshot.generation + 1),
      String(format: "auth-%020llu-intent.json", snapshot.generation),
    ]
    for reference in invalidReferences {
      var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
      object["intentMetadata"] = reference
      try AtomicFileWriter.write(
        JSONSerialization.data(withJSONObject: object), to: store.supervisionFileURL)
      #expect(RuntimePublication.metadata(at: store.supervisionFileURL) == nil)
    }
  }

  @Test func missingOrSymlinkedMetadataPreventsDeploymentSelection() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    try store.write(ProxyRuntimeFixture.makeDocument())
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let metadataURL = runtime.directory.appendingPathComponent(snapshot.intentMetadata)
    try FileManager.default.removeItem(at: metadataURL)
    #expect(RuntimePublication.load(at: store.supervisionFileURL) == nil)
    #expect(throws: (any Error).self) {
      try RuntimePublication.select(
        snapshot, configurationLink: runtime.contract, aclLink: store.aclFileURL)
    }
    try FileManager.default.createSymbolicLink(
      at: metadataURL,
      withDestinationURL: runtime.directory.appendingPathComponent(snapshot.configuration))
    #expect(RuntimePublication.load(at: store.supervisionFileURL) == nil)
    #expect(throws: (any Error).self) {
      try RuntimePublication.select(
        snapshot, configurationLink: runtime.contract, aclLink: store.aclFileURL)
    }
    #expect(!FileManager.default.fileExists(atPath: runtime.contract.path))
  }

  @Test func routingIntentChangesEvenWhenUpstreamJSONDoesNot() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let direct = ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL))
    let global = direct.replacingACL(.global(at: store.aclFileURL))
    try store.write(direct)

    #expect(try direct.jsonData() == global.jsonData())
    #expect(try store.contains(PreparedRuntimeContract(direct)))
    #expect(try !store.contains(PreparedRuntimeContract(global)))
    #expect(store.receiptIdentity(for: global) == nil)
    #expect(store.publishedSummary()?.contains("servers=1") == true)
  }

  @Test func damagedOutputIsNotConsideredCurrentAndKeepsFailureIdentity() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let document = ProxyRuntimeFixture.makeDocument()
    try store.write(document)
    try store.recordFailure(reason: "test failure")
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try AtomicFileWriter.write(
      Data("damaged output".utf8),
      to: runtime.directory.appendingPathComponent(snapshot.configuration))

    #expect(try !store.contains(PreparedRuntimeContract(document)))
    #expect(store.blocksDeployment(document))
    #expect(store.receiptIdentity(for: document) == snapshot.deploymentID)
    #expect(store.publishedSummary()?.contains("servers=1") == true)
  }

  @Test func publishedConfigurationContainsOnlyUpstreamFields() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    var listen = ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces)
    listen.lan.authenticationEnabled = true
    let document = SslocalRuntimeDocument(
      servers: [], listen: listen, acl: .direct(at: store.aclFileURL)
    ).authenticatingLAN(
      .init(username: "user", password: "lan-secret", directory: runtime.directory.path))
    try store.write(document)
    let snapshot = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let data = try Data(
      contentsOf: runtime.directory.appendingPathComponent(snapshot.configuration))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["servers", "locals", "acl"])
    #expect(data.range(of: Data("lan-secret".utf8)) == nil)
    #expect(object["acl"] as? String == store.aclFileURL.path)
  }

  @Test func supervisionContainsNoCredentialsAndAuthenticationUsesOpaqueIdentity() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    var listen = ProxyListeningConfiguration(listenerMode: .allIPv4Interfaces)
    listen.lan.authenticationEnabled = true
    listen.lan.username = "sample-lan-user"
    listen.lan.password = "sample-keychain-reference"
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
    for (key, value) in [
      ("version", 1 as Any), ("version", 99 as Any), ("configuration", "../outside.json" as Any),
      ("configurationID", "invalid-identity" as Any),
    ] {
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

extension RuntimePublicationTests {
  @Test func defaultStorageSeparatesConfigurationRuntimeAndLogs() {
    let configurationFiles = [
      CatalogFileStore.defaultFileURL(), ProxyListeningFileStore.defaultFileURL(),
      ActivationStateFileStore.defaultFileURL(), CustomRuleStore.defaultFileURL(),
      PluginMappingFileStore().fileURL,
    ]
    for file in configurationFiles {
      #expect(file.deletingLastPathComponent().lastPathComponent == "configuration")
    }
    #expect(ApplicationSupportPaths.current.runtime.directoryURL.lastPathComponent == "runtime")
    #expect(
      ApplicationSupportPaths.current.agentLogURL.deletingLastPathComponent().lastPathComponent
        == "logs")
  }
}

extension RuntimePublicationTests {
  @Test func stoppingRuntimePreservesConfigurationLogsAndCoordinationFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ApplicationSupportPaths(rootURL: root)
    let preserved = [
      paths.catalogFileURL, paths.proxyListeningFileURL, paths.customRulesFileURL,
      paths.activationStateFileURL, paths.pluginMappingFileURL, paths.agentLogURL,
      paths.configurationDirectoryURL.appendingPathComponent(".catalog.enc.tmp-in-flight"),
      root.appendingPathComponent("catalog.enc"),
    ]
    let sentinel = Data("must survive stopping the runtime".utf8)
    for file in preserved { try AtomicFileWriter.write(sentinel, to: file) }
    let store = RuntimeFileStore(fileURL: paths.runtime.fileURL)
    let document = ProxyRuntimeFixture.makeDocument().replacingACL(
      .direct(at: paths.runtime.aclFileURL))
    try store.write(document)
    let first = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try RuntimePublication.select(
      first, configurationLink: store.fileURL, aclLink: store.aclFileURL)
    try AtomicFileWriter.write(Data(), to: paths.runtime.agentLockURL)
    try store.deleteRuntimeFiles()

    for file in preserved { #expect(try Data(contentsOf: file) == sentinel) }
    #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    #expect(!FileManager.default.fileExists(atPath: store.supervisionFileURL.path))
    #expect(
      try Set(FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path))
        == ["runtime-generation", "runtime.lock", "agent.lock"])
    try store.write(document)
    let next = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(next.generation > first.generation)
  }
}

extension RuntimePublicationTests {
  @Test func newLayoutDoesNotLoadOrModifyFlatConfiguration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = ApplicationSupportPaths(rootURL: root)
    let oldURL = root.appendingPathComponent("catalog.enc")
    let oldStore = makeTestCatalogStore(fileURL: oldURL)
    var catalog = ConfigurationCatalog()
    _ = try catalog.addTestServer("old-layout")
    try oldStore.save(CatalogDocument(catalog: catalog))
    let oldBytes = try Data(contentsOf: oldURL)
    let newStore = makeTestCatalogStore(fileURL: paths.catalogFileURL)
    #expect(try newStore.load().catalog == ConfigurationCatalog())
    #expect(try Data(contentsOf: oldURL) == oldBytes)
    #expect(try oldStore.load().catalog == catalog)
  }
}
