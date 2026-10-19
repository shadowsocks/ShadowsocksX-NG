import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 监听文件持久化缝：只保存本地与局域网监听，不承载独立偏好。
final class ProxyListeningFileStoreTests: XCTestCase {
  private var directory: URL!
  private var store: ProxyListeningFileStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-settings-tests-\(UUID().uuidString)", isDirectory: true)
    store = ProxyListeningFileStore(
      fileURL: directory.appendingPathComponent("proxy-listening.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func writeRaw(_ text: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: store.fileURL)
  }

  private func makeWriteFailingStore() throws -> ProxyListeningFileStore {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blockedParent = directory.appendingPathComponent("blocked")
    try Data("not a directory".utf8).write(to: blockedParent)
    return ProxyListeningFileStore(
      fileURL: blockedParent.appendingPathComponent("proxy-listening.json"))
  }

  func testRoundTripKeepsListeningConfiguration() throws {
    var settings = ProxyListeningConfiguration()
    settings.listenerMode = .allIPv6Interfaces
    settings.socksPort = 2086
    settings.httpPort = 2087

    try store.save(settings)

    XCTAssertEqual(try store.load(), settings)
    let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
    XCTAssertTrue(raw.contains("udpRelayEnabled"))
    XCTAssertFalse(raw.contains("timeoutSeconds"))
    XCTAssertFalse(raw.contains("verboseLogging"))
    XCTAssertFalse(raw.contains("advertisedAddress"))
    XCTAssertTrue(raw.contains("all_ipv6_interfaces"))
    XCTAssertEqual(try store.load().mode, "tcp_and_udp")
  }

  func testListeningFileDoesNotOwnIndependentPreferences() throws {
    try store.save(ProxyListeningConfiguration())
    let data = try Data(contentsOf: store.fileURL)
    let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(record.keys), ["localListen", "lanListen"])
    XCTAssertEqual(
      ProxyListeningFileStore.defaultFileURL().lastPathComponent, "proxy-listening.json")
  }

  func testEveryListenerModeRoundTripsWithoutAnAdvertisedAddress() throws {
    for mode in ListenerMode.allCases {
      try store.save(ProxyListeningConfiguration(listenerMode: mode))

      XCTAssertEqual(try store.load().listenerMode, mode)
      let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
      XCTAssertFalse(raw.contains("advertisedAddress"))
    }
  }

  func testLoadPreservesPersistedLegacyDefaultPortsWithoutImplicitMigration() throws {
    var settings = ProxyListeningConfiguration()
    settings.socksPort = 1086
    settings.httpPort = 1087
    try store.save(settings)

    let loaded = try store.load()

    XCTAssertEqual(loaded.socksPort, 1086)
    XCTAssertEqual(loaded.httpPort, 1087)
  }

  func testMissingPortFieldsUseNewFactoryDefaults() throws {
    try writeRaw("{}")

    XCTAssertEqual(try store.load(), ProxyListeningConfiguration())
  }

  func testInvalidSaveDoesNotTouchExistingSettings() throws {
    try store.save(ProxyListeningConfiguration())
    var invalid = ProxyListeningConfiguration()
    invalid.socksPort = 0

    XCTAssertThrowsError(try store.save(invalid)) { error in
      XCTAssertEqual(
        error as? ProxyListeningStoreError,
        .invalid([.portOutOfRange(endpoint: .socks, port: 0)]))
    }
    XCTAssertEqual(try store.load(), ProxyListeningConfiguration())
  }

  func testSaveFailureIsTypedIOFailure() throws {
    store = try makeWriteFailingStore()

    XCTAssertThrowsError(try store.save(ProxyListeningConfiguration())) { error in
      guard case .ioFailure = error as? ProxyListeningStoreError else {
        return XCTFail("文件写入失败应保留为 typed io failure，实际为 \(error)")
      }
    }
  }
}
