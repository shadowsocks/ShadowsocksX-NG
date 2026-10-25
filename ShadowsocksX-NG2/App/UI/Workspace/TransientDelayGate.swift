import Foundation

/// 单条状态显示流的瞬态延迟门控：稳定值立即上屏；瞬态值（启动中/应用中/
/// 修复中等短命中间态）延迟一个 interval 后才上屏，期间被新值取代则按新值
/// 重新裁定；已上屏的瞬态至少保持一个 interval，避免「应用中」只闪一瞬又跳
/// 终态的二次闪烁。首值直接上屏——初始绘制没有可被闪烁的上一状态。
///
/// 时间经 now/sleep 注入，测试用虚拟时钟驱动；不持有 SwiftUI 类型。
@MainActor
final class TransientDelayGate<Value: Equatable> {
  private let interval: TimeInterval
  private let now: () -> TimeInterval
  private let sleep: (TimeInterval) async throws -> Void

  /// 显示回调；构造后立即接线。持有方须在自身完成初始化后才能捕获 self，
  /// 故不入构造参数。nil 时门控照常裁决但不外发。
  var display: ((Value) -> Void)?

  private var displayed: Value?
  private var pending: (value: Value, isTransient: Bool)?
  /// 已上屏瞬态的保持截止时刻；稳定值上屏时清除。窗口内的替换被排迟到
  /// 截止时刻，防止瞬态只闪一瞬。
  private var holdUntil: TimeInterval?
  private var scheduleGeneration = 0
  private var pendingTask: Task<Void, Never>?

  /// 当前排队显示任务；无排队（已上屏或无待显值）为 nil。供测试等待迟显完成。
  var scheduledDisplayTask: Task<Void, Never>? { pendingTask }

  init(
    interval: TimeInterval,
    now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
    sleep: @escaping (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.interval = interval
    self.now = now
    self.sleep = sleep
  }

  func update(_ value: Value, isTransient: Bool) {
    if displayed == nil {
      pending = (value, isTransient)
      displayPending()
      return
    }
    if displayed == value {
      pending = nil
      pendingTask?.cancel()
      return
    }
    // 重复 payload 不重排：沿用原定时刻，避免连续重发把瞬态无限推后。
    if pending?.value == value, pending?.isTransient == isTransient { return }
    pending = (value, isTransient)
    pendingTask?.cancel()
    let arrival = now()
    // 无保持窗口时用负无穷做中性值：稳定值的最早上屏时刻就是到达时刻，
    // 立即同步上屏（不能用正的极小值——虚拟时钟 0 会被顶成 epsilon 延迟）。
    let earliest = max(
      isTransient ? arrival + interval : arrival,
      holdUntil ?? -.greatestFiniteMagnitude)
    let delay = max(0, earliest - arrival)
    if delay <= 0 {
      displayPending()
      return
    }
    scheduleGeneration += 1
    let generation = scheduleGeneration
    pendingTask = Task { [weak self] in
      await self?.displayPendingIfCurrent(generation, after: delay)
    }
  }

  private func displayPendingIfCurrent(_ generation: Int, after delay: TimeInterval) async {
    guard generation == scheduleGeneration else { return }
    try? await sleep(delay)
    guard generation == scheduleGeneration else { return }
    displayPending()
  }

  private func displayPending() {
    guard let current = pending else { return }
    displayed = current.value
    holdUntil = current.isTransient ? now() + interval : nil
    pending = nil
    pendingTask = nil
    display?(current.value)
  }
}
