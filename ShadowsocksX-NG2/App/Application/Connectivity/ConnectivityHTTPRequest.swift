import Darwin
import Foundation

struct ConnectivityHTTPObservation: Sendable {
  var outcome: ServerConnectivity.Outcome = .network
  var totalMilliseconds: Double = 0
  var localTCPMilliseconds: Double?
  var sendMilliseconds: Double?
  var firstByteMilliseconds: Double?
  var headersMilliseconds: Double?
  var failureStage = "request"
}

/// One fresh loopback socket per request. Only client-observable phases are
/// exposed; proxy-side DNS, transport handshakes and remote TCP remain combined.
struct ConnectivityHTTPRequest: Sendable {
  func perform(url: URL, proxyPort: Int) async -> ServerConnectivity.Outcome {
    await observe(url: url, targetIP: nil, proxyPort: proxyPort, timeout: 5).outcome
  }

  func observe(
    url: URL, targetIP: String?, proxyPort: Int, timeout: Double
  ) async -> ConnectivityHTTPObservation {
    guard let request = Self.request(url: url, targetIP: targetIP) else {
      return ConnectivityHTTPObservation(outcome: .configuration)
    }
    let cancellation = Cancellation()
    return await withTaskCancellationHandler {
      if Task.isCancelled { return ConnectivityHTTPObservation() }
      return await Task.detached(priority: .utility) {
        let result = request.withCString {
          ConnectivityHTTPProbe(
            $0, Int32(clamping: proxyPort), Int32(max(0, min(timeout * 1000, 5000))),
            cancellation.pointer)
        }
        let outcome: ServerConnectivity.Outcome
        if result.timed_out != 0 {
          outcome = .requestTimeout
        } else if result.received_headers == 0 {
          outcome = .network
        } else if (200..<300).contains(result.status) {
          outcome = .success(milliseconds: Int(result.milliseconds.rounded()))
        } else {
          outcome = .http(Int(result.status))
        }
        let stages = ["request", "local_tcp", "send", "first_byte", "headers", "complete"]
        return ConnectivityHTTPObservation(
          outcome: outcome, totalMilliseconds: result.milliseconds,
          localTCPMilliseconds: result.local_tcp_ms >= 0 ? result.local_tcp_ms : nil,
          sendMilliseconds: result.send_ms >= 0 ? result.send_ms : nil,
          firstByteMilliseconds: result.first_byte_ms >= 0 ? result.first_byte_ms : nil,
          headersMilliseconds: result.headers_ms >= 0 ? result.headers_ms : nil,
          failureStage: stages[min(max(Int(result.stage), 0), 5)])
      }.value
    } onCancel: {
      cancellation.cancel()
    }
  }

  private static func request(url: URL, targetIP: String?) -> String? {
    guard ServerConnectivity.validURL(url.absoluteString) != nil,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let host = components.host, components.user == nil, components.password == nil
    else { return nil }
    let originalHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    let authority = originalHost + (components.port.map { ":\($0)" } ?? "")
    if let targetIP {
      guard ConnectivityAddress.family(targetIP) != nil else { return nil }
      components.host = targetIP.contains(":") ? "[\(targetIP)]" : targetIP
    }
    if components.percentEncodedPath.isEmpty { components.percentEncodedPath = "/" }
    guard let target = components.string,
      !target.contains("\r"), !target.contains("\n"), !authority.contains("\r"),
      !authority.contains("\n")
    else { return nil }
    return "GET \(target) HTTP/1.1\r\nHost: \(authority)\r\nConnection: close\r\n\r\n"
  }

  private final class Cancellation: @unchecked Sendable {
    let pointer = ConnectivityHTTPCreateCancellation()
    func cancel() { ConnectivityHTTPCancel(pointer) }
    deinit { ConnectivityHTTPDestroyCancellation(pointer) }
  }
}

/// Accept only address literals returned in matching DNS record types. No
/// hostnames, scoped interfaces or URL syntax can enter a pinned request.
enum ConnectivityAddress {
  static func family(_ value: String) -> Int32? {
    var ipv4 = in_addr()
    if inet_pton(AF_INET, value, &ipv4) == 1 { return AF_INET }
    var ipv6 = in6_addr()
    if inet_pton(AF_INET6, value, &ipv6) == 1 { return AF_INET6 }
    return nil
  }
}
