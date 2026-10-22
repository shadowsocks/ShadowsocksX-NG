import Combine
import XCTest

@testable import ShadowsocksX_NG2

/// Saved custom-rule intent and independent runtime application/recovery.
extension ProxyRuntimeControllerTests {
  func makeCustomRuleStore() throws -> (store: CustomRuleStore, directory: URL) {
    let directory = runtime.directory.appendingPathComponent(
      "custom-rules-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("custom-rules.json"))
    return (store, directory)
  }

  func makeControllerWithCustomRules(
    store: CustomRuleStore,
    probe: EndpointProbing = ProxyRuntimeFixture.FakeProbe.reachable(),
    settings: ProxyRuntimeSettings? = nil,
    proxyMode: ProxyMode? = nil,
    launchHealthTimeoutSeconds: TimeInterval = 0.05,
    launchHealthRetryDelay: @escaping () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(200))
    },
    ruleApplicationDelay: @escaping () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(150))
    },
    ruleSnapshots: BuiltinRuleSnapshots? = nil
  ) -> ProxyRuntimeController {
    makeController(
      probe: probe,
      listeningStore: InMemoryProxyListeningStore(),
      settings: settings
        ?? ProxyRuntimeSettings(listen: ActivationFixture.listen, agentEnabled: true),
      proxyMode: proxyMode,
      launchHealthTimeoutSeconds: launchHealthTimeoutSeconds,
      launchHealthRetryDelay: launchHealthRetryDelay,
      ruleApplicationDelay: ruleApplicationDelay,
      customRuleStore: store, ruleSnapshots: ruleSnapshots)
  }

  /// 从链接解析读取当前 ACL 变体内容（契约不再内嵌 content）。
  func activeACLContent(_ store: RuntimeFileStore) throws -> String {
    let data = try Data(contentsOf: store.aclFileURL)
    return String(bytes: data, encoding: .utf8) ?? ""
  }

}

