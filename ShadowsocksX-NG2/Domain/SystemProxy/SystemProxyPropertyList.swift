import Foundation

/// Pure projection of one SystemConfiguration Proxies dictionary. The key mapping is a
/// mechanical translation of the closed typed configuration : every field the
/// GUI supplies is written, disabled protocols lose their endpoint keys, PAC/auto-
/// discovery/simple-hostname exclusion follow their explicit flags, and the complete
/// exceptions list is always written. Keys outside the typed field set are preserved.
enum SystemProxyPropertyList {
  static let httpEnabled = "HTTPEnable"
  static let httpsEnabled = "HTTPSEnable"
  static let socksEnabled = "SOCKSEnable"
  static let httpPort = "HTTPPort"
  static let httpProxy = "HTTPProxy"
  static let httpsPort = "HTTPSPort"
  static let httpsProxy = "HTTPSProxy"
  static let socksPort = "SOCKSPort"
  static let socksProxy = "SOCKSProxy"
  static let pacEnabled = "ProxyAutoConfigEnable"
  static let pacURL = "ProxyAutoConfigURLString"
  static let pacJavaScript = "ProxyAutoConfigJavaScript"
  static let autoDiscoveryEnabled = "ProxyAutoDiscoveryEnable"
  static let exceptionsList = "ExceptionsList"
  static let excludeSimpleHostnames = "ExcludeSimpleHostnames"

  /// 一个协议族的 Proxies 键组。
  private struct ProtocolKeys {
    let enable: String
    let proxy: String
    let port: String
  }

  static func applying(
    _ configuration: SystemProxyConfiguration, to original: [String: Any]
  ) -> [String: Any] {
    var dictionary = original
    applyProtocol(
      enabled: configuration.socksEnabled, endpoint: configuration.socks,
      keys: ProtocolKeys(enable: socksEnabled, proxy: socksProxy, port: socksPort),
      into: &dictionary)
    applyProtocol(
      enabled: configuration.httpEnabled, endpoint: configuration.http,
      keys: ProtocolKeys(enable: httpEnabled, proxy: httpProxy, port: httpPort),
      into: &dictionary)
    applyProtocol(
      enabled: configuration.httpsEnabled, endpoint: configuration.https,
      keys: ProtocolKeys(enable: httpsEnabled, proxy: httpsProxy, port: httpsPort),
      into: &dictionary)

    dictionary[pacEnabled] = configuration.pacEnabled ? 1 : 0
    if !configuration.pacEnabled {
      // 关闭的 PAC 不留残余：URL 与 JavaScript 值一并移除。
      dictionary.removeValue(forKey: pacJavaScript)
      dictionary.removeValue(forKey: pacURL)
    }
    dictionary[autoDiscoveryEnabled] = configuration.autoDiscoveryEnabled ? 1 : 0
    dictionary[excludeSimpleHostnames] = configuration.excludeSimpleHostnames ? 1 : 0
    dictionary[exceptionsList] = configuration.exceptions
    return dictionary
  }

  /// Normalize only values whose SystemConfiguration meaning is equivalent.
  /// Unknown fields stay verbatim; stale managed endpoint/PAC values still differ.
  static func semanticallyNormalized(_ original: [String: Any]) -> [String: Any] {
    var values = original
    for key in [
      httpEnabled, httpsEnabled, socksEnabled, pacEnabled,
      autoDiscoveryEnabled, excludeSimpleHostnames,
    ] {
      if let number = values[key] as? NSNumber {
        values[key] = number.boolValue ? 1 : 0
      } else if values[key] == nil {
        values[key] = 0
      }
    }
    if let exceptions = values[exceptionsList] as? [String] {
      values[exceptionsList] = Set(exceptions).sorted()
    }
    return values
  }

  /// 启用的协议族写入显式端点；关闭的协议族移除端点键，保持字典与配置一致。
  private static func applyProtocol(
    enabled: Bool, endpoint: SystemProxyConfiguration.Endpoint,
    keys: ProtocolKeys,
    into dictionary: inout [String: Any]
  ) {
    dictionary[keys.enable] = enabled ? 1 : 0
    if enabled {
      dictionary[keys.proxy] = endpoint.host
      dictionary[keys.port] = endpoint.port
    } else {
      dictionary.removeValue(forKey: keys.proxy)
      dictionary.removeValue(forKey: keys.port)
    }
  }
}
