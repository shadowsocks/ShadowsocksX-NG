import Foundation

/// Persisted identity of a proxy mode. PAC is gone: the product
/// exposes rule / global / direct only.
enum ProxyModeKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case rule
  case global
  case direct
}

/// The mutually exclusive ways in which 2.0 exposes the local proxy to macOS.
/// Hashable 供菜单栏模式选择的勾选态 Picker 使用。
/// 规则模式另持久化 `RuleDefaultAction` 子选项。
enum ProxyMode: Codable, Equatable, Hashable, Sendable {
  case rule
  case global
  case direct

  private enum CodingKeys: String, CodingKey {
    case kind
  }

  private enum Kind: String, Codable {
    case rule
    case global
    case direct
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .rule:
      self = .rule
    case .global:
      self = .global
    case .direct:
      self = .direct
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .rule:
      try container.encode(Kind.rule, forKey: .kind)
    case .global:
      try container.encode(Kind.global, forKey: .kind)
    case .direct:
      try container.encode(Kind.direct, forKey: .kind)
    }
  }

  var label: String {
    switch self {
    case .rule:
      String(localized: "规则")
    case .global:
      String(localized: "全局")
    case .direct:
      String(localized: "直连")
    }
  }

  var kind: ProxyModeKind {
    switch self {
    case .rule: .rule
    case .global: .global
    case .direct: .direct
    }
  }

  /// Returns every mode supported by the product in stable selector order.
  static var availableModes: [ProxyMode] { [.rule, .global, .direct] }

  /// Derives the only system-proxy state that this mode is allowed to own.
  /// All three modes are projected as the local SOCKS and HTTP inbounds
  /// SOCKS 之外，系统 HTTP/HTTPS 代理指向恒开启的 HTTP 入站。
  /// 投影即 closed typed 配置：HTTPS 显式赋值、PAC/自动发现显式
  /// 关闭、简单主机名排除显式开启、例外列表全量给出。
  func systemProxyConfiguration(
    for document: SslocalRuntimeDocument,
    exceptions: [String] = []
  ) throws -> SystemProxyConfiguration {
    guard ProxyPortRange.valid.contains(document.socksPort) else {
      throw ProxyModeError.invalidSOCKSPort(document.socksPort)
    }
    guard ProxyPortRange.valid.contains(document.httpPort) else {
      throw ProxyModeError.invalidHTTPPort(document.httpPort)
    }
    let loopback = "127.0.0.1"
    return SystemProxyConfiguration(
      socks: .init(host: loopback, port: document.socksPort),
      http: .init(host: loopback, port: document.httpPort),
      https: .init(host: loopback, port: document.httpPort),
      excludeSimpleHostnames: true,
      exceptions: FixedLocalProxyRanges.systemProxyExceptions(including: exceptions))
  }
}

enum ProxyModeError: Error, Equatable, Sendable {
  case invalidSOCKSPort(Int)
  case invalidHTTPPort(Int)
}
