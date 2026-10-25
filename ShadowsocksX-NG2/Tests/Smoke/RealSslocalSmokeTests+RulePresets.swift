import Darwin
import XCTest

@testable import ShadowsocksX_NG2

extension RealSslocalACLRoutingSmokeTests {
  func testChinaProxyPresetRoutesChinaTargetsThroughProxyAndOtherTargetsDirect() throws {
    let echo = try LoopbackEchoServer()
    let exit = try ConnectionCountingServer()
    let ports = try grabThreeListenPorts(excluding: [echo.port, exit.port])
    let listen = ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1])
    let metadata = try BuiltinRuleCatalog.loadGeolocationCN(from: AppArtifact.bundle).metadata
    let snapshot = RuleSnapshot(
      metadata: metadata,
      rules: [
        ProxyRule(action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn")),
        ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "china-target.example.org")),
        ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "127.0.0.1/32")),
      ])
    let preset = RulePreset.chinaProxy
    for probeCIDR in [false, true] {
      let candidates = preset.rules(from: snapshot).filter { rule in
        if case .ipv4CIDR = rule.match.pattern { return probeCIDR }
        return true
      }
      let acl =
        probeCIDR
        ? ruleProbeACL(defaultAction: preset.defaultAction, rules: candidates)
        : ProxyACLDocument.rule(
          at: aclFileURL, defaultAction: preset.defaultAction, rules: candidates)
      let document = SslocalRuntimeDocument(
        servers: [
          SslocalServerDocument(
            id: "china-proxy", server: "127.0.0.1", serverPort: exit.port,
            password: "smoke-password", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
        ],
        listen: listen, acl: acl)
      let wrapper = try launchWrapper(document)
      defer { if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) } }
      try awaitGlobalInboundsReady(listen: listen, document: document)
      try assertReceiptOwnsListeners(document: document)
      for host in probeCIDR ? ["127.0.0.1"] : ["example.cn", "china-target.example.org"] {
        let before = exit.connectionCount
        _ = performSocksConnectReply(
          socksPort: listen.socksPort, targetHost: host, targetPort: echo.port)
        XCTAssertTrue(try waitForCondition(timeout: 5) { exit.connectionCount > before })
        let afterSOCKS = exit.connectionCount
        performHTTPConnect(httpPort: listen.httpPort, targetHost: host, targetPort: echo.port)
        XCTAssertTrue(try waitForCondition(timeout: 5) { exit.connectionCount > afterSOCKS })
      }
      if !probeCIDR { try assertChinaPresetDirectTargets(listen: listen, echo: echo, exit: exit) }
      stopWrapperAndAssertCleanExit(wrapper, description: "China proxy preset wrapper exits")
    }
  }
}

extension RealSslocalACLRoutingSmokeTests {
  private func assertChinaPresetDirectTargets(
    listen: ProxyListeningConfiguration, echo: LoopbackEchoServer, exit: ConnectionCountingServer
  ) throws {
    let before = exit.connectionCount
    try assertDirectDomain("unmatched.example.org", listen: listen, echoPort: echo.port, exit: exit)
    let payload = Array("default direct\n".utf8)
    XCTAssertEqual(
      try performDirectHTTPEcho(
        httpPort: listen.httpPort, targetHost: "unmatched.example.org", targetPort: echo.port,
        payload: payload), payload)
    XCTAssertEqual(exit.connectionCount, before)
  }
}
