import Combine
import Foundation

/// didChange 事实信号的每主队列轮合并器：属性 didSet 汇集到 `markChanged`，
/// 同一同步轮内多次标记只在轮末发一次。冲洗晚于当前同步轮——订阅方收到
/// 信号时读到的必是一组完整事实，不会读到写半程状态。
@MainActor
final class CoalescedFactSignal {
  /// 事实已变化通知（didChange 语义；每主队列轮至多一次）。
  let changes = PassthroughSubject<Void, Never>()
  private var flushScheduled = false

  /// didSet 的汇集点；重复标记合并为一次轮末冲洗。
  func markChanged() {
    guard !flushScheduled else { return }
    flushScheduled = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      flushScheduled = false
      changes.send()
    }
  }
}
