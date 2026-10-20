import Foundation

/// Effective binding policy used by runtime documents and port probes.
/// `disabled` represents the local loopback binding; LAN settings use
/// `LANListenerMode` and an independent enable switch.
enum ListenerMode: String, Codable, CaseIterable, Equatable, Sendable {
  case disabled
  case allIPv4Interfaces = "all_ipv4_interfaces"
  case allIPv4AndIPv6Interfaces = "all_ipv4_and_ipv6_interfaces"
  case allIPv6Interfaces = "all_ipv6_interfaces"

  var bindAddress: String {
    switch self {
    case .disabled: "127.0.0.1"
    case .allIPv4Interfaces: "0.0.0.0"
    case .allIPv4AndIPv6Interfaces, .allIPv6Interfaces: "::"
    }
  }

  /// `nil` omits the upstream option for IPv4 listeners. IPv6 wildcard modes
  /// explicitly select dual-stack or IPv6-only behavior.
  var ipv6Only: Bool? {
    switch self {
    case .disabled, .allIPv4Interfaces: nil
    case .allIPv4AndIPv6Interfaces: false
    case .allIPv6Interfaces: true
    }
  }

  var bindingHint: String {
    switch self {
    case .disabled: "127.0.0.1"
    case .allIPv4Interfaces: "0.0.0.0"
    case .allIPv4AndIPv6Interfaces: ":: / IPV6_V6ONLY=false"
    case .allIPv6Interfaces: ":: / IPV6_V6ONLY=true"
    }
  }

  var displayName: String {
    switch self {
    case .disabled: String(localized: "关闭")
    case .allIPv4Interfaces: String(localized: "所有 IPv4 接口")
    case .allIPv4AndIPv6Interfaces: String(localized: "所有 IPv4 与 IPv6 接口")
    case .allIPv6Interfaces: String(localized: "所有 IPv6 接口")
    }
  }

  var exposesNetworkInterfaces: Bool { self != .disabled }
}

/// `sslocal` 的一个本地入站。上游 v1.26.0 通过 `locals[]` 同时承载 SOCKS5
/// 与 HTTP；HTTP 直接由 shadowsocks-rust 提供，不经过 Legacy Privoxy。
struct SslocalLocalDocument: Codable, Equatable, Sendable {
  let inboundProtocol: String
  let localAddress: String
  let localPort: Int
  let mode: String
  var socks5AuthConfigPath: String?
  var httpAuthConfigPath: String?

  enum CodingKeys: String, CodingKey {
    case mode
    case socks5AuthConfigPath = "socks5_auth_config_path"
    case httpAuthConfigPath = "http_auth_config_path"
    case inboundProtocol = "protocol"
    case localAddress = "local_address"
    case localPort = "local_port"
  }
}

/// GUI 内存中的监听事实；不进入 sslocal 配置或 Agent 监管资料。
struct RuntimeListenDocument: Encodable, Equatable, Sendable {
  let listenerMode: ListenerMode
  let bindAddress: String
  var lan = LANListeningFacts()
  var authentication: RuntimeListenerAuthentication?

  enum CodingKeys: String, CodingKey {
    case lan, authentication
    case listenerMode = "listener_mode"
    case bindAddress = "bind_address"
  }
}

/// GUI 派生的运行意图；上游 JSON 由独立输出表示生成。
/// 密码与插件参数已在此解析为明文；私有意图编码不落盘，永不入日志。
struct SslocalRuntimeDocument: Equatable, Sendable {
  let servers: [SslocalServerDocument]
  var locals: [SslocalLocalDocument]
  let ipv6Only: Bool?
  var listen: RuntimeListenDocument
  /// 两个入站共用的稳定 ACL 路径；变体身份只供 GUI 准备和发布。
  let aclFilePath: String?
  let aclRuntime: ProxyACLDocument?

  init(
    servers: [SslocalServerDocument],
    listen: ProxyListeningConfiguration,
    acl: ProxyACLDocument? = nil
  ) {
    self.servers = servers
    locals = listen.locals
    self.listen = RuntimeListenDocument(
      listenerMode: listen.listenerMode,
      bindAddress: listen.bindAddress, lan: LANListeningFacts(listen.lan))
    ipv6Only = listen.listenerMode.ipv6Only
    aclFilePath = acl?.path
    aclRuntime = acl
  }

