import Combine
import XCTest

@testable import ShadowsocksX_NG2

/// 全局模式以 ACL 实现：proxy_all + 固定本地绕过；无活动服务器
/// 时 agent 仍监听、系统代理保持待应用；ACL 变化完整重启，失败保留最新意图。
final class ProxyRuntimeGlobalModeTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  func testGlobalModeDeploysProxyAllACLAndProjectsSOCKSProxyWithFixedExceptions() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.systemProxyState, .applied)
    let unregisterCount = agent.unregisterCount
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)

    await controller.setProxyMode(.global)

    XCTAssertEqual(controller.proxyMode, .global)
    XCTAssertEqual(controller.settings.preferredMode, .global)
    XCTAssertEqual(settingsStore.saved?.preferredMode, .global)
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(
      agent.unregisterCount, unregisterCount + 1, "ACL 变化触发完整 agent 重启")
    let document = try XCTUnwrap(runtimeStore.loadDocument())
    XCTAssertEqual(document.aclRuntime?.summary, "global")
    let expectedACL = ProxyACLDocument.global(at: runtimeStore.aclFileURL)
    XCTAssertTrue(expectedACL.content.hasPrefix("[proxy_all]\n[bypass_list]\n"))
    XCTAssertEqual(
      try Data(contentsOf: runtimeStore.aclFileURL),
      Data(expectedACL.content.utf8),
      "链接解析后的内容是 global 变体")
    XCTAssertEqual(
      systemProxy.applied.last?.socks,
      .init(host: "127.0.0.1", port: ActivationFixture.listen.socksPort))
    XCTAssertEqual(
      systemProxy.applied.last?.http,
      .init(host: "127.0.0.1", port: ActivationFixture.listen.httpPort))
    XCTAssertTrue(
      Set(FixedLocalProxyRanges.systemProxyExceptions).isSubset(
        of: Set(systemProxy.applied.last?.exceptions ?? [])),
      "系统例外包含固定本地范围")
    XCTAssertEqual(controller.systemProxyState, .applied)
  }

  func testGlobalModeWithoutServerKeepsListeningAndPendingUntilTargetRecovers() async throws {
    // 目录先播种、控制器再创建：bootstrap 快照读取器持有已提交目录，但尚无
    // 活动目标——正是「全局模式 + 无可用出口」的起点。
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    await controller.resyncOnLaunch()
    XCTAssertEqual(controller.state, .running, "无活动目标时 agent 仍监听")
    XCTAssertNil(controller.activeTargetID)
    let unregisterCount = agent.unregisterCount

    await controller.setProxyMode(.global)

    XCTAssertEqual(controller.proxyMode, .global)
    XCTAssertEqual(controller.state, .running, "全局模式空服务器列表仍提供本地监听")
    XCTAssertEqual(
      agent.unregisterCount, unregisterCount + 1, "ACL 变化触发完整 agent 重启")
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let document = try XCTUnwrap(runtimeStore.loadDocument())
    XCTAssertTrue(document.servers.isEmpty, "无活动目标时服务器列表为空")
    XCTAssertEqual(document.aclRuntime?.summary, "global")
    XCTAssertEqual(
      controller.systemProxyState, .paused,
      "无可用代理出口时系统代理意图保持待应用")
    XCTAssertTrue(systemProxy.applied.isEmpty, "不得把系统代理指向无出口入口")

    // 服务器有效且端点健康后自动应用已开启的系统代理意图。
    try await controller.activate(seeded.server)

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(
      controller.systemProxyState, .applied,
      "服务器有效且健康后自动收敛待应用意图")
    XCTAssertEqual(
      systemProxy.applied.last?.socks,
      .init(host: "127.0.0.1", port: ActivationFixture.listen.socksPort))
    XCTAssertEqual(
      systemProxy.applied.last?.http,
      .init(host: "127.0.0.1", port: ActivationFixture.listen.httpPort))
  }

  func testFailedGlobalInstanceKeepsNewModeAndStopsService() async throws {
    let seeded = try makeSeededCatalog()
    let settingsStore = InMemoryProxySettingsStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsStore: settingsStore,
      settings: ProxySettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true),
      launchHealthTimeoutSeconds: 0.05)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.systemProxyState, .applied)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let previousDocument = try XCTUnwrap(runtimeStore.loadDocument())
    let previousApplicationCount = systemProxy.applied.count

    agent.onRegister = { [runtimeStore, previousDocument] in
      guard let requested = runtimeStore.loadDocument() else { return }
      let accepted = requested.aclRuntime == nil ? requested : previousDocument
      try? runtimeStore.writeRuntimeReceipt(for: accepted, processID: 42)
    }

    await controller.setProxyMode(.global)

    XCTAssertEqual(controller.proxyMode, .global)
    XCTAssertEqual(controller.settings.preferredMode, .global)
    XCTAssertEqual(settingsStore.saved?.preferredMode, .global)
    XCTAssertEqual(runtimeStore.loadDocument()?.aclRuntime?.summary, "global")
    XCTAssertEqual(controller.state, .serviceFailed(.agent))
    XCTAssertNotNil(runtimeStore.readFailure())
    XCTAssertEqual(systemProxy.applied.count, previousApplicationCount)
    XCTAssertGreaterThan(systemProxy.clearCount, 0)
  }
}
