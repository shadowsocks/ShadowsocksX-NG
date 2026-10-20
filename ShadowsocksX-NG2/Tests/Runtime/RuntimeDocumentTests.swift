import XCTest

@testable import ShadowsocksX_NG2

/// 运行时文档缝：派生 JSON 的字段契约与监听设置透传。
/// 上游字段名以 shadowsocks-rust v1.26.0 配置契约为准；无插件时整体省略插件字段。
final class RuntimeDocumentTests: XCTestCase {
  private func encodedDictionary(_ document: SslocalRuntimeDocument) throws -> [String: Any] {
    let data = try document.jsonData()
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
  }

  private func makeDocument(
    plugin: String? = nil, pluginOpts: String? = nil
  ) -> SslocalRuntimeDocument {
    SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "server-1",
          server: "203.0.113.7",
          serverPort: 8388,
          password: "resolved-password",
          method: "aes-256-gcm",
          plugin: plugin,
          pluginOpts: pluginOpts
        )
      ], listen: ProxyListeningConfiguration()
    )
  }

  // MARK: 字段契约

  func testDocumentEncodesUpstreamContractKeys() throws {
    let dictionary = try encodedDictionary(
      makeDocument(plugin: "/bundle/plugins/x", pluginOpts: "obfs=http"))

    let locals = try XCTUnwrap(dictionary["locals"] as? [[String: Any]])
    XCTAssertEqual(locals.count, 2)
    XCTAssertEqual(locals[0]["local_address"] as? String, "127.0.0.1")
    XCTAssertEqual(locals[0]["local_port"] as? Int, 11086)
    XCTAssertEqual(locals[0]["protocol"] as? String, "socks")
    XCTAssertEqual(locals[0]["mode"] as? String, "tcp_and_udp")
    XCTAssertEqual(locals[1]["local_port"] as? Int, 11087)
    XCTAssertEqual(locals[1]["protocol"] as? String, "http")
    XCTAssertNil(dictionary["x_shadowsocksx_ng_listen"])
    XCTAssertNil(dictionary["x_shadowsocksx_ng_acl"])
    XCTAssertNil(dictionary["ipv6_only"])
    XCTAssertNil(dictionary["timeout"])
    let servers = try XCTUnwrap(dictionary["servers"] as? [[String: Any]])
    XCTAssertEqual(servers.count, 1)
    let server = servers[0]
    XCTAssertEqual(server["id"] as? String, "server-1", "叶子身份进入文档，供诊断与稳定标识")
    XCTAssertFalse(
      server.keys.contains("remarks"), "显示名是目录元数据，不进契约（只承载连接有效值）")
    XCTAssertEqual(server["server"] as? String, "203.0.113.7")
    XCTAssertEqual(server["server_port"] as? Int, 8388)
    XCTAssertEqual(server["password"] as? String, "resolved-password")
    XCTAssertEqual(server["method"] as? String, "aes-256-gcm")
    XCTAssertEqual(server["plugin"] as? String, "/bundle/plugins/x")
    XCTAssertEqual(server["plugin_opts"] as? String, "obfs=http")
  }

  func testPluginFieldsAreAbsentEntirelyWithoutPlugin() throws {
    let dictionary = try encodedDictionary(makeDocument())

    let server = try XCTUnwrap((dictionary["servers"] as? [[String: Any]])?[0])
    XCTAssertFalse(server.keys.contains("plugin"), "选「无」时 plugin 字段整体省略（D10）")
    XCTAssertFalse(server.keys.contains("plugin_opts"))
  }

  func testJSONDataIsStableAcrossEncodes() throws {
    let document = makeDocument(plugin: "/bundle/plugins/x")

    XCTAssertEqual(try document.jsonData(), try document.jsonData(), "编码确定性（sortedKeys）")
  }

  // MARK: 监听设置透传

  func testListenSettingsUseTCPAndUDPForSOCKSAndTCPOnlyForHTTP() {
    let listen = ProxyListeningConfiguration()

    XCTAssertEqual(listen.mode, "tcp_and_udp")
    XCTAssertEqual(listen.locals.map(\.mode), ["tcp_and_udp", "tcp_only"])
  }

  func testRuntimeDocumentLeavesTimeoutAndLoggingAtUpstreamDefaults() throws {
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "server-1", server: "example.com", serverPort: 8388,
          password: "pw", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
      ],
      listen: ProxyListeningConfiguration())

    let dictionary = try encodedDictionary(document)
    XCTAssertFalse(dictionary.keys.contains("timeout"))
    XCTAssertFalse(dictionary.keys.contains("verbose"))
  }

  func testACLIdentityStaysInMemoryAndOnlyPathIsEncoded() throws {
    let acl = ProxyACLDocument.direct(
      at: URL(fileURLWithPath: "/tmp/ssxng-tests/acl-active.ini"))
    let document = SslocalRuntimeDocument(
      servers: [], listen: ProxyListeningConfiguration(), acl: acl)
    let dictionary = try encodedDictionary(document)
    XCTAssertEqual(dictionary["acl"] as? String, acl.path)
    XCTAssertNil(dictionary["x_shadowsocksx_ng_acl"])

    let changedPath = document.replacingACL(
      .direct(at: URL(fileURLWithPath: "/tmp/ssxng-tests/other.acl")))
    XCTAssertNotEqual(document.listenFingerprint, changedPath.listenFingerprint)
  }

  func testLocalhostModeDerivesBothSslocalInbounds() {
    let listen = ProxyListeningConfiguration(
      listenerMode: .disabled,
      socksPort: 1086,
      httpPort: 1087)

    XCTAssertEqual(listen.bindAddress, "127.0.0.1")
    XCTAssertEqual(
      listen.locals,
      [
        SslocalLocalDocument(
          inboundProtocol: "socks", localAddress: "127.0.0.1", localPort: 1086,
          mode: "tcp_and_udp"),
        SslocalLocalDocument(
          inboundProtocol: "http", localAddress: "127.0.0.1", localPort: 1087,
          mode: "tcp_only"),
      ])
  }

  func testAllIPv4ModeUsesWildcardBindings() {
    let listen = ProxyListeningConfiguration(
      listenerMode: .allIPv4Interfaces,
      socksPort: 1086,
      httpPort: 1087)

    XCTAssertEqual(listen.bindAddress, "127.0.0.1")
    XCTAssertEqual(Set(listen.locals.map(\.localAddress)), ["127.0.0.1", "0.0.0.0"])
  }

  func testDualStackModeSetsIPv6OnlyFalseAndChangesListenerFingerprint() throws {
    var listen = ProxyListeningConfiguration()
    listen.listenerMode = .allIPv4AndIPv6Interfaces
    let dualStack = SslocalRuntimeDocument(servers: [], listen: listen)
    let dictionary = try encodedDictionary(dualStack)

    XCTAssertEqual(dictionary["ipv6_only"] as? Bool, false)
    XCTAssertEqual(dualStack.socksLocal?.probeHost, "127.0.0.1")

    listen.listenerMode = .allIPv6Interfaces
    let ipv6Only = SslocalRuntimeDocument(servers: [], listen: listen)

    XCTAssertEqual(try encodedDictionary(ipv6Only)["ipv6_only"] as? Bool, true)
    XCTAssertNotEqual(
      dualStack.listenFingerprint, ipv6Only.listenFingerprint,
      "IPv6_ONLY 差异必须使 wrapper 重启 sslocal，即使两者都绑定 ::")
  }

  func testListenerModeBindingsAndProxyLoopbackAddresses() {
    XCTAssertEqual(
      ListenerMode.allCases.map(\.bindingHint),
      [
        "127.0.0.1",
        "0.0.0.0",
        ":: / IPV6_V6ONLY=false",
        ":: / IPV6_V6ONLY=true",
      ])
    for mode in ListenerMode.allCases {
      let document = SslocalRuntimeDocument(
        servers: [], listen: ProxyListeningConfiguration(listenerMode: mode))
      XCTAssertEqual(document.socksLocal?.probeHost, "127.0.0.1")
    }
  }

  func testHTTPInboundIsAlwaysPresentAlongsideSOCKS() {
    let listen = ProxyListeningConfiguration(
      listenerMode: .disabled, socksPort: 2086, httpPort: 2087)

    XCTAssertEqual(listen.locals.map(\.inboundProtocol), ["socks", "http"])
  }
}
