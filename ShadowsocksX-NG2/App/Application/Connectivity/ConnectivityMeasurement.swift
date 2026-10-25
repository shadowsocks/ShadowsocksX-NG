import Darwin
import Foundation

/// Preparation and sampling stay behind one measurement interface. Dependencies
/// at the HTTP and DNS seams admit deterministic fixtures without real egress.
@MainActor
struct ConnectivityMeasurement {
  private struct Candidate {
    let address: String
    let milliseconds: Double
  }

  private struct AddressResolution {
    let addresses: [String]
    let trace: [ConnectivityTrace]
    let failure: ServerConnectivity.Outcome?
  }

  private struct Selection {
    let result: Result
    let address: String?
  }

  private struct SampleSummary {
    let outcome: ServerConnectivity.Outcome
    let medianMilliseconds: Double?
  }

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
    guard let host = validatedHost(in: url) else { return Result(outcome: .configuration) }
    let resolution = await resolveAddresses(
      host, proxyPort: proxyPort, deadline: preparationDeadline)
    var result = Result(trace: resolution.trace)
    if let failure = resolution.failure {
      result.outcome = failure
      result.trace.append(dnsFailureTrace())
      return result
    }
    let candidates = candidateAddresses(from: resolution.addresses)
    let selection = await selectCandidate(
      from: candidates, url: url, proxyPort: proxyPort,
      deadline: preparationDeadline, startingWith: result)
    guard let address = selection.address else { return selection.result }
    return await sample(url, address: address, proxyPort: proxyPort, startingWith: selection.result)
  }

  private func validatedHost(in url: URL) -> String? {
    guard ServerConnectivity.validURL(url.absoluteString) != nil else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
  }

  private func resolveAddresses(
    _ host: String, proxyPort: Int, deadline: ContinuousClock.Instant
  ) async -> AddressResolution {
    let literal = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    do {
      try Task.checkCancellation()
      if ConnectivityAddress.family(literal) != nil {
        return AddressResolution(addresses: [literal], trace: [], failure: nil)
      }
      if let resolve {
        return AddressResolution(
          addresses: try await resolve(host, proxyPort, deadline), trace: [], failure: nil)
      }
      let resolution = await ConnectivityDoHResolver().resolve(
        host: host, proxyPort: proxyPort, deadline: deadline)
      return AddressResolution(
        addresses: resolution.addresses, trace: resolution.trace, failure: nil)
    } catch {
      let failure: ServerConnectivity.Outcome =
        ContinuousClock.now >= deadline
        ? .preparationTimeout : .network
      return AddressResolution(addresses: [], trace: [], failure: failure)
    }
  }

  private func dnsFailureTrace() -> ConnectivityTrace {
    ConnectivityTrace(
      phase: .summary, status: Task.isCancelled ? .cancelled : .network, failureStage: .dns)
  }

  private func candidateAddresses(from addresses: [String]) -> [String] {
    var seen = Set<String>()
    var counts: [Int32: Int] = [:]
    return addresses.filter { address in
      guard let family = ConnectivityAddress.family(address), seen.insert(address).inserted,
        counts[family, default: 0] < 2
      else { return false }
      counts[family, default: 0] += 1
      return true
    }
  }

  private func selectCandidate(
    from candidates: [String], url: URL, proxyPort: Int,
    deadline: ContinuousClock.Instant, startingWith original: Result
  ) async -> Selection {
    var result = original
    var best: Candidate?
    var failure: ServerConnectivity.Outcome = .network
    for (index, address) in candidates.enumerated() {
      if Task.isCancelled { return Selection(result: cancelled(result), address: nil) }
      let remaining = Self.seconds(until: deadline)
      if remaining <= 0 { return selectionTimeout(result) }
      let observation = await request(url, address, proxyPort, min(3, remaining))
      result.trace.append(observation.trace(phase: .candidate, index: index + 1, address: address))
      failure = observation.outcome
      if isBetterCandidate(observation, than: best) {
        best = Candidate(address: address, milliseconds: observation.totalMilliseconds)
      }
    }
    if Task.isCancelled { return Selection(result: cancelled(result), address: nil) }
    guard ContinuousClock.now < deadline else { return selectionTimeout(result) }
    guard let best else {
      result.outcome = failure
      result.trace.append(
        ConnectivityTrace(phase: .summary, status: .network, failureStage: .selection))
      return Selection(result: result, address: nil)
    }
    result.selectedIP = best.address
    result.trace.append(
      ConnectivityTrace(phase: .selected, status: .success, address: best.address))
    return Selection(result: result, address: best.address)
  }

  private func isBetterCandidate(
    _ observation: ConnectivityHTTPObservation, than best: Candidate?
  ) -> Bool {
    guard case .success = observation.outcome else { return false }
    guard let best else { return true }
    return observation.totalMilliseconds < best.milliseconds
  }

  private func selectionTimeout(_ original: Result) -> Selection {
    var result = original
    result.outcome = .preparationTimeout
    result.trace.append(
      ConnectivityTrace(phase: .summary, status: .timeout, failureStage: .selection))
    return Selection(result: result, address: nil)
  }

  private func sample(
    _ url: URL, address: String, proxyPort: Int, startingWith original: Result
  ) async -> Result {
    var result = original
    for index in 1...3 {
      if Task.isCancelled { return cancelled(result) }
      let observation = await request(url, address, proxyPort, 5)
      result.samples.append(observation)
      result.trace.append(observation.trace(phase: .sample, index: index, address: address))
    }
    if Task.isCancelled { return cancelled(result) }
    let summary = sampleSummary(for: result.samples)
    result.outcome = summary.outcome
    if let median = summary.medianMilliseconds {
      result.trace.append(
        ConnectivityTrace(phase: .summary, status: .success, milliseconds: median))
    } else {
      result.trace.append(ConnectivityTrace(phase: .summary, status: .insufficientSamples))
    }
    return result
  }

  private func sampleSummary(for samples: [ConnectivityHTTPObservation]) -> SampleSummary {
    let successes = samples.compactMap { sample -> Double? in
      if case .success = sample.outcome { return sample.totalMilliseconds }
      return nil
    }.sorted()
    guard successes.count >= 2 else {
      let failure =
        samples.first(where: {
          if case .success = $0.outcome { return false }
          return true
        })?.outcome ?? .network
      return SampleSummary(outcome: failure, medianMilliseconds: nil)
    }
    let median = successes.count == 2 ? (successes[0] + successes[1]) / 2 : successes[1]
    return SampleSummary(
      outcome: .success(milliseconds: Int(median.rounded())), medianMilliseconds: median)
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
