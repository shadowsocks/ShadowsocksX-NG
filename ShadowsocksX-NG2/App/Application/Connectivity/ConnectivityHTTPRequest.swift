import Foundation

/// System libcurl exposes complete headers without body sniffing. Each easy
/// handle has isolated connection state and normal system certificate checks.
struct ConnectivityHTTPRequest: Sendable {
  func perform(url: URL, proxyPort: Int) async -> ServerConnectivity.Outcome {
    let cancellation = Cancellation()
    let started = ConnectivityHTTPNow()
    return await withTaskCancellationHandler {
      if Task.isCancelled { return .network }
      return await Task.detached(priority: .utility) {
        let result = url.absoluteString.withCString {
          ConnectivityHTTPMeasure($0, Int32(proxyPort), started, cancellation.pointer)
        }
        if result.timed_out != 0 { return ServerConnectivity.Outcome.requestTimeout }
        guard result.received_headers != 0 else { return .network }
        return (200..<300).contains(result.status)
          ? .success(milliseconds: Int(result.milliseconds)) : .http(Int(result.status))
      }.value
    } onCancel: {
      cancellation.cancel()
    }
  }

  /// Lifetime is shared by the worker and cancellation handler. The C token is
  /// atomic; destruction happens only after both users release this object.
  private final class Cancellation: @unchecked Sendable {
    let pointer = ConnectivityHTTPCreateCancellation()
    func cancel() { ConnectivityHTTPCancel(pointer) }
    deinit { ConnectivityHTTPDestroyCancellation(pointer) }
  }
}
