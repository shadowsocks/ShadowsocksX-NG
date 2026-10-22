import XCTest

@testable import ShadowsocksX_NG2

/// Pause one retry/debounce phase; subsequent passes remain asynchronous without wall-clock delay.
@MainActor
final class RuleRuntimeDelayGate {
  private let started: XCTestExpectation
  private let onTimeout: () -> Void
  private var didPause = false
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init(
    started: XCTestExpectation,
    onTimeout: @escaping () -> Void = {
      XCTFail("Timed out waiting for rule runtime delay release")
    }
  ) {
    self.started = started
    self.onTimeout = onTimeout
    (stream, continuation) = AsyncStream<Void>.makeStream()
  }

  func wait(timeout: Duration = .seconds(10)) async throws {
    try Task.checkCancellation()
    guard !didPause else {
      await Task.yield()
      return
    }
    didPause = true
    started.fulfill()
    // AsyncStream ends its iterator on cancellation, so the timer race can drain both children.
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { [stream] in
          for await _ in stream {}
          try Task.checkCancellation()
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw TestWaitError.timedOut("rule runtime delay release")
        }
        defer { group.cancelAll() }
        try await group.next()
      }
    } catch let error as TestWaitError {
      onTimeout()
      throw error
    }
  }

  func resume() {
    continuation.finish()
  }
}

/// Rule application can replace its task handle while an earlier save is finishing.
@MainActor
func withRuleApplicationTask<Value: Sendable>(
  _ task: Task<Value, Never>, controller: ProxyRuntimeController, release: () -> Void,
  body: () async throws -> Void
) async throws {
  try await withTestTask(
    task, release: release,
    finish: {
      controller.ruleApplicationTask?.cancel()
      await controller.ruleApplicationTask?.value
    }, body: body)
}

final class PausedRuntimeRuleSource: @unchecked Sendable {
  let started: XCTestExpectation
  private let release = TestBlockingGate("rule source release")
  init(started: XCTestExpectation) { self.started = started }
  func resume() { release.release() }
  func load(_ source: RulesSource) -> RuleSnapshot {
    if source == .geolocationCN {
      started.fulfill()
      _ = release.wait()
    }
    return rulesFixture(source)
  }
}
