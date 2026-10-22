import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class RealSslocalCustomRuleSmokeTests: RealSslocalSmokeTests {
  /// 自定义规则真实 sslocal 路由：「未匹配时代理」下自定义
  /// 域名直连不触 SS 出口，未匹配目标走代理；SOCKS 与 HTTP 入站共用 ACL。
  func testCustomRulesRouteOnSOCKSAndHTTPInProxyDefaultMode() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = ProxyListeningConfiguration(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let customRules = [
      ProxyRule(
        action: .direct, match: try RuleMatch(domainSuffix: "direct.example")),
      ProxyRule(
        action: .direct, match: try RuleMatch(domainExact: "exact.other.example")),
    ]
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "custom-smoke-server",
          server: "127.0.0.1",
          serverPort: fakeSSServer.port,
          password: "smoke-password",
          method: "aes-256-gcm",
          plugin: nil,
          pluginOpts: nil)
      ],
      listen: listen,
      acl: ruleProbeACL(
        defaultAction: .proxyWhenUnmatched,
        rules: customRules))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)
    try assertCustomDirectRulesBypass(
      listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)
    try assertCustomUnmatchedProxies(
      listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)

    stopWrapperAndAssertCleanExit(wrapper, description: "custom rule wrapper exits")
    try assertCustomCIDRBypass(
      servers: document.servers, listen: listen, echo: echoServer, exit: fakeSSServer)
  }

  private func assertCustomCIDRBypass(
    servers: [SslocalServerDocument], listen: ProxyListeningConfiguration,
    echo: LoopbackEchoServer, exit: ConnectionCountingServer
  ) throws {
    let cidrDocument = SslocalRuntimeDocument(
      servers: servers, listen: listen,
      acl: ruleProbeACL(
        defaultAction: .proxyWhenUnmatched,
        rules: [
          ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "127.0.0.1/32"))
        ]))
    let cidrWrapper = try launchWrapper(cidrDocument)
    try awaitGlobalInboundsReady(listen: listen, document: cidrDocument)
    let beforeCIDR = exit.connectionCount
    let payload = Array("custom cidr direct\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echo.port, payload: payload), payload)
    XCTAssertEqual(exit.connectionCount, beforeCIDR)
    stopWrapperAndAssertCleanExit(cidrWrapper, description: "custom CIDR wrapper exits")
  }

  /// 后缀与完整域名使用互不覆盖的夹具，分别证明直连完成。
  private func assertCustomDirectRulesBypass(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeDirect = fakeSS.connectionCount
    for host in ["sub.direct.example", "exact.other.example"] {
      try assertDirectDomain(host, listen: listen, echoPort: echoPort, exit: fakeSS)
      XCTAssertEqual(fakeSS.connectionCount, beforeDirect)
    }
  }

  /// 未匹配目标默认代理；HTTP 入站应用同一自定义规则 ACL。
  private func assertCustomUnmatchedProxies(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeHit = fakeSS.connectionCount
    _ = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "unmatched.example.org", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeHit },
      "未匹配目标应走代理并连接 Shadowsocks 出口")
    let beforeExactBoundary = fakeSS.connectionCount
    XCTAssertNotNil(
      performSocksConnectReply(
        socksPort: listen.socksPort, targetHost: "sub.exact.other.example", targetPort: echoPort))
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeExactBoundary },
      "完整域名规则不得覆盖子域名")

    let afterSocks = fakeSS.connectionCount
    let payload = Array("http domain direct\n".utf8)
    XCTAssertEqual(
      try performDirectHTTPEcho(
        httpPort: listen.httpPort, targetHost: "other.direct.example", targetPort: echoPort,
        payload: payload), payload)
    XCTAssertEqual(
      fakeSS.connectionCount, afterSocks,
      "HTTP 入站的自定义直连规则不得触达 Shadowsocks 出口")

    performHTTPConnect(httpPort: listen.httpPort, targetHost: "8.8.8.8", targetPort: 53)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterSocks },
      "HTTP 入站未匹配目标应走代理")
  }

  /// 自定义规则真实 sslocal 路由：「未匹配时直连」下自定义
  /// 域名代理命中 SS 出口，未匹配目标直连。
  func testCustomRulesRouteOnSOCKSAndHTTPInDirectDefaultMode() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = ProxyListeningConfiguration(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let customRules = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))
    ]
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "custom-direct-smoke-server",
          server: "127.0.0.1",
          serverPort: fakeSSServer.port,
          password: "smoke-password",
          method: "aes-256-gcm",
          plugin: nil,
          pluginOpts: nil)
      ],
      listen: listen,
      acl: ruleProbeACL(
        defaultAction: .directWhenUnmatched,
        rules: customRules))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)
    try assertCustomProxyCandidatesHitSS(
      listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)

    stopWrapperAndAssertCleanExit(wrapper, description: "custom direct-default wrapper exits")
  }

  /// 自定义代理候选命中 SS；未匹配直连；HTTP 入站共用 ACL。
  private func assertCustomProxyCandidatesHitSS(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeHit = fakeSS.connectionCount
    _ = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "sub.blocked.example", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeHit },
      "自定义代理候选应连接 Shadowsocks 出口")

    let afterHit = fakeSS.connectionCount
    try assertDirectDomain(
      "unmatched.example.org", listen: listen, echoPort: echoPort, exit: fakeSS)
    XCTAssertEqual(
      fakeSS.connectionCount, afterHit,
      "未匹配目标在 bypass_all 下应直连")

    performHTTPConnect(
      httpPort: listen.httpPort, targetHost: "cdn.blocked.example", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterHit },
      "HTTP 入站应应用同一自定义规则 ACL")
  }
}
