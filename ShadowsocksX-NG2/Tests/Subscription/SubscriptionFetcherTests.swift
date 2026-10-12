import XCTest

@testable import ShadowsocksX_NG2

/// 订阅获取缝（验收「HTTP 缝夹具」的传输侧）：HTTPS 门禁先于任何
/// 网络行为、状态码与 Content-Type 契约、传输失败点名、错误文案脱敏。
final class SubscriptionFetcherTests: XCTestCase {
  private let fetcher = HTTPSSubscriptionFetcher()

  // MARK: URL 门禁（发起连接之前）

  func testNonHTTPSRejectedBeforeAnyNetwork() async {
    // 端口 1 无监听：若实现先连网会得到 transport 错误；断言精确错误即证明
    // 门禁在连接之前。
    let url = URL(string: "http://127.0.0.1:1/sub.json")!

    do {
      _ = try await fetcher.fetch(url)
      XCTFail("HTTP 地址必须被拒绝")
    } catch let error as SubscriptionFetchError {
      XCTAssertEqual(error, .unsupportedScheme)
    } catch {
      XCTFail("应报 unsupportedScheme，实际 \(error)")
    }
  }

  func testFTPRejected() async {
    let url = URL(string: "ftp://127.0.0.1/sub.json")!
    do {
      _ = try await fetcher.fetch(url)
      XCTFail("非 HTTPS 必须被拒绝")
    } catch let error as SubscriptionFetchError {
      XCTAssertEqual(error, .unsupportedScheme)
    } catch {
      XCTFail("应报 unsupportedScheme，实际 \(error)")
    }
  }

  func testURLWithoutHostRejected() async {
    let url = URL(string: "https:///path")!
    do {
      _ = try await fetcher.fetch(url)
      XCTFail("无主机地址必须被拒绝")
    } catch let error as SubscriptionFetchError {
      XCTAssertEqual(error, .invalidURL)
    } catch {
      XCTFail("应报 invalidURL，实际 \(error)")
    }
  }

  // MARK: 传输失败（连接被拒；TLS 校验走系统默认、从不忽略）

  func testTransportErrorOnUnreachableHost() async throws {
    let port = try ProxyRuntimeFixture.unusedLoopbackPort()
    let url = URL(string: "https://127.0.0.1:\(port)/sub.json")!

    do {
      _ = try await fetcher.fetch(url)
      XCTFail("无监听端口必须报传输失败")
    } catch let error as SubscriptionFetchError {
      guard case .transport = error else {
        return XCTFail("应报 transport，实际 \(error)")
      }
    } catch {
      XCTFail("应报 transport，实际 \(error)")
    }
  }

  // MARK: 响应契约（纯函数）

  func testValidateAcceptsExactContentType() {
    XCTAssertNoThrow(
      try HTTPSSubscriptionFetcher.validate(
        statusCode: 200, contentType: "application/json; charset=utf-8"))
  }

  func testValidateIsCaseAndWhitespaceInsensitive() {
    XCTAssertNoThrow(
      try HTTPSSubscriptionFetcher.validate(
        statusCode: 200, contentType: "Application/JSON ;  charset=UTF-8"))
  }

  func testValidateRejectsContractViolations() {
    struct Case {
      let status: Int
      let type: String?
      let expected: SubscriptionFetchError
    }
    let cases: [Case] = [
      Case(status: 404, type: "application/json; charset=utf-8", expected: .httpStatus(code: 404)),
      Case(status: 500, type: "application/json; charset=utf-8", expected: .httpStatus(code: 500)),
      Case(status: 301, type: "application/json; charset=utf-8", expected: .httpStatus(code: 301)),
      Case(status: 200, type: nil, expected: .contentType(received: nil)),
      Case(
        status: 200, type: "text/plain; charset=utf-8",
        expected: .contentType(received: "text/plain; charset=utf-8")),
      Case(
        status: 200, type: "application/json",
        expected: .contentType(received: "application/json")),
      Case(
        status: 200, type: "application/json; charset=latin1",
        expected: .contentType(received: "application/json; charset=latin1")),
      Case(
        status: 200, type: "application/json; charset=utf-8; boundary=x",
        expected: .contentType(received: "application/json; charset=utf-8; boundary=x")),
    ]
    for violation in cases {
      XCTAssertThrowsError(
        try HTTPSSubscriptionFetcher.validate(
          statusCode: violation.status, contentType: violation.type),
        String(describing: violation.expected)
      ) { error in
        XCTAssertEqual(error as? SubscriptionFetchError, violation.expected)
      }
    }
  }

  // MARK: 重定向策略（纯函数）与脱敏

  func testRedirectPolicyOnlyAllowsHTTPS() {
    XCTAssertTrue(HTTPSSubscriptionFetcher.allowsRedirect(to: "https"))
    XCTAssertTrue(HTTPSSubscriptionFetcher.allowsRedirect(to: "HTTPS"))
    XCTAssertFalse(HTTPSSubscriptionFetcher.allowsRedirect(to: "http"))
    XCTAssertFalse(HTTPSSubscriptionFetcher.allowsRedirect(to: nil))
  }

  func testTransportDetailNeverCarriesURL() {
    let error = URLError(.cannotFindHost)
    let detail = HTTPSSubscriptionFetcher.redactedTransportDetail(error)

    XCTAssertFalse(detail.contains("sub.json"), "传输错误细节不得携带 URL：\(detail)")
    XCTAssertFalse(detail.contains("example.com"), "传输错误细节不得携带主机：\(detail)")
    XCTAssertTrue(detail.contains("URLError"), "点名错误类型：\(detail)")
  }
}

/// 获取缝夹具：按 URL 返回预设结果并记录请求（VM 语义测试用）。
final class FakeSubscriptionFetcher: SubscriptionFetching, @unchecked Sendable {
  enum Behavior {
    case success(Data)
    case failure(SubscriptionFetchError)
  }

  private let lock = NSLock()
  private var behavior: Behavior
  private var requests: [URL] = []

  init(behavior: Behavior) {
    self.behavior = behavior
  }

  /// 中途切换预设结果（工作流不再暴露可替换的获取器属性）。
  func setBehavior(_ behavior: Behavior) {
    lock.lock()
    defer { lock.unlock() }
    self.behavior = behavior
  }

  var lastURL: URL? {
    lock.lock()
    defer { lock.unlock() }
    return requests.last
  }

  var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requests.count
  }

  func fetch(_ url: URL) async throws -> Data {
    let behavior = lock.withLock {
      requests.append(url)
      return self.behavior
    }
    switch behavior {
    case .success(let data):
      return data
    case .failure(let error):
      throw error
    }
  }
}
