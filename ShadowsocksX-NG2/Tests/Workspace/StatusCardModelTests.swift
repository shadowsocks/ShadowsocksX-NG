import XCTest

@testable import ShadowsocksX_NG2

/// 侧栏底部状态卡的呈现政策：行结构、语义色调
/// 与活动目标回退文案从代理控制工作流的整体 snapshot 派生；文本与状态菜单
/// 共用 StatusMenuModel 的同一映射。
final class StatusCardModelTests: XCTestCase {
  private struct RuntimeToneCase {
    let facts: ProxyRuntimeFacts
    let expectedTone: StatusCardModel.Tone
  }

  private static let runtimeToneCases: [RuntimeToneCase] = [
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .starting, isOn: true),
      expectedTone: .neutral),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .running, isOn: true),
      expectedTone: .positive),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .off, isOn: false),
      expectedTone: .neutral),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .firewallBlocked, isOn: true),
      expectedTone: .attention),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .requiresApproval, isOn: true),
      expectedTone: .attention),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .launchFailed, isOn: false),
      expectedTone: .failure),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .serviceFailed, isOn: false),
      expectedTone: .failure),
  ]

  /// 从运行时事实构造最小 snapshot（其余字段与本组用例无关；与
  /// StatusMenuModelTests 的夹具同形状）。
  private func makeSnapshot(
    facts: ProxyRuntimeFacts,
    activationFailure: ActivationFailure? = nil,
    systemProxyApplication: SystemProxyApplicationFacts = .idle,
    mode: ProxyMode = .rule,
    activeTarget: ProxyActiveTargetFacts? = nil
  ) -> ProxyControlSnapshot {
    ProxyControlSnapshot(
      runtime: facts,
      agentIntentEnabled: true,
      activationFailure: activationFailure,
      systemProxyIntentEnabled: false,
      systemProxyApplication: systemProxyApplication,
      systemProxyApprovalRequired: false,
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

  // MARK: - agent 运行状态行

  func testRuntimeRowUsesSemanticTone() {
    for testCase in Self.runtimeToneCases {
      let card = StatusCardModel.card(from: makeSnapshot(facts: testCase.facts))
      XCTAssertEqual(card.runtimeRow.tone, testCase.expectedTone)
    }
  }

  /// agent 点名原因色调：运行失败跟随运行状态色调（受阻=警示红系跟随橙），
  /// 激活点名失败独立显红，无失败无 detail。
  func testRuntimeDetailToneFollowsRuntimeFailureThenActivationFailure() {
    let firewallBlocked = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(
          status: .firewallBlocked,
          isOn: true,
          failure: .firewallBlocked(FirewallBlockedFacts(executableName: "sslocal")))))
    XCTAssertEqual(firewallBlocked.runtimeDetail?.tone, .attention, "运行失败跟随运行状态色调")

    let activationRejected = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        activationFailure: .targetNotFound(NodeID(rawValue: "manual:gone"))))
    XCTAssertEqual(activationRejected.runtimeDetail?.tone, .failure, "激活点名失败独立显红")
    XCTAssertEqual(
      activationRejected.runtimeDetail?.text,
      AppPresentation.message(
        for: ActivationFailure.targetNotFound(NodeID(rawValue: "manual:gone"))))

    let healthy = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .running, isOn: true)))
    XCTAssertNil(healthy.runtimeDetail)
  }

  // MARK: - 系统代理行

  func testSystemProxyRowUsesSemanticToneAndFailureDetail() {
    let idle = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .off, isOn: false)))
    XCTAssertEqual(idle.systemProxyRow.tone, .neutral)
    XCTAssertNil(idle.systemProxyDetail)

    let pending = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyApplication: .pending))
    XCTAssertEqual(pending.systemProxyRow.tone, .attention)

    let applied = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyApplication: .applied))
    XCTAssertEqual(applied.systemProxyRow.tone, .positive)

    let failed = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        systemProxyApplication: .failed(.operation(.applyFailed))))
    XCTAssertEqual(failed.systemProxyRow.tone, .failure)
    XCTAssertEqual(failed.systemProxyDetail?.tone, .failure)
    XCTAssertEqual(
      failed.systemProxyDetail?.text,
      AppPresentation.message(
        for: RuntimeFailureFacts.systemProxy(.operation(.applyFailed))))
  }

  // MARK: - 活动目标与模式行

  func testTargetPresentationUsesPathThenFallsBackByMode() {
    let targetPath = "订阅分组 / 嵌套分组 / 日本 02"
    let withTarget = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        activeTarget: ProxyActiveTargetFacts(
          id: NodeID(rawValue: "manual:server"), pathSummary: targetPath)))
    XCTAssertEqual(withTarget.target.text, targetPath)
    XCTAssertFalse(withTarget.target.help.isEmpty)

    let direct = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .off, isOn: false),
        mode: .direct))
    XCTAssertFalse(direct.target.text.isEmpty)
    XCTAssertFalse(direct.target.help.isEmpty)

    let inactive = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .off, isOn: false)))
    XCTAssertFalse(inactive.target.text.isEmpty)
    XCTAssertFalse(inactive.target.help.isEmpty)
  }

  /// 模式行与状态菜单同一份 modeLabel（规则模式带子选项），视图不再自行重组。
  func testModeTextMatchesMenuModeLabel() {
    let rule = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .running, isOn: true)))
    XCTAssertEqual(
      rule.modeText,
      StatusMenuModel.summary(
        from: makeSnapshot(
          facts: ProxyRuntimeFacts(status: .running, isOn: true))
      ).modeLabel)

    let global = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        mode: .global))
    XCTAssertFalse(global.modeText.isEmpty)
  }
}
