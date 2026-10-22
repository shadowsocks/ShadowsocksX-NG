import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct DetailFeedbackStateTests {
  @Test func successExpiresFromCompletionRatherThanAppearance() async {
    let completedAt = Date(timeIntervalSince1970: 100)
    let result = SubscriptionRefreshCompletion(completedAt: completedAt)
    let gate = AsyncGate()
    let entered = AsyncGate()
    var delays: [TimeInterval] = []
    let state = DetailFeedbackState<SubscriptionRefreshCompletion>(
      now: { completedAt.addingTimeInterval(2) },
      sleep: { delay in
        delays.append(delay)
        entered.release()
        await gate.wait()
      })
    let task = Task { await state.present(result) }
    await entered.wait()
    #expect(state.completion == result)
    #expect(delays == [1])
    gate.release()
    await task.value
    #expect(state.completion == nil)
  }
  @Test func supersededTaskCannotClearNewResult() async {
    let date = Date(timeIntervalSince1970: 100)
    let first = SubscriptionRefreshCompletion(completedAt: date)
    let next = SubscriptionRefreshCompletion(completedAt: date, failure: .httpStatus(code: 503))
    let firstEntered = AsyncGate()
    let nextEntered = AsyncGate()
    let firstSleep = AsyncGate()
    let nextSleep = AsyncGate()
    var calls = 0
    let state = DetailFeedbackState<SubscriptionRefreshCompletion>(
      now: { date },
      sleep: { _ in
        calls += 1
        if calls == 1 {
          firstEntered.release()
          await firstSleep.wait()
        } else {
          nextEntered.release()
          await nextSleep.wait()
        }
      })
    let oldTask = Task { await state.present(first) }
    await firstEntered.wait()
    oldTask.cancel()
    let newTask = Task { await state.present(next) }
    await nextEntered.wait()
    firstSleep.release()
    await oldTask.value
    #expect(state.completion == next)
    nextSleep.release()
    await newTask.value
    #expect(state.completion == nil)
  }
  @Test(arguments: [
    (ActivationFeedbackState.Feedback.activated(skippedInvalid: 2), 3.0),
    (.rejected(.noActiveTarget), 10.0),
    (.failed(message: "failure"), 10.0),
  ])
  func activationUsesTheSharedLifetime(
    feedback: ActivationFeedbackState.Feedback, seconds: TimeInterval
  ) async {
    let date = Date(timeIntervalSince1970: 100)
    let result = ActivationFeedbackState.Completion(
      targetID: NodeID(rawValue: "a"), feedback: feedback, completedAt: date)
    await checkLifetime(result, seconds: seconds)
  }

  @Test func subscriptionFailureLastsTenSeconds() async {
    await checkLifetime(
      SubscriptionRefreshCompletion(
        completedAt: Date(timeIntervalSince1970: 100), failure: .httpStatus(code: 503)),
      seconds: 10)
  }

  @Test func leavingCancelsAndReturningUsesRemainingLifetime() async {
    let date = Date(timeIntervalSince1970: 100)
    let result = SubscriptionRefreshCompletion(completedAt: date)
    var now = date
    var delays: [TimeInterval] = []
    let firstEntered = AsyncGate()
    let nextEntered = AsyncGate()
    let firstSleep = AsyncGate()
    let nextSleep = AsyncGate()
    let state = DetailFeedbackState<SubscriptionRefreshCompletion>(
      now: { now },
      sleep: { delay in
        delays.append(delay)
        let isFirst = delays.count == 1
        let entered = isFirst ? firstEntered : nextEntered
        let sleeper = isFirst ? firstSleep : nextSleep
        try await withTaskCancellationHandler {
          entered.release()
          await sleeper.wait()
          try Task.checkCancellation()
        } onCancel: {
          sleeper.release()
        }
      })
    let firstVisit = Task { await state.present(result) }
    await firstEntered.wait()
    firstVisit.cancel()
    await firstVisit.value
    #expect(state.completion == nil)
    now = date.addingTimeInterval(2)
    let nextVisit = Task { await state.present(result) }
    await nextEntered.wait()
    #expect(state.completion == result)
    #expect(delays == [3, 1])
    nextSleep.release()
    await nextVisit.value
    now = date.addingTimeInterval(3)
    await state.present(result)
    #expect(state.completion == nil)
    #expect(delays == [3, 1])
  }

  @Test func clearingInputInvalidatesPendingExpiration() async {
    let date = Date(timeIntervalSince1970: 100)
    let result = SubscriptionRefreshCompletion(completedAt: date)
    let entered = AsyncGate()
    let sleeper = AsyncGate()
    let state = DetailFeedbackState<SubscriptionRefreshCompletion>(
      now: { date },
      sleep: { _ in
        entered.release()
        await sleeper.wait()
      })
    let task = Task { await state.present(result) }
    await entered.wait()
    await state.present(nil)
    #expect(state.completion == nil)
    sleeper.release()
    await task.value
    #expect(state.completion == nil)
  }

  private func checkLifetime<Result: DetailFeedbackResult & Equatable>(
    _ result: Result, seconds: TimeInterval
  ) async {
    var now = result.completedAt
    var delays: [TimeInterval] = []
    let entered = AsyncGate()
    let sleeper = AsyncGate()
    let state = DetailFeedbackState<Result>(
      now: { now },
      sleep: { delay in
        delays.append(delay)
        entered.release()
        await sleeper.wait()
      })
    let task = Task { await state.present(result) }
    await entered.wait()
    #expect(state.completion == result)
    #expect(delays == [seconds])
    sleeper.release()
    await task.value
    #expect(state.completion == nil)
    now = result.completedAt.addingTimeInterval(seconds)
    await state.present(result)
    #expect(state.completion == nil)
    #expect(delays == [seconds])
  }
}
