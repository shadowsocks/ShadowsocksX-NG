import Foundation

// MARK: - 信号与共享状态

/// 信号只置位并唤醒监管循环，全部判定在循环线程完成。标志与信号量成对
/// 配合有界监听轮询，进程退出由 Process 观测，不另设共享退出状态。
let signalsQueue = DispatchQueue(label: "com.qiuyuzhou.ShadowsocksX-NG2.agent.signals")

final class SignalFlags {
  private let lock = NSLock()
  private var stopRequested = false
  private var reloadRequested = false
  private let events = DispatchSemaphore(value: 0)

  func requestStop() {
    lock.lock()
    stopRequested = true
    lock.unlock()
    events.signal()
  }

  func requestReload() {
    lock.lock()
    reloadRequested = true
    lock.unlock()
    events.signal()
  }

  func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
    events.wait(timeout: timeout)
  }

  func consumeStop() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let value = stopRequested
    stopRequested = false
    return value
  }

  func consumeReload() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let value = reloadRequested
    reloadRequested = false
    return value
  }

}

func observeSignal(_ number: Int32, flags: SignalFlags, handler: @escaping () -> Void)
  -> DispatchSourceSignal
{
  signal(number, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: number, queue: signalsQueue)
  source.setEventHandler(handler: handler)
  source.resume()
  return source
}
