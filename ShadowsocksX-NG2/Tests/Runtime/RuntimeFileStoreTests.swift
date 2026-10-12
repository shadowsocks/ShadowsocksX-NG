import XCTest

@testable import ShadowsocksX_NG2

/// 运行时文件存取：0700/0600 权限基线、原子替换、
/// 读取侧判定与显式停止清理。
final class RuntimeFileStoreTests: XCTestCase {
  private var runtime: ProxyRuntimeFixture.TemporaryRuntime!
  private var store: RuntimeFileStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    store = RuntimeFileStore(fileURL: runtime.contract)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: runtime.directory)
    try super.tearDownWithError()
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int)
  }

  // MARK: 权限基线

  func testWriteCreatesDirectoryWith0700AndFileWith0600() throws {
    try store.write(ProxyRuntimeFixture.makeDocument())

    XCTAssertEqual(try permissions(of: runtime.directory), 0o700, "runtime/ 目录 0700")
    XCTAssertEqual(try permissions(of: runtime.contract), 0o600, "契约文件 0600")
  }

  func testWriteHealsDirectoryPermissionBaseline() throws {
    try FileManager.default.createDirectory(
      at: runtime.directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: runtime.directory.path)

    try store.write(ProxyRuntimeFixture.makeDocument())

    XCTAssertEqual(try permissions(of: runtime.directory), 0o700, "目录权限自愈回 0700")
  }

  func testAtomicReplaceKeepsFileAt0600() throws {
    try store.write(ProxyRuntimeFixture.makeDocument(localPort: 1086))

    try store.write(ProxyRuntimeFixture.makeDocument(localPort: 2086))

    XCTAssertEqual(try permissions(of: runtime.contract), 0o600, "替换后仍 0600")
    let document = try XCTUnwrap(store.loadDocument())
    XCTAssertEqual(document.socksPort, 2086, "内容已被原子替换")
  }

  func testWriteLeavesNoTemporaryFilesBehind() throws {
    try store.write(ProxyRuntimeFixture.makeDocument())
    try store.write(ProxyRuntimeFixture.makeDocument(localPort: 2087))

    let residue = try FileManager.default.contentsOfDirectory(atPath: runtime.directory.path)
      .filter { $0.hasPrefix(".sslocal-active.json.tmp-") }
    XCTAssertTrue(residue.isEmpty, "临时文件不应残留，实际 \(residue)")
  }

  func testACLAndContractAreWrittenWithProtectedPermissions() throws {
    let document = SslocalRuntimeDocument(
      servers: [],
      listen: SslocalListenSettings(),
      acl: .direct(at: store.aclFileURL))

    try store.write(document)

    XCTAssertEqual(try permissions(of: runtime.directory), 0o700)
    XCTAssertEqual(try permissions(of: runtime.contract), 0o600)
    XCTAssertEqual(
      try permissions(of: store.aclVariantFileURL(summary: "direct")), 0o600,
      "变体文件 0600；链接权限由文件系统决定，不作断言")
    XCTAssertEqual(store.loadDocument(), document)
  }

  /// ADR-0011：变体落在 `acl-<summary>.ini`，契约路径是稳定的 `acl-active.ini`
  /// 链接；换模式只换链接指向，不重写变体内容。
  func testWriteMaterializesVariantFileAndActiveLink() throws {
    let direct = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .direct(at: store.aclFileURL))
    try store.write(direct)

    let variantURL = store.aclVariantFileURL(summary: "direct")
    XCTAssertTrue(FileManager.default.fileExists(atPath: variantURL.path))
    let linkTarget = try FileManager.default.destinationOfSymbolicLink(
      atPath: store.aclFileURL.path)
    XCTAssertEqual(linkTarget, variantURL.lastPathComponent, "链接指向同目录变体文件")

    let global = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .global(at: store.aclFileURL))
    try store.write(global)

    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: store.aclFileURL.path),
      store.aclVariantFileURL(summary: "global").lastPathComponent)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: variantURL.path),
      "旧变体文件保留，切换只改链接指向")
  }

  /// digest 清单让未变内容免于重写（ADR-0011）：同内容二次落盘时变体文件
  /// 修改时间不变。
  func testUnchangedVariantContentSkipsRewrite() throws {
    let document = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .direct(at: store.aclFileURL))
    try store.write(document)
    let variantURL = store.aclVariantFileURL(summary: "direct")
    let firstAttributes = try FileManager.default.attributesOfItem(atPath: variantURL.path)
    let firstModification = try XCTUnwrap(firstAttributes[.modificationDate] as? Date)

    try store.write(document)

    let secondAttributes = try FileManager.default.attributesOfItem(atPath: variantURL.path)
    let secondModification = try XCTUnwrap(secondAttributes[.modificationDate] as? Date)
    XCTAssertEqual(firstModification, secondModification, "digest 相同跳过变体写入")
  }

  /// Q12-A：读取侧不读 ACL 内容、不核摘要；链接逃逸出运行目录才拒绝。
  func testLoadDocumentRejectsLinkEscapingRuntimeDirectory() throws {
    let document = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .direct(at: store.aclFileURL))
    try store.write(document)
    let outside = runtime.directory.deletingLastPathComponent()
      .appendingPathComponent("outside-\(UUID().uuidString).ini")
    try Data("[bypass_all]\n".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.removeItem(at: store.aclFileURL)
    try FileManager.default.createSymbolicLink(
      atPath: store.aclFileURL.path, withDestinationPath: outside.path)

    XCTAssertNil(store.loadDocument(), "链接解析后落在运行目录之外即拒绝")
  }

  func testContractWriteFailureRestoresPreviousVariantAndLink() throws {
    let contractURL = runtime.contract
    let previous = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .direct(at: store.aclFileURL))
    try store.write(previous)

    let failingStore = RuntimeFileStore(fileURL: contractURL) { data, url in
      guard url != contractURL else { throw NSError(domain: "test", code: 1) }
      try AtomicFileWriter.write(data, to: url)
    }
    let next = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .global(at: failingStore.aclFileURL))
    XCTAssertThrowsError(try failingStore.write(next))

    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: failingStore.aclFileURL.path),
      failingStore.aclVariantFileURL(summary: "direct").lastPathComponent,
      "契约写失败后链接回到此前指向")
    XCTAssertEqual(
      failingStore.loadDocument(), previous,
      "契约未写成功，读取侧仍看到此前文档")
  }

  /// digest 清单不得先于契约写落盘：否则回滚后清单说新内容、盘上是旧内容，
  /// 下次写同一新内容会被错误跳过。
  func testContractWriteFailureDoesNotLeakNewDigestIntoManifest() throws {
    let previous = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .direct(at: store.aclFileURL))
    try store.write(previous)

    let contractURL = runtime.contract
    let failingStore = RuntimeFileStore(fileURL: contractURL) { data, url in
      guard url != contractURL else { throw NSError(domain: "test", code: 1) }
      try AtomicFileWriter.write(data, to: url)
    }
    let next = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(),
      acl: .global(at: failingStore.aclFileURL))
    XCTAssertThrowsError(try failingStore.write(next))

    // 回滚成功后重试同一「global」写入：必须真写出 global 变体，不得被清单跳过。
    let retryStore = RuntimeFileStore(fileURL: contractURL)
    try retryStore.write(next)

    XCTAssertEqual(
      try Data(contentsOf: retryStore.aclFileURL),
      Data(ProxyACLDocument.global(at: retryStore.aclFileURL).content.utf8),
      "失败回滚后重试同一变体必须真正落盘")
    XCTAssertEqual(retryStore.loadDocument(), next)
  }

  // MARK: 读取侧判定

  func testLoadDocumentRoundTripsWrittenDocument() throws {
    let document = ProxyRuntimeFixture.makeDocument()
    try store.write(document)

    XCTAssertEqual(store.loadDocument(), document)
    XCTAssertEqual(store.readData(), try document.jsonData())
  }

  func testLoadDocumentReturnsNilForMissingFile() throws {
    XCTAssertNil(store.loadDocument())
    XCTAssertNil(store.readData())
  }

  func testLoadDocumentReturnsNilForCorruptJSON() throws {
    try Data("not json {".utf8).write(to: runtime.contract)

    XCTAssertNil(store.loadDocument())
  }

  func testLoadDocumentReturnsNilForStructurallyInvalidDocument() throws {
    try store.write(
      SslocalRuntimeDocument(
        servers: [], listen: SslocalListenSettings(socksPort: 0)))

    XCTAssertNil(store.loadDocument(), "本地端口无效属结构性无效（读取侧防御）")
  }

  // MARK: 显式停止清理

  func testDeleteRuntimeFilesRemovesContractPidAndStaleTemporaries() throws {
    try store.write(
      SslocalRuntimeDocument(
        servers: [], listen: SslocalListenSettings(), acl: .direct(at: store.aclFileURL)))
    try store.write(
      SslocalRuntimeDocument(
        servers: [], listen: SslocalListenSettings(), acl: .global(at: store.aclFileURL)))
    try Data("1086".utf8).write(to: runtime.pidFile)
    try Data("status".utf8).write(to: store.runtimeStatusFileURL)
    let staleTemporary = runtime.directory.appendingPathComponent(".sslocal-active.json.tmp-stale")
    try Data("partial".utf8).write(to: staleTemporary)

    store.deleteRuntimeFiles()

    XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.contract.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.pidFile.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.aclFileURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: store.aclVariantFileURL(summary: "direct").path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: store.aclVariantFileURL(summary: "global").path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: store.aclDigestManifestURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.runtimeStatusFileURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staleTemporary.path))
  }

  func testDeleteRuntimeFilesIsHarmlessWhenNothingExists() throws {
    store.deleteRuntimeFiles()
    store.deleteRuntimeFiles()
    XCTAssertTrue(true, "重复清理不抛错")
  }

  // MARK: 文档校验与监听指纹

  func testWellFormedValidationRejectsStructuralGarbage() {
    func document(
      localPort: Int = 1086,
      servers: [SslocalServerDocument]
    ) -> SslocalRuntimeDocument {
      SslocalRuntimeDocument(
        servers: servers,
        listen: SslocalListenSettings(
          socksPort: localPort))
    }
    func server(
      id: String = "s", address: String = "203.0.113.7", port: Int = 8388,
      method: String = "aes-256-gcm"
    ) -> SslocalServerDocument {
      SslocalServerDocument(
        id: id, server: address, serverPort: port, password: "pw",
        method: method, plugin: nil, pluginOpts: nil)
    }

    XCTAssertTrue(document(servers: [server()]).isWellFormed)
    XCTAssertTrue(
      document(servers: []).isWellFormed,
      "空 servers 合法：无活动目标的本地监听（issue #60）")
    XCTAssertFalse(document(localPort: 0, servers: [server()]).isWellFormed)
    XCTAssertFalse(document(localPort: 65_536, servers: [server()]).isWellFormed)
    XCTAssertFalse(document(servers: [server(port: 0)]).isWellFormed)
    XCTAssertFalse(document(servers: [server(address: "")]).isWellFormed)
    XCTAssertFalse(document(servers: [server(method: "")]).isWellFormed)
    XCTAssertFalse(document(servers: [server(id: "")]).isWellFormed)
  }

  func testListenFingerprintIgnoresServerChangesAndTracksListenFields() {
    let base = ProxyRuntimeFixture.makeDocument()
    let serverChanged = ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9")
    let listenChanged = ProxyRuntimeFixture.makeDocument(localPort: 2088)

    XCTAssertEqual(
      base.listenFingerprint, serverChanged.listenFingerprint,
      "仅服务器列表变化不影响监听指纹（走 SIGUSR1 热重载）")
    XCTAssertNotEqual(
      base.listenFingerprint, listenChanged.listenFingerprint,
      "监听端口变化改变指纹（走优雅重启）")
  }

  func testValidatedRuntimeRequiresFixedTCPAndUDPModeForSOCKS() throws {
    let base = ProxyRuntimeFixture.makeDocument()
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: base.jsonData()) as? [String: Any])
    var locals = try XCTUnwrap(object["locals"] as? [[String: Any]])
    locals[0]["mode"] = "tcp_only"
    object["locals"] = locals
    let data = try JSONSerialization.data(withJSONObject: object)

    XCTAssertNil(SslocalRuntimeDocument.decodeValidated(data))
  }
}
