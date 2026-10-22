import Foundation
import Network
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityHTTPTests {
  @Test(arguments: [204, 200, 302, 500])
  func sendsGETThroughProxyAndStopsAtHeaders(status: Int) async throws {
    let proxy = try HeaderProxy(status: status)
    defer { proxy.stop() }
    let port = try await proxy.start()
    let started = ContinuousClock.now
    // This name cannot resolve; a successful response proves proxy routing.
    let id = NodeID.fresh()
    let module = ServerConnectivity(
      configuration: { _ in Self.server },
      measure: { _, url, _ in
        await ConnectivityHTTPRequest().perform(url: url, proxyPort: port)
      })
    module.setURL(URL(string: "http://target.invalid/test")!)
    await module.wait(for: module.test([id]))
    let value = try #require(module.history(for: id).first?.outcome)
    if (200..<300).contains(status) {
      guard case .success = value else {
        Issue.record("Expected successful proxy response, got \(value)")
        return
      }
    } else {
      #expect(value == .http(status))
    }
    #expect(ContinuousClock.now - started < .seconds(2))
    #expect(proxy.requests.count == 1)
    #expect(proxy.requests.first?.hasPrefix("GET http://target.invalid/test HTTP/") == true)
  }

  @Test func fixedAddressPreservesHostAndReportsClientPhases() async throws {
    let proxy = try HeaderProxy(status: 204)
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid:8080/test?q=private%20value")!,
      targetIP: "2001:db8::1", proxyPort: port, timeout: 1)
    guard case .success = result.outcome else {
      Issue.record("Expected successful fixed-address request")
      return
    }
    let request = try #require(proxy.requests.first)
    #expect(request.hasPrefix("GET http://[2001:db8::1]:8080/test?q=private%20value HTTP/1.1\r\n"))
    #expect(request.contains("\r\nHost: target.invalid:8080\r\n"))
    #expect(result.localTCPMilliseconds != nil)
    #expect(result.sendMilliseconds != nil)
    #expect(result.firstByteMilliseconds != nil)
    #expect(result.headersMilliseconds != nil)
    #expect(result.totalMilliseconds >= 0)
  }

  @Test func informationalAndFragmentedHeadersDoNotWaitForBody() async throws {
    let proxy = try HeaderProxy(
      status: nil,
      parts: [
        "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Len",
        "gth: 999999\r\n\r\n",
      ])
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid/test")!, targetIP: "192.0.2.1", proxyPort: port,
      timeout: 1)
    guard case .success = result.outcome else {
      Issue.record("Expected complete final headers")
      return
    }
    #expect(result.firstByteMilliseconds != nil)
    #expect(result.headersMilliseconds != nil)
    #expect(result.totalMilliseconds < 1000)
  }

  @Test(arguments: [
    "HTTP/2 200 OK\r\n\r\n",
    "HTTP/1.1 200 OK\r\nInvalid Header\r\n\r\n",
    "HTTP/1.1 200 OK\r\nX-Large: " + String(repeating: "x", count: 65536),
    String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 3000),
  ])
  func rejectsMalformedOrUnboundedHeaders(response: String) async throws {
    let proxy = try HeaderProxy(status: nil, parts: [response])
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid/test")!, targetIP: "192.0.2.1", proxyPort: port,
      timeout: 1)
    #expect(result.outcome == .network)
    #expect(result.failureStage == "headers")
  }

  @Test func cumulativeHeadersIncludeFinalBlockAfterInformationalResponses() async throws {
    let proxy = try HeaderProxy(
      status: nil,
      parts: [
        String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 2500),
        "HTTP/1.1 204 No Content\r\nX-Large: " + String(repeating: "x", count: 5000) + "\r\n\r\n",
      ])
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid/test")!, targetIP: "192.0.2.1", proxyPort: port,
      timeout: 1)
    #expect(result.outcome == .network)
  }

  @Test func httpsIsRejectedBeforeOpeningProxyConnection() async throws {
    let proxy = try HeaderProxy(status: 204)
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().perform(
      url: URL(string: "https://target.invalid/test")!, proxyPort: port)
    #expect(result == .configuration)
    #expect(proxy.requests.isEmpty)
  }

  @Test func requestHasOneFiveSecondDeadline() async throws {
    let proxy = try HeaderProxy(status: nil)
    defer { proxy.stop() }
    let port = try await proxy.start()
    let id = NodeID.fresh()
    let module = ServerConnectivity(
      configuration: { _ in Self.server },
      measure: { _, url, _ in
        await ConnectivityHTTPRequest().perform(url: url, proxyPort: port)
      })
    module.setURL(URL(string: "http://target.invalid/slow")!)
    let started = ContinuousClock.now
    await module.wait(for: module.test([id]))
    #expect(module.history(for: id).first?.outcome == .requestTimeout)
    #expect(ContinuousClock.now - started >= .seconds(5))
    #expect(ContinuousClock.now - started < .seconds(6))
    #expect(proxy.requests.count == 1)
  }

  @Test func cancellationEndsRequestWithoutWaitingForHeaders() async throws {
    let proxy = try HeaderProxy(status: nil)
    defer { proxy.stop() }
    let port = try await proxy.start()
    let id = NodeID.fresh()
    let module = ServerConnectivity(
      configuration: { _ in Self.server },
      measure: { _, url, _ in
        await ConnectivityHTTPRequest().perform(url: url, proxyPort: port)
      })
    module.setURL(URL(string: "http://target.invalid/test")!)
    let batch = module.test([id])
    let pendingDeadline = ContinuousClock.now.advanced(by: .seconds(2))
    while proxy.requests.isEmpty, ContinuousClock.now < pendingDeadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(proxy.requests.count == 1)
    let cancelledAt = ContinuousClock.now
    await module.shutdown()
    #expect(ContinuousClock.now - cancelledAt < .seconds(1))
    await module.wait(for: batch)
    #expect(module.history(for: id).isEmpty)
    #expect(module.isCooling(id))
  }
  private static var server: SslocalServerDocument {
    SslocalServerDocument(
      id: "test", server: "example.com", serverPort: 443,
      password: "test", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
  }
}

