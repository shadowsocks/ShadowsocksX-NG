import Combine
import XCTest

@testable import ShadowsocksX_NG2

final class ProxyRuntimeModeCommandTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  func testHealthyModeSwitchKeepsRunningWithoutProbingPorts() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let controller = makeController(probe: probe)
    try await controller.activate(seeded.server)
    try Data("42".utf8).write(to: runtime.pidFile)
    let callsBefore = probe.callCount
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    var statesAtReload: [ProxyRuntimeController.AgentRunState] = []
    signals.reloadReceipt = {
      statesAtReload.append(controller.state)
      try? runtimeStore.writePublishedRuntimeReceipt(processID: 42)
    }

    await controller.setProxyMode(.direct)
    await controller.setProxyMode(.global)
    await controller.setProxyMode(.rule)

    XCTAssertEqual(statesAtReload, [.running, .running, .running])
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(probe.callCount, callsBefore, "热重载不得重新探测未变化的监听端口")
  }

  func testACLReloadWithReplacementChildStillProbesListeners() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let controller = makeController(probe: probe, processIsAlive: { [42, 43].contains($0) })
    try await controller.activate(seeded.server)
    try Data("42".utf8).write(to: runtime.pidFile)
    let callsBefore = probe.callCount
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    signals.reloadReceipt = { try? runtimeStore.writePublishedRuntimeReceipt(processID: 43) }

    await controller.setProxyMode(.direct)

    XCTAssertEqual(controller.state, .running)
    XCTAssertGreaterThan(probe.callCount, callsBefore, "新子进程必须重新验证监听")
  }

  func testACLReloadRequiresCurrentReceiptWithoutProbingUnchangedListeners() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let controller = makeController(probe: probe)
    try await controller.activate(seeded.server)
    try Data("42".utf8).write(to: runtime.pidFile)
    let callsBefore = probe.callCount
    signals.reloadReceipt = {}

    await controller.setProxyMode(.direct)

    XCTAssertEqual(controller.state, .serviceFailed(.agent))
    XCTAssertEqual(probe.callCount, callsBefore)
    XCTAssertNotNil(RuntimeFileStore(fileURL: runtime.contract).readFailure())
  }

  func testNewModeSupersedesPendingACLReloadWithoutStartingOrProbing() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let waiting = expectation(description: "waiting for reload receipt")
    let gate = RuleRuntimeDelayGate(started: waiting)
    let controller = makeController(
      probe: probe, launchHealthTimeoutSeconds: 5,
      launchHealthRetryDelay: { try await gate.wait() })
    try await controller.activate(seeded.server)
    try Data("42".utf8).write(to: runtime.pidFile)
    let callsBefore = probe.callCount
    signals.reloadReceipt = {}
    let pending = Task { await controller.setProxyMode(.direct) }
    try await withTestTask(
      pending, release: { gate.resume() },
      body: {
        try await requireTestPhase([waiting])
        XCTAssertEqual(controller.state, .running)
        let store = RuntimeFileStore(fileURL: runtime.contract)
        var stateAtReload: ProxyRuntimeController.AgentRunState?
        self.signals.reloadReceipt = {
          stateAtReload = controller.state
          try? store.writePublishedRuntimeReceipt(processID: 42)
        }
        await controller.setProxyMode(.global)
        XCTAssertEqual(stateAtReload, .running)
        XCTAssertEqual(controller.state, .running)
        XCTAssertEqual(probe.callCount, callsBefore)
      })
    XCTAssertTrue(controller.runtimeReloadProcesses.isEmpty)
    XCTAssertEqual(controller.proxyMode, .global)
    XCTAssertEqual(controller.state, .running)
  }

  func testSetProxyModePersistsTheChoiceAndARestoreRestoresIt() async throws {
    let listeningStore = InMemoryProxyListeningStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), listeningStore: listeningStore)

    await controller.setProxyMode(.global)

    XCTAssertEqual(controller.proxyMode, .global)
    XCTAssertEqual(controller.settings.preferredMode, .global)
    XCTAssertEqual(controller.controlPreferences.preferredMode, .global, "模式选择随快照持久化")

    // GUI 重启路径：恢复出的控制器不注入显式模式，从持久快照读回。
    let restored = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(
          listen: ActivationFixture.listen, preferences: controlPreferences), unreadableError: nil),
      proxyMode: nil)
    XCTAssertEqual(restored.proxyMode, .global)
  }

  func testDirectModeDeploysACLWithoutServerAndProjectsSOCKSProxy() async throws {
    let listeningStore = InMemoryProxyListeningStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))

    await controller.resyncOnLaunch()
    XCTAssertEqual(controller.state, .running)
    XCTAssertTrue(systemProxy.applied.isEmpty, "规则模式没有活动目标时不应用系统代理")
    let unregisterCount = agent.unregisterCount

    await controller.setProxyMode(.direct)

    XCTAssertEqual(controller.proxyMode, .direct)
    XCTAssertEqual(controller.settings.preferredMode, .direct)
    XCTAssertEqual(controller.controlPreferences.preferredMode, .direct)
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(agent.unregisterCount, unregisterCount + 1, "ACL 变化触发完整 agent 重启")
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let document = try XCTUnwrap(runtimeStore.loadDocument())
    XCTAssertTrue(document.servers.isEmpty, "直连模式允许空服务器列表")
    XCTAssertEqual(document.aclRuntime?.summary, "direct")
    let expectedACL = ProxyACLDocument.direct(at: runtimeStore.aclFileURL)
    XCTAssertEqual(
      try Data(contentsOf: runtimeStore.aclFileURL),
      Data(expectedACL.content.utf8),
      "链接解析后的内容是 direct 变体")
    XCTAssertEqual(
      systemProxy.applied.last?.socks,
      .init(host: "127.0.0.1", port: ActivationFixture.listen.socksPort))
    XCTAssertEqual(
      systemProxy.applied.last?.http,
      .init(host: "127.0.0.1", port: ActivationFixture.listen.httpPort))
    XCTAssertTrue(
      Set(FixedLocalProxyRanges.systemProxyExceptions).isSubset(
        of: Set(systemProxy.applied.last?.exceptions ?? [])))
    XCTAssertEqual(controller.systemProxyState, .applied)

    let registersBeforeDisable = agent.unregisterCount
    await controller.setSystemProxyEnabled(false)
    XCTAssertEqual(controller.state, .running, "关闭系统代理不停止本地入口")
    XCTAssertEqual(agent.unregisterCount, registersBeforeDisable)
    XCTAssertEqual(controller.systemProxyState, .idle)

    let restored = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settingsRestore: RestoredProxyRuntimeSettings(
        settings: ProxyRuntimeSettings(
          listen: ActivationFixture.listen, preferences: controlPreferences), unreadableError: nil),
      proxyMode: nil)
    XCTAssertEqual(restored.proxyMode, .direct, "模式选择从持久快照恢复")
  }

  func testFailedDirectInstanceKeepsNewModeAndStopsService() async throws {
    let seeded = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true),
      launchHealthTimeoutSeconds: 0.05)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.systemProxyState, .applied)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let previousDocument = try XCTUnwrap(runtimeStore.loadDocument())
    let previousApplicationCount = systemProxy.applied.count
    var observedStates: [ProxyRuntimeController.AgentRunState] = []
    let cancellable = controller.factChanges.changes.sink { @MainActor _ in
      observedStates.append(controller.state)
    }
    defer { cancellable.cancel() }

    agent.onRegister = { [runtimeStore, previousDocument] in
      guard let requested = runtimeStore.loadDocument() else { return }
      let accepted = requested.aclRuntime == nil ? requested : previousDocument
      try? runtimeStore.writeRuntimeReceipt(for: accepted, processID: 42)
    }

    await controller.setProxyMode(.direct)

    XCTAssertTrue(observedStates.contains(.starting), "重启期间呈现短暂不可用状态")
    XCTAssertEqual(controller.proxyMode, .direct)
    XCTAssertEqual(controller.settings.preferredMode, .direct)
    XCTAssertEqual(controller.controlPreferences.preferredMode, .direct)
    XCTAssertEqual(runtimeStore.loadDocument()?.aclRuntime?.summary, "direct")
    XCTAssertEqual(controller.state, .serviceFailed(.agent))
    XCTAssertTrue(controller.agentIntentEnabled)
    XCTAssertTrue(controller.systemProxyIntentEnabled)
    XCTAssertNotNil(runtimeStore.readFailure())
    XCTAssertEqual(systemProxy.applied.count, previousApplicationCount)
    XCTAssertGreaterThan(systemProxy.clearCount, 0)
  }

  func testDirectReceiptIsRecheckedAfterReachableStaleListenerProbes() async throws {
    let seeded = try makeSeededCatalog()
    let listeningStore = InMemoryProxyListeningStore()
    let processLiveness = ProcessLivenessRecorder()
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listeningStore: listeningStore,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true),
      processIsAlive: { processLiveness.isAlive($0) })
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.systemProxyState, .applied)

    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let appliedCount = systemProxy.applied.count
    agent.onRegister = { [runtimeStore] in
      guard let requested = runtimeStore.loadDocument() else { return }
      // 新直连实例用一次性存活的 pid 43。
      let processID: Int32 = requested.aclRuntime?.summary == "direct" ? 43 : 42
      try? runtimeStore.writeRuntimeReceipt(for: requested, processID: processID)
    }

    await controller.setProxyMode(.direct)

    XCTAssertEqual(controller.proxyMode, .direct)
    XCTAssertEqual(controller.state, .serviceFailed(.agent))
    XCTAssertEqual(runtimeStore.loadDocument()?.aclRuntime?.summary, "direct")
    XCTAssertNotNil(runtimeStore.readFailure())
    XCTAssertEqual(systemProxy.applied.count, appliedCount)
    XCTAssertGreaterThan(systemProxy.clearCount, 0)
  }
}

private final class ProcessLivenessRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var candidateChecks = 0

  func isAlive(_ pid: Int32) -> Bool {
    if pid == 42 { return true }
    guard pid == 43 else { return false }
    lock.lock()
    defer { lock.unlock() }
    candidateChecks += 1
    return candidateChecks == 1
  }
}
