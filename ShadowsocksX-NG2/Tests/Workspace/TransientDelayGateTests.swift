import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 瞬态门控裁决表：稳定值立即可见、瞬态值延迟上屏、短命瞬态被吞、
/// 已上屏瞬态保持最短时长。时间经注入的 now/sleep 虚拟化，不真实等待。
@MainActor
struct TransientDelayGateTests {
  @Test func firstValueDisplaysImmediatelyWithoutDelay() {
    var displayed: [String] = []
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { 0 },
      sleep: { _ in })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    #expect(displayed == ["applied"])
  }

  @Test func transientValueDisplaysOnlyAfterDelayInterval() async {
    var now: TimeInterval = 0
    var displayed: [String] = []
    var delays: [TimeInterval] = []
    let sleepEntered = AsyncGate()
    let sleepRelease = AsyncGate()
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { now },
      sleep: { delay in
        delays.append(delay)
        sleepEntered.release()
        await sleepRelease.wait()
      })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    gate.update("applying", isTransient: true)
    let task = gate.scheduledDisplayTask
    await sleepEntered.wait()
    #expect(delays == [0.4])
    #expect(displayed == ["applied"])
    now = 0.4
    sleepRelease.release()
    await task?.value
    #expect(displayed == ["applied", "applying"])
  }

  @Test func shortLivedTransientIsSupersededAndNeverDisplayed() async {
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    var displayed: [String] = []
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { now },
      sleep: { delay in await clock.sleep(delay) })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    let transientSleep = clock.armNextCall()
    gate.update("applying", isTransient: true)
    let transientTask = gate.scheduledDisplayTask
    await transientSleep.entered.wait()
    now = 0.2
    gate.update("failed", isTransient: false)
    #expect(displayed == ["applied", "failed"])
    transientSleep.release.release()
    await transientTask?.value
    #expect(displayed == ["applied", "failed"])
  }

  @Test func displayedTransientHoldsForMinimumInterval() async {
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    var displayed: [String] = []
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { now },
      sleep: { delay in await clock.sleep(delay) })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    let transientSleep = clock.armNextCall()
    gate.update("applying", isTransient: true)
    let transientTask = gate.scheduledDisplayTask
    await transientSleep.entered.wait()
    now = 0.4
    transientSleep.release.release()
    await transientTask?.value
    #expect(displayed == ["applied", "applying"])
    let heldSleep = clock.armNextCall()
    gate.update("failed", isTransient: false)
    let heldTask = gate.scheduledDisplayTask
    #expect(displayed == ["applied", "applying"])
    await heldSleep.entered.wait()
    #expect(clock.delays == [0.4, 0.4])
    now = 0.8
    heldSleep.release.release()
    await heldTask?.value
    #expect(displayed == ["applied", "applying", "failed"])
  }

  @Test func transientAfterDisplayedTransientWaitsForDelayAndHold() async {
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    var displayed: [String] = []
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { now },
      sleep: { delay in await clock.sleep(delay) })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    let applyingSleep = clock.armNextCall()
    gate.update("applying", isTransient: true)
    let applyingTask = gate.scheduledDisplayTask
    await applyingSleep.entered.wait()
    now = 0.4
    applyingSleep.release.release()
    await applyingTask?.value
    #expect(displayed == ["applied", "applying"])
    let repairingSleep = clock.armNextCall()
    now = 0.5
    gate.update("repairing", isTransient: true)
    let repairingTask = gate.scheduledDisplayTask
    #expect(displayed == ["applied", "applying"])
    await repairingSleep.entered.wait()
    #expect(clock.delays == [0.4, 0.4])
    now = 0.9
    repairingSleep.release.release()
    await repairingTask?.value
    #expect(displayed == ["applied", "applying", "repairing"])
  }

  @Test func duplicatePendingPayloadKeepsOriginalSchedule() async {
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    var displayed: [String] = []
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { now },
      sleep: { delay in await clock.sleep(delay) })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    let applyingSleep = clock.armNextCall()
    gate.update("applying", isTransient: true)
    let applyingTask = gate.scheduledDisplayTask
    await applyingSleep.entered.wait()
    now = 0.1
    gate.update("applying", isTransient: true)
    now = 0.4
    applyingSleep.release.release()
    await applyingTask?.value
    #expect(displayed == ["applied", "applying"])
    #expect(clock.delays == [0.4])
  }

  @Test func valueEqualToDisplayedCancelsPendingDisplay() async {
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    var displayed: [String] = []
    let gate = TransientDelayGate<String>(
      interval: 0.4,
      now: { now },
      sleep: { delay in await clock.sleep(delay) })
    gate.display = { displayed.append($0) }
    gate.update("applied", isTransient: false)
    let applyingSleep = clock.armNextCall()
    gate.update("applying", isTransient: true)
    let applyingTask = gate.scheduledDisplayTask
    await applyingSleep.entered.wait()
    gate.update("applied", isTransient: false)
    #expect(displayed == ["applied"])
    applyingSleep.release.release()
    await applyingTask?.value
    #expect(displayed == ["applied"])
    #expect(clock.delays == [0.4])
  }
}
