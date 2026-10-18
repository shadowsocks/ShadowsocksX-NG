import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 统一服务器导入管线的 interface 测试（docs/design/unified-server-import.md，
/// ADR-0027）：来源嗅探分派、SIP-008 整树导入与整份拒绝、来源间独立性、凭据
/// journal 回滚与命名兜底。全部经 `importServers(from:into:)` 单一接缝观察
/// projection 与结构化结果，不触碰内部存储。
@MainActor
struct CatalogWorkflowImportTests {
  // MARK: - SIP-008 整树导入

  @Test func sip008FileImportsTreeWithFreshIdentities() async throws {
    try await withImportWorkflow { workflow, credentials in
      let outcome = await workflow.importServers(
        from: [.file(name: "机场.json", data: Data(SIP008DocumentFixture.tree.utf8))], into: nil)

      let groupID = try #require(outcome.sources.first?.result.importedGroupID)
      #expect(outcome.sources.first?.result.importedCount == 2)
      #expect(outcome.selectionCandidate == groupID)

      let root = try #require(workflow.tree.node(withID: groupID))
      #expect(root.isGroup)
      #expect(root.isManual, "导入产物是手动子树")
      #expect(root.name == "我的机场")
      #expect(root.childCount == 3, "服务器 + 嵌套分组 + 服务器按文档顺序")
      #expect(root.childNodes.map(\.name) == ["香港 01", "嵌套组", "日本 02"])

      // ADR-0027：目录身份全新 UUID，文档 ID 只作装配键不进入目录。
      #expect(UUID(uuidString: groupID.rawValue) != nil, "根分组身份客户端所有、全新生成")
      for child in root.childNodes where !child.isGroup {
        #expect(UUID(uuidString: child.id.rawValue) != nil, "服务器叶子身份全新生成")
      }

      let first = try #require(root.childNodes.first)
      #expect(try workflow.serverEditForm(for: first.id)?.password == "pw1", "密码入凭据存储")
      #expect(try workflow.serverEditForm(for: first.id)?.remark == "香港 01")
      let second = try #require(root.childNodes.last)
      #expect(try workflow.serverEditForm(for: second.id)?.password == "pw2")
      #expect(credentials.storageCount == 0, "服务器秘密不写逐项凭据存储")
    }
  }

  @Test func sip008FlatFallbackNamesRootFromFileName() async throws {
    try await withImportWorkflow { workflow, _ in
      let outcome = await workflow.importServers(
        from: [.file(name: "我的机场.json", data: Data(SIP008DocumentFixture.flat.utf8))], into: nil)

      let groupID = try #require(outcome.sources.first?.result.importedGroupID)
      #expect(workflow.tree.node(withID: groupID)?.name == "我的机场", "文件名去扩展名兜底")
      #expect(workflow.tree.node(withID: groupID)?.childCount == 2, "扁平回退平铺根分组")
    }
  }

  @Test func sip008NamelessFileFallsBackToGenericRootName() async throws {
    try await withImportWorkflow { workflow, _ in
      let outcome = await workflow.importServers(
        from: [.file(name: "", data: Data(SIP008DocumentFixture.flat.utf8))], into: nil)

      let groupID = try #require(outcome.sources.first?.result.importedGroupID)
      #expect(workflow.tree.node(withID: groupID)?.name == "导入的服务器")
    }
  }

  @Test func sip008DuplicateRootNameGetsSuffix() async throws {
    try await withImportWorkflow { workflow, _ in
      _ = await workflow.importServers(
        from: [.file(name: "机场.json", data: Data(SIP008DocumentFixture.tree.utf8))], into: nil)
      _ = await workflow.importServers(
        from: [.file(name: "机场.json", data: Data(SIP008DocumentFixture.tree.utf8))], into: nil)

      #expect(workflow.tree.roots.count == 2)
      #expect(workflow.tree.roots.map(\.name) == ["我的机场", "我的机场 2"], "重名加序号后缀")
      #expect(workflow.tree.roots.map(\.id).count == 2, "重复导入产生独立副本（ADR-0027）")
    }
  }

  @Test func sip008PluginOptionsStoredWithoutProgram() async throws {
    try await withImportWorkflow { workflow, credentials in
      _ = await workflow.importServers(
        from: [.file(name: "opts.json", data: Data(SIP008DocumentFixture.pluginOptions.utf8))],
        into: nil)

      let group = try #require(workflow.tree.roots.first)
      #expect(group.name == "opts", "文件名兜底")
      let node = try #require(group.childNodes.first)
      let form = try #require(try workflow.serverEditForm(for: node.id))
      #expect(form.plugin.selection == .none, "无插件程序名")
      #expect(form.plugin.optionsPresent, "插件参数保真存入")
      #expect(form.password == "pw3")
      #expect(try workflow.serverDetailPluginOptions(for: node.id) == "mode=websocket")
    }
  }

