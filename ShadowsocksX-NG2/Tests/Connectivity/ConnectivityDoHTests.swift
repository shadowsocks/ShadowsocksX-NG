import Foundation
import Testing

@testable import ShadowsocksX_NG2

@Suite(.timeLimit(.minutes(1)))
struct ConnectivityDoHTests {
  @Test func fallsBackToCloudflareAndAcceptsOnlyMatchingIPRecords() async {
    let resolver = ConnectivityDoHResolver(sessionConfiguration: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [DNSAnswersProtocol.self]
      return configuration
    })
    let result = await resolver.resolve(
      host: "target.invalid", proxyPort: 1234, deadline: .now.advanced(by: .seconds(1)))
    #expect(result.addresses == ["192.0.2.1", "2001:db8::1"])
    #expect(result.trace.map(\.phase) == [.google, .cloudflare])
    #expect(result.trace.map(\.status) == [.network, .success])
    #expect(!result.trace.map(\.description).joined().contains("target.invalid"))
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

  @Test func pendingFamiliesAreCancelledAtDeadline() async throws {
    let resolver = ConnectivityDoHResolver(sessionConfiguration: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [PendingAnswersProtocol.self]
      return configuration
    })
    let started = ContinuousClock.now
    do {
      _ = try await resolver.query(
        host: "target.invalid", endpoint: "https://resolver.invalid/resolve", proxyPort: 1234,
        deadline: .now.advanced(by: .milliseconds(100)))
      Issue.record("Pending requests unexpectedly resolved")
    } catch {
      #expect(error is ConnectivityDoHResolver.Failure)
    }
    #expect(ContinuousClock.now - started >= .milliseconds(100))
    #expect(ContinuousClock.now - started < .seconds(1))
  }
}

private class DNSAnswersProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { return }
    let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "type" })?.value
    let failed = url.host == "dns.google"
    let answer =
      type == "1"
      ? #"{"Status":0,"Answer":[{"type":5,"data":"alias.invalid"},"#
        + #"{"type":1,"data":"192.0.2.1"},{"type":1,"data":"2001:db8::bad"},"#
        + #"{"type":1,"data":"bad.invalid"}]}"#
      : #"{"Status":0,"Answer":[{"type":28,"data":"2001:db8::1"},{"type":1,"data":"192.0.2.4"}]}"#
    let response = HTTPURLResponse(
      url: url, statusCode: failed ? 503 : 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/dns-json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(answer.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class PendingAnswersProtocol: DNSAnswersProtocol, @unchecked Sendable {
  override func startLoading() {}
}
