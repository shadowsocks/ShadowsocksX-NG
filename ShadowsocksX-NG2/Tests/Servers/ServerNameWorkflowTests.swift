import Foundation
import Testing

@testable import ShadowsocksX_NG2

private struct ServerNameImportCase: Sendable {
  let host: String
  let port: Int
  let supplied: String?
  let expected: String

  static let all: [Self] = [
    .init(host: "203.0.113.7", port: 8388, supplied: nil, expected: "203.0.113.7:8388"),
    .init(host: "203.0.113.7", port: 8389, supplied: "", expected: "203.0.113.7:8389"),
    .init(host: "server.example", port: 443, supplied: "", expected: "server.example:443"),
    .init(host: "2001:db8::7", port: 8388, supplied: " \t\n ", expected: "[2001:db8::7]:8388"),
    .init(host: "server.example", port: 8388, supplied: " 香港 01 ", expected: " 香港 01 "),
  ]
}

/// 名称行为通过目录命令与导入 interface 观察，覆盖持久化和无副作用拒绝。
@MainActor
struct ServerNameWorkflowTests {
  @Test(arguments: ["", " \t\n ", "\u{3000}"])
  func manualCreateAndEditRejectBlankNamesWithoutWrites(_ name: String) async throws {
    try await withWorkflow { workflow, store in
      let id = try await workflow.createServer(Self.draft(name: "原名"), into: nil)
      let before = try store.load()
      let treeBefore = workflow.tree
      do {
        _ = try await workflow.createServer(Self.draft(name: name), into: nil)
        Issue.record("空白名称应拒绝新建")
      } catch {
        #expect(error as? ServerFormError == .emptyName)
      }
      do {
        try await workflow.updateServer(id, draft: Self.draft(name: name, password: "changed"))
        Issue.record("空白名称应拒绝编辑")
      } catch {
        #expect(error as? ServerFormError == .emptyName)
      }
      #expect(try store.load() == before)
      #expect(workflow.tree == treeBefore)
    }
  }

  @Test
  func manualNamesAreTrimmedAndGeneratedNamesSurviveEndpointEdits() async throws {
    try await withWorkflow { workflow, store in
      let created = try await workflow.createServer(Self.draft(name: " \t新名称\n "), into: nil)
      #expect(try workflow.serverEditForm(for: created)?.remark == "新名称")
      try await workflow.updateServer(created, draft: Self.draft(name: "\n编辑名称\t"))
      #expect(try workflow.serverEditForm(for: created)?.remark == "编辑名称")
      _ = await workflow.importServers(
        from: [
          .clipboardText(
            SsUri(method: "aes-256-gcm", password: "p", host: "203.0.113.7", port: 8388)
              .encode())
        ], into: nil)
      let imported = try #require(workflow.tree.roots.last)
      var edited = Self.draft(name: imported.name)
      edited.address = "198.51.100.9"
      edited.port = 9999
      try await workflow.updateServer(imported.id, draft: edited)
      #expect(try workflow.serverEditForm(for: imported.id)?.remark == "203.0.113.7:8388")
      #expect(try store.load().catalog.entry(for: imported.id)?.displayName == "203.0.113.7:8388")
    }
  }

  @Test(arguments: ServerNameImportCase.all)
  fileprivate func uriImportsSaveNames(_ sample: ServerNameImportCase) async throws {
    try await withWorkflow { workflow, store in
      let uri = SsUri(
        method: "aes-256-gcm", password: "p", host: sample.host, port: sample.port,
        remark: sample.supplied)
      let result = await workflow.importServers(from: [.clipboardText(uri.encode())], into: nil)
      #expect(result.sources.first?.result.importedCount == 1)
      let node = try #require(workflow.tree.roots.first)
      #expect(node.name == sample.expected)
      #expect(try workflow.serverEditForm(for: node.id)?.remark == sample.expected)
      #expect(try store.load().catalog.entry(for: node.id)?.displayName == sample.expected)
    }
  }

