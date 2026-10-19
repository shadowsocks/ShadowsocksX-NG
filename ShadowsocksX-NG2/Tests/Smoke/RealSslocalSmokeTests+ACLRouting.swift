import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class RealSslocalACLRoutingSmokeTests: RealSslocalSmokeTests {
  func testDirectACLRoutesSOCKSAndHTTPLocallyWithoutServers() throws {
    let echoServer = try LoopbackEchoServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port])
    let listen = ProxyListeningConfiguration(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let document = SslocalRuntimeDocument(
      servers: [],
      listen: listen,
      acl: .direct(at: aclFileURL))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    XCTAssertTrue(
      try waitForCondition(timeout: 15) {
        EndpointHealthProbe.probe(host: "127.0.0.1", port: listen.socksPort, timeout: 1)
          == .reachable
          && EndpointHealthProbe.probe(host: "127.0.0.1", port: listen.httpPort, timeout: 1)
            == .reachable
      }, "直连模式应绑定 SOCKS 和 HTTP 入站")
    try assertReceiptOwnsListeners(document: document)

    let socksPayload = Array("socks direct\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echoServer.port, payload: socksPayload),
      socksPayload,
      "空服务器列表下 SOCKS 应通过 bypass_all 直连回环目标")

    let httpPayload = Array("http direct\n".utf8)
    XCTAssertEqual(
      try performDirectHTTPEcho(
        httpPort: listen.httpPort, targetPort: echoServer.port, payload: httpPayload),
      httpPayload,
      "HTTP 入站应应用同一 ACL 并直连回环目标")

    stopWrapperAndAssertCleanExit(wrapper, description: "direct wrapper exits")
    XCTAssertNil(
      RuntimeFileStore(fileURL: contractURL).readRuntimeReceipt(), "停止后应清除运行回执")
  }

  /// 全局模式 ACL 路由：proxy_all + 固定本地绕过。本地目标经
  /// SOCKS/HTTP 直连（不触 SS 出口），公网目标默认走代理（SS 出口被连接）。
  /// 两个入站共用同一 ACL；IPv6 系统例外的局限由 ACL 路由兜底（见 ADR）。
  func testGlobalACLRoutesLocalDirectAndPublicThroughProxyOnSOCKSAndHTTP() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = ProxyListeningConfiguration(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "global-smoke-server",
          server: "127.0.0.1",
          serverPort: fakeSSServer.port,
          password: "smoke-password",
          method: "aes-256-gcm",
          plugin: nil,
          pluginOpts: nil)
      ],
      listen: listen,
      acl: .global(at: aclFileURL))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)

    try assertLocalTargetsBypass(listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)
    try assertPublicTargetsProxy(listen: listen, fakeSS: fakeSSServer)

    stopWrapperAndAssertCleanExit(wrapper, description: "global wrapper exits")
    // Isolate host exceptions from the loopback IP bypass checked above.
    let hostACL = ProxyACLDocument(
      path: aclFileURL.path, summary: "fixed-host-probe",
      content: document.aclRuntime!.content.replacingOccurrences(of: "127.0.0.0/8\n", with: ""))
    let hostDocument = SslocalRuntimeDocument(
      servers: document.servers, listen: listen, acl: hostACL)
    let hostWrapper = try launchWrapper(hostDocument)
    try awaitGlobalInboundsReady(listen: listen, document: hostDocument)
    try assertHostnameAndIPv6Bypass(listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)
    stopWrapperAndAssertCleanExit(hostWrapper, description: "fixed host wrapper exits")
    XCTAssertNil(
      RuntimeFileStore(fileURL: contractURL).readRuntimeReceipt(),
      "停止后应清除运行回执")
  }

  /// 规则模式 ACL 路由：「未匹配时代理」→ proxy_all + 中国域名
  /// 直连候选。`.cn` 目标经本地 DNS 解析到 echo；非中国公网目标默认走代理。
  /// 专用规则探针去除回环绕过，固定本地绕过由全局模式用例覆盖。
  func testRuleProxyDefaultACLRoutesChinaDirectAndRestThroughProxy() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = ProxyListeningConfiguration(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let chinaRules = [
      ProxyRule(
        action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))
    ]
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "rule-smoke-server",
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
        rules: chinaRules))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)

    try assertRuleModeRouting(listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)

    stopWrapperAndAssertCleanExit(wrapper, description: "rule wrapper exits")
  }

  /// 规则模式 ACL 路由：中国 IPv4 CIDR 直连候选。命中 CIDR 的
  /// 目标不触达 SS 出口；未命中 CIDR 的公网目标默认走代理；SOCKS 与 HTTP
  /// 入站共用同一 ACL。CIDR 判定可能触发本地 DNS 查询（文档已声明）。
  func testRuleProxyDefaultACLRoutesChinaCIDRHitDirectAndMissThroughProxy() throws {
    let echoServer = try LoopbackEchoServer()
    let fakeSSServer = try ConnectionCountingServer()
    let selectedPorts = try grabThreeListenPorts(excluding: [echoServer.port, fakeSSServer.port])
    let listen = ProxyListeningConfiguration(
      socksPort: selectedPorts[0], httpPort: selectedPorts[1])
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "cidr-smoke-server",
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
        rules: try chinaCIDRSmokeRules()))
    XCTAssertTrue(document.isWellFormed)
    let wrapper = try launchWrapper(document)
    defer {
      if wrapper.isRunning { kill(wrapper.processIdentifier, SIGTERM) }
    }

    try awaitGlobalInboundsReady(listen: listen, document: document)
    try assertCIDRModeRouting(listen: listen, echoPort: echoServer.port, fakeSS: fakeSSServer)

    stopWrapperAndAssertCleanExit(wrapper, description: "cidr rule wrapper exits")
  }

  /// 冒烟夹具：`.cn` 域名 + 测试用 `127.0.0.1/32` CIDR 直连候选
  /// （仅验证命中/未命中路由，不代表真实中国 IP 归属）。
  private func chinaCIDRSmokeRules() throws -> [ProxyRule] {
    return [
      ProxyRule(
        action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn")),
      ProxyRule(
        action: .direct, match: try RuleMatch(ipv4CIDR: "127.0.0.1/32")),
    ]
  }

  /// CIDR 路由断言：命中 `127.0.0.1/32` 完成回显；未命中目标走代理。
  private func assertCIDRModeRouting(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let beforeHit = fakeSS.connectionCount
    let payload = Array("cidr direct\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echoPort, payload: payload),
      payload)
    XCTAssertEqual(
      fakeSS.connectionCount, beforeHit,
      "命中中国 IPv4 CIDR 的目标应直连，不得触达 Shadowsocks 出口")

    _ = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "1.1.1.1", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeHit },
      "未命中 CIDR 的公网目标应连接 Shadowsocks 出口")

    let afterSocks = fakeSS.connectionCount
    performHTTPConnect(httpPort: listen.httpPort, targetHost: "9.9.9.9", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterSocks },
      "HTTP 入站应应用同一规则 ACL")
  }

}

