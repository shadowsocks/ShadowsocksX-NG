import Foundation
import Testing
import XCTest

enum TestWaitError: Error {
  case timedOut(String)
}

/// A phase failure must leave the test body before it can issue another gated command.
@MainActor
func requireTestPhase(_ expectations: [XCTestExpectation], timeout: TimeInterval = 5) async throws {
  guard await XCTWaiter.fulfillment(of: expectations, timeout: timeout) == .completed else {
    throw TestWaitError.timedOut(expectations.map(\.expectationDescription).joined(separator: ", "))
  }
}

@MainActor
func requireTestCondition(
  _ description: String, timeout: Duration = .seconds(5), condition: () -> Bool
) async throws {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  while !condition() {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline else { throw TestWaitError.timedOut(description) }
    try await Task.sleep(for: .milliseconds(10))
  }
}

/// Release fixtures before joining a cancelled task, including on a phase failure.
@MainActor
func withTestTask<Value: Sendable>(
  _ task: Task<Value, Never>, release: () -> Void, finish: () async -> Void = {},
  body: () async throws -> Void
) async throws {
  do {
    try await body()
  } catch {
    release()
    task.cancel()
    _ = await task.value
    await finish()
    throw error
  }
  release()
  _ = await task.value
  await finish()
}

/// Broadcast release is remembered, including when cleanup runs before a worker enters.
final class TestBlockingGate: @unchecked Sendable {
  private let group = DispatchGroup()
  private let lock = NSLock()
  private var released = false
  private let onTimeout: @Sendable () -> Void

  init(
    _ description: String = "test worker release", file: StaticString = #filePath,
    line: UInt = #line, fileID: String = #fileID, column: Int = #column,
    onTimeout: (@Sendable () -> Void)? = nil
  ) {
    if let onTimeout {
      self.onTimeout = onTimeout
    } else if let test = Test.current {
      // Detached workers have no current test; retain the creating test and source location.
      let message = Comment(
        rawValue: "Timed out waiting for \(description) (created by \(test.name))")
      let location = SourceLocation(
        fileID: fileID, filePath: String(describing: file), line: Int(line), column: column)
      self.onTimeout = { Issue.record(message, sourceLocation: location) }
    } else {
      self.onTimeout = { XCTFail("Timed out waiting for \(description)", file: file, line: line) }
    }
    group.enter()
  }

  func wait(timeout: TimeInterval = 10) -> Bool {
    guard group.wait(timeout: .now() + timeout) == .success else {
      onTimeout()
      return false
    }
    return true
  }

  func release() {
    lock.lock()
    let shouldRelease = !released
    released = true
    lock.unlock()
    if shouldRelease { group.leave() }
  }
}
