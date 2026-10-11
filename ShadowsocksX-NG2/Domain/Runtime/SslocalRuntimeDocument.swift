import Foundation

/// One of the supported address-family policies for both local proxy inbounds.
enum ListenerMode: String, Codable, CaseIterable, Equatable, Sendable {
  case localhost
  case allIPv4Interfaces = "all_ipv4_interfaces"
  case allIPv4AndIPv6Interfaces = "all_ipv4_and_ipv6_interfaces"
  case allIPv6Interfaces = "all_ipv6_interfaces"

  var bindAddress: String {
    switch self {
    case .localhost: "127.0.0.1"
    case .allIPv4Interfaces: "0.0.0.0"
    case .allIPv4AndIPv6Interfaces, .allIPv6Interfaces: "::"
    }
  }

  /// `nil` omits the upstream option for IPv4 listeners. IPv6 wildcard modes
  /// explicitly select dual-stack or IPv6-only behavior.
  var ipv6Only: Bool? {
    switch self {
    case .localhost, .allIPv4Interfaces: nil
    case .allIPv4AndIPv6Interfaces: false
    case .allIPv6Interfaces: true
    }
  }

  /// 此监听方式可接受的回环地址（默认地址在前）：IPv4/仅本机只接受
  /// 127.0.0.1，双栈通配绑定同时接受两个回环族，仅 IPv6 只接受 ::1。
  var compatibleLoopbackAddresses: [String] {
    switch self {
    case .localhost, .allIPv4Interfaces: ["127.0.0.1"]
    case .allIPv4AndIPv6Interfaces: ["127.0.0.1", "::1"]
    case .allIPv6Interfaces: ["::1"]
    }
  }

  /// 健康探测、系统代理与 HTTP 导出行使用的默认兼容回环地址。
  var proxyLoopbackAddress: String {
    compatibleLoopbackAddresses[0]
  }

  var bindingHint: String {
    switch self {
    case .localhost: "127.0.0.1"
    case .allIPv4Interfaces: "0.0.0.0"
    case .allIPv4AndIPv6Interfaces: ":: / IPV6_V6ONLY=false"
    case .allIPv6Interfaces: ":: / IPV6_V6ONLY=true"
    }
  }

  var displayName: String {
    switch self {
    case .localhost: "仅本机"
    case .allIPv4Interfaces: "所有 IPv4 接口"
    case .allIPv4AndIPv6Interfaces: "所有 IPv4 与 IPv6 接口"
    case .allIPv6Interfaces: "仅所有 IPv6 接口"
    }
  }

  var exposesNetworkInterfaces: Bool { self != .localhost }
}

/// `sslocal` 的一个本地入站。上游 v1.25.0 通过 `locals[]` 同时承载 SOCKS5
/// 与 HTTP；HTTP 直接由 shadowsocks-rust 提供，不经过 Legacy Privoxy。
struct SslocalLocalDocument: Codable, Equatable, Sendable {
  let inboundProtocol: String
  let localAddress: String
  let localPort: Int
  let mode: String

  enum CodingKeys: String, CodingKey {
    case mode
    case inboundProtocol = "protocol"
    case localAddress = "local_address"
    case localPort = "local_port"
  }
}

/// wrapper 自有的监听身份扩展（issue #67 取代已删除的 PAC 扩展）。字段收在
/// `x_shadowsocksx_ng_listen` 下，上游 sslocal 会忽略该扩展；wrapper 与 GUI
/// 仍从同一原子文件读取同一份事实。
struct RuntimeListenDocument: Codable, Equatable, Sendable {
  let listenerMode: ListenerMode
  let bindAddress: String

  enum CodingKeys: String, CodingKey {
    case listenerMode = "listener_mode"
    case bindAddress = "bind_address"
  }
}

/// sslocal 运行时文档（spec #21 D5/D7）：激活派生出的完整 JSON 契约文档。
/// 密码与插件参数已在此解析为明文——只供运行时落盘，永不入日志。
struct SslocalRuntimeDocument: Codable, Equatable, Sendable {
  let servers: [SslocalServerDocument]
  let locals: [SslocalLocalDocument]
  let ipv6Only: Bool?
  let listen: RuntimeListenDocument
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
      bindAddress: listen.bindAddress)
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
/// 插件字段在无插件时整体省略（D10）。
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
  /// 共用口径，issue #38）。
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
    SslocalListenFingerprint(locals: locals, ipv6Only: ipv6Only, acl: aclRuntime)
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

  /// wrapper 读取侧防御校验：端口、协议与共享范围必须一致；无效文件按 D5
  /// 停止并清理，不能交给 KeepAlive 无限重放。空 `servers` 合法（issue #60）：
  /// 无活动目标时 agent 以空服务器列表提供本地监听；上游 sslocal v1.25.0
  /// 接受空 servers 并照常绑定本地入站。
  var isWellFormed: Bool {
    guard
      (aclFilePath == nil) == (aclRuntime == nil),
      aclRuntime.map({ $0.isWellFormed && $0.path == aclFilePath }) ?? true
    else { return false }

    let expectedBind = listen.listenerMode.bindAddress
    guard listen.bindAddress == expectedBind, ipv6Only == listen.listenerMode.ipv6Only else {
      return false
    }

    let socks = locals.filter { $0.inboundProtocol == "socks" }
    let http = locals.filter { $0.inboundProtocol == "http" }
    guard socks.count == 1, http.count <= 1, locals.count == socks.count + http.count else {
      return false
    }
    guard socks[0].mode == "tcp_and_udp" else { return false }
    guard http.allSatisfy({ $0.mode == "tcp_only" }) else { return false }

    let localPorts = locals.map(\.localPort)
    guard Set(localPorts).count == localPorts.count else { return false }
    guard
      locals.allSatisfy({ local in
        let expectedMode = local.inboundProtocol == "socks" ? "tcp_and_udp" : "tcp_only"
        return local.localAddress == expectedBind
          && ProxyPortRange.valid.contains(local.localPort)
          && local.mode == expectedMode
      })
    else { return false }

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
