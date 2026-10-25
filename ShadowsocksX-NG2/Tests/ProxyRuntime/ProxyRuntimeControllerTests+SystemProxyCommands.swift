import Combine
import XCTest

@testable import ShadowsocksX_NG2

extension ProxyRuntimeAgentAndSystemProxyTests {
  func testAgentOffClearsSystemProxyBeforeStoppingListeningAndCascadesIntentOff() async throws {
    let seeded = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let eventLog = ProxyRuntimeEventLog()
    agent.eventLog = eventLog
    systemProxy.eventLog = eventLog
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .applied)

    await controller.setAgentEnabled(false)

    XCTAssertEqual(controller.state, .off, "关闭级联后运行时停止")
    XCTAssertEqual(
      eventLog.events,
      ["register", "apply", "clear", "unregister"],
      "先清理系统设置，再停止 agent 监听")
    XCTAssertEqual(controller.systemProxyState, .idle, "级联后意图关闭且清理完成")
    XCTAssertEqual(controller.controlPreferences.agentEnabled, false)
    XCTAssertEqual(controller.controlPreferences.systemProxyEnabled, false, "级联关闭一并持久化")

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
      ProxyListeningStoreError.corrupt(detail: "SMError"))
    systemProxyHelper.statusAfterRegister = .notRegistered
    let second = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(
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
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.systemProxyState, .applied)

    // 删除活动目标 → 重展开失败 → 清除目标，agent 继续监听。
    var catalog = try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
    try catalog.remove(seeded.server)
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))

    let committed = try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
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
