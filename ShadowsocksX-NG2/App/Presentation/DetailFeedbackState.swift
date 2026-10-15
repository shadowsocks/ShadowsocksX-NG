import Foundation
import Observation

/// 结果身份和完成时间来自命令；业务内容留在各自的呈现入口。
protocol DetailFeedbackResult: Identifiable where ID == UUID {
  var completedAt: Date { get }
  var isSuccess: Bool { get }
}

extension ActivationFeedbackState.Completion: DetailFeedbackResult {
  var isSuccess: Bool { feedback.isSuccess }
}

extension SubscriptionRefreshCompletion: DetailFeedbackResult {
  var isSuccess: Bool { failure == nil }
}

/// 详情会话持有展示寿命；命令结果仍由原工作流保留。
@Observable
@MainActor
final class DetailFeedbackState<Result: DetailFeedbackResult> {
  private(set) var completion: Result?
  private var generation = 0
  private let now: () -> Date
  private let sleep: (TimeInterval) async throws -> Void

  init(
    now: @escaping () -> Date = Date.init,
    sleep: @escaping (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.now = now
    self.sleep = sleep
  }

  func present(_ result: Result?) async {
    guard !Task.isCancelled else { return }
    generation += 1
    let currentGeneration = generation
    completion = nil
    guard let result else { return }
    let remaining = result.completedAt.addingTimeInterval(result.isSuccess ? 3 : 10)
      .timeIntervalSince(now())
    guard remaining > 0 else { return }
    completion = result
    defer {
      if generation == currentGeneration { completion = nil }
    }
    try? await sleep(remaining)
  }
}
