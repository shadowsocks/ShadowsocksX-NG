import XCTest

@testable import ShadowsocksX_NG2

/// 状态菜单呈现逻辑：头部状态摘要从代理
/// 控制工作流的整体 snapshot 派生，agent 与系统代理两个状态面分开呈现。不
/// 持有 AppKit 类型；HTTP 导出行与目标路径摘要分别在代理控制与目录 module
/// 测试覆盖。
final class StatusMenuModelTests: XCTestCase {
  private struct RuntimeSummaryCase {
    let facts: ProxyRuntimeFacts
    let expectedStatus: String
    let expectedIsOn: Bool
  }

  private static let runtimeSummaryCases: [RuntimeSummaryCase] = [
    RuntimeSummaryCase(
      facts: ProxyRuntimeFacts(status: .starting, isOn: true),
      expectedStatus: "正在启动代理…",
      expectedIsOn: true),
    RuntimeSummaryCase(
      facts: ProxyRuntimeFacts(status: .running, isOn: true),
      expectedStatus: "代理运行中",
      expectedIsOn: true),
    RuntimeSummaryCase(
      facts: ProxyRuntimeFacts(
        status: .firewallBlocked,
        isOn: true,
        failure: .firewallBlocked(FirewallBlockedFacts(executableName: "sslocal"))),
      expectedStatus: "代理运行中（局域网受阻）",
      expectedIsOn: true),
    RuntimeSummaryCase(
      facts: ProxyRuntimeFacts(
        status: .launchFailed,
        isOn: false,
        failure: .launch(
          .localEndpoint(
            endpoint: "http", host: "127.0.0.1", port: 11087, cause: .refused))),
      expectedStatus: "启动失败",
      expectedIsOn: false),
    RuntimeSummaryCase(
      facts: ProxyRuntimeFacts(
        status: .requiresApproval, isOn: true, failure: .requiresApproval),
      expectedStatus: "等待允许后台代理",
      expectedIsOn: true),
    RuntimeSummaryCase(
      facts: ProxyRuntimeFacts(
        status: .serviceFailed,
        isOn: false,
        failure: .service(.persistence)),
      expectedStatus: "服务管理失败",
      expectedIsOn: false),
  ]

  /// 从运行时事实构造最小 snapshot（其余字段与本组用例无关）。
  private func makeSnapshot(
    facts: ProxyRuntimeFacts,
    agentIntent: Bool = true,
    activationFailure: ActivationFailure? = nil,
    systemProxyIntent: Bool = false,
    systemProxyApplication: SystemProxyApplicationFacts = .idle,
    systemProxyApprovalRequired: Bool = false,
    mode: ProxyMode = .rule,
    activeTarget: ProxyActiveTargetFacts? = nil
  ) -> ProxyControlSnapshot {
    ProxyControlSnapshot(
      runtime: facts,
      agentIntentEnabled: agentIntent,
      activationFailure: activationFailure,
      systemProxyIntentEnabled: systemProxyIntent,
      systemProxyApplication: systemProxyApplication,
      systemProxyApprovalRequired: systemProxyApprovalRequired,
      proxyMode: mode,
      ruleDefaultAction: .proxyWhenUnmatched,
      availableModes: ProxyMode.availableModes,
      activeTarget: activeTarget,
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
        listen: RuntimeListenFacts(listen: SslocalListenSettings()),
        commandAddress: TerminalCommandAddress(
          bsdName: "lo0", address: "127.0.0.1", displayName: "lo0")))
  }

  // MARK: - 头部状态摘要

  func testSummaryRunningStateIsOnWithNoDetail() {
    let summary = StatusMenuModel.summary(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .running, isOn: true)))
    XCTAssertTrue(summary.agentIntentEnabled)
    XCTAssertTrue(summary.isOn)
    XCTAssertEqual(summary.status, "代理运行中")
    XCTAssertNil(summary.detail)
  }

  func testSummaryOffStateIsOff() {
    let summary = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .off, isOn: false),
        agentIntent: false,
        mode: .global))
    XCTAssertFalse(summary.agentIntentEnabled, "开关意图独立于运行状态")
    XCTAssertFalse(summary.isOn)
    XCTAssertEqual(summary.status, "代理未运行")
    XCTAssertNil(summary.detail)
  }

  func testSummaryProjectsEveryStableRuntimeStatus() {
    for testCase in Self.runtimeSummaryCases {
      let summary = StatusMenuModel.summary(from: makeSnapshot(facts: testCase.facts))
      XCTAssertEqual(summary.isOn, testCase.expectedIsOn)
      XCTAssertEqual(summary.status, testCase.expectedStatus)
      XCTAssertEqual(
        summary.detail,
        testCase.facts.failure.map { AppPresentation.message(for: $0) })
    }
  }

  /// 激活拒绝/目标清除的点名原因独立于运行状态呈现：agent 仍
  /// 在监听时也必须可读。
  func testSummaryCarriesActivationFailureAlongsideRunningState() {
    let summary = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        activationFailure: .targetNotFound(NodeID(rawValue: "manual:gone"))))
    XCTAssertEqual(summary.status, "代理运行中")
    XCTAssertEqual(
      summary.detail,
      AppPresentation.message(
        for: ActivationFailure.targetNotFound(
          NodeID(rawValue: "manual:gone"))))
  }

  /// 系统代理状态面：意图与实际应用分开，失败携带点名原因。
  func testSummaryProjectsSystemProxyApplicationIndependently() {
    let idle = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .off, isOn: false),
        systemProxyIntent: false,
        systemProxyApplication: .idle))
    XCTAssertFalse(idle.systemProxyIntentEnabled)
    XCTAssertEqual(idle.systemProxyStatus, "系统代理：未应用")
    XCTAssertNil(idle.systemProxyDetail)

    let pending = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyIntent: true,
        systemProxyApplication: .pending))
    XCTAssertTrue(pending.systemProxyIntentEnabled)
    XCTAssertEqual(pending.systemProxyStatus, "系统代理：待应用")
    XCTAssertNil(pending.systemProxyDetail)

    let approvalPending = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyIntent: true,
        systemProxyApplication: .pending,
        systemProxyApprovalRequired: true))
    XCTAssertEqual(approvalPending.systemProxyStatus, "系统代理：待批准")
    XCTAssertNil(approvalPending.systemProxyDetail)

    let applied = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyIntent: true,
        systemProxyApplication: .applied))
    XCTAssertEqual(applied.systemProxyStatus, "系统代理：已应用")

    let failed = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyIntent: true,
        systemProxyApplication: .failed(.operation(.applyFailed))))
    XCTAssertEqual(failed.systemProxyStatus, "系统代理：应用失败")
    XCTAssertEqual(
      failed.systemProxyDetail,
      AppPresentation.message(
        for: RuntimeFailureFacts.systemProxy(.operation(.applyFailed))))
  }

  func testSummaryCarriesModeLabelAndTargetPathFromSnapshot() {
    let summary = StatusMenuModel.summary(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        mode: .global,
        activeTarget: ProxyActiveTargetFacts(
          id: NodeID(rawValue: "manual:server"), pathSummary: "订阅分组 / 嵌套分组 / 日本 02")))
    XCTAssertEqual(summary.modeLabel, "全局")
    XCTAssertEqual(summary.targetPath, "订阅分组 / 嵌套分组 / 日本 02")
  }

  func testSummaryTargetPathIsNilWithoutActiveTarget() {
    let summary = StatusMenuModel.summary(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .off, isOn: false)))
    XCTAssertNil(summary.targetPath)
  }
}
