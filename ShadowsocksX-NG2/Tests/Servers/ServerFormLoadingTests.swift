import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ServerFormLoadingTests {
  @Test func absentServerCannotLoadAnEditForm() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.enc")),
        runtime: FakeCatalogRuntime()))
    #expect(try workflow.serverEditForm(for: .fresh()) == nil)
  }
  @Test
  func appearingAgainAndUpdatingPresentationDoNotReloadManualDraft() {
    let fields = ServerFormFields()
    let id = NodeID(rawValue: "manual")
    var reads = 0
    let load = { (_: NodeID) -> ServerEditForm? in
      reads += 1
      return Self.form()
    }
    fields.showServer(id, load: load)
    fields.remark = "未保存名称"
    fields.showServer(id, load: load)
    fields.updatePresentation(ServerFormPresentation(isEditable: true, plugin: Self.form().plugin))
    #expect(reads == 1)
    #expect(fields.remark == "未保存名称")
    #expect(fields.hasChanges)
    fields.reloadServer(load: load)
    #expect(reads == 2)
    #expect(fields.remark == "服务器")
    #expect(!fields.hasChanges)
  }

  @Test
  func resetFailurePreservesManualDraftButBlocksSavingUntilReloadSucceeds() {
    let fields = ServerFormFields()
    fields.showServer(NodeID(rawValue: "manual")) { _ in Self.form() }
    fields.password = "edited password"
    fields.reloadServer { _ in throw ServerFormLoadError.credentialsUnavailable }
    #expect(fields.password == "edited password")
    #expect(fields.hasLoadedServer)
    #expect(!fields.canSaveServer)
    #expect(fields.loadFailure == .credentialsUnavailable)
    fields.reloadServer { _ in Self.form(password: "latest") }
    #expect(fields.password == "latest")
    #expect(fields.canSaveServer)
    #expect(fields.loadFailure == nil)
    #expect(!fields.hasChanges)
  }

  @Test
  func failedSelectionNeverShowsPreviousServerAndLateSaveDoesNotResetNewDraft() {
    let fields = ServerFormFields()
    let first = NodeID(rawValue: "first")
    let second = NodeID(rawValue: "second")
    fields.showServer(first) { _ in Self.form() }
    fields.showServer(second) { _ in throw ServerFormLoadError.credentialsUnavailable }
    #expect(fields.password.isEmpty)
    #expect(fields.address.isEmpty)
    #expect(!fields.hasLoadedServer)
    #expect(!fields.canSaveServer)
    fields.reloadServer { _ in Self.form(password: "second password") }
    fields.password = "unsaved second password"
    fields.didSaveServer(first) { _ in
      Issue.record("保存其他服务器不应装载当前草稿")
      return Self.form()
    }
    #expect(fields.password == "unsaved second password")
    fields.didSaveServer(second) { _ in Self.form(password: "saved second password") }
    #expect(fields.password == "saved second password")
    #expect(!fields.hasChanges)
  }

  @Test
  func onlyAffectedReadOnlyServerReloadsAndFailedReloadClearsOldFields() {
    let fields = ServerFormFields()
    let id = NodeID(rawValue: "subscription")
    fields.showServer(id) { _ in Self.form(isEditable: false) }
    fields.subscriptionDidRefresh(affectedServers: [NodeID(rawValue: "other")]) { _ in
      Issue.record("其他订阅不应触发装载")
      return nil
    }
    #expect(fields.password == "pw")
    fields.subscriptionDidRefresh(affectedServers: [id]) { _ in
      throw ServerFormLoadError.credentialsUnavailable
    }
    #expect(fields.password.isEmpty)
    #expect(fields.portText.isEmpty)
    #expect(fields.pluginOptions.composedString == "")
    #expect(!fields.hasLoadedServer)
    #expect(fields.loadFailure == .credentialsUnavailable)
    fields.updatePresentation(
      ServerFormPresentation(isEditable: false, plugin: Self.form().plugin))
    fields.subscriptionDidRefresh(affectedServers: [id]) { _ in
      Self.form(isEditable: false, password: "new password")
    }
    #expect(fields.password == "new password")
    #expect(fields.loadFailure == nil)

    fields.showServer(NodeID(rawValue: "manual")) { _ in Self.form() }
    fields.password = "manual draft"
    fields.subscriptionDidRefresh(affectedServers: [fields.serverID!]) { _ in
      Issue.record("手动草稿不应自动装载")
      return nil
    }
    #expect(fields.password == "manual draft")
  }

  @Test func presentationOmitsSecretsAndEditFormReadsCompleteRecord() async throws {
    try await Self.withWorkflow(credentials: InMemoryCredentialStore()) { workflow in
      let program = ManagedPluginCatalog.plugins[0].program
      let id = try await workflow.createServer(
        ServerEditDraft(
          address: "203.0.113.1", port: 8388, encryptionMethod: "aes-256-gcm",
          password: "pw", remark: "服务器", plugin: .named(program: program),
          pluginOptions: "mode=websocket"), into: nil)
      let presentation = try #require(workflow.serverFormPresentation(for: id))
      #expect(presentation.isEditable)
      #expect(presentation.plugin.optionsPresent)
      #expect(presentation.plugin.options.isEmpty)
      let form = try #require(try workflow.serverEditForm(for: id))
      #expect(form.password == "pw")
      #expect(form.plugin.options == "mode=websocket")
    }
  }

  @Test
  func successfulRefreshReloadsSecretChangesAndFailureDoesNotReload() async throws {
    let fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.flat(serverCount: 1)))
    let credentials = InMemoryCredentialStore()
    try await Self.withWorkflow(credentials: credentials, fetcher: fetcher) { workflow in
      let summary = try await workflow.createSubscription(urlString: "https://example.com/sub.json")
      let server = try #require(workflow.tree.node(withID: summary.groupID)?.childNodes.first)
      let fields = ServerFormFields()
      fields.showServer(server.id, load: workflow.serverEditForm)
      let oldTree = workflow.tree
      var reloads = 0
      let observation = workflow.subscriptionServerRefreshes.sink { affected in
        fields.updatePresentation(workflow.serverFormPresentation(for: server.id))
        fields.subscriptionDidRefresh(affectedServers: affected) { id in
          reloads += 1
          return try workflow.serverEditForm(for: id)
        }
      }
      defer { observation.cancel() }
      let original = try #require(
        String(data: SubscriptionDocs.flat(serverCount: 1), encoding: .utf8))
      let changed = original.replacingOccurrences(
        of: "\"password\": \"pw\"", with: "\"password\": \"new password\"")
      fetcher.setBehavior(.success(Data(changed.utf8)))
      await workflow.refreshSubscription(summary.id)
      #expect(workflow.tree.roots.map(\.id) == oldTree.roots.map(\.id))
      #expect(workflow.tree.node(withID: server.id)?.createdAt == server.createdAt)
      #expect(workflow.tree.node(withID: server.id)?.updatedAt != server.updatedAt)
      #expect(fields.password == "new password")
      #expect(reloads == 1)
      fetcher.setBehavior(.failure(.transport(detail: "fixture failure")))
      await workflow.refreshSubscription(summary.id)
      #expect(reloads == 1)
      #expect(fields.password == "new password")
      fetcher.setBehavior(.success(Data(changed.utf8)))
      _ = try await workflow.createSubscription(urlString: "https://other.example/sub.json")
      #expect(reloads == 1)
    }
  }

  private static func withWorkflow(
    credentials: CredentialStoring,
    fetcher: SubscriptionFetching = FakeSubscriptionFetcher(behavior: .success(Data())),
    _ body: (CatalogWorkflow) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), subscriptionFetcher: fetcher)
    try await body(workflow)
  }

  private static func form(isEditable: Bool = true, password: String = "pw") -> ServerEditForm {
    ServerEditForm(
      address: "203.0.113.1", port: 8388, encryptionMethod: "aes-256-gcm",
      password: password, remark: "服务器",
      plugin: PluginSectionState(
        selection: .none, programs: [], mappingsUnreadable: false,
        optionsPresent: false, options: ""), isEditable: isEditable)
  }
}