  // MARK: - SIP-008 整份拒绝

  @Test func sip008InvalidRecordRejectsWholeSource() async throws {
    try await withImportWorkflow { workflow, credentials in
      let document = """
        {"version":1,"servers":[
          {"server":"203.0.113.7","server_port":8388,"password":"pw","method":"aes-256-gcm"},
          {"server":"203.0.113.8","server_port":8389,"password":"","method":"aes-256-gcm"}]}
        """
      let outcome = await workflow.importServers(
        from: [.file(name: "bad.json", data: Data(document.utf8))], into: nil)

      let failure = try #require(outcome.sources.first?.result.sourceFailure)
      guard case .parse(.recordValidation(let index, _)) = failure else {
        Issue.record("应为记录校验失败：\(failure)")
        return
      }
      #expect(index == 1, "点名无效记录")
      #expect(workflow.tree.roots.isEmpty, "整份拒绝不留部分子树")
      #expect(credentials.storageCount == 0, "拒绝路径不写凭据")
    }
  }

  // MARK: - 二维码图片

  @Test func qrImageImportsDetectedServers() async throws {
    try await withImportWorkflow { workflow, _ in
      let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#二维码"
      let png = try QrCodeCodec.generatePNG(for: uri)

      let outcome = await workflow.importServers(
        from: [.file(name: "qr.png", data: png)], into: nil)

      #expect(outcome.sources.first?.result.importedCount == 1)
      #expect(workflow.tree.roots.first?.name == "二维码")
    }
  }

  @Test func qrImageWithoutSSPayloadFails() async throws {
    try await withImportWorkflow { workflow, _ in
      let png = try QrCodeCodec.generatePNG(for: "plain text payload")

      let outcome = await workflow.importServers(
        from: [.file(name: "qr.png", data: png)], into: nil)

      let failure = try #require(outcome.sources.first?.result.sourceFailure)
      guard case .qrPayloadNotFound = failure else {
        Issue.record("应为二维码无 ss:// 负载：\(failure)")
        return
      }
      #expect(workflow.tree.roots.isEmpty)
    }
  }

  // MARK: - 文本文件与剪贴板

  @Test func textFileImportsLinesPartially() async throws {
    try await withImportWorkflow { workflow, _ in
      let text = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#文件行\n垃圾行\n"
      let outcome = await workflow.importServers(
        from: [.file(name: "list.txt", data: Data(text.utf8))], into: nil)

      let facts = try #require(outcome.sources.first?.result.partialFacts)
      #expect(facts.addedCount == 1)
      #expect(facts.failures.count == 1)
      #expect(facts.failures[0].lineIndex == 1)
      #expect(outcome.selectionCandidate == nil, "根层文本来源无可选中新分组")
    }
  }

  @Test func blankLinesKeepOriginalFailureIndexes() async throws {
    try await withImportWorkflow { workflow, _ in
      let text = "第一行垃圾\n\n\nss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388"
      let outcome = await workflow.importServers(
        from: [.clipboardText(text)], into: nil)

      let facts = try #require(outcome.sources.first?.result.partialFacts)
      #expect(facts.addedCount == 1)
      #expect(facts.failures.count == 1)
      #expect(facts.failures[0].lineIndex == 0, "失败行按含空行的原始下标点名")
    }
  }

  @Test func clipboardEmptyTextFailsWithoutCatalogChange() async throws {
    try await withImportWorkflow { workflow, _ in
      let outcome = await workflow.importServers(
        from: [.clipboardText("   \n  ")], into: nil)

      let failure = try #require(outcome.sources.first?.result.sourceFailure)
      guard case .noImportableLines = failure else {
        Issue.record("应为无可导入行：\(failure)")
        return
      }
      #expect(workflow.tree.roots.isEmpty)
    }
  }

  // MARK: - 来源独立性与提交失败回滚

  @Test func sourcesImportIndependently() async throws {
    try await withImportWorkflow { workflow, _ in
      let broken = """
        {"version":1,"servers":[
          {"server":"203.0.113.7","server_port":8388,"password":"","method":"aes-256-gcm"}]}
        """
      let text = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#可用来源"

      let outcome = await workflow.importServers(
        from: [.file(name: "bad.json", data: Data(broken.utf8)), .clipboardText(text)], into: nil)

      #expect(outcome.sources.count == 2)
      #expect(outcome.sources[0].result.sourceFailure != nil, "坏文件整体失败")
      #expect(outcome.sources[1].result.importedCount == 1, "失败不影响其他来源")
      #expect(workflow.tree.roots.count == 1, "只有可用来源落盘")
      #expect(workflow.tree.roots.first?.name == "可用来源")
    }
  }

