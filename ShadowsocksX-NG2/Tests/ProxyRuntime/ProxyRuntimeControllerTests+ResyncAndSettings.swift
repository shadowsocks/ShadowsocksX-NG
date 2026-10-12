import Combine
import XCTest

@testable import ShadowsocksX_NG2

final class ProxyRuntimeResyncAndSettingsTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  // MARK: GUI 重启重同步

  func testResyncWithRegisteredAgentAndMatchingContractSkipsRewrite() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let enabledSettings = ProxySettings(listen: ActivationFixture.listen, agentEnabled: true)
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), agentStatus: .notRegistered,
      settingsStore: settingsStore, settings: enabledSettings)
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertTrue(agent.registerCount >= 1)
    let contractMtime =
      try FileManager.default.attributesOfItem(
        atPath: runtime.contract.path
      )[.modificationDate] as? Date

    // 模拟 GUI 重启：全新控制器，agent 已注册、wrapper pid 存活（本测试进程）。
    try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: runtime.pidFile)
    let restarted = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), agentStatus: .registered,
      settingsStore: settingsStore, settings: enabledSettings)

    await restarted.resyncOnLaunch()

    XCTAssertEqual(restarted.state, .running)
    XCTAssertEqual(agent.registerCount, 1, "已注册不再重复注册")
    let afterResyncMtime =
      try FileManager.default.attributesOfItem(
        atPath: runtime.contract.path
      )[.modificationDate] as? Date
    XCTAssertEqual(contractMtime, afterResyncMtime, "相同契约内容跳过写入（幂等）")
    XCTAssertTrue(
      signals.signalsSent.filter { $0.signal != 0 }.isEmpty,
      "内容一致不需要 reload 信号")
  }

  func testLegacyImportBoundaryStopsRuntimeWithoutRestoringSystemProxy() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    var importedSettings = ProxySettings()
    importedSettings.preferredMode = .global
    settingsStore.saved = importedSettings
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      systemProxy: systemProxy)

    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    XCTAssertEqual(controller.state, .running)

    await controller.legacyImportDidCommit()

    XCTAssertEqual(controller.state, .off)
    XCTAssertEqual(controller.settings, importedSettings)
    XCTAssertEqual(controller.activeTargetID, seeded.server)
    XCTAssertEqual(systemProxy.clearCount, 0, "Legacy 导入不能写入或清理系统代理")
    XCTAssertTrue(systemProxy.applied.isEmpty, "导入边界不应重新应用系统代理")
  }

  func testUpdatingSettingsPersistsAndReactivatesTheRuntimeContract() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))

    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    var next = controller.settings
    next.listen.httpPort = 2088
    next.proxyExceptions = "localhost, 127.0.0.1"
    try await controller.updateSettings(next)

    let document = try XCTUnwrap(RuntimeFileStore(fileURL: runtime.contract).loadDocument())
    XCTAssertEqual(controller.settings, next)
    XCTAssertEqual(settingsStore.saved, next)
    XCTAssertEqual(document.httpPort, 2088)
    XCTAssertEqual(
      systemProxy.applied.last?.exceptions,
      FixedLocalProxyRanges.systemProxyExceptions(including: ["localhost", "127.0.0.1"]),
      "系统代理意图开启时随设置更新重新应用")
  }
}
