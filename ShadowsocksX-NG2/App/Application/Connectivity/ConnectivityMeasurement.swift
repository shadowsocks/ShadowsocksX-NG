import Darwin
import Foundation

/// Preparation and sampling stay behind one measurement interface. Dependencies
/// at the HTTP and DNS seams admit deterministic fixtures without real egress.
@MainActor
struct ConnectivityMeasurement {
  struct Result {
    var outcome: ServerConnectivity.Outcome = .network
    var selectedIP: String?
    var samples: [ConnectivityHTTPObservation] = []
    var trace: [ConnectivityTrace] = []
  }

  var resolve: ((String, Int, ContinuousClock.Instant) async throws -> [String])?
  var request: (URL, String, Int, Double) async -> ConnectivityHTTPObservation = {
    await ConnectivityHTTPRequest().observe(url: $0, targetIP: $1, proxyPort: $2, timeout: $3)
  }

  func measure(
    url: URL, proxyPort: Int, preparationDeadline: ContinuousClock.Instant
  ) async -> Result {
    var result = Result()
    guard ServerConnectivity.validURL(url.absoluteString) != nil,
      let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
    else {
      result.outcome = .configuration
      return result
    }
    let literal = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    let addresses: [String]
    do {
      try Task.checkCancellation()
      if ConnectivityAddress.family(literal) != nil {
        addresses = [literal]
      } else if let resolve {
        addresses = try await resolve(host, proxyPort, preparationDeadline)
      } else {
        let resolution = await ConnectivityDoHResolver().resolve(
          host: host, proxyPort: proxyPort, deadline: preparationDeadline)
        result.trace += resolution.trace
        addresses = resolution.addresses
      }
    } catch {
      result.outcome = ContinuousClock.now >= preparationDeadline ? .preparationTimeout : .network
      result.trace.append(
        ConnectivityTrace(
          phase: .summary, status: Task.isCancelled ? .cancelled : .network, failureStage: .dns))
      return result
    }
    var seen = Set<String>()
    var counts: [Int32: Int] = [:]
    let candidates = addresses.filter { address in
      guard let family = ConnectivityAddress.family(address),
        seen.insert(address).inserted, counts[family, default: 0] < 2
      else { return false }
      counts[family, default: 0] += 1
      return true
    }
    var best: (String, Double)?
    var failure: ServerConnectivity.Outcome = .network
    for (index, address) in candidates.enumerated() {
      if Task.isCancelled { return cancelled(result) }
      let remaining = Self.seconds(until: preparationDeadline)
      if remaining <= 0 {
        result.outcome = .preparationTimeout
        result.trace.append(
          ConnectivityTrace(phase: .summary, status: .timeout, failureStage: .selection))
        return result
      }
      let observation = await request(url, address, proxyPort, min(3, remaining))
      result.trace.append(observation.trace(phase: .candidate, index: index + 1, address: address))
      failure = observation.outcome
      if case .success = observation.outcome,
        best == nil || observation.totalMilliseconds < best!.1
      {
        best = (address, observation.totalMilliseconds)
      }
    }
    if Task.isCancelled { return cancelled(result) }
    guard ContinuousClock.now < preparationDeadline else {
      result.outcome = .preparationTimeout
      result.trace.append(
        ConnectivityTrace(phase: .summary, status: .timeout, failureStage: .selection))
      return result
    }
    guard let best else {
      result.outcome = failure
      result.trace.append(
        ConnectivityTrace(phase: .summary, status: .network, failureStage: .selection))
      return result
    }
    result.selectedIP = best.0
    result.trace.append(ConnectivityTrace(phase: .selected, status: .success, address: best.0))
    for index in 1...3 {
      if Task.isCancelled { return cancelled(result) }
      let observation = await request(url, best.0, proxyPort, 5)
      result.samples.append(observation)
      result.trace.append(observation.trace(phase: .sample, index: index, address: best.0))
    }
    if Task.isCancelled { return cancelled(result) }
    let successes = result.samples.compactMap { sample -> Double? in
      if case .success = sample.outcome { return sample.totalMilliseconds }
      return nil
    }.sorted()
    guard successes.count >= 2 else {
      result.outcome =
        result.samples.first(where: {
          if case .success = $0.outcome { return false }
          return true
        })?.outcome ?? .network
      result.trace.append(ConnectivityTrace(phase: .summary, status: .insufficientSamples))
      return result
    }
    let median = successes.count == 2 ? (successes[0] + successes[1]) / 2 : successes[1]
    result.outcome = .success(milliseconds: Int(median.rounded()))
    result.trace.append(ConnectivityTrace(phase: .summary, status: .success, milliseconds: median))
    return result
  }

  static func seconds(until deadline: ContinuousClock.Instant) -> Double {
    let parts = ContinuousClock.now.duration(to: deadline).components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }

  private func cancelled(_ original: Result) -> Result {
    var result = original
    result.outcome = .network
    result.trace.append(ConnectivityTrace(phase: .summary, status: .cancelled))
    return result
  }
}

extension ConnectivityHTTPObservation {
  func trace(phase: ConnectivityTrace.Phase, index: Int, address: String) -> ConnectivityTrace {
    let status: ConnectivityTrace.Status
    var http: Int?
    switch outcome {
    case .success: status = .success
    case .requestTimeout, .preparationTimeout: status = .timeout
    case .http(let code):
      status = .http
      http = code
    case .configuration, .unsupported: status = .configuration
    default: status = .network
    }
    return ConnectivityTrace(
      phase: phase, status: status, index: index, address: address,
      milliseconds: totalMilliseconds, localTCPMilliseconds: localTCPMilliseconds,
      sendMilliseconds: sendMilliseconds, firstByteMilliseconds: firstByteMilliseconds,
      headersMilliseconds: headersMilliseconds,
      failureStage: status == .success || status == .http
        ? .none : ConnectivityTrace.FailureStage(rawValue: failureStage) ?? .request,
      httpStatus: http)
  }
}