  @Test func commitFailureDoesNotPublishImportedRecords() async throws {
    try await withGateBrokenWorkflow { workflow, credentials in
      let text = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#提交失败"

      let outcome = await workflow.importServers(from: [.clipboardText(text)], into: nil)

      let failure = try #require(outcome.sources.first?.result.sourceFailure)
      guard case .commit = failure else {
        Issue.record("应为提交失败：\(failure)")
        return
      }
      #expect(workflow.tree.roots.isEmpty, "目录提交失败不留节点")
    }
  }

  @Test func selectionCandidatePrefersLastImportedGroup() async throws {
    try await withImportWorkflow { workflow, _ in
      let text = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#根层"
      let outcome = await workflow.importServers(
        from: [
          .clipboardText(text),
          .file(name: "机场.json", data: Data(SIP008DocumentFixture.tree.utf8)),
        ],
        into: nil)

      let fileGroupID = try #require(outcome.sources[1].result.importedGroupID)
      #expect(outcome.selectionCandidate == fileGroupID, "选中最后一个成功来源的新分组")
    }
  }

  // MARK: - 夹具

  /// 临时目录 + 内存凭据与库密钥；UUID 后缀命名，进程私有资源（runner 并行安全）。
  private func withImportWorkflow(
    _ body: @MainActor (CatalogWorkflow, InMemoryCredentialStore) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-import-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let credentials = InMemoryCredentialStore()
    let coordinator = CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(
        fileURL: directory.appendingPathComponent("catalog.json")),
      runtime: FakeCatalogRuntime())
    let workflow = makeCatalogWorkflow(coordinator: coordinator)
    try await body(workflow, credentials)
  }

  /// 目录文件置于 gate 子目录；把 gate 目录替换为同名文件后，下一次持久化
  /// 必然失败（回滚测试的确定性失败注入，与 CatalogWorkflowRollbackTests 同法）。
  private func withGateBrokenWorkflow(
    _ body: @MainActor (CatalogWorkflow, InMemoryCredentialStore) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("catalog-import-gate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gateDir = directory.appendingPathComponent("gate")
    try FileManager.default.createDirectory(at: gateDir, withIntermediateDirectories: true)
    let credentials = InMemoryCredentialStore()
    let coordinator = CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(fileURL: gateDir.appendingPathComponent("catalog.json")),
      runtime: FakeCatalogRuntime())
    let workflow = makeCatalogWorkflow(coordinator: coordinator)
    try FileManager.default.removeItem(at: gateDir)
    try Data().write(to: gateDir)
    try await body(workflow, credentials)
  }
}

/// SIP-008 文档夹具（与导出侧键名同构）。
private enum SIP008DocumentFixture {
  /// 根分组 + 嵌套分组 + 两台服务器。
  static let tree = """
    {
      "version": 1,
      "servers": [
        {"id": "11111111-1111-4111-8111-111111111111",
         "remarks": "香港 01", "server": "203.0.113.7", "server_port": 8388,
         "password": "pw1", "method": "aes-256-gcm"},
        {"id": "22222222-2222-4222-8222-222222222222",
         "remarks": "日本 02", "server": "203.0.113.8", "server_port": 8389,
         "password": "pw2", "method": "aes-256-gcm"}
      ],
      "x_shadowsocksx_ng": {
        "schema_version": 1,
        "root_group_id": "doc-root-group",
        "groups": [
          {"id": "doc-root-group", "name": "我的机场", "children": [
            {"type": "server", "id": "11111111-1111-4111-8111-111111111111"},
            {"type": "group", "id": "doc-nested-group"},
            {"type": "server", "id": "22222222-2222-4222-8222-222222222222"}
          ]},
          {"id": "doc-nested-group", "name": "嵌套组", "children": []}
        ]
      }
    }
    """

  /// 无扩展的标准扁平文档（第三方 SIP-008 消费形态）。
  static let flat = """
    {
      "version": 1,
      "servers": [
        {"remarks": "香港 01", "server": "203.0.113.7", "server_port": 8388,
         "password": "pw1", "method": "aes-256-gcm"},
        {"remarks": "日本 02", "server": "203.0.113.8", "server_port": 8389,
         "password": "pw2", "method": "aes-256-gcm"}
      ]
    }
    """

  /// 有插件参数但缺插件程序名的记录（保真存入语义）。
  static let pluginOptions = """
    {
      "version": 1,
      "servers": [
        {"id": "33333333-3333-4333-8333-333333333333", "server": "203.0.113.9",
         "server_port": 8390, "password": "pw3", "method": "aes-256-gcm",
         "plugin_opts": "mode=websocket"}
      ]
    }
    """
}
