import Combine
import Foundation

/// 提示寿命从命令结束时计算；切回详情不会重新计时。
@MainActor
final class SubscriptionRefreshFeedbackState: ObservableObject {
  @Published private(set) var completion: SubscriptionRefreshCompletion?

  var expiresAt: Date? {
    completion.map { Self.expiration(of: $0) }
  }

  func present(_ completion: SubscriptionRefreshCompletion?, now: Date = Date()) {
    self.completion = completion.flatMap { Self.expiration(of: $0) > now ? $0 : nil }
  }

  func expire(_ id: UUID) {
    guard completion?.id == id else { return }
    completion = nil
  }

  private static func expiration(of completion: SubscriptionRefreshCompletion) -> Date {
    completion.completedAt.addingTimeInterval(completion.failure == nil ? 3 : 10)
  }
}
