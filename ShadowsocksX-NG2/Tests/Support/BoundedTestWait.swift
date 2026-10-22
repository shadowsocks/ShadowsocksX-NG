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

/// Broadcast async release is remembered, and timed-out waiters do not occupy a worker thread.
final class TestAsyncGate: @unchecked Sendable {
  private struct Waiter {
    let continuation: CheckedContinuation<Bool, Never>
    var timeoutTask: Task<Void, Never>?
  }

  private let lock = NSLock()
  private var released = false
  private var waiters: [UUID: Waiter] = [:]
  private let onTimeout: @Sendable () -> Void

  init(
    _ description: String = "test worker release", file: StaticString = #filePath,
    line: UInt = #line, fileID: String = #fileID, column: Int = #column,
    onTimeout: (@Sendable () -> Void)? = nil
  ) {
    if let onTimeout {
      self.onTimeout = onTimeout
    } else if let test = Test.current {
      let message = Comment(
        rawValue: "Timed out waiting for \(description) (created by \(test.name))")
      let location = SourceLocation(
        fileID: fileID, filePath: String(describing: file), line: Int(line), column: column)
      self.onTimeout = { Issue.record(message, sourceLocation: location) }
    } else {
      self.onTimeout = { XCTFail("Timed out waiting for \(description)", file: file, line: line) }
    }
  }

  func wait(timeout: Duration = .seconds(10)) async -> Bool {
    let id = UUID()
    return await withCheckedContinuation { continuation in
      lock.lock()
      guard !released else {
        lock.unlock()
        continuation.resume(returning: true)
        return
      }
      waiters[id] = Waiter(continuation: continuation)
      lock.unlock()

      let timeoutTask = Task { [weak self] in
        do {
          try await Task.sleep(for: timeout)
          self?.expire(id)
        } catch {
          // Release cancels the timer after resuming the waiter.
        }
      }

      lock.lock()
      if var waiter = waiters[id] {
        waiter.timeoutTask = timeoutTask
        waiters[id] = waiter
        lock.unlock()
      } else {
        lock.unlock()
        timeoutTask.cancel()
      }
    }
  }

  func release() {
    lock.lock()
    guard !released else {
      lock.unlock()
      return
    }
    released = true
    let pending = Array(waiters.values)
    waiters.removeAll()
    lock.unlock()

    for waiter in pending {
      waiter.timeoutTask?.cancel()
      waiter.continuation.resume(returning: true)
    }
  }

  private func expire(_ id: UUID) {
    lock.lock()
    let waiter = waiters.removeValue(forKey: id)
    lock.unlock()
    guard let waiter else { return }
    onTimeout()
    waiter.continuation.resume(returning: false)
  }
}
