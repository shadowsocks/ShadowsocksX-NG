import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct PluginRecordTests {
  @Test(arguments: [
    #"""
    {"userPlugins":[{"id":"00000000-0000-0000-0000-000000000001","names":["tool"],
    "path":"/missing/tool","arguments":[],"plugin_mode":"udp_only"}],"managedArguments":{}}
    """#,
    #"""
    {"userPlugins":[],"managedArguments":{},
    "managedModes":{"v2ray-plugin":"udp_only"}}
    """#,
  ])
  func unknownTransportModeBlocksReadingWithoutRewriting(configurationJSON: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let original = Data(
      "{\"version\":2,\"configuration\":\(configurationJSON)}".utf8)
    try original.write(to: store.fileURL)
    #expect(throws: PluginMappingError.unreadable) { try store.load() }
    #expect(try Data(contentsOf: store.fileURL) == original)
  }

  @Test func oldV2RecordsDefaultToTCPWithoutRewriting() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let original = Data(
      #"""
      {"version":2,"configuration":{"userPlugins":[
      {"id":"00000000-0000-0000-0000-000000000001","names":["tool"],
      "path":"/missing/tool","arguments":[]}],"managedArguments":{}}}
      """#
      .utf8)
    try original.write(to: store.fileURL)
    let configuration = try store.load()
    #expect(configuration.userPlugins.first?.mode == .tcpOnly)
    #expect(
      PluginCatalogSnapshot(configuration: configuration).managedRecords["v2ray-plugin"]?.mode
        == .tcpOnly)
    #expect(try Data(contentsOf: store.fileURL) == original)
    try store.save(configuration)
    #expect(try store.load() == configuration)
  }

  @Test @MainActor func managedModePersistsAcrossAliasesAndArgumentClearing() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    try Data(
      #"""
      {"version":2,"configuration":{"userPlugins":[],
      "managedArguments":{"v2ray-plugin":["--verbose"]},
      "managedModes":{"v2ray-plugin":"tcp_and_udp"}}}
      """#
      .utf8
    ).write(to: store.fileURL)
    let managed = BundleManagedPluginProvider(bundleURL: root)
    let catalog = PluginCatalog(store: store, managed: managed, inspector: QuietPluginInspector())
    #expect(catalog.resolve(program: "v2ray-plugin-v1")?.mode == .tcpAndUDP)
    try catalog.commit([.managedArguments(program: "v2ray-plugin", arguments: [])])
    let restored = PluginCatalog(store: store, managed: managed, inspector: QuietPluginInspector())
    #expect(restored.resolve(program: "v2ray-plugin")?.mode == .tcpAndUDP)
    #expect(restored.resolve(program: "v2ray-plugin")?.arguments == [])
    try restored.commit([.save(UserPluginRecord(names: ["v2ray-plugin"], path: binary.path))])
    #expect(restored.resolve(program: "v2ray-plugin")?.mode == .tcpOnly)
    #expect(restored.resolve(program: "v2ray-plugin-v1")?.mode == .tcpAndUDP)
  }

  @Test @MainActor func nameConflictAndInvalidArgumentsDoNotPublish() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let catalog = PluginCatalog(store: store, inspector: QuietPluginInspector())
    let first = UserPluginRecord(names: ["tool", "tool-v2"], path: binary.path)
    try catalog.commit([.save(first)])
    let bytes = try Data(contentsOf: store.fileURL)
    let generation = catalog.catalogSnapshot().generation
    #expect(throws: PluginMappingError.nameExists) {
      try catalog.commit([.save(UserPluginRecord(names: ["tool-v2"], path: binary.path))])
    }
    #expect(throws: PluginMappingError.invalidArguments) {
      try catalog.commit([.managedArguments(program: "v2ray-plugin", arguments: ["bad\0value"])])
    }
    #expect(try Data(contentsOf: store.fileURL) == bytes)
    #expect(catalog.catalogSnapshot().generation == generation)
    #expect(catalog.userRecords == [first])
    var renamed = first
    renamed.names = ["tool-v2"]
    try catalog.commit([.save(renamed)])
    #expect(catalog.resolve(program: "tool") == nil)
    #expect(catalog.userRecords.first?.id == first.id)
    #expect(catalog.resolve(program: "tool-v2")?.path == binary.path)
  }

  @Test func legacyMappingsMigrateIndependentlyAndReadDoesNotRewriteFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let original = Data(
      #"{"version":1,"mappings":{"tool":"/missing/tool","tool-v2":"/missing/tool"}}"#.utf8)
    try original.write(to: store.fileURL)
    let configuration = try store.load()
    #expect(configuration.userPlugins.count == 2)
    #expect(Set(configuration.userPlugins.map(\.id)).count == 2)
    #expect(configuration.userPlugins.map(\.names) == [["tool"], ["tool-v2"]])
    #expect(
      configuration.userPlugins.allSatisfy {
        $0.arguments.isEmpty && $0.path == "/missing/tool" && $0.mode == .tcpOnly
      })
    #expect(try Data(contentsOf: store.fileURL) == original)
    try store.save(configuration)
    #expect(try store.load() == configuration)
    let json = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
    #expect(json["version"] as? Int == 2)
  }

  @Test(arguments: [PluginTransportMode.tcpOnly, .tcpAndUDP])
  @MainActor func activationWritesLocalArgumentsWithoutChangingServerOptions(
    mode: PluginTransportMode
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let plugins = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      inspector: QuietPluginInspector())
    try plugins.commit([
      .save(
        UserPluginRecord(
          names: ["tool", "tool-v2"], path: binary.path,
          arguments: ["--threads", "4", "--log-file", "/tmp/My Log.txt", ""], mode: mode))
    ])
    var catalog = ConfigurationCatalog()
    let leaf = try ActivationFixture.addPlainServer(
      "Plugin", in: &catalog)
    var fields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    fields.pluginProgram = "tool-v2"
    fields.pluginOptions = "options"
    fields.pluginOptions = "tls;host=example.com"
    try catalog.updateServer(leaf, with: fields)
    var machine = ActivationStateMachine()
    let runtime = try machine.activate(
      leaf, in: catalog, plugins: plugins,
      options: RuntimeDocumentOptions(listen: ActivationFixture.listen))
    let json = try #require(
      JSONSerialization.jsonObject(with: runtime.document.jsonData()) as? [String: Any])
    let server = try #require((json["servers"] as? [[String: Any]])?.first)
    #expect(
      server["plugin_args"] as? [String] == ["--threads", "4", "--log-file", "/tmp/My Log.txt", ""])
    #expect(server["plugin_mode"] as? String == (mode == .tcpAndUDP ? "tcp_and_udp" : nil))
    #expect(server["plugin"] as? String == binary.path)
    #expect(server["plugin_opts"] as? String == "tls;host=example.com")
    #expect(try ActivationFixture.serverFields(of: leaf, in: catalog).pluginProgram == "tool-v2")
  }

  @Test @MainActor func aliasesShareArgumentsAndOnlyExplicitNamesOverrideManaged() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let catalog = PluginCatalog(
      store: store, managed: BundleManagedPluginProvider(bundleURL: root),
      inspector: QuietPluginInspector())
    let record = UserPluginRecord(
      names: ["v2ray-plugin", "custom-v2"], path: binary.path,
      arguments: ["--config", "/Users/me/My Config.json", "", "--verbose"])
    try catalog.commit([.save(record)])
    let snapshot = catalog.catalogSnapshot()
    #expect(snapshot.resolve(program: "custom-v2")?.arguments == record.arguments)
    #expect(snapshot.resolve(program: "v2ray-plugin") == snapshot.resolve(program: "custom-v2"))
    #expect(snapshot.entry(for: "v2ray-plugin-v1")?.source == .managed)
    #expect(snapshot.resolve(program: "v2ray-plugin-v1")?.arguments == [])
    let restored = PluginCatalog(store: store, inspector: QuietPluginInspector())
    #expect(restored.userRecords == [record])
  }

}

extension PluginRecordTests {
  @Test @MainActor func cloakOverrideOnlyReplacesExplicitAlias() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = root.appendingPathComponent("Contents/Helpers/Plugins/ck-client")
    try FileManager.default.createDirectory(
      at: client.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: client)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: client.path)
    let catalog = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      managed: BundleManagedPluginProvider(bundleURL: root), inspector: QuietPluginInspector())
    try catalog.commit([.managedArguments(program: "ck-client", arguments: ["-v"])])
    let userClient = root.appendingPathComponent("user-client")
    try Data("#!/bin/sh\n".utf8).write(to: userClient)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: userClient.path)
    let user = UserPluginRecord(
      names: ["cloak"], path: userClient.path, arguments: ["-c", "local.json"])
    try catalog.commit([.save(user)])
    #expect(catalog.resolve(program: "cloak")?.arguments == user.arguments)
    #expect(catalog.resolve(program: "cloak-v2")?.arguments == ["-v"])
    #expect(catalog.catalogSnapshot().entry(for: "cloak")?.source == .user)
    #expect(catalog.catalogSnapshot().entry(for: "cloak-v2")?.source == .managed)
    try FileManager.default.removeItem(at: userClient)
    #expect(catalog.resolve(program: "cloak") == nil)
    #expect(catalog.resolve(program: "cloak-v2")?.path == client.path)
    #expect(catalog.catalogSnapshot().entry(for: "cloak")?.source == .user)
    try catalog.commit([.remove(user.id)])
    #expect(catalog.resolve(program: "cloak")?.arguments == ["-v"])
  }
}

extension PluginRecordTests {
  @Test @MainActor func sharingKeepsReferenceAndOptionsWithoutLocalArguments() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let plugins = PluginCatalog(
      store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
      inspector: QuietPluginInspector())
    try plugins.commit([
      .save(
        UserPluginRecord(
          names: ["tool", "tool-v2"], path: binary.path,
          arguments: ["--local-argument-sentinel"], mode: .tcpAndUDP))
    ])
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), plugins: plugins)
    let group = try await workflow.createGroup(named: "Share", into: nil)
    let id = try await workflow.createServer(
      ServerEditDraft(
        address: "example.com", port: 8388,
        encryptionMethod: "aes-256-gcm", password: "pw", remark: "Plugin",
        plugin: .named(program: "tool-v2"), pluginOptions: "tls;host=example.com"), into: group)
    let draft = try workflow.configurationGroupExportDraft(for: group)
    let json = try #require(JSONSerialization.jsonObject(with: draft.data) as? [String: Any])
    let server = try #require((json["servers"] as? [[String: Any]])?.first)
    #expect(server["plugin"] as? String == "tool-v2")
    #expect(server["plugin_opts"] as? String == "tls;host=example.com")
    #expect(server["plugin_args"] == nil)
    #expect(server["plugin_mode"] == nil)
    let uri = try workflow.shareURI(for: id)
    #expect(uri.contains("tool-v2"))
    #expect(!uri.contains("local-argument-sentinel"))
    #expect(!uri.contains("tcp_and_udp"))
    let exportedText = try #require(String(bytes: draft.data, encoding: .utf8))
    #expect(!exportedText.contains(binary.path))
  }

  @Test @MainActor func managedArgumentsRemainWithUncoveredAliasesAndCanBeCleared() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    let store = PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json"))
    let managed = BundleManagedPluginProvider(bundleURL: root)
    let catalog = PluginCatalog(store: store, managed: managed, inspector: QuietPluginInspector())
    try catalog.commit([.managedArguments(program: "v2ray-plugin", arguments: ["--verbose"])])
    #expect(catalog.resolve(program: "v2ray-plugin-v1")?.arguments == ["--verbose"])
    let user = UserPluginRecord(
      names: ["v2ray-plugin"], path: binary.path, arguments: ["--threads", "4"])
    try catalog.commit([.save(user)])
    #expect(catalog.resolve(program: "v2ray-plugin")?.arguments == ["--threads", "4"])
    let restored = PluginCatalog(store: store, managed: managed, inspector: QuietPluginInspector())
    #expect(restored.resolve(program: "v2ray-plugin-v1")?.arguments == ["--verbose"])
    try restored.commit([.managedArguments(program: "v2ray-plugin", arguments: [])])
    #expect(restored.resolve(program: "v2ray-plugin-v1")?.arguments == [])
    #expect(restored.resolve(program: "v2ray-plugin")?.arguments == ["--threads", "4"])
    try restored.commit([.remove(user.id)])
    #expect(restored.resolve(program: "v2ray-plugin")?.arguments == [])
  }
}
