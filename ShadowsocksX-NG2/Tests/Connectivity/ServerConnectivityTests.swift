import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ServerConnectivityTests {
  @Test func repeatedRequestsShareWorkAndCoolingDoesNotAddHistory() async {
    let id = NodeID(rawValue: UUID().uuidString)
    var calls = 0
    var now = Date(timeIntervalSince1970: 100)
    let module = ServerConnectivity(
      configuration: { _ in .fixture }, now: { now },
      measure: { _, _, _ in
        calls += 1
        await Task.yield()
        return .success(milliseconds: 42)
      })
    let batch = module.test([id, id])
    _ = module.test([id])
    await module.wait(for: batch)
    #expect(calls == 1)
    #expect(module.history(for: id).count == 1)
    let skipped = module.test([id])
    #expect(module.batch(skipped)?.cooling == [id])
    #expect(module.history(for: id).count == 1)
    now.addTimeInterval(10)
    await module.wait(for: module.test([id]))
    #expect(calls == 2)
  }

  @Test func overlappingBatchesShareOneSlotUntilCleanupCompletes() async {
    let ids = (0..<7).map { _ in NodeID.fresh() }
    let gate = AsyncGate()
    var active = 0
    var peak = 0
    var calls = 0
    let module = ServerConnectivity(
      configuration: { _ in .fixture },
      measure: { _, _, _ in
        active += 1
        calls += 1
        peak = max(peak, active)
        await gate.wait()
        active -= 1
        return .success(milliseconds: 12)
      })
    let firstTarget = module.test(Array(ids.prefix(5)))
    let secondTarget = module.test(Array(ids.suffix(5)))
    for _ in 0..<100 { await Task.yield() }
    #expect(calls == 1)
    #expect(module.testing.count == 7)
    gate.release()
    await module.wait(for: firstTarget)
    await module.wait(for: secondTarget)
    #expect(peak == 1)
    #expect(calls == 7)
    #expect(ids.allSatisfy { module.history(for: $0).count == 1 })
  }

  @Test func credentialValueChangesSuppressLateResultsAndPreserveCooldown() async {
    let id = NodeID.fresh()
    var server = SslocalServerDocument.fixture
    let gate = AsyncGate()
    let module = ServerConnectivity(
      configuration: { _ in server },
      measure: { _, _, _ in
        await gate.wait()
        return .success(milliseconds: 9)
      })
    let batch = module.test([id])
    await Task.yield()
    server = SslocalServerDocument(
      id: "test", server: "example.com", serverPort: 443,
      password: "changed", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
    module.configurationsChanged()
    gate.release()
    await module.wait(for: batch)
    #expect(module.history(for: id).isEmpty)
    #expect(module.isCooling(id))
    module.setURL(URL(string: "https://example.com/check")!)
    #expect(module.isCooling(id))
  }

  @Test func latestFailureReplacesSuccessAndHistoryIsBounded() async {
    let id = NodeID.fresh()
    var now = Date(timeIntervalSince1970: 100)
    var outcome = ServerConnectivity.Outcome.success(milliseconds: 11)
    let module = ServerConnectivity(
      configuration: { _ in .fixture }, now: { now },
      measure: { _, _, _ in outcome })
    await module.wait(for: module.test([id]))
    outcome = .http(302)
    for _ in 0..<12 {
      now.addTimeInterval(10)
      await module.wait(for: module.test([id]))
    }
    #expect(module.history(for: id).count == 10)
    #expect(module.history(for: id).first?.outcome == .http(302))
    let summary = module.summary(for: [id], at: now)
    #expect(summary.hasResults)
    #expect(summary.record == nil)
    #expect(!summary.isTesting)
  }

  @Test func freshResultsBeatStaleAndTiesUseCatalogOrder() async {
    let ids = (0..<3).map { _ in NodeID.fresh() }
    var now = Date(timeIntervalSince1970: 100)
    var latency = 1
    let module = ServerConnectivity(
      configuration: { _ in .fixture }, now: { now },
      measure: { _, _, _ in .success(milliseconds: latency) })
    await module.wait(for: module.test([ids[0]]))
    now.addTimeInterval(300)
    latency = 20
    await module.wait(for: module.test(Array(ids.suffix(2))))
    #expect(module.summary(for: ids, at: now).serverID == ids[1])
    module.networkChanged()
    #expect(module.summary(for: ids, at: now).serverID == ids[0])
    #expect(module.summary(for: ids, at: now).record?.isExpired(at: now) == true)
    module.setURL(URL(string: "https://example.com/new")!)
    #expect(!module.summary(for: ids, at: now).hasResults)
  }

  @Test func URLAndNetworkChangesSuppressInFlightAndShutdownDrainsQueuedWork() async {
    let ids = (0..<5).map { _ in NodeID.fresh() }
    let gate = AsyncGate()
    let module = ServerConnectivity(
      configuration: { _ in .fixture },
      measure: { _, _, _ in
        await gate.wait()
        return .success(milliseconds: 9)
      })
    let batch = module.test(ids)
    await Task.yield()
    module.networkChanged()
    let shutdown = Task { await module.shutdown() }
    await Task.yield()
    #expect(!module.testing.isEmpty)
    gate.release()
    await shutdown.value
    await module.wait(for: batch)
    #expect(module.testing.isEmpty)
    #expect(ids.allSatisfy { module.history(for: $0).isEmpty && module.isCooling($0) })
  }

  @Test func queuedConfigurationIsRecheckedBeforeLaunching() async {
    let ids = (0..<4).map { _ in NodeID.fresh() }
    let gate = AsyncGate()
    var changed = false
    var calls = 0
    let module = ServerConnectivity(
      configuration: { id in
        if changed && id == ids[3] { throw ServerFormLoadError.notFound }
        return .fixture
      },
      measure: { _, _, _ in
        calls += 1
        await gate.wait()
        return .success(milliseconds: 5)
      })
    let batch = module.test(ids)
    for _ in 0..<100 { await Task.yield() }
    changed = true
    gate.release()
    await module.wait(for: batch)
    #expect(calls == 3)
    #expect(module.history(for: ids[3]).isEmpty)
    #expect(module.isCooling(ids[3]))
  }

  @Test func URLValidationAllowsHTTPOnly() {
    #expect(ServerConnectivity.validURL("http://example.com/check") != nil)
    #expect(ServerConnectivity.validURL("https://example.com/check?q=secret") == nil)
    for value in [
      "file:///tmp/check", "ftp://example.com", "https:///", "example.com", "http://x/#fragment",
    ] {
      #expect(ServerConnectivity.validURL(value) == nil)
    }
  }

}

extension SslocalServerDocument {
  fileprivate static var fixture: Self {
    Self(
      id: "test", server: "example.com", serverPort: 443, password: "secret",
      method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
  }
}