/// Controlled HTTP proxy: headers arrive, but the declared body never does.
private final class HeaderProxy: @unchecked Sendable {
  private let listener: NWListener
  private let status: Int?
  private let parts: [String]?
  private let lock = NSLock()
  private var received: [String] = []
  private var connections: [NWConnection] = []
  var requests: [String] { lock.withLock { received } }

  init(status: Int?, parts: [String]? = nil) throws {
    self.status = status
    self.parts = parts
    listener = try NWListener(using: .tcp, on: .any)
  }

  func start() async throws -> Int {
    listener.newConnectionHandler = { [self] connection in
      lock.withLock { connections.append(connection) }
      connection.start(queue: DispatchQueue(label: UUID().uuidString))
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, _, _ in
        if let data { lock.withLock { received.append(String(data: data, encoding: .utf8) ?? "") } }
        if let parts {
          send(parts, through: connection)
          return
        }
        guard let status else { return }
        let headers =
          "HTTP/1.1 \(status) Response\r\nLocation: http://another.invalid/redirect\r\nContent-Length: 99999\r\n\r\n"
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { _ in })
      }
    }
    return try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { [self] state in
        switch state {
        case .ready:
          listener.stateUpdateHandler = nil
          continuation.resume(returning: Int(listener.port!.rawValue))
        case .failed(let error):
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: error)
        default: break
        }
      }
      listener.start(queue: DispatchQueue(label: UUID().uuidString))
    }
  }

  private func send(_ parts: [String], through connection: NWConnection) {
    guard let first = parts.first else { return }
    connection.send(
      content: Data(first.utf8),
      completion: .contentProcessed { [self] _ in
        if parts.count > 1 {
          DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [self] in
            send(Array(parts.dropFirst()), through: connection)
          }
        }
      })
  }

  func stop() {
    listener.cancel()
    listener.newConnectionHandler = nil
    let connections = lock.withLock { self.connections }
    for connection in connections {
      connection.cancel()
    }
  }
}
