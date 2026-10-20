import XCTest

@testable import ShadowsocksX_NG2

/// 设置主缝：偏好校验与绕过列表解析只通过公开领域入口断言，不依赖
/// SwiftUI 视图实现。
final class ProxyRuntimeSettingsTests: XCTestCase {
  func testFactoryDefaultsAvoidLegacyPortsAndValidate() {
    let settings = ProxyRuntimeSettings()

    XCTAssertEqual(settings.listen.socksPort, 11086)
    XCTAssertEqual(settings.listen.httpPort, 11087)
    XCTAssertFalse(settings.agentEnabled, "全新用户无服务器配置，Agent 默认 off")
    XCTAssertFalse(settings.systemProxyEnabled)
    XCTAssertTrue(settings.validationErrors.isEmpty)
  }

  func testProxyExceptionsSplitCommaChineseCommaAndWhitespaceWithoutDuplicates() {
    var settings = ProxyRuntimeSettings()
    settings.proxyExceptions = "localhost, 127.0.0.1、localhost\n::1"

    XCTAssertEqual(settings.proxyExceptionList, ["localhost", "127.0.0.1", "::1"])
  }

  func testListenerModeDoesNotAddAddressTextValidation() {
    var settings = ProxyRuntimeSettings()
    settings.listen.listenerMode = .allIPv6Interfaces
    settings.listen.socksPort = settings.listen.httpPort

    XCTAssertEqual(
      settings.validationErrors,
      [
        .duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 11087)
      ])
  }
}