  @Test(arguments: ServerNameImportCase.all)
  fileprivate func legacyImportsSaveNames(_ sample: ServerNameImportCase) async throws {
    try await withWorkflow { _, store in
      var profile: [String: Any] = [
        "ServerHost": sample.host, "ServerPort": sample.port,
        "Method": "aes-256-gcm", "Password": "p",
      ]
      if let supplied = sample.supplied { profile["Remark"] = supplied }
      let snapshot = try LegacySnapshot(propertyList: ["ServerProfiles": [profile]])
      let importer = LegacyImportService(
        source: FixedLegacySnapshotProvider(snapshot: snapshot), catalogStore: store,
        marker: InMemoryLegacyImportMarker())
      let result = try importer.importCurrentSnapshot()
      #expect(result.report.importedServerCount == 1)
      let catalog = try store.load().catalog
      let group = try #require(catalog.entry(for: result.groupID))
      guard case .group(let fields) = group.kind else {
        Issue.record("预期导入分组")
        return
      }
      let id = try #require(fields.children.first)
      let entry = try #require(catalog.entry(for: id))
      #expect(entry.displayName == sample.expected)
      guard case .server(let server) = entry.kind else {
        Issue.record("预期服务器")
        return
      }
      #expect(server.remark == sample.expected)
    }
  }

  @Test(arguments: ServerNameImportCase.all)
  fileprivate func subscriptionImportsSaveNames(_ sample: ServerNameImportCase) async throws {
    let fetcher = FakeSubscriptionFetcher(behavior: .success(try Self.document(sample)))
    try await withWorkflow(fetcher: fetcher) { workflow, store in
      let subscription = try await workflow.createSubscription(
        urlString: "https://provider.example/s")
      let group = try #require(workflow.tree.node(withID: subscription.groupID))
      let node = try #require(group.childNodes.first)
      #expect(node.name == sample.expected)
      #expect(try workflow.serverEditForm(for: node.id)?.remark == sample.expected)
      #expect(try store.load().catalog.entry(for: node.id)?.displayName == sample.expected)
    }
  }

