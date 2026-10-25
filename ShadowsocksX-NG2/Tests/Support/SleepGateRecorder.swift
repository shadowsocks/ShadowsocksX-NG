import Foundation

/// 顺序虚拟 sleep 记录器：调用前先 `armNextCall()` 预约一对门闩，下一次
/// sleep 记录延迟、报到后挂起在预约门闩上；测试据此按调用序推进虚拟时钟，
/// 不轮询、不真实等待。
@MainActor
final class SleepGateRecorder {
  private(set) var delays: [TimeInterval] = []
  private var armedEntered: AsyncGate?
  private var armedRelease: AsyncGate?

  func sleep(_ delay: TimeInterval) async {
    delays.append(delay)
    let entered = armedEntered ?? AsyncGate()
    let release = armedRelease ?? AsyncGate()
    armedEntered = nil
    armedRelease = nil
    entered.release()
    await release.wait()
  }

  func armNextCall() -> (entered: AsyncGate, release: AsyncGate) {
    let pair = (entered: AsyncGate(), release: AsyncGate())
    armedEntered = pair.entered
    armedRelease = pair.release
    return pair
  }
}
