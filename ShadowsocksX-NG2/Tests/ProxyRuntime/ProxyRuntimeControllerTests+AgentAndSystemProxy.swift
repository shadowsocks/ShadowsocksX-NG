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
      settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: false))

    await controller.setAgentEnabled(true)

    XCTAssertEqual(controller.state, .running, "无活动目标 agent 仍提供本地监听")
    XCTAssertEqual(agent.registerCount, 1, "开启意图驱动注册")
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
      settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: false))

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
    let settingsStore = InMemoryProxySettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), settingsStore: settingsStore,
      settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setAgentEnabled(false)
    XCTAssertEqual(settingsStore.saved?.agentEnabled, false, "关闭选择已持久化")

    // GUI 重启：agent 注册态残留、运行时文件残留，恢复快照携带关闭意图。
    agent.setStatus(.registered)
    try Data("stale contract".utf8).write(to: runtime.contract)
    try Data("99999".utf8).write(to: runtime.pidFile)
    let restarted = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      agentStatus: .registered,
      settingsStore: settingsStore,
      settingsRestore: RestoredProxySettings(
        settings: try XCTUnwrap(settingsStore.load()), unreadableError: nil))

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
            including: ProxySettings().proxyExceptionList))
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

    // 条件恢复：探测可达后，下一次收敛自动应用待应用意图。
    probe.setOutcomes([.reachable])
    try await controller.activate(seeded.server)
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

  func testDisableClearFailureIsPresentedAndObservationStillStops() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    systemProxy.clearError = SystemProxyError.commitFailed("busy")

    await controller.setSystemProxyEnabled(false)

    XCTAssertEqual(controller.systemProxyState, .clearFailed(.operation(.commitFailed)))
    XCTAssertFalse(systemProxyNetworkChangeMonitor.isObserving, "清理失败后也结束临时观察")
  }

  /// 系统代理意图持久化：GUI 重启后从恢复快照读回。
  func testSystemProxyIntentPersistsAcrossGUIRestart() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), settingsStore: settingsStore)
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    XCTAssertEqual(settingsStore.saved?.systemProxyEnabled, true)

    let restarted = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      agentStatus: .registered,
      settingsStore: settingsStore,
      settingsRestore: RestoredProxySettings(
        settings: try XCTUnwrap(settingsStore.load()), unreadableError: nil))
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
  func testAgentOffClearsSystemProxyBeforeStoppingListeningAndCascadesIntentOff() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let eventLog = ProxyRuntimeEventLog()
    agent.eventLog = eventLog
    systemProxy.eventLog = eventLog
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .applied)

    await controller.setAgentEnabled(false)

    XCTAssertEqual(
      eventLog.events,
      ["register", "apply", "clear", "unregister"],
      "先清理系统设置，再停止 agent 监听")
    XCTAssertEqual(controller.systemProxyState, .idle, "级联后意图关闭且清理完成")
    XCTAssertEqual(settingsStore.saved?.agentEnabled, false)
    XCTAssertEqual(settingsStore.saved?.systemProxyEnabled, false, "级联关闭一并持久化")

    // 重启 agent 不恢复系统代理意图。
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(systemProxy.applied.count, 1, "不再应用系统代理")
    XCTAssertEqual(controller.systemProxyState, .idle)
    XCTAssertFalse(systemProxyNetworkChangeMonitor.isObserving, "意图关闭不开网络观察")
  }

  /// 系统代理意图本就关闭时关闭 agent：不做任何系统设置操作。
  func testAgentOffWithSystemProxyIntentAlreadyOffSendsNoClear() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    await controller.setAgentEnabled(false)

    XCTAssertEqual(controller.state, .off)
    XCTAssertEqual(systemProxy.clearCount, 0, "未发生 on→off 迁移，不清理")
    XCTAssertEqual(controller.systemProxyState, .idle)
  }

  /// 级联持久化失败：迁移未被记录则不清理，系统设置
  /// 原样，意图保持待应用；agent 按用户要求停止。
  func testAgentOffCascadePersistenceFailureLeavesSettingsAndStopsAgent() async throws {
    // agent 关闭意图照常持久化；级联写（systemProxyEnabled=false）失败。
    final class CascadeFailingSettingsStore: ProxySettingsStoring {
      var saved: ProxySettings?
      func load() throws -> ProxySettings { saved ?? ProxySettings() }
      func save(_ settings: ProxySettings) throws {
        if !settings.systemProxyEnabled {
          throw ProxySettingsStoreError.corrupt(detail: "disk full")
        }
        saved = settings
      }
    }
    let seeded = try makeSeededCatalog()
    let settingsStore = CascadeFailingSettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .applied)

    await controller.setAgentEnabled(false)

    XCTAssertEqual(controller.state, .off, "agent 按用户要求停止")
    XCTAssertEqual(systemProxy.clearCount, 0, "未持久化的迁移不触发清理")
    XCTAssertEqual(settingsStore.saved?.systemProxyEnabled, true, "意图保持开启")
    XCTAssertEqual(controller.settings.systemProxyEnabled, true)
    XCTAssertEqual(controller.systemProxyState, .pending, "意图开启但 agent 已停止")
  }

  /// 特权 helper 待批准：意图保持待应用、系统设置不变，
  /// 置位批准路径；收敛被 helper 门禁挡下，不尝试写入。
  func testHelperApprovalRequiredKeepsIntentPendingAndOffersApprovalPath() async throws {
    let seeded = try makeSeededCatalog()
    systemProxyHelper.setStatus(.requiresApproval)
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    await controller.setSystemProxyEnabled(true)

    XCTAssertEqual(controller.systemProxyState, .pending, "意图保持待应用")
    XCTAssertTrue(controller.systemProxyApprovalRequired, "呈现批准路径")
    XCTAssertTrue(systemProxy.applied.isEmpty, "helper 不可用不写入")
    XCTAssertEqual(systemProxyNetworkChangeMonitor.isObserving, true, "意图开启照常观察")

    // 批准路径：打开登录项设置并重试收敛；批准达成后 applied。
    systemProxyHelper.setStatus(.approved)
    await controller.systemProxyObserver.openSystemProxyHelperApproval()

    XCTAssertEqual(controller.systemProxyState, .applied)
    XCTAssertFalse(controller.systemProxyApprovalRequired)
    XCTAssertEqual(systemProxyHelper.openApprovalPathCount, 1)
  }

  /// helper 未注册时显式开启即注册：注册成功走正常
  /// 收敛；注册失败保持待应用与批准路径。
  func testExplicitEnableRegistersHelperAndSurvivesRegistrationFailure() async throws {
    let seeded = try makeSeededCatalog()
    systemProxyHelper.setStatus(.notRegistered)
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    await controller.setSystemProxyEnabled(true)

    XCTAssertEqual(systemProxyHelper.registerCount, 1, "首次显式开启注册 helper")
    XCTAssertEqual(controller.systemProxyState, .applied)

    // 重新安装/注册丢失后的重试路径：注册失败也保持意图待应用。
    let secondSystemProxy = ProxyRuntimeFixture.FakeSystemProxy()
    systemProxyHelper.setStatus(.notRegistered)
    systemProxyHelper.setRegisterError(
      ProxySettingsStoreError.corrupt(detail: "SMError"))
    systemProxyHelper.statusAfterRegister = .notRegistered
    let second = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true),
      systemProxy: secondSystemProxy)
    try await second.activate(seeded.server)
    await second.setAgentEnabled(true)

    await second.setSystemProxyEnabled(false)
    await second.setSystemProxyEnabled(true)

    XCTAssertEqual(second.systemProxyState, .pending, "注册失败保持待应用")
    XCTAssertTrue(second.systemProxyApprovalRequired, "呈现批准路径")
    XCTAssertTrue(secondSystemProxy.applied.isEmpty, "注册失败不写入")
  }

  /// 清理失败：typed 呈现且无后台重试；观察在该次尝试后停止。
  func testDisableClearFailureIsPresentedWithoutDeferredRetry() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    systemProxy.clearError = SystemProxyError.helperUnavailable("helper gone")

    await controller.setSystemProxyEnabled(false)

    XCTAssertEqual(controller.systemProxyState, .clearFailed(.operation(.helperUnavailable)))
    XCTAssertFalse(systemProxyNetworkChangeMonitor.isObserving, "清理失败后也结束临时观察")
    XCTAssertEqual(systemProxy.clearCount, 1, "只请求一次清理，无后台重试")
  }

  func testEnabledSystemProxyInspectsAllPassiveChangesWithoutReapplying() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    XCTAssertEqual(systemProxy.applied.count, 1)
    XCTAssertTrue(systemProxyNetworkChangeMonitor.isObserving)

    systemProxyNetworkChangeMonitor.emit(.proxyConfiguration)
    await Task.yield()
    XCTAssertEqual(systemProxy.applied.count, 1, "代理配置变化不触发重写")

    systemProxyNetworkChangeMonitor.emit(.networkConfiguration)
    let reads = systemProxy.readCount
    await waitUntil(systemProxy.readCount > reads)
    XCTAssertEqual(systemProxy.applied.count, 1, "网络位置或服务变化只检查")

    systemProxyNetworkChangeMonitor.emit(.networkPath)
    let pathReads = systemProxy.readCount
    await waitUntil(systemProxy.readCount > pathReads)
    XCTAssertEqual(systemProxy.applied.count, 1, "网络路径变化只检查")
  }

  func testDisableCleanupRescansChangesThatArriveDuringCleanupThenStopsObservation() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    await controller.setSystemProxyEnabled(true)
    var emittedCleanupChange = false
    let monitor = systemProxyNetworkChangeMonitor!
    systemProxy.onClear = {
      guard !emittedCleanupChange else { return }
      emittedCleanupChange = true
      monitor.emit(.proxyConfiguration)
    }

    await controller.setSystemProxyEnabled(false)

    XCTAssertEqual(systemProxy.clearCount, 2, "清理期间代理变化触发第二次全量扫描")
    XCTAssertFalse(systemProxyNetworkChangeMonitor.isObserving, "关闭清理结束后停止监听")
    XCTAssertEqual(controller.systemProxyState, .idle)
  }

  /// 无效活动目标：清除目标且不悄悄回退；agent 继续以空服务器
  /// 列表监听；目标失效不清理系统设置，意图保持待应用。
  func testInvalidTargetOnCommitKeepsListeningAndHoldsSystemProxyIntent() async throws {
    let seeded = try makeSeededCatalog()
    try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: runtime.pidFile)
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .applied)

    // 删除活动目标 → 重展开失败 → 清除目标，agent 继续监听。
    var catalog = try CatalogFileStore(fileURL: catalogFileURL).load().catalog
    try catalog.remove(seeded.server)
    try CatalogFileStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))

    let committed = try CatalogFileStore(fileURL: catalogFileURL).load().catalog
    _ = await controller.catalogDidCommit(snapshot: committed)

    XCTAssertNil(controller.activeTargetID)
    XCTAssertNotNil(controller.lastActivationFailure, "点名原因独立呈现")
    XCTAssertEqual(controller.state, .running, "agent 保持监听")
    XCTAssertEqual(agent.unregisterCount, 0, "不注销 agent")
    let onDisk = try XCTUnwrap(RuntimeFileStore(fileURL: runtime.contract).loadDocument())
    XCTAssertTrue(onDisk.servers.isEmpty, "运行时以空服务器列表继续监听")
    XCTAssertEqual(systemProxy.clearCount, 1, "目标失效清除不可用入口")
    XCTAssertEqual(controller.systemProxyState, .paused, "清除成功后暂停并保留意图")
  }
  func testResyncWithInvalidActiveTargetClearsAndKeepsListening() async throws {
    _ = try makeSeededCatalog()
    try Data("garbage".utf8).write(to: runtime.contract)
    let missingTarget = NodeID(rawValue: "removed-target")
    try ActivationStateFileStore(fileURL: activationFileURL).save(activeTargetID: missingTarget)
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), agentStatus: .registered)

    await controller.resyncOnLaunch()

    XCTAssertEqual(controller.state, .running, "目标失效后 agent 继续监听")
    XCTAssertNil(controller.activeTargetID)
    let persisted = try ActivationStateFileStore(fileURL: activationFileURL).loadActiveTargetID()
    XCTAssertNil(persisted, "失效目标已清除")
    let onDisk = try XCTUnwrap(RuntimeFileStore(fileURL: runtime.contract).loadDocument())
    XCTAssertTrue(onDisk.servers.isEmpty, "以空服务器列表继续监听")
    XCTAssertNotNil(controller.lastActivationFailure)
    XCTAssertTrue(systemProxy.applied.isEmpty, "系统代理意图关闭，不写系统设置")
  }
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
      settings: ProxySettings(
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