  private init(
    servers: [SslocalServerDocument],
    locals: [SslocalLocalDocument],
    listen: RuntimeListenDocument,
    ipv6Only: Bool?,
    acl: ProxyACLDocument?
  ) {
    self.servers = servers
    self.locals = locals
    self.listen = listen
    self.ipv6Only = ipv6Only
    aclFilePath = acl?.path
    aclRuntime = acl
  }

  func jsonData() throws -> Data {
    try Self.jsonEncoder.encode(
      SslocalConfigurationDocument(
        servers: servers, locals: locals, ipv6Only: ipv6Only, aclFilePath: aclFilePath))
  }

  var intentSHA256: String? {
    try? ProxyACLDocument.digest(intentData())
  }

  /// 私有意图编码只用于等价比较；不落盘，也不作为 sslocal 的输入。
  fileprivate func intentData() throws -> Data {
    struct Intent: Encodable {
      let servers: [SslocalServerDocument]
      let locals: [SslocalLocalDocument]
      let ipv6Only: Bool?
      let listen: RuntimeListenDocument
      let acl: ProxyACLDocument?
    }
    return try Self.jsonEncoder.encode(
      Intent(servers: servers, locals: locals, ipv6Only: ipv6Only, listen: listen, acl: aclRuntime))
  }

  func replacingACL(_ acl: ProxyACLDocument?) -> SslocalRuntimeDocument {
    SslocalRuntimeDocument(
      servers: servers,
      locals: locals,
      listen: listen,
      ipv6Only: ipv6Only,
      acl: acl)
  }

  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()
}

/// sslocal 的输出格式；GUI 运行意图中的监听事实和 ACL 身份不进入此文档。
struct SslocalConfigurationDocument: Codable, Equatable, Sendable {
  let servers: [SslocalServerDocument]
  var locals: [SslocalLocalDocument]
  let ipv6Only: Bool?
  let aclFilePath: String?

  enum CodingKeys: String, CodingKey {
    case servers, locals
    case ipv6Only = "ipv6_only"
    case aclFilePath = "acl"
  }
}

/// 上游 `servers[]` 条目。id 携带叶子身份，供上游稳定标识；显示名是目录
/// 元数据，不进契约（GLOSSARY.md「Runtime configuration file」）。
/// 插件字段在无插件时整体省略。
struct SslocalServerDocument: Codable, Equatable, Sendable {
  let id: String
  let server: String
  let serverPort: Int
  let password: String
  let method: String
  let plugin: String?
  let pluginOpts: String?
  var pluginArgs: [String]?
  var pluginMode: PluginTransportMode?

  enum CodingKeys: String, CodingKey {
    case id, server
    case serverPort = "server_port"
    case password, method, plugin
    case pluginOpts = "plugin_opts"
    case pluginArgs = "plugin_args"
    case pluginMode = "plugin_mode"
  }
}

extension SslocalLocalDocument {
  /// 探测用主机名：通配绑定地址按回环探测（wrapper 监听判定与 GUI 健康门
  /// 共用口径）。
  var probeHost: String {
    switch localAddress {
    case "0.0.0.0": "127.0.0.1"
    case "::": "::1"
    default: localAddress
    }
  }
}

extension SslocalRuntimeDocument {
  var listenFingerprint: SslocalListenFingerprint {
    SslocalListenFingerprint(
      locals: locals, ipv6Only: ipv6Only, acl: aclRuntime,
      authentication: listen.authentication)
  }

  var socksLocal: SslocalLocalDocument? {
    locals.first { $0.inboundProtocol == "socks" }
  }

  var socksAddress: String { socksLocal?.localAddress ?? "" }
  var socksPort: Int { socksLocal?.localPort ?? 0 }
  var socksMode: String { socksLocal?.mode ?? "" }

  /// HTTP 入站端口；缺 HTTP 入站时为 0。完整入站组由 `isWellFormed` 在
  /// 跨进程契约缝拒绝，端口合法性由 settings store 保证。
  var httpPort: Int {
    locals.first { $0.inboundProtocol == "http" }?.localPort ?? 0
  }

