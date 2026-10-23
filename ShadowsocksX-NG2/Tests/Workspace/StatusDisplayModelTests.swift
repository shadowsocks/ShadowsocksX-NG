import Combine
import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 状态显示 debounce 呈现模型：代理服务与系统代理两个意图的呈现 payload
/// 从整体 snapshot 派生后经瞬态门控发布。断言用语义色调与结构（detail 空
/// 非空、hint 变化），不断言具体本地化文案。
@MainActor
struct StatusDisplayModelTests {
  private let runningFacts = ProxyRuntimeFacts(status: .running, isOn: true)

  /// 快速模式切换：applying 短命即回 applied，「应用中」整段不得上屏。
  @Test func fastModeSwitchNeverShowsTransientSystemProxyState() async {
    let snapshots = CurrentValueSubject<ProxyControlSnapshot, Never>(
      makeSnapshot(systemProxyApplication: .applied))
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    let model = StatusDisplayModel(
      snapshots: snapshots, interval: 0.4, now: { now },
      sleep: { delay in await clock.sleep(delay) })
    #expect(model.systemProxy.row.tone == .positive)
    let armed = clock.armNextCall()
    snapshots.send(makeSnapshot(systemProxyApplication: .applying))
    let transientTask = model.scheduledSystemProxyDisplayTask
    #expect(model.systemProxy.row.tone == .positive, "瞬态「应用中」不得立即上屏")
    snapshots.send(makeSnapshot(systemProxyApplication: .applied))
    #expect(model.systemProxy.row.tone == .positive, "快路径完成后瞬态从未上屏")
    armed.release.release()
    await transientTask?.value
    #expect(clock.delays == [0.4])
  }

  /// applying 持续存在时（真正慢的写入）延迟后要上屏，不能永远藏住。
  @Test func persistentSystemProxyTransientDisplaysAfterDelay() async {
    let snapshots = CurrentValueSubject<ProxyControlSnapshot, Never>(
      makeSnapshot(systemProxyApplication: .applied))
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    let model = StatusDisplayModel(
      snapshots: snapshots, interval: 0.4, now: { now },
      sleep: { delay in await clock.sleep(delay) })
    let armed = clock.armNextCall()
    snapshots.send(makeSnapshot(systemProxyApplication: .applying))
    let task = model.scheduledSystemProxyDisplayTask
    await armed.entered.wait()
    #expect(model.systemProxy.row.tone == .positive)
    now = 0.4
    armed.release.release()
    await task?.value
    #expect(model.systemProxy.row.tone == .attention)
  }

