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
    for _ in 0..<20 { await Task.yield() }
    await module.shutdown()
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
  private let lock = NSLock()
  private var received: [String] = []
  private var connections: [NWConnection] = []
  var requests: [String] { lock.withLock { received } }

  init(status: Int?) throws {
    self.status = status
    listener = try NWListener(using: .tcp, on: .any)
  }

  func start() async throws -> Int {
    listener.newConnectionHandler = { [self] connection in
      lock.withLock { connections.append(connection) }
      connection.start(queue: DispatchQueue(label: UUID().uuidString))
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, _, _ in
        if let data { lock.withLock { received.append(String(data: data, encoding: .utf8) ?? "") } }
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

  func stop() {
    listener.cancel()
    listener.newConnectionHandler = nil
    let connections = lock.withLock { self.connections }
    connections.forEach { $0.cancel() }
  }
}
