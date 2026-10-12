import Foundation

/// 订阅获取缝：HTTPS 强制、TLS/证书校验不放松、Content-Type
/// 与状态码按 SIP-008 契约检查。测试注入夹具，生产走 URLSession 实现。
protocol SubscriptionFetching: Sendable {
  func fetch(_ url: URL) async throws -> Data
}

/// 获取失败点名原因。任何细节都不携带订阅 URL（完整 URL 与 token 永不
/// 进入错误文案、日志与诊断）。
enum SubscriptionFetchError: Error, Equatable, Sendable {
  /// URL 无法构造或没有主机。
  case invalidURL
  /// 非 HTTPS 地址；宽松模式不受支持。
  case unsupportedScheme
  /// 重定向目标不是 HTTPS（降级一律拒绝）。
  case insecureRedirect
  /// 连接/TLS 握手失败等传输层错误（默认证书校验失败也在此呈现）。
  case transport(detail: String)
  /// HTTP 状态码非 200。
  case httpStatus(code: Int)
  /// Content-Type 不是 `application/json; charset=utf-8`（大小写与空白不敏感）。
  case contentType(received: String?)
}

/// URLSession 实现：重定向守卫只放行 https→https；TLS 校验用系统默认行为
/// （从不实现证书忽略）。响应契约校验抽为纯函数便于夹具测试。
struct HTTPSSubscriptionFetcher: SubscriptionFetching {
  /// 单次请求超时（秒）。
  var timeoutInterval: TimeInterval = 15

  private static let requiredContentType = "application/json;charset=utf-8"

  func fetch(_ url: URL) async throws -> Data {
    guard url.scheme?.lowercased() == "https" else {
      throw SubscriptionFetchError.unsupportedScheme
    }
    guard url.host != nil else { throw SubscriptionFetchError.invalidURL }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeoutInterval
    // 守卫是任务级 delegate：只拦截非 HTTPS 降级重定向，不触碰 TLS 校验链路。
    let redirectGuard = RedirectGuard()
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await Self.session.data(for: request, delegate: redirectGuard)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw SubscriptionFetchError.transport(detail: Self.redactedTransportDetail(error))
    }
    if redirectGuard.didBlockInsecureRedirect {
      throw SubscriptionFetchError.insecureRedirect
    }
    guard let http = response as? HTTPURLResponse else {
      throw SubscriptionFetchError.transport(detail: "nonHTTPResponse")
    }
    try Self.validate(
      statusCode: http.statusCode,
      contentType: http.value(forHTTPHeaderField: "Content-Type"))
    return data
  }

  /// 响应契约（纯函数）：200 + `application/json; charset=utf-8`。
  static func validate(statusCode: Int, contentType: String?) throws {
    guard statusCode == 200 else { throw SubscriptionFetchError.httpStatus(code: statusCode) }
    let normalized = (contentType ?? "").lowercased().filter { !$0.isWhitespace }
    guard normalized == requiredContentType else {
      throw SubscriptionFetchError.contentType(received: contentType)
    }
  }

  /// 重定向放行策略（纯函数）：仅 https → https。
  static func allowsRedirect(to scheme: String?) -> Bool {
    scheme?.lowercased() == "https"
  }

  /// 传输错误脱敏描述：URLError 只取错误码符号名；其余只取类型名。两者都
  /// 不携带 URL 或主机。
  static func redactedTransportDetail(_ error: Error) -> String {
    if let urlError = error as? URLError {
      return "URLError.\(String(describing: urlError.code))"
    }
    return String(describing: type(of: error))
  }

  /// 共享会话（无会话级 delegate）。
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    return URLSession(configuration: configuration)
  }()
}

/// 重定向守卫：跟随 https→https；降级到非 HTTPS 时拒绝并标记，请求随后以
/// 3xx 原样响应或取消收场，由调用方按标记点名 `insecureRedirect`。
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var blocked = false

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard HTTPSSubscriptionFetcher.allowsRedirect(to: request.url?.scheme) else {
      lock.lock()
      blocked = true
      lock.unlock()
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }

  var didBlockInsecureRedirect: Bool {
    lock.lock()
    defer { lock.unlock() }
    return blocked
  }
}
