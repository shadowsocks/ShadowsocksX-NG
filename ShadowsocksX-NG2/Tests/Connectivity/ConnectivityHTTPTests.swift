import Foundation
import Network
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityHTTPTests {
  @Test(arguments: [(204, false), (200, false), (302, false), (500, false), (200, true)])
  func sendsGETThroughProxyAndStopsAtHeaders(status: Int, informational: Bool) async throws {
    let headers =
      "HTTP/1.1 \(status) Response\r\nLocation: http://another.invalid/redirect\r\nContent-Length: 99999\r\n\r\n"
    let proxy = try HeaderProxy(
      response: (informational ? "HTTP/1.1 100 Continue\r\n\r\n" : "") + headers)
    defer { proxy.stop() }
    let port = try await proxy.start()
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
    #expect(proxy.requests.count == 1)
    #expect(proxy.requests.first?.hasPrefix("GET http://target.invalid/test HTTP/") == true)
  }

  @Test func informationalAndFragmentedHeadersDoNotWaitForBody() async throws {
    // Leave the socket readable while the reader supplies exact response chunks.
    let proxy = try HeaderProxy(response: "ready")
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await Task.detached {
      var chunks = [
        "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Len",
        "gth: 999999\r\n\r\n",
      ].map { Array($0.utf8) }
      let cancellation = ConnectivityHTTPCreateCancellation()
      defer { ConnectivityHTTPDestroyCancellation(cancellation) }
      return withUnsafeMutablePointer(to: &chunks) { context in
        "GET http://target.invalid/test HTTP/1.1\r\nHost: target.invalid\r\n\r\n".withCString {
          ConnectivityHTTPProbeWithReader(
            $0, Int32(port), 5000, cancellation,
            { buffer, capacity, context in
              let chunks = context!.assumingMemoryBound(to: [[UInt8]].self)
              guard !chunks.pointee.isEmpty else { return 0 }
              let chunk = chunks.pointee.removeFirst()
              precondition(chunk.count <= capacity)
              chunk.withUnsafeBytes {
                buffer!.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
              }
              return chunk.count
            }, context)
        }
      }
    }.value
    #expect(result.received_headers == 1)
    #expect(result.status == 200)
    #expect(result.timed_out == 0)
  }

  @Test func fixedAddressPreservesHostAndReportsClientPhases() async throws {
    let proxy = try HeaderProxy(
      response: "HTTP/1.1 204 No Content\r\nContent-Length: 99999\r\n\r\n")
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid:8080/test?q=private%20value")!,
      targetIP: "2001:db8::1", proxyPort: port, timeout: 5)
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

  @Test(arguments: [
    "HTTP/2 200 OK\r\n\r\n",
    "HTTP/1.1 200 OK\r\nInvalid Header\r\n\r\n",
    "HTTP/1.1 200 OK\r\nX-Large: " + String(repeating: "x", count: 65536),
    String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 3000),
    // Each block fits; only the cumulative budget including final headers is exceeded.
    "HTTP/1.1 100 Continue\r\nX-Large: " + String(repeating: "x", count: 60000) + "\r\n\r\n"
      + "HTTP/1.1 204 No Content\r\nX-Large: " + String(repeating: "x", count: 6000) + "\r\n\r\n",
  ])
  func rejectsMalformedOrUnboundedHeaders(response: String) async throws {
    let proxy = try HeaderProxy(response: response)
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid/test")!, targetIP: "192.0.2.1", proxyPort: port,
      timeout: 5)
    #expect(result.outcome == .network)
    #expect(result.failureStage == "headers")
  }

  @Test func httpsIsRejectedBeforeOpeningProxyConnection() async throws {
    let proxy = try HeaderProxy(
      response: "HTTP/1.1 204 No Content\r\nContent-Length: 99999\r\n\r\n")
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().perform(
      url: URL(string: "https://target.invalid/test")!, proxyPort: port)
    #expect(result == .configuration)
    #expect(proxy.requests.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func timesOutWhileWaitingForFirstByte() async throws {
    let proxy = try HeaderProxy()
    defer { proxy.stop() }
    let port = try await proxy.start()
    let result = await ConnectivityHTTPRequest().observe(
      url: URL(string: "http://target.invalid/slow")!, targetIP: nil, proxyPort: port,
      timeout: 0.5)
    #expect(result.outcome == .requestTimeout)
    #expect(result.failureStage == "first_byte")
    #expect(result.totalMilliseconds >= 500)
    #expect(proxy.requests.count == 1)
  }

  @Test func cancellationEndsRequestWithoutWaitingForHeaders() async throws {
    let proxy = try HeaderProxy()
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
  private let response: String?
  private let lock = NSLock()
  private var received: [String] = []
  private var connections: [NWConnection] = []
  var requests: [String] { lock.withLock { received } }

  init(response: String? = nil) throws {
    self.response = response
    listener = try NWListener(using: .tcp, on: .any)
  }

  func start() async throws -> Int {
    listener.newConnectionHandler = { [self] connection in
      lock.withLock { connections.append(connection) }
      connection.start(queue: DispatchQueue(label: UUID().uuidString))
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, _, _ in
        if let data { lock.withLock { received.append(String(data: data, encoding: .utf8) ?? "") } }
        if let response {
          connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
        }
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

  func stop() {
    listener.cancel()
    listener.newConnectionHandler = nil
    let connections = lock.withLock { self.connections }
    for connection in connections {
      connection.cancel()
    }
  }
}
