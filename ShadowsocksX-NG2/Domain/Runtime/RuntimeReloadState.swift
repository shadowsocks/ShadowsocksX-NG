import Foundation

/// 启动期间累积重载信号，只有全部投递成功后才清空。
struct RuntimeReloadState {
  private var pending = Set<Int32>()

  mutating func enqueue(_ next: RuntimeSupervision, from current: RuntimeSupervision) {
    pending.formUnion(next.reloadSignals(from: current))
  }

  mutating func flush(send: (Int32) -> Bool) -> Bool {
    guard pending.sorted().allSatisfy(send) else { return false }
    pending.removeAll()
    return true
  }
}
