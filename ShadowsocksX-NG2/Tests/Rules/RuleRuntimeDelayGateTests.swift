import Testing
import XCTest

@MainActor
struct RuleRuntimeDelayGateTests {
  @Test func releaseBeforeWaitIsRemembered() async throws {
    let gate = RuleRuntimeDelayGate(started: XCTestExpectation(description: "entered"))
    gate.resume()
    gate.resume()
    try await gate.wait()
  }

  @Test func missingReleaseTimesOutAndReportsFailure() async {
    var reported = false
    let gate = RuleRuntimeDelayGate(
      started: XCTestExpectation(description: "entered"), onTimeout: { reported = true })
    await #expect(throws: TestWaitError.self) {
      try await gate.wait(timeout: .milliseconds(20))
    }
    #expect(reported)
    gate.resume()
    gate.resume()
  }

  @Test func cancellationBeforeEntryDoesNotSuspend() async {
    let gate = RuleRuntimeDelayGate(started: XCTestExpectation(description: "entered"))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await gate.wait()
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func cancellationWhileWaitingDrainsTheWait() async throws {
    let entered = XCTestExpectation(description: "entered")
    let gate = RuleRuntimeDelayGate(started: entered)
    let task = Task { try await gate.wait() }
    try await requireTestPhase([entered])
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    gate.resume()
  }

  @Test func releaseAndCancellationCanRaceWithoutDoubleResume() async throws {
    for _ in 0..<100 {
      let entered = XCTestExpectation(description: "entered")
      let gate = RuleRuntimeDelayGate(started: entered)
      let task = Task { try await gate.wait() }
      try await requireTestPhase([entered])
      let cancellation = Task.detached { task.cancel() }
      gate.resume()
      gate.resume()
      do { try await task.value } catch {
        #expect(error is CancellationError)
      }
      await cancellation.value
    }
  }
}
