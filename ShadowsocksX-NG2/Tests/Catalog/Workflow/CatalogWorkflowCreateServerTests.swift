import XCTest

@testable import ShadowsocksX_NG2

/// 表单新建手动服务器的点名校验用例（标签 + 草稿 + 预期 typed error）。
private struct InvalidCreateDraftCase {
  let label: String
  let draft: ServerEditDraft
  let expected: ServerFormError

  init(_ label: String, _ draft: ServerEditDraft, _ expected: ServerFormError) {
    self.label = label
    self.draft = draft
    self.expected = expected
  }
}

/// 表单新建手动服务器命令（`createServer`）的 UI-facing interface 测试：
/// 落点与身份、凭据入存储、点名校验拒绝与插件选择落盘，语义与编辑提交对称。
@MainActor
final class CatalogWorkflowCreateServerTests: XCTestCase {
  private var workDir: URL!
  private var fileURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var runtime: FakeCatalogRuntime!
  var workflow: CatalogWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    // 专用工作目录：写入器会把父目录强制 0700（不得指向临时根）。
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-create-server-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    fileURL = workDir.appendingPathComponent("catalog.json")
    credentials = InMemoryCredentialStore()
    runtime = FakeCatalogRuntime()
    runtime.hasActiveTarget = true
    workflow = makeWorkflow()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  private func makeWorkflow() -> CatalogWorkflow {
    let coordinator = CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(fileURL: fileURL), runtime: runtime)
    return makeCatalogWorkflow(
      coordinator: coordinator,
      plugins: NoManagedPluginProvider())
  }

  func testCreateServerAddsManualLeafWithCredentialAndReturnsIdentity() async throws {
    let groupID = try await workflow.createGroup(named: "手动组", into: nil)
    let id = try await workflow.createServer(
      ServerEditDraft(
        address: "203.0.113.10", port: 8389, encryptionMethod: "aes-256-gcm",
        password: "表单密码", remark: "新来的", plugin: .none, pluginOptions: nil),
      into: groupID)
    let node = try XCTUnwrap(workflow.tree.node(withID: id))
    XCTAssertFalse(node.isGroup)
    XCTAssertTrue(node.isManual)
    XCTAssertEqual(node.parentID, groupID)
    let form = try XCTUnwrap(try workflow.serverEditForm(for: id))
    XCTAssertEqual(form.address, "203.0.113.10")
    XCTAssertEqual(form.port, 8389)
    XCTAssertEqual(form.remark, "新来的")
    XCTAssertEqual(form.encryptionMethod, "aes-256-gcm")
    XCTAssertEqual(form.password, "表单密码", "密码作为凭据写入，目录持引用")
    XCTAssertTrue(node.invalidReasons.isEmpty)
  }

  func testCreateServerRejectsInvalidDraftsLeavingCatalogAndCredentialsUntouched() async throws {
    let groupID = try await workflow.createGroup(named: "组", into: nil)
    for caseItem in Self.invalidDraftCases {
      await expectThrowsAsync(
        { _ = try await workflow.createServer(caseItem.draft, into: groupID) },
        onThrow: { error in
          XCTAssertEqual(error as? ServerFormError, caseItem.expected, caseItem.label)
        })
    }

    XCTAssertEqual(workflow.tree.node(withID: groupID)?.childCount, 0, "校验失败不进目录")
  }

  func testCreateServerPluginSelectionStoresProgramAndOptions() async throws {
    let id = try await workflow.createServer(
      ServerEditDraft(
        address: "203.0.113.10", port: 8388, encryptionMethod: "aes-256-gcm",
        password: "密码", remark: "插件服务器", plugin: .named(program: "v2ray-plugin"),
        pluginOptions: "mode=websocket;host=example.com"),
      into: nil)
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .named(program: "v2ray-plugin"))
    XCTAssertTrue(plugin.optionsPresent)
    XCTAssertEqual(plugin.options, "mode=websocket;host=example.com")
  }

  /// 表单校验用例表：与 `updateServer` 同规则的点名拒绝（含受管集外插件）。
  private static var invalidDraftCases: [InvalidCreateDraftCase] {
    func draft(
      address: String = "203.0.113.10", port: Int = 8388,
      encryptionMethod: String = "aes-256-gcm", password: String = "密码",
      plugin: PluginSelection = .none
    ) -> ServerEditDraft {
      ServerEditDraft(
        address: address, port: port, encryptionMethod: encryptionMethod, password: password,
        remark: "", plugin: plugin, pluginOptions: nil)
    }
    return [
      InvalidCreateDraftCase("空地址", draft(address: "  "), .invalidAddress),
      InvalidCreateDraftCase("端口下界", draft(port: 0), .invalidPort),
      InvalidCreateDraftCase("端口上界", draft(port: 65_536), .invalidPort),
      InvalidCreateDraftCase("缺加密方式", draft(encryptionMethod: " "), .missingEncryptionMethod),
      InvalidCreateDraftCase(
        "不支持加密方式", draft(encryptionMethod: "future-cipher"),
        .unsupportedEncryptionMethod("future-cipher")),
      InvalidCreateDraftCase("空密码", draft(password: ""), .invalidPassword),
      InvalidCreateDraftCase(
        "受管集外插件", draft(plugin: .named(program: "future-plugin")),
        .pluginUnknown("future-plugin")),
    ]
  }
}