final class CustomRuleControllerTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  /// 规则内容变化重编译 ACL 并按完整重启路径生效。
  func testUpdateCustomRulesRecompilesACLAndRestarts() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen,
      preferredMode: .rule,
      ruleDefaultAction: .proxyWhenUnmatched,
      agentEnabled: true)
    let controller = makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: .rule)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(controller.proxyMode, .rule)
    let unregisterBefore = agent.unregisterCount

    let rule = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "internal.example"))
    let outcome = await controller.commitRuleDocument(CustomRuleDocument(rules: [rule])).outcome

    XCTAssertEqual(outcome, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.load(), [rule])
    XCTAssertEqual(agent.unregisterCount, unregisterBefore + 1, "ACL 变化触发完整 agent 重启")
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let document = try XCTUnwrap(runtimeStore.loadDocument())
    XCTAssertEqual(document.aclRuntime?.summary, "rule-proxy-default")
    XCTAssertTrue(
      try activeACLContent(runtimeStore).contains("||internal.example"),
      "自定义直连规则应进入规则模式 ACL")
  }

  func testOppositeActionsPersistAndReorderingDoesNotRedeploy() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen, preferredMode: .rule,
      ruleDefaultAction: .directWhenUnmatched, agentEnabled: true)
    let controller = makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: .rule)
    try await controller.activate(seeded.server)
    let rules = [
      CustomRule(action: .direct, match: try RuleMatch(domainSuffix: "order.example")),
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: "a.order.example")),
      CustomRule(action: .direct, match: try RuleMatch(domainExact: "a.order.example")),
    ]
    let first = await controller.commitRuleDocument(CustomRuleDocument(rules: rules)).outcome
    XCTAssertEqual(first, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.load(), rules, "保存保留用户 UUID 和全部意图")
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let before = try activeACLContent(runtimeStore)
    let unregisterBefore = agent.unregisterCount
    let summary = controller.readCustomRuleSummary()
    let reversed = Array(rules.reversed())
    let reordered = await controller.commitRuleDocument(CustomRuleDocument(rules: reversed))
      .outcome
    XCTAssertEqual(reordered, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.load(), reversed)
    XCTAssertEqual(try activeACLContent(runtimeStore), before)
    XCTAssertEqual(agent.unregisterCount, unregisterBefore)
    XCTAssertEqual(controller.readCustomRuleSummary(), summary)
  }

  /// 校验拒绝：固定本地冲突整批不落地，旧规则保持不变。
  func testUpdateCustomRulesRejectsFixedLocalConflictAndKeepsPreviousRules() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let existing = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "kept.example"))
    try store.save([existing])
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen,
      preferredMode: .rule,
      ruleDefaultAction: .proxyWhenUnmatched,
      agentEnabled: true)
    let controller = makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: .rule)
    try await controller.activate(seeded.server)

    let conflicting = CustomRule(
      action: .proxy, match: try RuleMatch(ipv4CIDR: "127.0.0.0/8"))
    let outcome = await controller.commitRuleDocument(
      CustomRuleDocument(rules: [existing, conflicting])
    ).outcome

    guard case .rejected(let rejected) = outcome else {
      return XCTFail("应拒绝固定本地冲突，实际 \(outcome)")
    }
    XCTAssertEqual(rejected.map(\.reason), [.conflictsWithFixedLocalScope])
    XCTAssertFalse(rejected[0].explanation.isEmpty)
    XCTAssertEqual(try store.load(), [existing], "拒绝时旧规则保持不变")
  }

  /// Failed application retains saved rules and the failed deployment.
  func testFailedCustomRuleDeployKeepsSavedRulesAndStopsRuntime() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let existing = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "kept.example"))
    try store.save([existing])
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen,
      preferredMode: .rule,
      ruleDefaultAction: .proxyWhenUnmatched,
      agentEnabled: true,
      systemProxyEnabled: true)
    let controller = makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: .rule, launchHealthTimeoutSeconds: 0.05)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.state, .running)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let previousDocument = try XCTUnwrap(runtimeStore.loadDocument())
    let previousApplicationCount = systemProxy.applied.count

    agent.onRegister = { [runtimeStore, previousDocument] in
      try? runtimeStore.writeRuntimeReceipt(for: previousDocument, processID: 42)
    }

    let newRule = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "new-rule.example"))
    let result = await controller.commitRuleDocument(CustomRuleDocument(rules: [newRule]))

    XCTAssertEqual(result.outcome, .saved)
    XCTAssertEqual(result.document, CustomRuleDocument(rules: [newRule]))
    await controller.ruleApplicationTask?.value
    XCTAssertNotNil(controller.runtimeFacts.failure)
    XCTAssertEqual(try store.load(), [newRule], "部署失败保留已保存规则")
    XCTAssertNotEqual(runtimeStore.loadDocument(), previousDocument)
    XCTAssertNotNil(runtimeStore.readFailure())
    XCTAssertFalse(controller.state.isOn)
    XCTAssertTrue(controller.agentIntentEnabled)
    XCTAssertTrue(controller.systemProxyIntentEnabled)
    XCTAssertEqual(systemProxy.applied.count, previousApplicationCount)
    XCTAssertGreaterThan(systemProxy.clearCount, 0)
  }

  /// 全局模式不加载自定义规则：保存成功但 ACL 不变、不触发重启。
  func testGlobalModePersistsCustomRulesWithoutACLRestart() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen,
      preferredMode: .global,
      agentEnabled: true)
    let controller = makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: .global)
    try await controller.activate(seeded.server)
    XCTAssertEqual(controller.proxyMode, .global)
    let unregisterBefore = agent.unregisterCount

    let rule = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "internal.example"))
    let outcome = await controller.commitRuleDocument(CustomRuleDocument(rules: [rule])).outcome

    XCTAssertEqual(outcome, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.load(), [rule])
    XCTAssertEqual(agent.unregisterCount, unregisterBefore, "全局模式 ACL 不含自定义规则，无需重启")
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let document = try XCTUnwrap(runtimeStore.loadDocument())
    XCTAssertEqual(document.aclRuntime?.summary, "global")
    XCTAssertFalse(try activeACLContent(runtimeStore).contains("internal.example"))
  }

  /// 诊断摘要只含数量与内容版本。
  func testCustomRuleSummaryExposesCountAndVersionOnly() async throws {
    let (store, _) = try makeCustomRuleStore()
    try store.save([
      CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "secret.example"))
    ])
    let controller = makeControllerWithCustomRules(store: store)

    let summary = try XCTUnwrap(controller.readCustomRuleSummary())

    XCTAssertEqual(summary.count, 1)
    XCTAssertEqual(summary.contentVersion.count, 12)
    XCTAssertFalse(summary.contentVersion.contains("secret"))
  }
}
