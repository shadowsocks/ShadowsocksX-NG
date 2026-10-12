import XCTest

@testable import ShadowsocksX_NG2

/// 侧栏底部状态卡的呈现政策：行结构、语义色调
/// 与活动目标回退文案从代理控制工作流的整体 snapshot 派生；文本与状态菜单
/// 共用 StatusMenuModel 的同一映射。
final class StatusCardModelTests: XCTestCase {
  private struct RuntimeToneCase {
    let facts: ProxyRuntimeFacts
    let expectedText: String
    let expectedTone: StatusCardModel.Tone
  }

  private static let runtimeToneCases: [RuntimeToneCase] = [
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .starting, isOn: true),
      expectedText: "正在启动代理…",
      expectedTone: .neutral),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .running, isOn: true),
      expectedText: "代理运行中",
      expectedTone: .positive),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .off, isOn: false),
      expectedText: "代理未运行",
      expectedTone: .neutral),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .firewallBlocked, isOn: true),
      expectedText: "代理运行中（局域网受阻）",
      expectedTone: .attention),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .requiresApproval, isOn: true),
      expectedText: "等待允许后台代理",
      expectedTone: .attention),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .launchFailed, isOn: false),
      expectedText: "启动失败",
      expectedTone: .failure),
    RuntimeToneCase(
      facts: ProxyRuntimeFacts(status: .serviceFailed, isOn: false),
      expectedText: "服务管理失败",
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

  func testRuntimeRowProjectsStatusTextWithSemanticTone() {
    for testCase in Self.runtimeToneCases {
      let card = StatusCardModel.card(from: makeSnapshot(facts: testCase.facts))
      XCTAssertEqual(card.runtimeRow.label, "后台代理")
      XCTAssertEqual(card.runtimeRow.text, testCase.expectedText)
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

  func testSystemProxyRowTonePerApplicationAndFailureDetail() {
    let idle = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .off, isOn: false)))
    XCTAssertEqual(idle.systemProxyRow.label, "系统代理设置")
    XCTAssertEqual(idle.systemProxyRow.text, "未应用")
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
    XCTAssertEqual(failed.systemProxyRow.text, "应用失败")
    XCTAssertEqual(failed.systemProxyRow.tone, .failure)
    XCTAssertEqual(failed.systemProxyDetail?.tone, .failure)
    XCTAssertEqual(
      failed.systemProxyDetail?.text,
      AppPresentation.message(
        for: RuntimeFailureFacts.systemProxy(.operation(.applyFailed))))
  }

  // MARK: - 活动目标与模式行

  func testTargetPresentationUsesPathThenFallsBackByMode() {
    let withTarget = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .running, isOn: true),
        activeTarget: ProxyActiveTargetFacts(
          id: NodeID(rawValue: "manual:server"), pathSummary: "订阅分组 / 嵌套分组 / 日本 02")))
    XCTAssertEqual(withTarget.target.text, "订阅分组 / 嵌套分组 / 日本 02")
    XCTAssertEqual(withTarget.target.help, "活动目标：订阅分组 / 嵌套分组 / 日本 02")

    let direct = StatusCardModel.card(
      from: makeSnapshot(
        facts: ProxyRuntimeFacts(status: .off, isOn: false),
        mode: .direct))
    XCTAssertEqual(direct.target.text, "直连模式（无需服务器）")
    XCTAssertEqual(direct.target.help, "直连模式无需选择活动目标")

    let inactive = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .off, isOn: false)))
    XCTAssertEqual(inactive.target.text, "未激活")
    XCTAssertEqual(inactive.target.help, "未设置活动目标；在首页或服务器目录中激活")
  }

  /// 模式行与状态菜单同一份 modeLabel（规则模式带子选项），视图不再自行重组。
  func testModeTextMatchesMenuModeLabel() {
    let rule = StatusCardModel.card(
      from: makeSnapshot(facts: ProxyRuntimeFacts(status: .running, isOn: true)))
    XCTAssertEqual(rule.modeText, "规则 · 代理")
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
    XCTAssertEqual(global.modeText, "全局")
  }
}
