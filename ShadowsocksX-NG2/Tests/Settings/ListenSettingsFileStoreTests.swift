import XCTest

@testable import ShadowsocksX_NG2

/// 监听设置持久化：用户改过的端口必须跨启动保留
/// 且任何读取路径不得静默改写——文件缺失回落出厂默认，损坏或端口无效一律
/// 点名报错交由上层呈现，绝不静默修正。
final class ListenSettingsFileStoreTests: XCTestCase {
  private var directory: URL!
  private var store: ListenSettingsFileStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-tests-\(UUID().uuidString)", isDirectory: true)
    store = ListenSettingsFileStore(
      fileURL: directory.appendingPathComponent("listen-settings.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int)
  }

  private func writeRaw(_ text: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: store.fileURL)
  }

  func testLoadWithoutFileReturnsFactoryDefaultsAndCreatesNothing() throws {
    let settings = try store.load()

    XCTAssertEqual(settings, SslocalListenSettings(), "文件缺失即出厂状态，非静默改端口")
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
  }

  func testSaveAndLoadRoundTripPreservesUserPortsAndListenerMode() throws {
    var settings = SslocalListenSettings()
    settings.listenerMode = .allIPv4AndIPv6Interfaces
    settings.socksPort = 2086
    settings.httpPort = 2087

    try store.save(settings)

    XCTAssertEqual(try store.load(), settings)
    let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
    XCTAssertFalse(raw.contains("udpRelayEnabled"))
    XCTAssertFalse(raw.contains("advertisedAddress"))
    XCTAssertTrue(raw.contains("all_ipv4_and_ipv6_interfaces"))
    XCTAssertEqual(try permissions(of: directory), 0o700)
    XCTAssertEqual(try permissions(of: store.fileURL), 0o600)
  }

  func testLoadIgnoresRemovedUDPRelayAndPACPreferencesAndPreservesLegacyDefaultPorts() throws {
    try writeRaw(
      #"{"listenerMode":"localhost","socksPort":1086,"#
        + #""httpProxyEnabled":true,"httpPort":1087,"pacPort":1089,"udpRelayEnabled":false}"#)

    let settings = try store.load()

    XCTAssertEqual(settings.socksPort, 1086)
    XCTAssertEqual(settings.httpPort, 1087)
    XCTAssertEqual(settings.mode, "tcp_and_udp")
  }

  func testMissingPortFieldsUseNewFactoryDefaults() throws {
    try writeRaw(
      #"{"listenerMode":"localhost","httpProxyEnabled":true,"#
        + #""udpRelayEnabled":false}"#)

    XCTAssertEqual(try store.load(), SslocalListenSettings())
  }

  func testSaveRejectsInvalidPortsWithoutTouchingExistingFile() throws {
    try store.save(SslocalListenSettings())

    var invalid = SslocalListenSettings()
    invalid.socksPort = 70000
    XCTAssertThrowsError(try store.save(invalid)) { error in
      XCTAssertEqual(
        error as? ListenSettingsStoreError,
        .invalidPorts([.portOutOfRange(endpoint: .socks, port: 70000)]))
    }
    XCTAssertEqual(
      try store.load(),
      SslocalListenSettings(),
      "被拒绝的保存不得改动已落盘的用户配置")
  }

  func testLoadReportsCorruptFileInsteadOfSilentlyRewritingPorts() throws {
    try writeRaw("{not json")

    XCTAssertThrowsError(try store.load()) { error in
      guard case .corrupt = error as? ListenSettingsStoreError else {
        return XCTFail("损坏文件必须点名报错，实际 \(error)")
      }
    }
  }

  func testLoadDistinguishesReadFailureFromCorruption() throws {
    try writeRaw("{}")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000], ofItemAtPath: store.fileURL.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: store.fileURL.path)
    }

    XCTAssertThrowsError(try store.load()) { error in
      guard case .ioFailure = error as? ListenSettingsStoreError else {
        return XCTFail("读取失败必须与损坏区分，实际 \(error)")
      }
    }
  }

  func testLoadRejectsPersistedDuplicatePorts() throws {
    try writeRaw(
      #"{"listenerMode":"localhost","socksPort":1086,"#
        + #""httpProxyEnabled":true,"httpPort":1086,"udpRelayEnabled":false}"#)

    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertEqual(
        error as? ListenSettingsStoreError,
        .invalidPorts([.duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 1086)]))
    }
  }
}
