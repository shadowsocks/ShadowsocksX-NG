import Foundation
import Synchronization
import Testing
import XCTest

@testable import ShadowsocksX_NG2

@Suite(.timeLimit(.minutes(1)))
struct ConnectivityDoHTests {
  @Test func fallsBackToCloudflare() async {
    let resolver = ConnectivityDoHResolver(
      sessionConfiguration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FallbackAnswersProtocol.self]
        return configuration
      },
      waitForDeadline: { _ in
        let pending = AsyncStream<Void> { (_: AsyncStream<Void>.Continuation) in }
        for await _ in pending {}
      })
    let result = await resolver.resolve(
      host: "target.invalid", proxyPort: 1234, deadline: .now.advanced(by: .seconds(60)))
    #expect(result.addresses == ["192.0.2.1", "2001:db8::1"])
    #expect(result.trace.map(\.phase) == [.google, .cloudflare])
    #expect(result.trace.map(\.status) == [.network, .success])
    #expect(!result.trace.map(\.description).joined().contains("target.invalid"))
  }

  @Test func acceptsOnlyMatchingIPRecords() throws {
    let data = Data(
      (#"{"Status":0,"Answer":[{"type":5,"data":"alias.invalid"},"#
        + #"{"type":1,"data":"192.0.2.1"},{"type":1,"data":"2001:db8::bad"},"#
        + #"{"type":1,"data":"bad.invalid"},{"type":28,"data":"2001:db8::1"},"#
        + #"{"type":28,"data":"192.0.2.4"}]}"#).utf8)
    #expect(try ConnectivityDoHResolver.addresses(from: data, type: 1) == ["192.0.2.1"])
    #expect(try ConnectivityDoHResolver.addresses(from: data, type: 28) == ["2001:db8::1"])
  }

  @Test func familyThatExceedsDeadlineDoesNotDiscardOtherFamily() async {
    let events = AsyncStream<[String]?> { continuation in
      continuation.yield(["192.0.2.1"])
      continuation.yield(nil)
      continuation.yield(["2001:db8::1"])
      continuation.finish()
    }
    let addresses = await ConnectivityDoHResolver.collectAddresses(from: events)
    #expect(addresses == ["192.0.2.1"])
  }

  @Test func completedFamiliesDoNotWaitForDeadline() async {
    let events = AsyncStream<[String]?> { continuation in
      continuation.yield(["192.0.2.1"])
      continuation.yield(["2001:db8::1"])
    }
    let addresses = await ConnectivityDoHResolver.collectAddresses(from: events)
    #expect(addresses == ["192.0.2.1", "2001:db8::1"])
  }

  @MainActor
  @Test func pendingFamiliesAreCancelledAtDeadline() async throws {
    let host = UUID().uuidString.lowercased() + ".invalid"
    let started = XCTestExpectation(description: "Both address families started")
    let stopped = XCTestExpectation(description: "Both address families cancelled")
    started.expectedFulfillmentCount = 2
    stopped.expectedFulfillmentCount = 2
    PendingAnswersProtocol.observers.withLock {
      $0[host] = { loading in
        if loading { started.fulfill() } else { stopped.fulfill() }
      }
    }
    defer { PendingAnswersProtocol.observers.withLock { $0[host] = nil } }
    let deadline = AsyncStream<Void>.makeStream()
    let resolver = ConnectivityDoHResolver(
      sessionConfiguration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingAnswersProtocol.self]
        return configuration
      },
      waitForDeadline: { _ in
        for await _ in deadline.stream {}
      })
    let task = Task {
      do {
        _ = try await resolver.query(
          host: host, endpoint: "https://\(host)/resolve", proxyPort: 1234,
          deadline: .now)
        Issue.record("Pending requests unexpectedly resolved")
      } catch {
        #expect(error is ConnectivityDoHResolver.Failure)
      }
    }
    try await withTestTask(
      task, release: { deadline.continuation.finish() },
      body: {
        try await requireTestPhase([started])
        deadline.continuation.finish()
        try await requireTestPhase([stopped])
      })
  }
}

private final class FallbackAnswersProtocol: URLProtocol, @unchecked Sendable {
  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { return }
    let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "type" })?.value
    let failed = url.host == "dns.google"
    let answer =
      type == "1"
      ? #"{"Status":0,"Answer":[{"type":1,"data":"192.0.2.1"}]}"#
      : #"{"Status":0,"Answer":[{"type":28,"data":"2001:db8::1"}]}"#
    let response = HTTPURLResponse(
      url: url, statusCode: failed ? 503 : 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/dns-json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(answer.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class PendingAnswersProtocol: URLProtocol, @unchecked Sendable {
  static let observers = Mutex<[String: @Sendable (Bool) -> Void]>([:])

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { observe(loading: true) }
  override func stopLoading() { observe(loading: false) }

  private func observe(loading: Bool) {
    guard let host = request.url?.host else { return }
    let observer = Self.observers.withLock { $0[host] }
    observer?(loading)
  }
}
