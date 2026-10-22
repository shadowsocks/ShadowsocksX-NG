import Darwin
import Foundation
import Network

/// HTTPS is confined to preparation. An ephemeral, proxy-required session has
/// no shared connection/cache state, redirects, cookies or direct fallback.
private struct ConnectivityDoHAnswer: Decodable {
  let type: Int
  let data: String
}

private struct ConnectivityDoHResponse: Decodable {
  let status: Int
  let answers: [ConnectivityDoHAnswer]?

  enum CodingKeys: String, CodingKey {
    case status = "Status"
    case answers = "Answer"
  }
}

struct ConnectivityDoHResolver: Sendable {
  var sessionConfiguration: @Sendable () -> URLSessionConfiguration = { .ephemeral }

  struct Resolution: Sendable {
    var addresses: [String] = []
    var trace: [ConnectivityTrace] = []
  }
  enum Failure: Error { case invalidResponse, deadline }

  func resolve(host: String, proxyPort: Int, deadline: ContinuousClock.Instant) async -> Resolution
  {
    var resolution = Resolution()
    let providers: [(ConnectivityTrace.Phase, String)] = [
      (.google, "https://dns.google/resolve"),
      (.cloudflare, "https://cloudflare-dns.com/dns-query"),
    ]
    for (phase, endpoint) in providers {
      if Task.isCancelled || ContinuousClock.now >= deadline { break }
      let started = ContinuousClock.now
      let providerDeadline = min(deadline, started.advanced(by: .seconds(3)))
      do {
        resolution.addresses = try await query(
          host: host, endpoint: endpoint, proxyPort: proxyPort, deadline: providerDeadline)
        resolution.trace.append(
          ConnectivityTrace(
            phase: phase, status: .success, milliseconds: elapsed(since: started)))
        return resolution
      } catch {
        let status: ConnectivityTrace.Status =
          Task.isCancelled
          ? .cancelled : ContinuousClock.now >= providerDeadline ? .timeout : .network
        resolution.trace.append(
          ConnectivityTrace(
            phase: phase, status: status, milliseconds: elapsed(since: started), failureStage: .dns)
        )
      }
    }
    return resolution
  }

  /// Both address families share the provider deadline. A failed family does
  /// not discard usable answers from the other family.
  func query(
    host: String, endpoint: String, proxyPort: Int, deadline: ContinuousClock.Instant
  ) async throws -> [String] {
    guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: proxyPort) ?? 0), proxyPort > 0
    else {
      throw Failure.invalidResponse
    }
    let configuration = sessionConfiguration()
    var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .ipv4(.loopback), port: port))
    proxy.allowFailover = false
    proxy.excludedDomains = []
    configuration.proxyConfigurations = [proxy]
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 3
    configuration.timeoutIntervalForResource = 3
    let session = URLSession(
      configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let addresses = await withTaskGroup(of: [String]?.self) { group in
      for type in [1, 28] {
        group.addTask {
          await answers(host: host, endpoint: endpoint, type: type, session: session)
        }
      }
      group.addTask {
        try? await ContinuousClock().sleep(until: deadline)
        return nil
      }
      defer { group.cancelAll() }
      return await Self.collectAddresses(from: group)
    }
    guard !addresses.isEmpty else { throw Failure.invalidResponse }
    // Stable family order makes equal-time candidate ties reproducible.
    return addresses.filter { ConnectivityAddress.family($0) == AF_INET }
      + addresses.filter { ConnectivityAddress.family($0) == AF_INET6 }
  }

  /// A nil event is the shared deadline; keep families received before it.
  static func collectAddresses<Results: AsyncSequence>(from results: Results) async rethrows
    -> [String] where Results.Element == [String]?
  {
    var found: [String] = []
    var families = 0
    for try await family in results {
      guard let family else { break }
      found += family
      families += 1
      if families == 2 { break }
    }
    return found
  }

  private func answers(host: String, endpoint: String, type: Int, session: URLSession) async
    -> [String]
  {
    guard var url = URLComponents(string: endpoint), url.scheme == "https" else { return [] }
    url.queryItems = [
      URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: "\(type)"),
    ]
    guard let url = url.url else { return [] }
    var request = URLRequest(url: url)
    request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    do {
      let (bytes, response) = try await session.bytes(for: request)
      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        return []
      }
      var data = Data()
      for try await byte in bytes {
        guard data.count < 65536 else { return [] }
        data.append(byte)
      }
      let answer = try JSONDecoder().decode(ConnectivityDoHResponse.self, from: data)
      guard answer.status == 0 else { return [] }
      return (answer.answers ?? []).filter {
        $0.type == type && ConnectivityAddress.family($0.data) == (type == 1 ? AF_INET : AF_INET6)
      }.map(\.data)
    } catch {
      return []
    }
  }

  private func elapsed(since started: ContinuousClock.Instant) -> Double {
    let parts = started.duration(to: .now).components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
  }

  private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(nil)
    }
  }
}