extension RealSslocalSmokeTests {
  func awaitGlobalInboundsReady(
    listen: ProxyListeningConfiguration, document: SslocalRuntimeDocument
  ) throws {
    XCTAssertTrue(
      try waitForCondition(timeout: 15) {
        EndpointHealthProbe.probe(host: "127.0.0.1", port: listen.socksPort, timeout: 1)
          == .reachable
          && EndpointHealthProbe.probe(host: "127.0.0.1", port: listen.httpPort, timeout: 1)
            == .reachable
      }, "全局模式应绑定 SOCKS 和 HTTP 入站")
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    XCTAssertTrue(
      try waitForCondition(timeout: 30) {
        guard let receipt = runtimeStore.readRuntimeReceipt() else { return false }
        return receipt.deploymentID == runtimeStore.receiptIdentity(for: document)
          && kill(receipt.processID, 0) == 0
      }, "应发布仍存活的 sslocal 子进程回执")
  }

  /// 规则模式路由断言：`.cn` 直连候选不触 SS 出口；未匹配公网目标经 SS 出口
  /// （SOCKS 与 HTTP 入站同样生效）。
  func assertRuleModeRouting(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    // .cn 域名候选直连：SOCKS CONNECT example.cn 不应触达 SS 出口。
    let beforeCN = fakeSS.connectionCount
    try assertDirectDomain("example.cn", listen: listen, echoPort: echoPort, exit: fakeSS)
    XCTAssertEqual(
      fakeSS.connectionCount, beforeCN,
      "规则模式的 .cn 直连候选不得触达 Shadowsocks 出口")

    // 非中国公网目标默认代理。
    let publicReply = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "8.8.8.8", targetPort: 53)
    XCTAssertNotNil(publicReply, "未匹配目标应走代理路径")
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > beforeCN },
      "未匹配的公网目标应连接 Shadowsocks 出口")

    // HTTP 入站对未匹配目标同样走代理。
    let afterSocks = fakeSS.connectionCount
    performHTTPConnect(httpPort: listen.httpPort, targetHost: "1.1.1.1", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterSocks },
      "HTTP 入站应应用同一规则 ACL")
  }

  func assertLocalTargetsBypass(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let socksPayload = Array("socks local\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echoPort, payload: socksPayload),
      socksPayload,
      "全局 ACL 的本地绕过应让 SOCKS 直连回环目标")
    let httpPayload = Array("http local\n".utf8)
    XCTAssertEqual(
      try performDirectHTTPEcho(
        httpPort: listen.httpPort, targetPort: echoPort, payload: httpPayload),
      httpPayload,
      "HTTP 入站应应用同一 ACL 并直连回环目标")
    XCTAssertEqual(fakeSS.connectionCount, 0, "本地绕过不得触达 Shadowsocks 出口")
  }

  func assertPublicTargetsProxy(
    listen: ProxyListeningConfiguration, fakeSS: ConnectionCountingServer
  ) throws {
    let publicSocksReply = performSocksConnectReply(
      socksPort: listen.socksPort, targetHost: "8.8.8.8", targetPort: 53)
    XCTAssertNotNil(publicSocksReply, "公网目标应走代理路径")
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount >= 1 },
      "公网目标应连接 Shadowsocks 出口，而不是直连")
    let afterSocks = fakeSS.connectionCount

    performHTTPConnect(httpPort: listen.httpPort, targetHost: "1.1.1.1", targetPort: 443)
    XCTAssertTrue(
      try waitForCondition(timeout: 5) { fakeSS.connectionCount > afterSocks },
      "HTTP 入站的公网目标应同样连接 Shadowsocks 出口")
    XCTAssertTrue(
      fakeSS.connectionCount >= 2,
      "SOCKS 与 HTTP 对公网目标遵循同一 ACL 路由")
  }

  /// 主机名固定绕过与 IPv6 回环：本地 DNS 将主机名解析到 echo，
  /// 成功回显证明直连完成；IPv6 回环无监听时验证失败应答且不触达 SS。
  func assertHostnameAndIPv6Bypass(
    listen: ProxyListeningConfiguration, echoPort: Int, fakeSS: ConnectionCountingServer
  ) throws {
    let afterPublic = fakeSS.connectionCount
    XCTAssertEqual(
      try performSocksEcho(
        socksPort: listen.socksPort,
        request: socksDomainConnectRequest(host: "localhost", port: echoPort),
        payload: Array("localhost\n".utf8),
        successMessage: "localhost 应绕过并直连"),
      Array("localhost\n".utf8))
    for host in ["printer.local", "nas"] {
      try assertDirectDomain(host, listen: listen, echoPort: echoPort, exit: fakeSS)
    }
    XCTAssertEqual(
      fakeSS.connectionCount, afterPublic,
      "localhost/*.local/无点主机名的固定绕过不得触达 Shadowsocks 出口")

    let afterHostnames = fakeSS.connectionCount
    XCTAssertNotNil(
      performSocksConnectReply(
        socksPort: listen.socksPort,
        request: socksIPv6ConnectRequest(port: echoPort)))
    XCTAssertEqual(
      fakeSS.connectionCount, afterHostnames,
      "IPv6 本地目标不得触达 Shadowsocks 出口，由 ACL 路由兜底")
  }
}
