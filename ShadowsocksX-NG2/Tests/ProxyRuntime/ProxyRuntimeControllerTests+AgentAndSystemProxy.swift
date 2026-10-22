import Combine
import XCTest

@testable import ShadowsocksX_NG2

/// Agent 开关与系统代理开关的拆分语义：与既有开关用例同文件
/// 追加（Xcode 测试扫描限制），扩展持有独立用例组。
final class ProxyRuntimeAgentAndSystemProxyTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  func testEnableWithoutActiveTargetDeploysEmptyServerListening() async throws {
    _ = try makeSeededCatalog()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))

    await controller.setAgentEnabled(true)

    XCTAssertEqual(controller.state, .running, "无活动目标 agent 仍提供本地监听")
    XCTAssertEqual(agent.registerCount, 1, "开启意图驱动注册")
    XCTAssertEqual(controller.controlPreferences.agentEnabled, true, "开启意图随快照持久化")
    let onDisk = try XCTUnwrap(
      RuntimeFileStore(fileURL: runtime.contract).loadDocument())
    XCTAssertTrue(onDisk.servers.isEmpty, "无活动目标以空服务器列表监听")
    XCTAssertEqual(onDisk.socksPort, ActivationFixture.listen.socksPort)
    XCTAssertTrue(systemProxy.applied.isEmpty, "系统代理意图关闭，不写系统设置")
    XCTAssertEqual(controller.systemProxyState, .idle)
  }
  /// 首次运行默认语义（ADR-0011）：全新用户没有服务器配置，GUI 重同步不
  /// 注册、不拉起 Agent；启动永不清理系统代理设置。
  func testFirstRunResyncKeepsAgentOffWithoutSystemProxy() async throws {
    _ = try makeSeededCatalog()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: false))

    await controller.resyncOnLaunch()

    XCTAssertEqual(controller.state, .off)
    XCTAssertEqual(agent.registerCount, 0, "首次运行默认不启动 agent")
    XCTAssertFalse(controller.settings.agentEnabled)
    XCTAssertEqual(systemProxy.clearCount, 0, "启动时意图关闭不清理系统设置")
    XCTAssertFalse(systemProxyNetworkChangeMonitor.isObserving, "无观察进行")
    XCTAssertNil(
      RuntimeFileStore(fileURL: runtime.contract).loadDocument(),
      "Agent 未启用时不写运行时契约")
    XCTAssertEqual(controller.systemProxyState, .idle)
    XCTAssertTrue(systemProxy.applied.isEmpty)
  }
  /// 显式关闭 agent 的选择持久化：GUI 重启（全新控制器 + 恢复
  /// 快照 + 注册态残留）后仍收敛到关闭。
  func testExplicitAgentOffPersistsAcrossGUIRestart() async throws {
    let seeded = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setAgentEnabled(false)
    XCTAssertEqual(controller.controlPreferences.agentEnabled, false, "关闭选择已持久化")

    // GUI 重启：agent 注册态残留、运行时文件残留，恢复快照携带关闭意图。
    agent.setStatus(.registered)
    try Data("stale contract".utf8).write(to: runtime.contract)
    try Data("99999".utf8).write(to: runtime.pidFile)
    let restarted = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      agentStatus: .registered,
      listeningStore: listeningStore,
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(
          listen: ActivationFixture.listen, preferences: controlPreferences), unreadableError: nil))

    await restarted.resyncOnLaunch()

    XCTAssertEqual(restarted.state, .off, "显式关闭的选择在 GUI 重启后仍生效")
    XCTAssertEqual(agent.registerCount, 1, "重启后的关闭路径不得重新注册")
    XCTAssertEqual(agent.unregisterCount, 2, "注册态残留按停止协议再次收敛")
    XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.contract.path))
  }
  func testSystemProxyIntentAppliesOnlyAfterHealthGateAndExitAvailable() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())

    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)

    XCTAssertEqual(controller.systemProxyState, .applied)
    XCTAssertEqual(
      systemProxy.applied,
      [
        SystemProxyConfiguration(
          socks: .init(host: "127.0.0.1", port: ActivationFixture.listen.socksPort),
          http: .init(host: "127.0.0.1", port: ActivationFixture.listen.httpPort),
          https: .init(host: "127.0.0.1", port: ActivationFixture.listen.httpPort),
          exceptions: FixedLocalProxyRanges.systemProxyExceptions(
            including: ProxyRuntimeSettings().proxyExceptionList))
      ],
      "系统代理只在本地端点健康且存在可用出口后写入")
  }
  /// 端点不健康时系统代理意图保持待应用；条件恢复后随下次收敛自动应用，
  /// 无需重新开关系统代理（「条件恢复后自动收敛」）。
  func testSystemProxyIntentStaysPendingUntilEndpointsRecover() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.refusing()
    let controller = makeController(probe: probe)

    // 激活即按默认意图部署：端点持续不可达 → 启动失败（走满注入的短健康窗）。
    try await controller.activate(seeded.server)
    if case .launchFailed = controller.state {
    } else {
      XCTFail("端点不可达应呈现启动失败，实际 \(controller.state)")
    }
    await controller.setSystemProxyEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .paused, "失效时清除并保留意图")
    XCTAssertTrue(systemProxy.applied.isEmpty, "端点不健康不得写系统代理")

    // 条件恢复后由用户显式重试；普通收敛不得重试已确认失败。
    probe.setOutcomes([.reachable])
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(controller.systemProxyState, .applied, "恢复后自动收敛待应用意图")
    XCTAssertEqual(systemProxy.applied.count, 1)
  }
  /// 关闭系统代理：on→off 意图迁移触发一次无条件清理；本地监听
  /// 与 agent 注册态不受影响。
  func testSystemProxyOffClearsAllSettingsAndKeepsListening() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .applied)

    await controller.setSystemProxyEnabled(false)

    XCTAssertEqual(controller.systemProxyState, .idle)
    XCTAssertEqual(systemProxy.clearCount, 1)
    XCTAssertEqual(controller.state, .running, "本地监听不受系统代理开关影响")
    XCTAssertEqual(agent.unregisterCount, 0, "不注销 agent")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: runtime.contract.path), "运行时契约保留")
  }

  /// 系统代理意图持久化：GUI 重启后从恢复快照读回。
  func testSystemProxyIntentPersistsAcrossGUIRestart() async throws {
    let seeded = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), listeningStore: listeningStore)
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    XCTAssertEqual(controller.controlPreferences.systemProxyEnabled, true)

    let restarted = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      agentStatus: .registered,
      listeningStore: listeningStore,
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(
          listen: ActivationFixture.listen, preferences: controlPreferences), unreadableError: nil))
    XCTAssertTrue(restarted.systemProxyIntentEnabled)

    await restarted.resyncOnLaunch()

    XCTAssertEqual(restarted.systemProxyState, .applied, "启动时先重应用当前网络位置")
    XCTAssertTrue(systemProxyNetworkChangeMonitor.isObserving, "重同步完成后开始网络观察")
  }
  /// 系统代理写入错误以 typed fact 呈现，agent 继续运行。
  func testSystemProxyApplyFailureSurfacesTypedFailureAndKeepsAgentRunning() async throws {
    let seeded = try makeSeededCatalog()
    systemProxy.applyError = SystemProxyError.applyFailed("write failed")
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    await controller.setSystemProxyEnabled(true)

    XCTAssertEqual(
      controller.systemProxyState, .failed(.operation(.applyFailed)), "写入错误以 typed 呈现")
    XCTAssertEqual(controller.state, .running, "agent 不受系统代理失败影响")
    XCTAssertTrue(systemProxy.applied.isEmpty)
  }
  /// 关闭 agent 的级联：系统代理意图仍开启时一并持久化为关闭，
  /// 先请求清理、再停止监听；之后重启 agent 不会恢复系统代理意图。
}

