/// 本地代理端点的端口语义：端口是显式用户配置，
/// 出厂默认与 Legacy 隔离（SOCKS5 11086 / HTTP 11087）；系统任何路径
/// 都不静默改端口——建议端口只产出候选，必须经用户确认保存后才生效；激活
/// 是否成功以 runtime 实际绑定为准（健康门禁），本层的占用校验只是设置编辑
/// 期尽力而为的即时提示。

/// 本地代理端点；显示名与诊断报告的措辞一致。PAC 端点已移除。
enum ProxyEndpointKind: Hashable, Sendable, CaseIterable {
  case socks
  case http
  case lanSocks
  case lanHTTP

  var displayName: String {
    switch self {
    case .socks: "SOCKS5"
    case .http: "HTTP"
    case .lanSocks: "局域网 SOCKS"
    case .lanHTTP: "局域网 HTTP"
    }
  }
}

/// 端口配置校验错误：点名端点与端口（错误信息要求）。
enum PortSettingError: Error, Hashable, Sendable {
  case portOutOfRange(endpoint: ProxyEndpointKind, port: Int)
  /// 两个端点的配置端口相同；`endpoint` 在枚举序（socks → http）中在前。
  case duplicatePort(endpoint: ProxyEndpointKind, otherEndpoint: ProxyEndpointKind, port: Int)
}

/// 建议空闲端口算法：32768–65535 高位段升序扫描，跳过排除集合与不
/// 空闲端口。空闲判定由调用方注入，保证主缝可测。
enum PortSuggestion {
  static let range = 32768...65535

  static func firstFree(excluding excludedPorts: Set<Int>, isFree: (Int) -> Bool) -> Int? {
    for candidate in range where !excludedPorts.contains(candidate) {
      if isFree(candidate) { return candidate }
    }
    return nil
  }
}

extension SslocalListenSettings {
  /// 端点的配置端口。
  func configuredPort(for endpoint: ProxyEndpointKind) -> Int {
    switch endpoint {
    case .socks: socksPort
    case .http: httpPort
    case .lanSocks: lan.socksPort
    case .lanHTTP: lan.httpPort
    }
  }

  /// 端口配置校验：范围 1025–65535、四端点配置值互异。错误按固定次序
  /// （socks/http 范围检查，再 socks-http 冲突）。
  func portValidationErrors() -> [PortSettingError] {
    var errors: [PortSettingError] = []
    for endpoint in ProxyEndpointKind.allCases {
      let port = configuredPort(for: endpoint)
      if !ProxyPortRange.valid.contains(port) {
        errors.append(.portOutOfRange(endpoint: endpoint, port: port))
      }
    }
    for pair in Self.endpointPairs {
      let first = configuredPort(for: pair.0)
      if first == configuredPort(for: pair.1) {
        errors.append(.duplicatePort(endpoint: pair.0, otherEndpoint: pair.1, port: first))
      }
    }
    return errors
  }

  /// 为 `endpoint` 建议一个空闲端口：高位段升序首个空闲且不等于另个端点
  /// 配置值的候选；整段无可用返回 nil。只产出候选，绝不替用户改配置。
  func suggestedPort(for endpoint: ProxyEndpointKind, isFree: (Int) -> Bool) -> Int? {
    let others = Set(ProxyEndpointKind.allCases.filter { $0 != endpoint }.map(configuredPort))
    return PortSuggestion.firstFree(excluding: others, isFree: isFree)
  }

  private static let endpointPairs: [(ProxyEndpointKind, ProxyEndpointKind)] = [
    (.socks, .http), (.socks, .lanSocks), (.socks, .lanHTTP),
    (.http, .lanSocks), (.http, .lanHTTP), (.lanSocks, .lanHTTP),
  ]
}
