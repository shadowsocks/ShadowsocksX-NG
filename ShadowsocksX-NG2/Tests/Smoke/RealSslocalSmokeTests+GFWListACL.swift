import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class RealSslocalGFWListSmokeTests: RealSslocalSmokeTests {
  /// 规则＋未匹配时直连：bypass_all + GFWList 代理候选。命中
  /// GFWList 域名走代理；未匹配域名与 IP 字面目标直连；SOCKS 与 HTTP 共用 ACL。
  func testRuleDirectDefaultACLRoutesGFWListProxyAndUnmatchedDirect() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = SslocalListenSettings(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let gfwRules = [
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example")),
      ProxyRule(
        action: .proxy, match: try RuleMatch(domainSuffix: "cdn.blocked.example")),
    ]
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "gfw-smoke-server",
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
        rules: gfwRules))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)
    try assertLocalTargetsBypass(listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)
    try assertGFWListDirectDefaultRouting(
      listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)

    stopWrapperAndAssertCleanExit(wrapper, description: "gfwlist rule wrapper exits")
  }

  /// 原版 sslocal ACL 域名/IP 优先级：域名 proxy_list 先于
  /// bypass_list，IP bypass_list 先于 proxy_list；两个入站共用同一 ACL。
  func testRealSslocalDomainAndIPACLPriorityOnSOCKSAndHTTP() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = SslocalListenSettings(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let acl = priorityProbeACL()
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "priority-smoke-server",
          server: "127.0.0.1",
          serverPort: fakeSSServer.port,
          password: "smoke-password",
          method: "aes-256-gcm",
          plugin: nil,
          pluginOpts: nil)
      ],
      listen: listen,
      acl: acl)
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)
    try assertDomainPriorityBeatsBypassList(listen: listen, fakeSS: fakeSSServer)
    try assertIPPriorityBeatsProxyList(
      listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)

    let afterHTTPBase = fakeSSServer.connectionCount
    performHTTPConnect(httpPort: listen.httpPort, targetHost: "sub.example.com", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSSServer.connectionCount > afterHTTPBase },
      "HTTP 入站应应用同一域名优先级")

    stopWrapperAndAssertCleanExit(wrapper, description: "priority wrapper exits")
  }

  /// 双列表优先级探针 ACL：域名与 IP 各有冲突项，用于观测 sslocal 真实匹配顺序。
  private func priorityProbeACL() -> ProxyACLDocument {
    let aclContent = """
      [proxy_all]
      [bypass_list]
      10.0.0.0/8
      172.16.0.0/12
      192.168.0.0/16
      169.254.0.0/16
      ::1/128
      fe80::/10
      fc00::/7
      ||localhost
      ||local
      ^[^.]+$
      127.0.0.1/32
      ||sub.example.com
      [proxy_list]
      ||example.com
      127.0.0.0/8
      """
    let acl = ProxyACLDocument(
      path: aclFileURL.standardizedFileURL.path,
      summary: "priority-probe",
      content: aclContent)
    XCTAssertTrue(acl.isWellFormed)
    return acl
  }

  /// 域名：proxy_list 的 `||example.com` 覆盖 bypass_list 的 `||sub.example.com`。
  private func assertDomainPriorityBeatsBypassList(
    listen: SslocalListenSettings, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeDomain = fakeSS.connectionCount
    _ = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "sub.example.com", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeDomain },
      "域名优先级：proxy_list 应优先于 bypass_list")
  }

  /// IP：bypass_list 的 `127.0.0.1/32` 覆盖 proxy_list 的 `127.0.0.0/8`；
  /// 同 CIDR 内未单列直连的 IP 仍走 proxy_list。
  private func assertIPPriorityBeatsProxyList(
    listen: SslocalListenSettings, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeIP = fakeSS.connectionCount
    let payload = Array("priority direct\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echoPort, payload: payload),
      payload)
    XCTAssertEqual(
      fakeSS.connectionCount, beforeIP,
      "IP 优先级：bypass_list 应优先于 proxy_list")

    _ = performSocksConnectReply(
      socksPort: listen.socksPort,
      request: socksIPv4ConnectRequest([127, 0, 0, 2], port: echoPort))
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeIP },
      "未在 bypass_list 单列的 IP 应命中 proxy_list CIDR")
  }

  /// GFWList「未匹配时直连」路由断言：命中代理候选走 SS；未匹配域名与 IP
  /// 字面目标不触达 SS（bypass_all 默认直连）。
  func assertGFWListDirectDefaultRouting(
    listen: SslocalListenSettings, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeHit = fakeSS.connectionCount
    _ = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "blocked.example", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeHit },
      "GFWList 代理候选应连接 Shadowsocks 出口")

    let afterHit = fakeSS.connectionCount
    _ = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "cdn.blocked.example", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterHit },
      "GFWList 子域代理候选应连接 Shadowsocks 出口")

    let afterMatched = fakeSS.connectionCount
    try assertDirectDomain(
      "unmatched.example.org", listen: listen, echoPort: echoPort, exit: fakeSS)
    XCTAssertEqual(
      fakeSS.connectionCount, afterMatched,
      "未匹配域名在 bypass_all 下应直连，不得触达 Shadowsocks 出口")

    let payload = Array("unmatched IP direct\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echoPort, payload: payload),
      payload)
    XCTAssertEqual(
      fakeSS.connectionCount, afterMatched,
      "未命中规则的 IP 字面目标应直连")

    performHTTPConnect(httpPort: listen.httpPort, targetHost: "blocked.example", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterMatched },
      "HTTP 入站应应用同一 GFWList ACL")
  }
}
