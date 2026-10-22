import Foundation

/// GUI 准备、特权 helper 机械执行的 closed typed 系统代理配置。
/// 完整闭合：SOCKS/HTTP/HTTPS 的启停与端点、PAC、自动发现、简单主机名排除
/// 与完整例外列表全部显式给出；helper 不补默认值、不从 HTTP 推断 HTTPS、
/// 不把缺省解释为「保留旧值」。Codable 使其可跨 XPC 以 payload 传输。
/// 成员逐一内联默认值：GUI 策略恒为三协议族全开、PAC/自动发现关闭、
/// 简单主机名排除开启——合成 memberwise init 自带这些默认参数。
struct SystemProxyConfiguration: Codable, Equatable, Sendable {
  /// 一个系统代理协议族指向的本地端点。
  struct Endpoint: Codable, Equatable, Sendable {
    let host: String
    let port: Int
  }

  var socksEnabled = true
  var socks: Endpoint
  var httpEnabled = true
  var http: Endpoint
  /// HTTPS 系统代理由 GUI 显式赋值（当前实现与 HTTP 入站共用端点），
  /// helper 只翻译不推断。
  var httpsEnabled = true
  var https: Endpoint
  var pacEnabled = false
  var autoDiscoveryEnabled = false
  var excludeSimpleHostnames = true
  /// 完整例外列表：每次 apply 全量覆盖，空列表也是显式值。
  var exceptions: [String]
}