  /// pending（待应用/待批准）是 resting 态：立即可见，不经门控。
  @Test func pendingApplicationStateIsNotGated() async {
    let snapshots = CurrentValueSubject<ProxyControlSnapshot, Never>(
      makeSnapshot(systemProxyApplication: .applied))
    let clock = SleepGateRecorder()
    let model = StatusDisplayModel(
      snapshots: snapshots, interval: 0.4, now: { 0 },
      sleep: { delay in await clock.sleep(delay) })
    let pending = makeSnapshot(systemProxyApplication: .pending)
    snapshots.send(pending)
    #expect(
      StatusDisplayModel.systemProxyStatus(from: pending).row.tone == .attention,
      "派生口径：待应用 = attention")
    #expect(model.systemProxy.row.tone == .attention)
    #expect(clock.delays.isEmpty)
    #expect(model.scheduledSystemProxyDisplayTask == nil)
  }

  /// 代理服务侧瞬态 = 启动中：同样延迟上屏。
  @Test func agentStartingStateIsGated() async {
    let snapshots = CurrentValueSubject<ProxyControlSnapshot, Never>(
      makeSnapshot(systemProxyApplication: .idle))
    let clock = SleepGateRecorder()
    var now: TimeInterval = 0
    let model = StatusDisplayModel(
      snapshots: snapshots, interval: 0.4, now: { now },
      sleep: { delay in await clock.sleep(delay) })
    let armed = clock.armNextCall()
    snapshots.send(
      makeSnapshot(
        facts: ProxyRuntimeFacts(status: .starting, isOn: true),
        systemProxyApplication: .idle))
    let task = model.scheduledAgentDisplayTask
    #expect(model.agent.row.tone == .positive, "运行中保持可见")
    await armed.entered.wait()
    now = 0.4
    armed.release.release()
    await task?.value
    #expect(model.agent.row.tone == .neutral, "启动中延迟后上屏")
  }

  /// 点名原因不随 payload 抑制：无法检查（面板与首页都渲染）与已暂停
  /// （payload 携带暂停事实，首页据此抑制、面板渲染作暂停说明）并存。
  @Test func pausedStateCarriesDetailAndPauseFlag() async {
    let snapshots = CurrentValueSubject<ProxyControlSnapshot, Never>(
      makeSnapshot(systemProxyApplication: .applied))
    let model = StatusDisplayModel(
      snapshots: snapshots, interval: 0.4, now: { 0 }, sleep: { _ in })
    snapshots.send(makeSnapshot(systemProxyApplication: .unreadable(.unknown)))
    #expect(model.systemProxy.detail != nil, "无法检查的点名原因立即可见")
    #expect(model.systemProxy.row.tone == .failure)
    #expect(!model.systemProxy.isPaused)
    snapshots.send(makeSnapshot(systemProxyApplication: .paused))
    #expect(model.systemProxy.detail != nil, "暂停说明保留在 detail（面板渲染）")
    #expect(model.systemProxy.isPaused, "首页据此抑制 detail（hint 已是暂停说明）")
    #expect(model.systemProxy.row.tone == .attention)
  }

  /// hint 文案随系统代理流派生：批准阻塞提示立即生效（稳定态）。
  @Test func approvalRequirementChangesHintImmediately() async {
    let snapshots = CurrentValueSubject<ProxyControlSnapshot, Never>(
      makeSnapshot(systemProxyApplication: .idle))
    let model = StatusDisplayModel(
      snapshots: snapshots, interval: 0.4, now: { 0 }, sleep: { _ in })
    let idleHint = model.systemProxy.hint
    snapshots.send(makeSnapshot(systemProxyApplication: .idle, approvalRequired: true))
    #expect(model.systemProxy.hint != idleHint)
    #expect(model.systemProxy.row.tone == .neutral)
  }

  /// 从运行时事实构造最小 snapshot（其余字段与本组用例无关；与
  /// StatusCardModelTests 的夹具同形状）。
  private func makeSnapshot(
    facts: ProxyRuntimeFacts = ProxyRuntimeFacts(status: .running, isOn: true),
    systemProxyApplication: SystemProxyApplicationFacts,
    approvalRequired: Bool = false
  ) -> ProxyControlSnapshot {
    ProxyControlSnapshot(
      runtime: facts,
      agentIntentEnabled: true,
      activationFailure: nil,
      systemProxyIntentEnabled: false,
      systemProxyApplication: systemProxyApplication,
      systemProxyApprovalRequired: approvalRequired,
      proxyMode: .rule,
      ruleDefaultAction: .proxyWhenUnmatched,
      availableModes: ProxyMode.availableModes,
      activeTarget: nil,
      skippedInvalidServerCount: 0,
      httpExport: HTTPExportCapability(
        copyableLine:
          "export http_proxy=http://127.0.0.1:11087;export https_proxy=http://127.0.0.1:11087;"),
      commandAddressPicker: TerminalCommandAddressPicker(
        isVisible: false,
        candidates: [
          TerminalCommandAddress(bsdName: "lo0", address: "127.0.0.1", displayName: "lo0")
        ],
        selected: TerminalCommandAddress(bsdName: "lo0", address: "127.0.0.1", displayName: "lo0")),
      terminalProxyEnvironmentCommands: TerminalProxyEnvironmentCommands(
        listen: RuntimeListenFacts(listen: ProxyListeningConfiguration()),
        commandAddress: TerminalCommandAddress(
          bsdName: "lo0", address: "127.0.0.1", displayName: "lo0")))
  }
}
