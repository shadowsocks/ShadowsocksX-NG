import XCTest

@testable import ShadowsocksX_NG2

/// helper XPC 契约测试：typed payload 往返、引擎应答编码与
/// 串行 last-writer 语义，全部用确定性替身，不触真实 XPC 与 SystemConfiguration。
final class SystemProxyHelperContractTests: XCTestCase {
  private let configuration = SystemProxyConfiguration(
    socks: .init(host: "127.0.0.1", port: 1086),
    http: .init(host: "127.0.0.1", port: 1087),
    https: .init(host: "127.0.0.1", port: 1087),
    exceptions: ["localhost"])

  /// 并发闭包与断言之间的线程安全值交接。
  private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []

    func append(_ item: Element) {
      lock.lock()
      items.append(item)
      lock.unlock()
    }

    var all: [Element] {
      lock.lock()
      defer { lock.unlock() }
      return items
    }
  }

  func testConfigurationPayloadRoundTripsThroughJSON() throws {
    let payload = try SystemProxyHelperWire.encodeConfiguration(configuration)
    let decoded = try SystemProxyHelperWire.decodeConfiguration(payload)
    XCTAssertEqual(decoded, configuration)
  }

  func testEngineAnswersApplyWithTypedOutcome() throws {
    let requested = try SystemProxyHelperWire.encodeConfiguration(configuration)
    let observed = LockedArray<SystemProxyHelperEngine.Request>()
    let response = SystemProxyHelperEngine.response(
      request: .success(.apply(configuration)),
      perform: { request in
        observed.append(request)
        return .applied(.written)
      })

    XCTAssertEqual(observed.all, [.apply(configuration)], "helper 收到 closed typed 配置")
    XCTAssertEqual(response, .applied(.written))
    XCTAssertEqual(
      try SystemProxyHelperWire.decodeConfiguration(requested), configuration,
      "payload 与配置一致")
  }

  func testEngineAnswersClearWithTypedOutcome() {
    let response = SystemProxyHelperEngine.response(
      request: .success(.clear), perform: { _ in .cleared })
    XCTAssertEqual(response, .cleared)
  }

  func testEngineEncodesTypedFailuresAndInvalidPayloads() throws {
    let failure = SystemProxyHelperEngine.response(
      request: .failure(SystemProxyError.commitFailed("busy")),
      perform: { _ in .cleared })
    XCTAssertEqual(failure, .failure(.commitFailed("busy")))

    let genericFailure = SystemProxyHelperEngine.response(
      request: .failure(ProxySettingsStoreError.corrupt(detail: "bad")),
      perform: { _ in .cleared })
    XCTAssertEqual(
      genericFailure, .failure(.helperUnavailable("corrupt(detail: \"bad\")")),
      "非 SystemProxyError 归并为 helperUnavailable")

    XCTAssertThrowsError(
      try SystemProxyHelperWire.decodeConfiguration(Data("not json".utf8))
    ) { error in
      guard case SystemProxyError.invalidRequest = error else {
        return XCTFail("无效 payload 应为 invalidRequest，实际 \(error)")
      }
    }
  }

  /// 串行 last-writer：注入的假写入器在共享串行队列上按
  /// 接受顺序执行，最后接受的请求决定最终结果。
  func testEngineProcessesRequestsSeriallyWithLastWriterWins() async throws {
    let recorder = LockedArray<String>()
    let queue = DispatchQueue(label: "test.system-proxy-helper.serial")
    let engine = SystemProxyHelperEngine(
      perform: { request in
        switch request {
        case .apply(let applied):
          recorder.append("apply:\(applied.socks.port)")
        case .clear:
          recorder.append("clear")
        }
        return .applied(.written)
      },
      queue: queue)

    let first = try SystemProxyHelperWire.encodeConfiguration(configuration)
    let second = try SystemProxyHelperWire.encodeConfiguration(
      SystemProxyConfiguration(
        socks: .init(host: "127.0.0.1", port: 2086),
        http: .init(host: "127.0.0.1", port: 2087),
        https: .init(host: "127.0.0.1", port: 2087),
        exceptions: ["localhost"]))

    let replies = LockedArray<Data>()
    let replyExpectation = expectation(description: "replies")
    replyExpectation.expectedFulfillmentCount = 3
    engine.apply(first) {
      replies.append($0)
      replyExpectation.fulfill()
    }
    engine.clear {
      replies.append($0)
      replyExpectation.fulfill()
    }
    engine.apply(second) {
      replies.append($0)
      replyExpectation.fulfill()
    }
    await fulfillment(of: [replyExpectation], timeout: 5)

    XCTAssertEqual(recorder.all, ["apply:1086", "clear", "apply:2086"], "逐个串行执行")
    XCTAssertEqual(replies.all.count, 3)
    for reply in replies.all {
      XCTAssertEqual(
        try SystemProxyHelperWire.decode(reply), .applied(.written), "每个请求都有 typed 应答")
    }
  }
}
