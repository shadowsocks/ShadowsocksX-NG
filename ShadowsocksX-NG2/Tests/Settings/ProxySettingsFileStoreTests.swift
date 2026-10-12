import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 偏好持久化缝：设置文件只保存公开偏好；重置不触碰配置目录与活动目标
/// 使用的其他文件。
final class ProxySettingsFileStoreTests: XCTestCase {
  private var directory: URL!
  private var store: ProxySettingsFileStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-settings-tests-\(UUID().uuidString)", isDirectory: true)
    store = ProxySettingsFileStore(
      fileURL: directory.appendingPathComponent("settings.json"),
      legacyListenFileURL: directory.appendingPathComponent("listen-settings.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func writeRaw(_ text: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: store.fileURL)
  }

  private func makeWriteFailingStore() throws -> ProxySettingsFileStore {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blockedParent = directory.appendingPathComponent("blocked")
    try Data("not a directory".utf8).write(to: blockedParent)
    return ProxySettingsFileStore(
      fileURL: blockedParent.appendingPathComponent("settings.json"),
      legacyListenFileURL: directory.appendingPathComponent("listen-settings.json"))
  }

  func testRoundTripKeepsPreferences() throws {
    var settings = ProxySettings()
    settings.listen.listenerMode = .allIPv6Interfaces
    settings.listen.socksPort = 2086
    settings.listen.httpPort = 2087
    settings.proxyExceptions = "localhost, 127.0.0.1"
    settings.preferredMode = .direct

    try store.save(settings)

    XCTAssertEqual(try store.load(), settings)
    let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
    XCTAssertFalse(raw.contains("udpRelayEnabled"))
    XCTAssertFalse(raw.contains("timeoutSeconds"))
    XCTAssertFalse(raw.contains("verboseLogging"))
    XCTAssertFalse(raw.contains("advertisedAddress"))
    XCTAssertTrue(raw.contains("all_ipv6_interfaces"))
    XCTAssertEqual(try store.load().listen.mode, "tcp_and_udp")
  }

  func testEveryListenerModeRoundTripsWithoutAnAdvertisedAddress() throws {
    for mode in ListenerMode.allCases {
      try store.save(ProxySettings(listen: SslocalListenSettings(listenerMode: mode)))

      XCTAssertEqual(try store.load().listen.listenerMode, mode)
      let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
      XCTAssertFalse(raw.contains("advertisedAddress"))
    }
  }

  func testLoadPreservesPersistedLegacyDefaultPortsWithoutImplicitMigration() throws {
    var settings = ProxySettings()
    settings.listen.socksPort = 1086
    settings.listen.httpPort = 1087
    try store.save(settings)

    let loaded = try store.load()

    XCTAssertEqual(loaded.listen.socksPort, 1086)
    XCTAssertEqual(loaded.listen.httpPort, 1087)
  }

  func testMissingPortFieldsUseNewFactoryDefaults() throws {
    try writeRaw("{}")

    XCTAssertEqual(try store.load(), ProxySettings())
  }

  func testUnknownEnabledModesIsIgnoredAndNeverWrittenBack() throws {
    try writeRaw("{\"enabledModes\":[\"global\"],\"preferredMode\":\"global\"}")

    XCTAssertEqual(try store.load().preferredMode, .global)
    try store.save(ProxySettings())
    let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
    XCTAssertFalse(raw.contains("enabledModes"))
  }

  func testLegacyPACPreferredModeFallsBackToRuleWithoutLosingOtherFields() throws {
    try writeRaw(
      """
      {"preferredMode":"pac","socksPort":2086,"httpPort":2087,"timeoutSeconds":120,
       "verboseLogging":true,
       "pacUserRules":"@@example.com","gfwListURLConfigured":true,"pacPort":2089}
      """)

    let loaded = try store.load()
    XCTAssertEqual(loaded.preferredMode, .rule)
    XCTAssertEqual(loaded.listen.socksPort, 2086)
    XCTAssertEqual(loaded.listen.httpPort, 2087)
  }

  func testInvalidSaveDoesNotTouchExistingSettings() throws {
    try store.save(ProxySettings())
    var invalid = ProxySettings()
    invalid.listen.socksPort = 0

    XCTAssertThrowsError(try store.save(invalid)) { error in
      XCTAssertEqual(
        error as? ProxySettingsStoreError,
        .invalid([.portOutOfRange(endpoint: .socks, port: 0)]))
    }
    XCTAssertEqual(try store.load(), ProxySettings())
  }

  func testSaveFailureIsTypedIOFailure() throws {
    store = try makeWriteFailingStore()

    XCTAssertThrowsError(try store.save(ProxySettings())) { error in
      guard case .ioFailure = error as? ProxySettingsStoreError else {
        return XCTFail("文件写入失败应保留为 typed io failure，实际为 \(error)")
      }
    }
  }

  func testMissingNewFileMigratesLegacyListenSettingsAndUsesNewDefaults() throws {
    var legacy = SslocalListenSettings()
    legacy.socksPort = 2086
    try ListenSettingsFileStore(fileURL: store.legacyListenFileURL).save(legacy)

    let loaded = try store.load()

    XCTAssertEqual(loaded.listen, legacy)
  }
}
