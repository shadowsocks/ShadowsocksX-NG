import Combine
import XCTest

@testable import ShadowsocksX_NG2

// MARK: - 确定性替身（snapshot 与命令 contract；不触真实运行时）
// 供本文件与 ProxyCommandAddressWorkflowTests 共用（测试 target 内部）。

/// 可编程 runtime 替身：事实可编程、命令全记录；
/// changes 为手动 subject，同步发值保证观察测试确定性。
@MainActor
final class FakeProxyRuntime: ProxyRuntimeAdapting {
  var runtimeFacts: ProxyRuntimeFacts
  var agentIntentEnabled: Bool
  var activationFailure: ActivationFailure?
  var systemProxyIntentEnabled: Bool
  var systemProxyApplication: SystemProxyApplicationFacts
  var systemProxyApprovalRequired = false
  var systemProxyInspection = SystemProxyInspectionFacts()
  var proxyMode: ProxyMode
  var rulePreset: RulePreset = .chinaDirect
  var skippedInvalidServerCount = 0
  var activeTargetID: NodeID?
  var httpExportCapability = HTTPExportCapability(
    copyableLine:
      "export http_proxy=http://127.0.0.1:11087;export https_proxy=http://127.0.0.1:11087;")
  var listenFacts = RuntimeListenFacts(listen: ProxyListeningConfiguration())

  private let changeSubject = PassthroughSubject<Void, Never>()
  var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

  private(set) var resyncCount = 0
  private(set) var agentCommands: [Bool] = []
  private(set) var systemProxyCommands: [Bool] = []
  private(set) var approvalCommandCount = 0
  private(set) var modeCommands: [ProxyMode] = []
  private(set) var rulePresetCommands: [RulePreset] = []

  init(
    facts: ProxyRuntimeFacts = ProxyRuntimeFacts(status: .off, isOn: false),
    agentIntent: Bool = true,
    systemProxyIntent: Bool = false,
    systemProxyApplication: SystemProxyApplicationFacts = .idle,
    mode: ProxyMode = .rule
  ) {
    runtimeFacts = facts
    agentIntentEnabled = agentIntent
    systemProxyIntentEnabled = systemProxyIntent
    self.systemProxyApplication = systemProxyApplication
    proxyMode = mode
  }

  func emitChange() { changeSubject.send() }

  func resyncOnLaunch() async { resyncCount += 1 }

  func setAgentEnabled(_ enabled: Bool) async { agentCommands.append(enabled) }

  func setSystemProxyEnabled(_ enabled: Bool) async { systemProxyCommands.append(enabled) }

  func openSystemProxyHelperApproval() async { approvalCommandCount += 1 }

  func repairSystemProxy() async {}
  func retrySystemProxyClear() async {}
  func recheckSystemProxy() async {}

  func setProxyMode(_ mode: ProxyMode) async { modeCommands.append(mode) }

  func setRulePreset(_ preset: RulePreset) async {
    rulePresetCommands.append(preset)
  }
}

/// 可编程目标事实替身：路径摘要可编程、查询全记录。
@MainActor
final class FakeTargetFacts: ProxyTargetFactsReading {
  var pathByTarget: [NodeID: String] = [:]
  private(set) var queriedTargetIDs: [NodeID?] = []

  func activeTargetFacts(for targetID: NodeID?) -> ProxyActiveTargetFacts? {
    queriedTargetIDs.append(targetID)
    guard let targetID else { return nil }
    return ProxyActiveTargetFacts(id: targetID, pathSummary: pathByTarget[targetID])
  }
}

