import XCTest

@testable import ShadowsocksX_NG2

extension RuleEnablementControllerTests {
  func testSelectedPresetDrivesACLAndInactivePresetSaveDoesNotDeploy() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let controller = makeControllerWithCustomRules(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .rule, ruleApplicationDelay: { await Task.yield() })
    try await controller.activate(seeded.server)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let before = try activeACLContent(runtimeStore)
    let registrations = agent.registerCount
    let custom = CustomRule(
      action: .proxy, match: try RuleMatch(domainSuffix: "preset-only.example"))
    let saved = await controller.commitRuleDocument(
      CustomRuleDocument(rules: [custom]), preset: .chinaProxy)
    XCTAssertEqual(saved.outcome, .saved)
    XCTAssertNil(controller.ruleApplicationTask)
    XCTAssertEqual(try activeACLContent(runtimeStore), before)
    XCTAssertEqual(agent.registerCount, registrations)
    XCTAssertTrue(try controller.documents(for: .chinaDirect).load().rules.isEmpty)
    await controller.setRulePreset(.chinaProxy)
    let china = try activeACLContent(runtimeStore)
    XCTAssertTrue(china.hasPrefix("[bypass_all]"))
    XCTAssertTrue(china.contains("preset-only.example"))
    XCTAssertTrue(china.contains("[proxy_list]"))
    XCTAssertEqual(controller.controlPreferences.rulePreset, .chinaProxy)
    let generation = controller.modeChangeGeneration
    await controller.setRulePreset(.chinaProxy)
    XCTAssertEqual(controller.rulePreset, .chinaProxy)
    XCTAssertEqual(controller.modeChangeGeneration, generation)
    XCTAssertEqual(try activeACLContent(runtimeStore), china)
    await controller.setRulePreset(.chinaDirect)
    XCTAssertEqual(try activeACLContent(runtimeStore), before)
    await controller.setRulePreset(.gfwlist)
    XCTAssertFalse(try activeACLContent(runtimeStore).contains("preset-only.example"))
  }
}
