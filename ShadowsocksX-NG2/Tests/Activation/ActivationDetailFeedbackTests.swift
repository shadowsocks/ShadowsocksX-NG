import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ActivationDetailFeedbackTests {
  @Test func successExpiresFromCompletionWithoutRestartingOnReturn() {
    let date = Date(timeIntervalSince1970: 100)
    let result = ActivationFeedbackState.Completion(
      targetID: NodeID(rawValue: "a"), feedback: .activated(skippedInvalid: 2), completedAt: date)
    let state = ActivationDetailFeedbackState()
    state.present(result, now: date.addingTimeInterval(2))
    #expect(state.completion == result)
    #expect(state.expiresAt == date.addingTimeInterval(3))
    state.present(result, now: date.addingTimeInterval(3))
    #expect(state.completion == nil)
  }

  @Test(arguments: [
    ActivationFeedbackState.Feedback.failed(message: "failure"),
    .rejected(.noActiveTarget),
  ])
  func failuresLastTenSecondsAndStaleExpirationDoesNotClearNewResult(
    feedback: ActivationFeedbackState.Feedback
  ) {
    let date = Date(timeIntervalSince1970: 100)
    let first = ActivationFeedbackState.Completion(
      targetID: NodeID(rawValue: "a"), feedback: .activated(skippedInvalid: 0), completedAt: date)
    let next = ActivationFeedbackState.Completion(
      targetID: NodeID(rawValue: "a"), feedback: feedback, completedAt: date)
    let state = ActivationDetailFeedbackState()
    state.present(first, now: date)
    state.present(next, now: date.addingTimeInterval(3))
    state.expire(first.id)
    #expect(state.completion == next)
    #expect(state.expiresAt == date.addingTimeInterval(10))
    state.present(next, now: date.addingTimeInterval(10))
    #expect(state.completion == nil)
  }
}
