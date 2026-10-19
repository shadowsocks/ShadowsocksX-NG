import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// Built-in modes keep a stable selector order and project local proxy settings.
final class ProxyModeAvailabilityTests: XCTestCase {
  func testBuiltInModesAreAlwaysAvailableInProductOrder() {
    XCTAssertEqual(
      ProxyMode.availableModes.map(\.kind),
      [.rule, .global, .direct])
  }

  func testDirectModeUsesLocalSOCKSAndIncludesFixedBypasses() {
    let document = SslocalRuntimeDocument(servers: [], listen: ProxyListeningConfiguration())

    let configuration = ProxyMode.direct.systemProxyConfiguration(for: document)

    XCTAssertEqual(
      configuration.socks,
      .init(host: "127.0.0.1", port: ProxyListeningConfiguration.defaultSocksPort))
    XCTAssertEqual(
      configuration.http,
      .init(host: "127.0.0.1", port: ProxyListeningConfiguration.defaultHTTPPort))
    XCTAssertEqual(
      configuration.exceptions,
      FixedLocalProxyRanges.systemProxyExceptions)
  }

  func testIPv6LANModeKeepsLocalSystemProxyEndpoints() {
    let listen = ProxyListeningConfiguration(listenerMode: .allIPv6Interfaces)
    let document = SslocalRuntimeDocument(servers: [], listen: listen)

    let configuration = ProxyMode.direct.systemProxyConfiguration(for: document)

    XCTAssertEqual(configuration.socks, .init(host: "127.0.0.1", port: listen.socksPort))
    XCTAssertEqual(configuration.http, .init(host: "127.0.0.1", port: listen.httpPort))
  }

  /// 全局模式：系统 SOCKS/HTTP 投影 + 固定本地例外，与直连共用
  /// 同一安全范围；公网路由由 ACL 决定，不由系统例外决定。
  func testGlobalModeUsesLocalSOCKSAndIncludesFixedBypasses() {
    let document = SslocalRuntimeDocument(servers: [], listen: ProxyListeningConfiguration())

    let configuration = ProxyMode.global.systemProxyConfiguration(for: document)

    XCTAssertEqual(
      configuration.socks,
      .init(host: "127.0.0.1", port: ProxyListeningConfiguration.defaultSocksPort))
    XCTAssertEqual(
      configuration.http,
      .init(host: "127.0.0.1", port: ProxyListeningConfiguration.defaultHTTPPort))
    XCTAssertEqual(
      configuration.exceptions,
      FixedLocalProxyRanges.systemProxyExceptions)
    XCTAssertFalse(
      configuration.exceptions.contains("100.64.0.0/10"),
      "不加入 CGNAT")
  }
}
