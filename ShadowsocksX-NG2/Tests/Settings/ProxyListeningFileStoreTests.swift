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
    store = makeTestListeningStore(
      fileURL: directory.appendingPathComponent("proxy-listening.enc"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func makeWriteFailingStore() throws -> ProxyListeningFileStore {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blockedParent = directory.appendingPathComponent("blocked")
    try Data("not a directory".utf8).write(to: blockedParent)
    return makeTestListeningStore(
      fileURL: blockedParent.appendingPathComponent("proxy-listening.enc"))
  }

  func testRoundTripKeepsListeningConfiguration() throws {
    var settings = ProxyListeningConfiguration()
    settings.listenerMode = .allIPv6Interfaces
    settings.socksPort = 2086
    settings.httpPort = 2087

    try store.save(settings)

    XCTAssertEqual(try store.load(), settings)
    XCTAssertEqual(try store.load().mode, "tcp_and_udp")
  }

  func testEncryptedListeningHasItsOwnFile() {
    XCTAssertEqual(
      ProxyListeningFileStore.defaultFileURL().lastPathComponent, "proxy-listening.enc")
  }

  func testEveryListenerModeRoundTripsWithoutAnAdvertisedAddress() throws {
    for mode in ListenerMode.allCases {
      try store.save(ProxyListeningConfiguration(listenerMode: mode))

      XCTAssertEqual(try store.load().listenerMode, mode)
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
