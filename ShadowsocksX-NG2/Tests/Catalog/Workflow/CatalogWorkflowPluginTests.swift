import XCTest

@testable import ShadowsocksX_NG2

/// 插件区编辑语义经目录工作流 module interface 观察：
/// 选择器三态呈现与落盘、「无」整体清除、参数写删钥匙串、集外引用原样保留，
/// 以及经编辑面的 ss:// 分享往返。走内存凭据存储与注入 bundleURL 的受管插件
/// 提供。
@MainActor
final class CatalogWorkflowPluginTests: XCTestCase {
  private var workDir: URL!
  private var bundleRoot: URL!
  private var fileURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var workflow: CatalogWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "catalog-plugin-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    bundleRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-plugin-bundle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: bundleRoot.appendingPathComponent("Contents/Helpers/Plugins"),
      withIntermediateDirectories: true)
    fileURL = workDir.appendingPathComponent("catalog.json")
    credentials = InMemoryCredentialStore()
    workflow = makeWorkflow()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: workDir)
    try? FileManager.default.removeItem(at: bundleRoot)
    try await super.tearDown()
  }

  private var pluginBinaryName: String { ManagedPluginCatalog.plugins[0].program }

  private func writePluginBinary() throws {
    let url = bundleRoot.appendingPathComponent("Contents/Helpers/Plugins/\(pluginBinaryName)")
    try Data("#!/bin/sh\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }

  private func makeWorkflow() -> CatalogWorkflow {
    makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: CatalogFileStore(fileURL: fileURL), runtime: FakeCatalogRuntime()),
      credentials: credentials,
      plugins: BundleManagedPluginProvider(bundleURL: bundleRoot))
  }

  /// 直建目录（不经 URI 导入）后重载工作流，返回该服务器身份。
  private func addPluginServer(program: String?, options: String?) async throws -> NodeID {
    var catalog = ConfigurationCatalog()
    var fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      passwordRef: CredentialReference(rawValue: "ref-pw"),
      remark: "带插件")
    try credentials.save("pw", for: fields.passwordRef)
    if let program {
      fields.pluginProgram = program
      if let options {
        let reference = CredentialReference(rawValue: "ref-opts")
        try credentials.save(options, for: reference)
        fields.pluginOptionsRef = reference
      }
    }
    try catalog.addServer(fields)
    try CatalogFileStore(fileURL: fileURL).save(CatalogDocument(catalog: catalog))
    workflow = makeWorkflow()
    return try XCTUnwrap(workflow.tree.roots.first?.id)
  }

  private func update(
    _ id: NodeID,
    plugin: PluginSelection,
    pluginOptions: String?,
    address: String = "203.0.113.7"
  ) async throws {
    try await workflow.updateServer(
      id,
      draft: ServerEditDraft(
        address: address, port: 8388, encryptionMethod: "aes-256-gcm", password: "pw",
        remark: "带插件", plugin: plugin, pluginOptions: pluginOptions))
  }

  // MARK: - 选择器呈现

  func testManagedSelectionShownWithFactsAndParamsPlaintext() async throws {
    try writePluginBinary()
    let id = try await addPluginServer(program: pluginBinaryName, options: "mode=websocket")
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .named(program: pluginBinaryName))
    XCTAssertEqual(
      plugin.programs.first { $0.program == pluginBinaryName }?.availability, .available, "二进制在位即提供"
    )
    XCTAssertTrue(plugin.optionsPresent)
    XCTAssertEqual(plugin.options, "mode=websocket", "参数明文供输入框预填")
    XCTAssertEqual(
      Set(plugin.programs.map(\.program)),
      Set(["cloak", "cloak-v2", pluginBinaryName, "v2ray-plugin-v1"]))
  }

  func testMissingBinaryShowsManagedButNotProvided() async throws {
    let id = try await addPluginServer(program: pluginBinaryName, options: nil)
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .named(program: pluginBinaryName))
    XCTAssertEqual(
      plugin.programs.first { $0.program == pluginBinaryName }?.availability, .missing,
      "打包损坏/降级丢插件时点名呈现")
  }

  func testUnknownProgramRendersExplicitUnknownState() async throws {
    let id = try await addPluginServer(program: "obfs-local", options: "obfs=http")
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .unknown(program: "obfs-local"), "集外引用显式未提供")
    XCTAssertFalse(
      plugin.programs.contains { $0.program == "obfs-local" && $0.availability == .available })
    XCTAssertTrue(plugin.optionsPresent, "已配置参数的事实照常呈现")
    XCTAssertEqual(plugin.options, "", "集外引用不解析参数明文")
  }

  func testNoPluginSelectionIsDefault() async throws {
    let id = try await addPluginServer(program: nil, options: nil)
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .none)
    XCTAssertFalse(plugin.optionsPresent)
  }

  // MARK: - 落盘语义

  func testSelectingManagedPluginSavesProgramAndOptions() async throws {
    try writePluginBinary()
    let id = try await addPluginServer(program: nil, options: nil)
    try await update(
      id, plugin: .named(program: pluginBinaryName),
      pluginOptions: "mode=websocket;host=example.com")
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .named(program: pluginBinaryName))
    XCTAssertEqual(plugin.options, "mode=websocket;host=example.com")
    XCTAssertTrue(plugin.optionsPresent)
  }

  func testSavingEmptyOptionsDropsOptions() async throws {
    try writePluginBinary()
    let id = try await addPluginServer(program: pluginBinaryName, options: "mode=websocket")
    try await update(id, plugin: .named(program: pluginBinaryName), pluginOptions: "   ")
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .named(program: pluginBinaryName), "程序引用保留")
    XCTAssertFalse(plugin.optionsPresent, "空参数即无参数引用")
    XCTAssertEqual(plugin.options, "")
    // 秘密确实从凭据存储删除（引用固定为夹具常量）。
    XCTAssertNil(
      try credentials.secret(for: CredentialReference(rawValue: "ref-opts")),
      "清空参数即删除钥匙串秘密")
  }

  func testSelectingNoneClearsProgramAndOptions() async throws {
    let id = try await addPluginServer(program: pluginBinaryName, options: "mode=websocket")
    try await update(id, plugin: .none, pluginOptions: nil)
    let plugin = try XCTUnwrap(try workflow.serverEditForm(for: id)?.plugin)
    XCTAssertEqual(plugin.selection, .none)
    XCTAssertFalse(plugin.optionsPresent)
    XCTAssertNil(try credentials.secret(for: CredentialReference(rawValue: "ref-opts")))
  }

  func testUnknownSelectionPreservesReferenceAndOptionsVerbatim() async throws {
    let id = try await addPluginServer(program: "obfs-local", options: "obfs=http")
    try await update(
      id, plugin: .unknown(program: "obfs-local"), pluginOptions: nil,
      address: "198.51.100.9")
    let form = try XCTUnwrap(try workflow.serverEditForm(for: id))
    XCTAssertEqual(form.address, "198.51.100.9", "连接字段照常更新")
    XCTAssertEqual(form.plugin.selection, .unknown(program: "obfs-local"), "集外引用原样保留")
    XCTAssertTrue(form.plugin.optionsPresent)
    let ref = CredentialReference(rawValue: "ref-opts")
    XCTAssertEqual(try credentials.secret(for: ref), "obfs=http", "参数秘密不动")
  }

  func testForgedUnmanagedSelectionIsRejected() async throws {
    let id = try await addPluginServer(program: nil, options: nil)
    await expectThrowsAsync(
      {
        try await update(id, plugin: .named(program: "obfs-local"), pluginOptions: nil)
      },
      onThrow: { error in
        XCTAssertEqual(error as? ServerFormError, .pluginUnknown("obfs-local"))
      })
  }

  // MARK: - 分享往返（与 ss:// URI 编解码一致）

  func testSharedSsUriRoundTripsThroughEditorEdit() async throws {
    try writePluginBinary()
    let id = try await addPluginServer(program: nil, options: nil)
    try await update(
      id, plugin: .named(program: pluginBinaryName),
      pluginOptions: "mode=websocket;host=example.com")

    let shared = try workflow.shareURI(for: id)
    let decoded = try SsUri.decode(shared)
    XCTAssertEqual(decoded.pluginProgram, pluginBinaryName)
    XCTAssertEqual(decoded.pluginOptions, "mode=websocket;host=example.com")

    // 导回目录：插件字段同构（新建身份，不按内容去重）。
    let outcome = await workflow.importServers(from: [.clipboardText(shared)], into: nil)
    XCTAssertEqual(outcome.sources.first?.result.importedCount, 1)
    let importedNode = try XCTUnwrap(
      workflow.tree.roots.dropFirst().first, "第二个根节点应是新导入的服务器")
    let imported = try XCTUnwrap(try workflow.serverEditForm(for: importedNode.id))
    XCTAssertEqual(imported.plugin.selection, .named(program: pluginBinaryName))
    XCTAssertEqual(imported.plugin.options, "mode=websocket;host=example.com")
  }
}