extension ServerFormLoadingTests {
  @Test
  func newFormStartsUnchangedAndReturningToDefaultsClearsChanges() {
    let fields = ServerFormFields.newForm()
    #expect(!fields.hasChanges)
    fields.remark = "未保存"
    #expect(fields.hasChanges)
    fields.remark = ""
    #expect(!fields.hasChanges)
    fields.portText = "bad"
    #expect(fields.hasChanges)
  }

  @Test func detailFactsOmitSecretsAndExplicitParameterReadPreservesRawValue() async throws {
    try await Self.withWorkflow(credentials: InMemoryCredentialStore()) { workflow in
      let program = ManagedPluginCatalog.plugins[0].program
      let id = try await workflow.createServer(
        ServerEditDraft(
          address: "203.0.113.1", port: 8388, encryptionMethod: "aes-256-gcm",
          password: "pw", remark: "服务器", plugin: .named(program: program),
          pluginOptions: "tls;host=example.com;host=other.example;empty="), into: nil)
      let facts = try #require(workflow.serverDetailPresentation(for: id))
      #expect(facts.name == "服务器")
      #expect(facts.plugin.options.isEmpty)
      #expect(
        try workflow.serverDetailPluginOptions(for: id)
          == "tls;host=example.com;host=other.example;empty=")
    }
  }

  @Test
  func unknownPluginDetailReadsOptionsWithoutLoadingPassword() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json"))
    let credentials = FormCredentialStore()
    let optionsRef = CredentialReference.fresh()
    try credentials.save("opaque=one;opaque=two", for: optionsRef)
    var catalog = ConfigurationCatalog()
    let id = try catalog.addServer(
      ServerFields(
        address: "203.0.113.1", port: 8388, encryptionMethod: "aes-256-gcm",
        password: "password", remark: "未知插件服务器",
        pluginProgram: "unknown-test-plugin", pluginOptions: "opaque=one;opaque=two"))
    try store.save(CatalogDocument(catalog: catalog))
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()))
    credentials.reads = 0
    #expect(
      workflow.serverDetailPresentation(for: id)?.plugin.selection
        == .unknown(program: "unknown-test-plugin"))
    #expect(credentials.reads == 0)
    #expect(try workflow.serverDetailPluginOptions(for: id) == "opaque=one;opaque=two")
    #expect(credentials.reads == 0)
  }

  @Test
  func parameterSessionSwitchesIdentityAndOnlyReloadsAffectedRefreshes() {
    let parameters = ServerDetailParameters()
    let first = NodeID(rawValue: "first")
    let second = NodeID(rawValue: "second")
    var reads = 0
    parameters.showServer(first) { _ in
      reads += 1
      return "tls;host=one;host=two;empty="
    }
    #expect(parameters.options.rows.filter { !$0.isBlank }.count == 4)
    parameters.showServer(first) { _ in
      reads += 1
      return "tls;host=one;host=two;empty="
    }
    parameters.didRefresh(affectedServers: [second]) { _ in
      Issue.record("不相关刷新不应重载")
      return ""
    }
    parameters.didRefresh(affectedServers: [first]) { _ in
      reads += 1
      return "host=new"
    }
    #expect(reads == 3)
    #expect(parameters.options.composedString == "host=new")
    parameters.showServer(second) { _ in throw ServerFormLoadError.credentialsUnavailable }
    #expect(parameters.options.composedString == "")
    #expect(parameters.failure == .credentialsUnavailable)
    parameters.reload { _ in "trailing\\" }
    #expect(parameters.failure == nil)
    #expect(parameters.options.mode == .rawText)
    #expect(parameters.options.rawText == "trailing\\")
    parameters.didRefresh(affectedServers: [second]) { _ in
      throw ServerFormLoadError.credentialsUnavailable
    }
    #expect(parameters.options.rawText.isEmpty)
    #expect(parameters.failure == .credentialsUnavailable)
  }

  @Test
  func editingPresentationChangesNeverReplaceDraftAndDeletionBlocksSaving() {
    let fields = ServerFormFields()
    let id = NodeID(rawValue: "manual")
    let form = ServerEditForm(
      address: "203.0.113.1", port: 8388, encryptionMethod: "aes-256-gcm",
      password: "pw", remark: "服务器",
      plugin: PluginSectionState(
        selection: .unknown(program: "plugin"), programs: [], mappingsUnreadable: false,
        optionsPresent: true, options: ""), isEditable: true)
    fields.showServer(id) { _ in form }
    fields.remark = "未保存名称"
    let updatedPlugin = PluginSectionState(
      selection: .named(program: "plugin"), programs: [], mappingsUnreadable: false,
      optionsPresent: true, options: "")
    fields.updatePresentation(
      ServerFormPresentation(isEditable: true, plugin: updatedPlugin), preservingDraft: true)
    #expect(fields.pluginChoice == .unknown(program: "plugin"))
    #expect(fields.remark == "未保存名称")
    #expect(fields.canSaveServer)
    fields.updatePresentation(nil, preservingDraft: true)
    #expect(!fields.canSaveServer)
    #expect(fields.hasLoadedServer)
    #expect(fields.password == "pw")
    #expect(fields.remark == "未保存名称")
  }

}

private final class FormCredentialStore: CredentialStoring {
  let storage = InMemoryCredentialStore()
  var reads = 0
  var failReads = false

  func secret(for reference: CredentialReference) throws -> String? {
    reads += 1
    if failReads { throw CredentialStoreError.secretNotUTF8 }
    return try storage.secret(for: reference)
  }

  func save(_ secret: String, for reference: CredentialReference) throws {
    try storage.save(secret, for: reference)
  }

  func delete(_ reference: CredentialReference) throws { try storage.delete(reference) }
}
