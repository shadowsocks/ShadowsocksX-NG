import Foundation

/// The allowed range for local proxy listener ports.
enum ProxyPortRange {
  static let valid = 1025...65_535
}

/// 本机入口始终开启，端口是独立保存的配置。
struct LocalListeningSettings: Codable, Equatable, Sendable {
  var socksPort = 11086
  var httpPort = 11087
}

/// 网络共享入口与本机入口共存，凭据只携带 Keychain 引用。
struct LANListeningSettings: Codable, Equatable, Sendable {
  var isEnabled = false
  var mode: LANListenerMode = .allIPv4Interfaces
  var socksPort = 11088
  var httpPort = 11089
  var udpRelayEnabled = false
  var authenticationEnabled = false
  var username = "user"
  var passwordReference: String?

  var effectiveMode: ListenerMode { isEnabled ? mode.bindingMode : .disabled }
}

/// 局域网地址族配置；关闭时仍保留所选方式。
enum LANListenerMode: String, Codable, CaseIterable, Equatable, Sendable {
  case allIPv4Interfaces = "all_ipv4_interfaces"
  case allIPv4AndIPv6Interfaces = "all_ipv4_and_ipv6_interfaces"
  case allIPv6Interfaces = "all_ipv6_interfaces"

  var bindingMode: ListenerMode {
    switch self {
    case .allIPv4Interfaces: .allIPv4Interfaces
    case .allIPv4AndIPv6Interfaces: .allIPv4AndIPv6Interfaces
    case .allIPv6Interfaces: .allIPv6Interfaces
    }
  }

  var bindAddress: String { bindingMode.bindAddress }
  var bindingHint: String { bindingMode.bindingHint }
  var displayName: String { bindingMode.displayName }
}

struct SslocalListenSettings: Equatable, Sendable {
  static let defaultSocksPort = 11086
  static let defaultHTTPPort = 11087

  var local = LocalListeningSettings()
  var lan = LANListeningSettings()

  init(
    listenerMode: ListenerMode = .disabled,
    socksPort: Int = Self.defaultSocksPort, httpPort: Int = Self.defaultHTTPPort
  ) {
    local = LocalListeningSettings(socksPort: socksPort, httpPort: httpPort)
    self.listenerMode = listenerMode
  }

  var listenerMode: ListenerMode {
    get { lan.effectiveMode }
    set {
      lan.isEnabled = newValue != .disabled
      if let mode = LANListenerMode(rawValue: newValue.rawValue) { lan.mode = mode }
    }
  }
  var socksPort: Int {
    get { local.socksPort }
    set { local.socksPort = newValue }
  }
  var httpPort: Int {
    get { local.httpPort }
    set { local.httpPort = newValue }
  }
  var bindAddress: String { "127.0.0.1" }
  var mode: String { "tcp_and_udp" }
  var configuredPorts: [Int] { [socksPort, httpPort, lan.socksPort, lan.httpPort] }

  var locals: [SslocalLocalDocument] {
    var result = [
      SslocalLocalDocument(
        inboundProtocol: "socks", localAddress: bindAddress,
        localPort: socksPort, mode: mode),
      SslocalLocalDocument(
        inboundProtocol: "http", localAddress: bindAddress,
        localPort: httpPort, mode: "tcp_only"),
    ]
    if lan.isEnabled {
      result += [
        SslocalLocalDocument(
          inboundProtocol: "socks", localAddress: lan.mode.bindAddress,
          localPort: lan.socksPort, mode: lan.udpRelayEnabled ? "tcp_and_udp" : "tcp_only"),
        SslocalLocalDocument(
          inboundProtocol: "http", localAddress: lan.mode.bindAddress,
          localPort: lan.httpPort, mode: "tcp_only"),
      ]
    }
    return result
  }
}

/// Typed effective listener facts exposed by the runtime boundary. This is the
/// complete identity of the listeners that are actually intended to be bound.
struct RuntimeListenFacts: Equatable, Sendable {
  let listenerMode: ListenerMode
  let socksPort: Int
  let httpPort: Int
  var lan = LANListeningSettings()

  init(listen: SslocalListenSettings) {
    self.init(
      listenerMode: .disabled,
      socksPort: listen.socksPort,
      httpPort: listen.httpPort)
    lan = listen.lan
  }

  init(
    listenerMode: ListenerMode,
    socksPort: Int,
    httpPort: Int
  ) {
    self.listenerMode = listenerMode
    self.socksPort = socksPort
    self.httpPort = httpPort
  }

  init(document: SslocalRuntimeDocument) {
    let socks = document.locals.first { $0.inboundProtocol == "socks" }
    let http = document.locals.first { $0.inboundProtocol == "http" }
    self.init(
      listenerMode: .disabled,
      socksPort: socks?.localPort ?? 0,
      httpPort: http?.localPort ?? SslocalListenSettings.defaultHTTPPort)
    lan = document.listen.lan
  }

  var bindAddress: String { listenerMode.bindAddress }
}

/// 监听指纹：服务器列表变化可热重载；任一本地入站、
/// ACL 内容/路径/摘要变化都必须由 wrapper 完整重启 sslocal。
struct SslocalListenFingerprint: Equatable, Sendable {
  let locals: [SslocalLocalDocument]
  let ipv6Only: Bool?
  let acl: ProxyACLDocument?
  var authentication: RuntimeListenerAuthentication?
}
