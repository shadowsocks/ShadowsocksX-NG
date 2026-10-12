import Foundation

/// Address-family policy for the optional LAN SOCKS and HTTP inbounds.
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

/// `sslocal` 的一个本地入站。上游 v1.25.0 通过 `locals[]` 同时承载 SOCKS5
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

/// wrapper 自有的监听身份扩展（取代已删除的 PAC 扩展）。字段收在
/// `x_shadowsocksx_ng_listen` 下，上游 sslocal 会忽略该扩展；wrapper 与 GUI
/// 仍从同一原子文件读取同一份事实。
struct RuntimeListenDocument: Codable, Equatable, Sendable {
  let listenerMode: ListenerMode
  let bindAddress: String
  var lan = LANListeningSettings()
  var authentication: RuntimeListenerAuthentication?

  enum CodingKeys: String, CodingKey {
    case lan, authentication
    case listenerMode = "listener_mode"
    case bindAddress = "bind_address"
  }
}

/// sslocal 运行时文档：激活派生出的完整 JSON 契约文档。
/// 密码与插件参数已在此解析为明文——只供运行时落盘，永不入日志。
struct SslocalRuntimeDocument: Codable, Equatable, Sendable {
  let servers: [SslocalServerDocument]
  var locals: [SslocalLocalDocument]
  let ipv6Only: Bool?
  var listen: RuntimeListenDocument
  /// Upstream sslocal ACL file path. The wrapper-owned extension carries the
  /// matching content and digest so both inbounds use the same validated file.
  let aclFilePath: String?
  let aclRuntime: ProxyACLDocument?

  enum CodingKeys: String, CodingKey {
    case servers, locals
    case ipv6Only = "ipv6_only"
    case aclFilePath = "acl"
    case aclRuntime = "x_shadowsocksx_ng_acl"
    case listen = "x_shadowsocksx_ng_listen"
  }

  init(
    servers: [SslocalServerDocument],
    listen: SslocalListenSettings,
    acl: ProxyACLDocument? = nil
  ) {
    self.servers = servers
    locals = listen.locals
    self.listen = RuntimeListenDocument(
      listenerMode: listen.listenerMode,
      bindAddress: listen.bindAddress, lan: listen.lan)
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    servers = try container.decode([SslocalServerDocument].self, forKey: .servers)
    locals = try container.decode([SslocalLocalDocument].self, forKey: .locals)
    ipv6Only = try container.decodeIfPresent(Bool.self, forKey: .ipv6Only)
    listen = try container.decode(RuntimeListenDocument.self, forKey: .listen)
    aclFilePath = try container.decodeIfPresent(String.self, forKey: .aclFilePath)
    aclRuntime = try container.decodeIfPresent(ProxyACLDocument.self, forKey: .aclRuntime)
  }

  func jsonData() throws -> Data {
    try Self.jsonEncoder.encode(self)
  }

  var deploymentSHA256: String? {
    guard let data = try? jsonData() else { return nil }
    return ProxyACLDocument.digest(data)
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
  static func decodeValidated(_ data: Data) -> SslocalRuntimeDocument? {
    guard
      let document = try? JSONDecoder().decode(SslocalRuntimeDocument.self, from: data),
      document.isWellFormed
    else { return nil }
    return document
  }

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

  /// HTTP 入站端口；缺 HTTP 入站时为 0（无效端口，系统代理投影层拒绝）。
  var httpPort: Int {
    locals.first { $0.inboundProtocol == "http" }?.localPort ?? 0
  }

  /// wrapper 读取侧防御校验：端口、协议与共享范围必须一致；无效文件会停止并
  /// 清理，不能交给 KeepAlive 无限重放。空 `servers` 合法：
  /// 无活动目标时 agent 以空服务器列表提供本地监听；上游 sslocal v1.25.0
  /// 接受空 servers 并照常绑定本地入站。
  var isWellFormed: Bool {
    guard
      (aclFilePath == nil) == (aclRuntime == nil),
      aclRuntime.map({ $0.isWellFormed && $0.path == aclFilePath }) ?? true
    else { return false }

    guard listen.bindAddress == "127.0.0.1", listen.listenerMode == listen.lan.mode,
      ipv6Only == listen.lan.mode.ipv6Only
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
    var expected = SslocalListenSettings()
    expected.local.socksPort = socksPort
    expected.local.httpPort = httpPort
    expected.lan = listen.lan
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

/// A single deployment's encoded contract and receipt identity. Keep this value
/// local to preparation/deployment so on-disk state is still checked each time.
struct PreparedRuntimeContract: Sendable {
  let document: SslocalRuntimeDocument
  let data: Data
  let sha256: String

  init(_ document: SslocalRuntimeDocument) throws {
    self.document = document
    data = try document.jsonData()
    sha256 = ProxyACLDocument.digest(data)
  }
}
