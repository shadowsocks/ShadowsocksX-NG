import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityMeasurementTests {
  @Test func selectsFastestSuccessfulIPAndSamplesItsMedian() async throws {
    var addresses: [String] = []
    var limits: [Double] = []
    let values = [90, 20, 200, 40, 60]
    let module = ConnectivityMeasurement(
      resolve: { _, _, _ in ["192.0.2.1", "192.0.2.2"] },
      request: { _, address, _, timeout in
        let index = addresses.count
        addresses.append(address)
        limits.append(timeout)
        return ConnectivityHTTPObservation(
          outcome: .success(milliseconds: values[index]),
          totalMilliseconds: Double(values[index]))
      })
    let result = await module.measure(
      url: URL(string: "http://target.invalid/check?token=private")!, proxyPort: 1234,
      preparationDeadline: .now.advanced(by: .seconds(30)))
    #expect(result.outcome == .success(milliseconds: 60))
    #expect(result.selectedIP == "192.0.2.2")
    #expect(addresses == ["192.0.2.1", "192.0.2.2", "192.0.2.2", "192.0.2.2", "192.0.2.2"])
    #expect(limits == [3, 3, 5, 5, 5])
    #expect(result.samples.count == 3)
  }
  @Test(arguments: [true, false])
  func requiresTwoSuccessesAndAveragesTwoSamples(twoSuccesses: Bool) async {
    var calls = 0
    let module = ConnectivityMeasurement(
      resolve: { _, _, _ in ["192.0.2.1"] },
      request: { _, _, _, _ in
        defer { calls += 1 }
        if calls == 2 || (!twoSuccesses && calls == 3) {
          return ConnectivityHTTPObservation(outcome: .requestTimeout, failureStage: "first_byte")
        }
        return ConnectivityHTTPObservation(
          outcome: .success(milliseconds: 10), totalMilliseconds: calls == 1 ? 10 : 30)
      })
    let result = await module.measure(
      url: URL(string: "http://target.invalid/")!, proxyPort: 1234,
      preparationDeadline: .now.advanced(by: .seconds(30)))
    #expect(calls == 4)
    #expect(result.outcome == (twoSuccesses ? .success(milliseconds: 20) : .requestTimeout))
    #expect(result.trace.filter { $0.phase == .sample }.count == 3)
    #expect(result.trace.last?.status == (twoSuccesses ? .success : .insufficientSamples))
  }

  @Test func boundsCandidatesPerFamilyAndDoesNotSelectFailedResponses() async {
    var addresses: [String] = []
    let module = ConnectivityMeasurement(
      resolve: { _, _, _ in
        [
          "not-an-ip", "192.0.2.1", "192.0.2.1", "192.0.2.2", "192.0.2.3",
          "2001:db8::1", "2001:db8::2", "2001:db8::3",
        ]
      },
      request: { _, address, _, _ in
        addresses.append(address)
        return ConnectivityHTTPObservation(
          outcome: address == "2001:db8::2" ? .success(milliseconds: 10) : .http(302),
          totalMilliseconds: 10)
      })
    let result = await module.measure(
      url: URL(string: "http://target.invalid/")!, proxyPort: 1234,
      preparationDeadline: .now.advanced(by: .seconds(30)))
    #expect(Array(addresses.prefix(4)) == ["192.0.2.1", "192.0.2.2", "2001:db8::1", "2001:db8::2"])
    #expect(Array(addresses.suffix(3)) == Array(repeating: "2001:db8::2", count: 3))
    #expect(result.outcome == .success(milliseconds: 10))
  }

  @Test func expiredPreparationDoesNotRequestAndRecordsItsFailureStage() async {
    var calls = 0
    let module = ConnectivityMeasurement(
      resolve: { _, _, _ in ["192.0.2.1"] },
      request: { _, _, _, _ in
        calls += 1
        return ConnectivityHTTPObservation()
      })
    let result = await module.measure(
      url: URL(string: "http://target.invalid/")!, proxyPort: 1234,
      preparationDeadline: .now.advanced(by: .seconds(-1)))
    #expect(result.outcome == .preparationTimeout)
    #expect(calls == 0)
    #expect(result.trace.last?.status == .timeout)
    #expect(result.trace.last?.failureStage == .selection)
  }

  @Test func literalTargetSkipsDNSAndLogsNeverContainURLSecrets() async {
    var resolutions = 0
    let module = ConnectivityMeasurement(
      resolve: { _, _, _ in
        resolutions += 1
        return []
      },
      request: { _, _, _, _ in
        ConnectivityHTTPObservation(outcome: .success(milliseconds: 15), totalMilliseconds: 15)
      })
    let result = await module.measure(
      url: URL(string: "http://192.0.2.1/private?token=SECRET")!, proxyPort: 1234,
      preparationDeadline: .now.advanced(by: .seconds(30)))
    #expect(resolutions == 0)
    #expect(result.outcome == .success(milliseconds: 15))
    let lines = result.trace.map { RuntimeLogEvent.connectivityMeasurement(id: UUID(), entry: $0) }
    #expect(lines.allSatisfy { $0.diagnosticReportLine == nil })
    #expect(lines.allSatisfy { $0.standardErrorLine() == nil })
    #expect(!lines.map(\.description).joined().contains("SECRET"))
    #expect(!lines.map(\.description).joined().contains("private"))
  }

  @Test func cancellationDuringCandidateDoesNotStartMoreRequests() async {
    let gate = AsyncGate()
    var calls = 0
    let module = ConnectivityMeasurement(
      resolve: { _, _, _ in ["192.0.2.1", "192.0.2.2"] },
      request: { _, _, _, _ in
        calls += 1
        await gate.wait()
        return ConnectivityHTTPObservation(
          outcome: .success(milliseconds: 10), totalMilliseconds: 10)
      })
    let task = Task {
      await module.measure(
        url: URL(string: "http://target.invalid/")!, proxyPort: 1234,
        preparationDeadline: .now.advanced(by: .seconds(30)))
    }
    while calls == 0 { await Task.yield() }
    task.cancel()
    gate.release()
    let result = await task.value
    #expect(calls == 1)
    #expect(result.samples.isEmpty)
    #expect(result.trace.last?.status == .cancelled)
  }

}