  /// GUI 准备侧校验：端口、协议与共享范围必须一致。空 `servers` 合法：
  /// 无活动目标时 agent 以空服务器列表提供本地监听；上游 sslocal v1.26.0
  /// 接受空 servers 并照常绑定本地入站。
  var isWellFormed: Bool {
    guard
      (aclFilePath == nil) == (aclRuntime == nil),
      aclRuntime.map({ $0.isWellFormed && $0.path == aclFilePath }) ?? true
    else { return false }

    guard listen.bindAddress == "127.0.0.1", listen.listenerMode == listen.lan.effectiveMode,
      ipv6Only == listen.lan.effectiveMode.ipv6Only
    else { return false }
    let local = locals.filter { $0.localAddress == "127.0.0.1" }
    let network = locals.filter { $0.localAddress != "127.0.0.1" }
    guard local.count == 2, local.filter({ $0.inboundProtocol == "socks" }).count == 1,
      local.filter({ $0.inboundProtocol == "http" }).count == 1,
      local.allSatisfy({
        $0.mode == ($0.inboundProtocol == "socks" ? "tcp_and_udp" : "tcp_only")
          && $0.socks5AuthConfigPath == nil && $0.httpAuthConfigPath == nil
      })
    else { return false }
    var expected = ProxyListeningConfiguration()
    expected.local.socksPort = socksPort
    expected.local.httpPort = httpPort
    expected.lan = listen.lan.configuration
    guard network.count == (listen.lan.isEnabled ? 2 : 0),
      expected.configuredPorts.allSatisfy({ ProxyPortRange.valid.contains($0) }),
      Set(expected.configuredPorts).count == 4
    else { return false }
    for (actual, desired) in zip(locals, expected.locals) {
      guard actual.inboundProtocol == desired.inboundProtocol,
        actual.localAddress == desired.localAddress, actual.localPort == desired.localPort,
        actual.mode == desired.mode
      else { return false }
    }
    if listen.lan.isEnabled && listen.lan.authenticationEnabled {
      guard let auth = listen.authentication, auth.isValid, auth.username == listen.lan.username,
        network.first(where: { $0.inboundProtocol == "socks" })?.socks5AuthConfigPath
          == auth.socksPath,
        network.first(where: { $0.inboundProtocol == "http" })?.httpAuthConfigPath == auth.httpPath
      else { return false }
    } else if listen.authentication != nil
      || network.contains(where: {
        $0.socks5AuthConfigPath != nil || $0.httpAuthConfigPath != nil
      })
    {
      return false
    }

    return servers.allSatisfy { server in
      (1...65535).contains(server.serverPort)
        && !server.id.isEmpty
        && !server.server.isEmpty
        && !server.method.isEmpty
    }
  }
}

/// GUI 准备的运行意图与私有摘要；Agent 回执使用独立随机部署身份。
struct PreparedRuntimeContract: Sendable {
  let document: SslocalRuntimeDocument
  let sha256: String

  init(_ document: SslocalRuntimeDocument) throws {
    self.document = document
    sha256 = try ProxyACLDocument.digest(document.intentData())
  }
}

extension Redactor {
  /// 运行时文档只允许暴露数量与模式元数据。
  static func documentSummary(_ document: SslocalRuntimeDocument) -> String {
    let protocols = document.locals.map(\.inboundProtocol).joined(separator: ",")
    return "servers=\(document.servers.count) protocols=\(protocols) mode=\(document.socksMode)"
  }
}

/// 控制器在准备完成后仅保留健康检查与界面所需事实，不缓存完整秘密文档。
struct RuntimeDeploymentFacts: Equatable, Sendable {
  let locals: [SslocalLocalDocument]
  let listen: RuntimeListenFacts
  let hasServers: Bool
  let aclSummary: String?
  let intentSHA256: String?
  let configurationIntentSHA256: String?

  init(_ document: SslocalRuntimeDocument) {
    locals = document.locals.map {
      SslocalLocalDocument(
        inboundProtocol: $0.inboundProtocol, localAddress: $0.localAddress,
        localPort: $0.localPort, mode: $0.mode)
    }
    listen = RuntimeListenFacts(document: document)
    hasServers = !document.servers.isEmpty
    aclSummary = document.aclRuntime?.summary
    intentSHA256 = document.intentSHA256
    configurationIntentSHA256 = document.replacingACL(nil).intentSHA256
  }
}
