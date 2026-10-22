import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class RealSslocalRuleSemanticsSmokeTests: RealSslocalSmokeTests {
  override var usesLocalDNS: Bool { false }
  func testRuleSemanticsWithProxyDefaultAndReversedOrder() throws {
    try assertRuleSemantics(defaultHeader: "[proxy_all]", unmatchedProxies: true)
  }

  func testRuleSemanticsWithDirectDefaultAndReversedOrder() throws {
    try assertRuleSemantics(defaultHeader: "[bypass_all]", unmatchedProxies: false)
  }

  /// Test-only dual-list ACL: product proxy-default intentionally omits proxy_list.
  /// Only loopback IPs and reserved .invalid domains are requested. Opposite
  /// defaults distinguish actual rule hits from an unmatched default result.
  private func assertRuleSemantics(defaultHeader: String, unmatchedProxies: Bool) throws {
    let echo = try LoopbackEchoServer()
    let exit = try ConnectionCountingServer()
    let bypass = [
      "||overlap.invalid", "||partial.invalid",
    ]
    let proxy = [
      "127.0.0.0/8", "::ffff:127.0.0.0/120",
      "||overlap.invalid", "|a.partial.invalid",
      "|exact.invalid", "||suffix.invalid",
    ]
    for reversed in [false, true] {
      let ports = try grabThreeListenPorts(excluding: [echo.port, exit.port])
      let listen = ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1])
      let bypass = bypass + [reversed ? "::ffff:127.0.0.1/128" : "127.0.0.1/32"]
      let lines =
        [defaultHeader, "[bypass_list]"]
        + (reversed ? Array(bypass.reversed()) : bypass) + ["[proxy_list]"]
        + (reversed ? Array(proxy.reversed()) : proxy)
      let document = SslocalRuntimeDocument(
        servers: [
          SslocalServerDocument(
            id: "rule-semantics", server: "127.0.0.1", serverPort: exit.port,
            password: "smoke-password", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
        ],
        listen: listen,
        acl: ProxyACLDocument(
          path: aclFileURL.path, summary: "rule-semantics",
          content: lines.joined(separator: "\n") + "\n"))
      let wrapper = try launchWrapper(document)
      defer { if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) } }
      try awaitGlobalInboundsReady(listen: listen, document: document)
      try assertDomainRuleSemantics(
        listen: listen, exit: exit, port: echo.port, unmatchedProxies: unmatchedProxies)
      let before = exit.connectionCount
      XCTAssertEqual(
        performSocksConnectReply(
          socksPort: listen.socksPort,
          request: mappedConnectRequest([127, 0, 0, 1], port: echo.port)), 0)
      XCTAssertEqual(
        performSocksConnectReply(
          socksPort: listen.socksPort,
          request: socksIPv4ConnectRequest([127, 0, 0, 1], port: echo.port)), 0)
      XCTAssertEqual(exit.connectionCount, before, "Mapped and IPv4 bypass both protect loopback")
      try assertRuleRoute(
        socksPort: listen.socksPort, exit: exit,
        request: mappedConnectRequest([127, 0, 0, 2], port: echo.port), proxies: true,
        description: "IP overlap keeps remaining proxy targets")
      stopWrapperAndAssertCleanExit(wrapper, description: "rule semantics wrapper exits")
    }
  }

  private func assertDomainRuleSemantics(
    listen: ProxyListeningConfiguration, exit: ConnectionCountingServer, port: Int,
    unmatchedProxies: Bool
  ) throws {
    for host in [
      "overlap.invalid", "a.overlap.invalid", "a.partial.invalid",
      "exact.invalid", "suffix.invalid", "a.suffix.invalid",
    ] {
      try assertRuleRoute(
        socksPort: listen.socksPort, exit: exit,
        request: socksDomainConnectRequest(host: host, port: port), proxies: true,
        description: host)
    }
    try assertRuleRoute(
      socksPort: listen.socksPort, exit: exit,
      request: socksDomainConnectRequest(host: "b.partial.invalid", port: port),
      proxies: false, description: "partial overlap keeps remaining direct targets")
    for host in ["a.exact.invalid", "notsuffix.invalid"] {
      try assertRuleRoute(
        socksPort: listen.socksPort, exit: exit,
        request: socksDomainConnectRequest(host: host, port: port),
        proxies: unmatchedProxies, description: "unmatched boundary: \(host)")
    }
  }

  private func assertRuleRoute(
    socksPort: Int, exit: ConnectionCountingServer, request: [UInt8],
    proxies: Bool, description: String
  ) throws {
    let before = exit.connectionCount
    let reply = performSocksConnectReply(socksPort: socksPort, request: request)
    XCTAssertNotNil(reply, "SOCKS routing request completed: \(description)")
    if proxies {
      XCTAssertTrue(try waitForCondition(timeout: 5) { exit.connectionCount > before }, description)
    } else {
      Thread.sleep(forTimeInterval: 0.2)
      XCTAssertEqual(exit.connectionCount, before, description)
    }
  }

  private func mappedConnectRequest(_ octets: [UInt8], port: Int) -> [UInt8] {
    var request: [UInt8] = [5, 1, 0, 4]
    request += Array(repeating: 0, count: 10) + [255, 255] + octets
    withUnsafeBytes(of: UInt16(port).bigEndian) { request.append(contentsOf: $0) }
    return request
  }
}