  @Test
  func subscriptionRenamesKeepIdentityAndRefreshesRegenerateMissingNames() async throws {
    let initial = ServerNameImportCase.all[0]
    let fetcher = FakeSubscriptionFetcher(behavior: .success(try Self.document(initial)))
    try await withWorkflow(fetcher: fetcher) { workflow, _ in
      let subscription = try await workflow.createSubscription(
        urlString: "https://provider.example/s")
      let id = try #require(workflow.tree.node(withID: subscription.groupID)?.childNodes.first?.id)
      fetcher.setBehavior(
        .success(
          try Self.document(
            .init(host: initial.host, port: initial.port, supplied: "远端新名", expected: "远端新名"))))
      await workflow.refreshSubscription(subscription.id)
      #expect(workflow.tree.node(withID: id)?.name == "远端新名")
      fetcher.setBehavior(.success(try Self.document(initial, password: "updated-password")))
      await workflow.refreshSubscription(subscription.id)
      #expect(try workflow.serverEditForm(for: id)?.password == "updated-password")
      fetcher.setBehavior(.success(try Self.document(initial)))
      await workflow.refreshSubscription(subscription.id)
      #expect(workflow.tree.node(withID: id)?.name == "203.0.113.7:8388")
      fetcher.setBehavior(.success(try Self.document(ServerNameImportCase.all[1])))
      await workflow.refreshSubscription(subscription.id)
      let replacement = try #require(
        workflow.tree.node(withID: subscription.groupID)?.childNodes.first)
      #expect(replacement.name == "203.0.113.7:8389")
      #expect(replacement.id != id)
    }
  }

  @Test
  func subscriptionRefreshReplacesSecretsAndClearsUnusedPluginOptions() async throws {
    let sample = ServerNameImportCase.all[0]
    let fetcher = FakeSubscriptionFetcher(
      behavior: .success(
        try Self.document(
          sample, plugin: "v2ray-plugin", pluginOptions: "mode=websocket")))
    try await withWorkflow(fetcher: fetcher) { workflow, _ in
      let subscription = try await workflow.createSubscription(
        urlString: "https://provider.example/s")
      let id = try #require(workflow.tree.node(withID: subscription.groupID)?.childNodes.first?.id)
      fetcher.setBehavior(
        .success(
          try Self.document(
            sample, password: "new-password", plugin: "v2ray-plugin", pluginOptions: "mode=quic")))
      await workflow.refreshSubscription(subscription.id)
      let updated = try #require(try workflow.serverEditForm(for: id))
      #expect(updated.password == "new-password")
      #expect(updated.plugin.options == "mode=quic")
      fetcher.setBehavior(.success(try Self.document(sample, password: "new-password")))
      await workflow.refreshSubscription(subscription.id)
      let cleared = try #require(try workflow.serverEditForm(for: id))
      #expect(cleared.password == "new-password")
      #expect(cleared.plugin.selection == .none)
      #expect(cleared.plugin.options.isEmpty)
      #expect(!cleared.plugin.optionsPresent)
    }
  }

  @Test
  func duplicateEndpointsRejectRefreshAndPreserveSavedSnapshot() async throws {
    let sample = ServerNameImportCase.all[0]
    let fetcher = FakeSubscriptionFetcher(behavior: .success(try Self.document(sample)))
    try await withWorkflow(fetcher: fetcher) { workflow, store in
      let subscription = try await workflow.createSubscription(
        urlString: "https://provider.example/s")
      let treeBefore = workflow.tree
      let catalogBefore = try store.load().catalog
      let duplicate = Data(
        """
        {"version":1,"servers":[
          {"server":"203.0.113.7","server_port":8388,"method":"aes-256-gcm","password":"p","remarks":"甲"},
          {"server":"203.0.113.7","server_port":8388,"method":"aes-256-gcm","password":"other","remarks":"乙"}
        ]}
        """.utf8)
      fetcher.setBehavior(.success(duplicate))
      await workflow.refreshSubscription(subscription.id)
      #expect(workflow.tree == treeBefore)
      #expect(try store.load().catalog == catalogBefore)
      guard case .failed(_, let failure) = workflow.subscriptions.first?.status else {
        Issue.record("重复端点应拒绝整个刷新")
        return
      }
      #expect(failure == .duplicateIdentity)
    }
  }

  @Test(arguments: ["server", "server_port", "method", "password", "plugin", "plugin_opts"])
  func idLessIdentityDependsOnlyOnEndpoint(_ changedField: String) throws {
    let base: [String: Any] = [
      "server": "203.0.113.7", "server_port": 8388, "method": "aes-256-gcm",
      "password": "p", "plugin": "v2ray-plugin", "plugin_opts": "mode=websocket",
    ]
    let replacements: [String: Any] = [
      "server": "203.0.113.8", "server_port": 8389, "method": "aes-128-gcm",
      "password": "p2", "plugin": "other-plugin", "plugin_opts": "mode=quic",
    ]
    func identity(_ server: [String: Any]) throws -> NodeID {
      let data = try JSONSerialization.data(withJSONObject: ["version": 1, "servers": [server]])
      let snapshot = try SubscriptionDocumentParser.parse(
        data, subscriptionID: NodeID(rawValue: "sub"))
      guard case .server(let leaf) = snapshot.root.children.first else {
        throw NSError(domain: "ServerNameTests", code: 1)
      }
      return leaf.id
    }
    var changed = base
    changed[changedField] = replacements[changedField]
    if changedField == "server" || changedField == "server_port" {
      #expect(try identity(base) != identity(changed))
    } else {
      #expect(try identity(base) == identity(changed))
    }
  }

  @Test
  func providerIDsAllowDistinctServersAtTheSameEndpoint() throws {
    let data = Data(
      """
      {"version":1,"servers":[
        {"id":"aaaaaaaa-0000-4000-8000-00000000000a","server":"203.0.113.7","server_port":8388,
         "method":"aes-256-gcm","password":"p","remarks":"甲"},
        {"id":"bbbbbbbb-0000-4000-8000-00000000000b","server":"203.0.113.7","server_port":8388,
         "method":"aes-256-gcm","password":"other","remarks":"乙"}
      ]}
      """.utf8)
    let snapshot = try SubscriptionDocumentParser.parse(
      data, subscriptionID: NodeID(rawValue: "sub"))
    #expect(snapshot.root.children.count == 2)
  }

}

extension ServerNameWorkflowTests {
  private static func draft(name: String, password: String = "p") -> ServerEditDraft {
    ServerEditDraft(
      address: "203.0.113.7", port: 8388, encryptionMethod: "aes-256-gcm", password: password,
      remark: name, plugin: .none, pluginOptions: nil)
  }

  private static func document(
    _ sample: ServerNameImportCase, password: String = "p", plugin: String? = nil,
    pluginOptions: String? = nil
  ) throws -> Data {
    var server: [String: Any] = [
      "server": sample.host, "server_port": sample.port, "method": "aes-256-gcm",
      "password": password,
    ]
    if let supplied = sample.supplied { server["remarks"] = supplied }
    if let plugin { server["plugin"] = plugin }
    if let pluginOptions { server["plugin_opts"] = pluginOptions }
    return try JSONSerialization.data(withJSONObject: ["version": 1, "servers": [server]])
  }

  private func withWorkflow(
    fetcher: SubscriptionFetching = FakeSubscriptionFetcher(behavior: .success(Data())),
    _ body:
      @MainActor (CatalogWorkflow, CatalogFileStore) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("server-name-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json"))
    let coordinator = CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime())
    let workflow = makeCatalogWorkflow(
      coordinator: coordinator, subscriptionFetcher: fetcher)
    try await body(workflow, store)
  }
}
