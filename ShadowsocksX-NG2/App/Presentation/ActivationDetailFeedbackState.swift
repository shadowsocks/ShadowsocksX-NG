import Combine
import Foundation

/// 详情结果从命令结束时计时；命令状态保留给其他激活入口。
@MainActor
final class ActivationDetailFeedbackState: ObservableObject {
  @Published private(set) var completion: ActivationFeedbackState.Completion?

  var expiresAt: Date? {
    completion.map { Self.expiration(of: $0) }
  }

  func present(_ completion: ActivationFeedbackState.Completion?, now: Date = Date()) {
    self.completion = completion.flatMap { Self.expiration(of: $0) > now ? $0 : nil }
  }

  func expire(_ id: UUID) {
    guard completion?.id == id else { return }
    completion = nil
  }

  private static func expiration(of completion: ActivationFeedbackState.Completion) -> Date {
    completion.completedAt.addingTimeInterval(completion.feedback.isSuccess ? 3 : 10)
  }
}
