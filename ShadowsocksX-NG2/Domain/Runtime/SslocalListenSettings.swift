import Foundation

/// The allowed range for local proxy listener ports.
enum ProxyPortRange {
  static let valid = 1000...65_535
}

/// 本地端点与单一监听方式的派生设置。HTTP 入站恒开启，与 SOCKS 共用同一
/// 监听方式；默认端口与 Legacy 隔离（11086/11087）。
struct SslocalListenSettings: Equatable, Sendable {
  static let defaultSocksPort = 11086
  static let defaultHTTPPort = 11087

  var listenerMode: ListenerMode = .localhost
  var socksPort: Int = Self.defaultSocksPort
  var httpPort: Int = Self.defaultHTTPPort

  var bindAddress: String { listenerMode.bindAddress }
  var mode: String { "tcp_and_udp" }

  var locals: [SslocalLocalDocument] {
    [
      SslocalLocalDocument(
        inboundProtocol: "socks",
        localAddress: bindAddress,
        localPort: socksPort,
        mode: mode),
      SslocalLocalDocument(
        inboundProtocol: "http",
        localAddress: bindAddress,
        localPort: httpPort,
        mode: "tcp_only"),
    ]
  }
}

/// Typed effective listener facts exposed by the runtime boundary. This is the
/// complete identity of the listeners that are actually intended to be bound.
struct RuntimeListenFacts: Equatable, Sendable {
  let listenerMode: ListenerMode
  let socksPort: Int
  let httpPort: Int

  init(listen: SslocalListenSettings) {
    self.init(
      listenerMode: listen.listenerMode,
      socksPort: listen.socksPort,
      httpPort: listen.httpPort)
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
      listenerMode: document.listen.listenerMode,
      socksPort: socks?.localPort ?? 0,
      httpPort: http?.localPort ?? SslocalListenSettings.defaultHTTPPort)
  }

  var bindAddress: String { listenerMode.bindAddress }
}

/// 监听指纹：服务器列表变化可热重载；任一本地入站、
/// ACL 内容/路径/摘要变化都必须由 wrapper 完整重启 sslocal。
struct SslocalListenFingerprint: Equatable, Sendable {
  let locals: [SslocalLocalDocument]
  let ipv6Only: Bool?
  let acl: ProxyACLDocument?
}