extension ProxyRuntimeAgentAndSystemProxyTests {
  /// 意图已开启时的开启命令是失败态的显式重试入口：无需先关再开。
  func testAgentEnableCommandRetriesConvergenceWhileIntentAlreadyOn() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.refusing()
    let controller = makeController(probe: probe)

    // 激活即按默认意图部署：端点不可达 → 启动失败（走满注入的短健康窗）。
    try await controller.activate(seeded.server)
    if case .launchFailed = controller.state {
    } else {
      XCTFail("端点不可达应呈现启动失败，实际 \(controller.state)")
    }

    probe.setOutcomes([.reachable])
    await controller.setAgentEnabled(true)

    XCTAssertEqual(controller.state, .running, "意图已开启时开启命令重走收敛")
    XCTAssertEqual(controller.systemProxyState, .idle)
  }

  /// 等值零写入路径：seam 返回 unchanged 时仍呈现 applied，并
  /// 发一条 GUI 事件行供诊断日志回答「这次为何没有授权弹窗」。
  func testUnchangedSystemProxyValuesStayAppliedAndEmitEventLine() async throws {
    let seeded = try makeSeededCatalog()
    systemProxy.applyOutcome = .unchanged
    let recorder = RuntimeLogRecorder()
    RuntimeLog.setSink(recorder)
    defer { RuntimeLog.setSink(nil) }
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    XCTAssertEqual(controller.systemProxyState, .applied, "unchanged 仍视为已应用")
    XCTAssertGreaterThanOrEqual(
      systemProxy.applied.count, 1, "收敛调用照常发生，跳过发生在 seam 内")
    XCTAssertTrue(
      recorder.recorded.contains(.systemProxyUnchanged),
      "跳过路径发事件行，实际 \(recorder.recorded)")
  }

  /// LaunchDaemon 清单漂移：launchd 沿用注册提交时的 job
  /// 定义快照，app 更新改了清单后须注销重注才生效。已批准注册仅在清单指纹
  /// 与注册时不一致时重注（审批与签名绑定，不重弹授权）；首次注册成功即记录
  /// 指纹，指纹一致不动作。
  func testHelperRegistrationRefreshesOnlyOnPlistDrift() async throws {
    let defaults = UserDefaults.standard
    let stampKey = SystemProxyHelperRegistrationStamp.defaultsKey
    defer { defaults.removeObject(forKey: stampKey) }
    defaults.removeObject(forKey: stampKey)

    let seeded = try makeSeededCatalog()
    systemProxyHelper.setStatus(.notRegistered)
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)

    let stampAfterRegister = try XCTUnwrap(
      defaults.string(forKey: stampKey), "注册成功应记录 LaunchDaemon 清单指纹")
    let registerCountAfterEnable = systemProxyHelper.registerCount
    let unregisterCountAfterEnable = systemProxyHelper.unregisterCount

    // 指纹一致：后续收敛不注销重注。
    await controller.systemProxyObserver.convergeSystemProxy()
    XCTAssertEqual(systemProxyHelper.registerCount, registerCountAfterEnable, "指纹一致不重注")
    XCTAssertEqual(systemProxyHelper.unregisterCount, unregisterCountAfterEnable)
    XCTAssertEqual(controller.systemProxyState, .applied)

    // 指纹漂移（模拟 app 更新改了清单）：注销重注一次并更新指纹。
    defaults.set("drifted-stamp", forKey: stampKey)
    await controller.systemProxyObserver.convergeSystemProxy()
    XCTAssertEqual(systemProxyHelper.unregisterCount, unregisterCountAfterEnable + 1, "漂移触发重注")
    XCTAssertEqual(systemProxyHelper.registerCount, registerCountAfterEnable + 1)
    XCTAssertEqual(defaults.string(forKey: stampKey), stampAfterRegister, "重注后记录当前清单指纹")
    XCTAssertEqual(controller.systemProxyState, .applied, "重注后照常收敛应用")
  }
}

/// 测试专用事件接收缝。
private final class RuntimeLogRecorder: RuntimeEventSink, @unchecked Sendable {
  private let lock = NSLock()
  private var events: [RuntimeLogEvent] = []

  var recorded: [RuntimeLogEvent] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }

  func append(event: RuntimeLogEvent, timestamp: Date) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }
}