/// 代理控制工作流的 snapshot 与命令 contract：整体一致性、
/// typed commands、窄目录事实缝、运行时变化重观察与命令边界。
@MainActor
final class ProxyControlWorkflowTests: XCTestCase {
  private var runtime: FakeProxyRuntime!
  private var targetFacts: FakeTargetFacts!
  private var interfaceFacts: FakeLocalInterfaceFacts!
  private var workflow: ProxyControlWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    runtime = FakeProxyRuntime()
    targetFacts = FakeTargetFacts()
    interfaceFacts = FakeLocalInterfaceFacts()
    workflow = ProxyControlWorkflow(
      runtime: runtime, targetFacts: targetFacts, interfaceFacts: interfaceFacts)
  }

  private static let serverID = NodeID(rawValue: "manual:server-1")

  /// 默认监听设置下的预期完整命令（字面量组装，独立于生产派生路径）。
  private static let defaultLoopbackCommands = TerminalProxyEnvironmentCommands(
    zshBash:
      "export http_proxy='http://127.0.0.1:11087'; "
      + "export https_proxy='http://127.0.0.1:11087'; "
      + "export all_proxy='socks5://127.0.0.1:11086'; "
      + "export no_proxy='localhost,127.0.0.1,::1,.local';",
    fish:
      "set -gx http_proxy 'http://127.0.0.1:11087'; "
      + "set -gx https_proxy 'http://127.0.0.1:11087'; "
      + "set -gx all_proxy 'socks5://127.0.0.1:11086'; "
      + "set -gx no_proxy 'localhost,127.0.0.1,::1,.local';",
    nushell:
      "$env.http_proxy = 'http://127.0.0.1:11087'; "
      + "$env.https_proxy = 'http://127.0.0.1:11087'; "
      + "$env.all_proxy = 'socks5://127.0.0.1:11086'; "
      + "$env.no_proxy = 'localhost,127.0.0.1,::1,.local';",
    windowsCMD:
      "set \"http_proxy=http://127.0.0.1:11087\" & "
      + "set \"https_proxy=http://127.0.0.1:11087\" & "
      + "set \"all_proxy=socks5://127.0.0.1:11086\" & "
      + "set \"no_proxy=localhost,127.0.0.1,::1,.local\"",
    windowsPowerShell:
      "$env:http_proxy = 'http://127.0.0.1:11087'; "
      + "$env:https_proxy = 'http://127.0.0.1:11087'; "
      + "$env:all_proxy = 'socks5://127.0.0.1:11086'; "
      + "$env:no_proxy = 'localhost,127.0.0.1,::1,.local';")

  // MARK: - 整体 snapshot

  func testSnapshotAssemblesAllFactsFromSingleObservation() {
    runtime.runtimeFacts = ProxyRuntimeFacts(
      status: .running,
      isOn: true,
      failure: .firewallBlocked(FirewallBlockedFacts(executableName: "sslocal")))
    runtime.agentIntentEnabled = true
    runtime.activationFailure = .noActiveTarget
    runtime.systemProxyIntentEnabled = true
    runtime.systemProxyApplication = .pending
    runtime.proxyMode = .global
    runtime.skippedInvalidServerCount = 3
    runtime.activeTargetID = Self.serverID
    runtime.httpExportCapability = HTTPExportCapability(
      copyableLine: "export http_proxy=http://127.0.0.1:11087;")
    targetFacts.pathByTarget[Self.serverID] = "组A / 香港 01"
    runtime.emitChange()

    let loopback = TerminalCommandAddress(bsdName: "lo0", address: "127.0.0.1", displayName: "lo0")
    XCTAssertEqual(
      workflow.snapshot,
      ProxyControlSnapshot(
        runtime: ProxyRuntimeFacts(
          status: .running,
          isOn: true,
          failure: .firewallBlocked(FirewallBlockedFacts(executableName: "sslocal"))),
        agentIntentEnabled: true,
        activationFailure: .noActiveTarget,
        systemProxyIntentEnabled: true,
        systemProxyApplication: .pending,
        systemProxyApprovalRequired: false,
        proxyMode: .global,
        rulePreset: .chinaDirect,
        availableModes: ProxyMode.availableModes,
        activeTarget: ProxyActiveTargetFacts(id: Self.serverID, pathSummary: "组A / 香港 01"),
        skippedInvalidServerCount: 3,
        httpExport: HTTPExportCapability(
          copyableLine: "export http_proxy=http://127.0.0.1:11087;"),
        commandAddressPicker: TerminalCommandAddressPicker(
          isVisible: false, candidates: [loopback], selected: loopback),
        terminalProxyEnvironmentCommands: Self.defaultLoopbackCommands))
    XCTAssertEqual(
      workflow.snapshot.availableModes, ProxyMode.availableModes,
      "可用模式是 issue #46 Domain 单点策略的投影")
  }

  // MARK: - typed commands：转发并整体重发布

  func testAgentEnableCommandForwardsAndRepublishesWholeSnapshot() async {
    let before = workflow.snapshot
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .running, isOn: true)
    runtime.agentIntentEnabled = true
    runtime.skippedInvalidServerCount = 2
    runtime.activeTargetID = Self.serverID

    let after = await workflow.setAgentEnabled(true)

    XCTAssertEqual(runtime.agentCommands, [true])
    XCTAssertEqual(after, workflow.snapshot, "命令返回值就是已发布的最新 snapshot")
    XCTAssertNotEqual(after, before, "命令完成后整体重发布")
    XCTAssertEqual(after.runtime, ProxyRuntimeFacts(status: .running, isOn: true))
    XCTAssertEqual(after.skippedInvalidServerCount, 2)
  }

  func testAgentDisableCommandForwardsAndRepublishesWholeSnapshot() async {
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .running, isOn: true)
    runtime.agentIntentEnabled = true
    _ = await workflow.setAgentEnabled(true)
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .off, isOn: false)
    runtime.agentIntentEnabled = false
    runtime.skippedInvalidServerCount = 0
    runtime.activeTargetID = nil

    let after = await workflow.setAgentEnabled(false)

    XCTAssertEqual(runtime.agentCommands, [true, false])
    XCTAssertEqual(after.runtime, ProxyRuntimeFacts(status: .off, isOn: false))
    XCTAssertFalse(after.agentIntentEnabled)
    XCTAssertNil(after.activeTarget)
  }

  /// 系统代理命令与 agent 命令互不触碰对方事实。
  func testSystemProxyCommandsForwardIndependentlyFromAgentCommands() async {
    runtime.agentIntentEnabled = true
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .running, isOn: true)
    _ = await workflow.setAgentEnabled(true)
    runtime.systemProxyIntentEnabled = true
    runtime.systemProxyApplication = .applied

    let applied = await workflow.setSystemProxyEnabled(true)

    XCTAssertEqual(runtime.systemProxyCommands, [true])
    XCTAssertTrue(applied.systemProxyIntentEnabled)
    XCTAssertEqual(applied.systemProxyApplication, .applied)
    XCTAssertEqual(applied.agentIntentEnabled, true, "agent 意图不被系统代理命令触碰")

    runtime.systemProxyIntentEnabled = false
    runtime.systemProxyApplication = .idle
    let off = await workflow.setSystemProxyEnabled(false)

    XCTAssertEqual(runtime.systemProxyCommands, [true, false])
    XCTAssertFalse(off.systemProxyIntentEnabled)
    XCTAssertEqual(off.systemProxyApplication, .idle)
    XCTAssertEqual(runtime.agentCommands, [true], "系统代理命令不触发 agent 命令")
  }

  func testModeCommandForwardsAndRepublishesWholeSnapshot() async {
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .running, isOn: true)
    _ = await workflow.setAgentEnabled(true)
    runtime.proxyMode = .global

    let after = await workflow.setProxyMode(.global)

    XCTAssertEqual(runtime.modeCommands, [.global])
    XCTAssertEqual(after.proxyMode, .global)
    XCTAssertEqual(after.runtime, ProxyRuntimeFacts(status: .running, isOn: true))
  }

  func testRulePresetCommandsForwardAndRepublishWithoutLosingIdentity() async {
    for preset in RulePreset.allCases {
      let before = runtime.rulePreset
      let after = await workflow.setRulePreset(preset)
      XCTAssertEqual(runtime.rulePresetCommands.last, preset)
      // 命令完成后从 runtime 重读事实，不提前发布请求值。
      XCTAssertEqual(after.rulePreset, before)
      runtime.rulePreset = preset
      runtime.emitChange()
      XCTAssertEqual(workflow.snapshot.rulePreset, preset)
      XCTAssertEqual(workflow.snapshot.ruleDefaultAction, preset.defaultAction)
      XCTAssertEqual(workflow.snapshot.proxyMode, runtime.proxyMode)
    }
    XCTAssertEqual(runtime.rulePresetCommands, RulePreset.allCases)
  }

  func testResyncOnLaunchForwardsAndRepublishes() async {
    let before = workflow.snapshot
    runtime.runtimeFacts = ProxyRuntimeFacts(
      status: .running, isOn: true, failure: nil)

    await workflow.resyncOnLaunch()

    XCTAssertEqual(runtime.resyncCount, 1)
    XCTAssertNotEqual(workflow.snapshot, before)
    XCTAssertEqual(workflow.snapshot.runtime.status, .running)
  }

  // MARK: - 运行时变化重观察

  func testRuntimeChangeRepublishesWholeSnapshotWithoutCommand() {
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .starting, isOn: true)
    runtime.emitChange()
    XCTAssertEqual(workflow.snapshot.runtime.status, .starting)

    runtime.runtimeFacts = ProxyRuntimeFacts(status: .running, isOn: true)
    runtime.emitChange()
    XCTAssertEqual(workflow.snapshot.runtime.status, .running)
    XCTAssertTrue(workflow.snapshot.runtime.isOn)
  }

  // MARK: - 窄目录目标事实缝

  func testActiveTargetFactsComeFromNarrowCatalogSeam() {
    runtime.activeTargetID = Self.serverID
    targetFacts.pathByTarget[Self.serverID] = "订阅分组 / 香港 01"
    runtime.emitChange()

    XCTAssertEqual(
      workflow.snapshot.activeTarget,
      ProxyActiveTargetFacts(id: Self.serverID, pathSummary: "订阅分组 / 香港 01"))
    XCTAssertEqual(targetFacts.queriedTargetIDs.last, Self.serverID)
  }

  func testNoActiveTargetYieldsNilTargetFacts() {
    XCTAssertNil(workflow.snapshot.activeTarget)
    XCTAssertEqual(targetFacts.queriedTargetIDs, [nil] as [NodeID?], "init 观察即查询一次")
  }

  func testTargetMissingFromTreeKeepsExistenceWithNilSummary() {
    runtime.activeTargetID = Self.serverID
    targetFacts.pathByTarget[Self.serverID] = nil
    runtime.emitChange()

    let target = workflow.snapshot.activeTarget
    XCTAssertEqual(target?.id, Self.serverID, "存在性来自活动目标身份")
    XCTAssertNil(target?.pathSummary, "目标不在当前目录树中时摘要为 nil")
  }

  // MARK: - 命令边界

  /// 四个命令各自只触达自己的运行时缝：模式命令不派发 agent/系统代理命令，
  /// 重同步不派发开关命令；目录激活、订阅刷新、设置保存与诊断导出不在本
  /// module 的依赖面上（类型层面不存在这些入口）。
  func testCommandsTouchOnlyTheirOwnRuntimeAdapter() async {
    await workflow.setAgentEnabled(true)
    await workflow.setSystemProxyEnabled(true)
    await workflow.setProxyMode(.global)
    await workflow.resyncOnLaunch()

    XCTAssertEqual(runtime.agentCommands, [true])
    XCTAssertEqual(runtime.systemProxyCommands, [true])
    XCTAssertEqual(runtime.modeCommands, [.global])
    XCTAssertEqual(runtime.resyncCount, 1)
  }
}
