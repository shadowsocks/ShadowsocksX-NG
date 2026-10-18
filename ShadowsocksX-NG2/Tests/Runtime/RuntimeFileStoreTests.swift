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
    XCTAssertEqual(try permissions(of: store.supervisionFileURL), 0o600, "契约文件 0600")
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

    XCTAssertEqual(try permissions(of: store.supervisionFileURL), 0o600, "替换后仍 0600")
    let document = try XCTUnwrap(store.loadDocument())
    XCTAssertEqual(document.socksPort, 2086, "内容已被原子替换")
  }

  func testWriteLeavesNoTemporaryFilesBehind() throws {
    try store.write(ProxyRuntimeFixture.makeDocument())
    try store.write(ProxyRuntimeFixture.makeDocument(localPort: 2087))

    let residue = try FileManager.default.contentsOfDirectory(atPath: runtime.directory.path)
      .filter(AtomicFileWriter.isResidueName)
    XCTAssertTrue(residue.isEmpty, "临时文件不应残留，实际 \(residue)")
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
    try AtomicFileWriter.write(Data("not json {".utf8), to: store.supervisionFileURL)

    XCTAssertNil(store.loadDocument())
  }

  func testWriteRejectsStructurallyInvalidDocument() throws {
    XCTAssertThrowsError(
      try store.write(
        SslocalRuntimeDocument(
          servers: [], listen: SslocalListenSettings(socksPort: 0))))
    XCTAssertNil(store.loadDocument())
  }

  func testExplicitStopCleansFilesButPreservesGenerationHighWatermark() throws {
    try store.write(ProxyRuntimeFixture.makeDocument())
    let first = try XCTUnwrap(RuntimePublication.load(at: store.supervisionFileURL))
    try store.deleteRuntimeFiles()
    XCTAssertNil(store.loadDocument())
    try store.deleteRuntimeFiles()
    try store.write(ProxyRuntimeFixture.makeDocument())
    XCTAssertGreaterThan(
      try XCTUnwrap(RuntimePublication.load(at: store.supervisionFileURL)).generation,
      first.generation)
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
      "空 servers 合法：无活动目标的本地监听")
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
