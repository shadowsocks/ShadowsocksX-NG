import Testing
import XCTest

@MainActor
struct BoundedTestWaitTests {
  @Test func missingPhaseStopsTheBodyAndDrainsItsTask() async throws {
    let entered = XCTestExpectation(description: "worker entered")
    let gate = RuleRuntimeDelayGate(started: entered)
    var exited = false
    var continued = false
    let task = Task {
      try? await gate.wait()
      exited = true
    }
    try await requireTestPhase([entered])
    await #expect(throws: TestWaitError.self) {
      try await withTestTask(
        task, release: { gate.resume() },
        body: {
          try await requireTestPhase(
            [XCTestExpectation(description: "phase never reached")], timeout: 0.02)
          continued = true
        })
    }
    #expect(!continued)
    #expect(exited)
  }

  @Test func missingConditionHasADeadline() async {
    await #expect(throws: TestWaitError.self) {
      try await requireTestCondition("never true", timeout: .milliseconds(20)) { false }
    }
  }

  @Test func cancelledConditionWaitStops() async {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await requireTestCondition("never true") { false }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func asyncGateTimesOutWithoutBlockingAWorker() async {
    let gate = TestAsyncGate(onTimeout: {})
    #expect(await gate.wait(timeout: .milliseconds(20)) == false)
  }

  @Test func asyncGateRemembersEarlyAndRepeatedRelease() async {
    let gate = TestAsyncGate()
    gate.release()
    gate.release()
    #expect(await gate.wait(timeout: .zero))
  }

  @Test func asyncGateReleasesEveryWorker() async throws {
    let gate = TestAsyncGate()
    let entered = XCTestExpectation(description: "workers entered")
    entered.expectedFulfillmentCount = 4
    let workers = (0..<4).map { _ in
      Task.detached {
        entered.fulfill()
        return await gate.wait()
      }
    }
    try await requireTestPhase([entered])
    gate.release()
    gate.release()
    for worker in workers { #expect(await worker.value) }
  }
}
