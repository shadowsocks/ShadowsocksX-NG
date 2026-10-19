import XCTest

@testable import ShadowsocksX_NG2

/// Verify the editor's public commands against the production commit adapter,
/// using the existing hostless runtime and system-proxy fixtures.
final class CustomRuleEditingControllerTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  func testEditorSaveWhileOffPersistsWithoutStartingRuntime() async throws {
    let (store, _) = try makeCustomRuleStore()
    let controller = makeControllerWithCustomRules(
      store: store, settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: false))
    let workflow = editingWorkflow(controller)
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.kind = .ipAddress
    draft.content = "8.8.8.8"
    draft.action = .direct
    let result = await workflow.saveCustomRule(draft)
    XCTAssertEqual(result, .committed(.saved))
    XCTAssertEqual(try store.load().first?.id, draft.id)
    XCTAssertEqual(controller.state, .off)
    XCTAssertEqual(agent.registerCount, 0)
    XCTAssertEqual(workflow.snapshot.commitFeedback?.operation, .add)
  }

  func testEditorChangesRuntimeACLOnceAndRetainsUUIDAcrossEdits() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let controller = makeControllerWithCustomRules(
      store: store,
      settings: ProxySettings(
        listen: ActivationFixture.listen, preferredMode: .rule,
        ruleDefaultAction: .proxyWhenUnmatched, agentEnabled: true), proxyMode: .rule)
    try await controller.activate(seeded.server)
    let workflow = editingWorkflow(controller)
    await workflow.refresh()
    let registrations = agent.registerCount
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.content = "new-rule.example"
    draft.action = .direct
    let added = await workflow.saveCustomRule(draft)
    XCTAssertEqual(added, .committed(.saved))
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(agent.registerCount, registrations + 1)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    XCTAssertTrue(try activeACLContent(runtimeStore).contains("||new-rule.example"))
    var edited = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: draft.id))
    edited.content = "edited-rule.example"
    let saved = await workflow.saveCustomRule(edited)
    XCTAssertEqual(saved, .committed(.saved))
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(agent.registerCount, registrations + 2)
    XCTAssertEqual(try store.load().map(\.id), [draft.id])
    XCTAssertFalse(try activeACLContent(runtimeStore).contains("||new-rule.example"))
    XCTAssertTrue(try activeACLContent(runtimeStore).contains("||edited-rule.example"))
    XCTAssertEqual(workflow.snapshot.commitFeedback?.operation, .edit)
  }

  func testEditorFailedDeploymentKeepsSavedEditAndStopsRuntime() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let existing = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "kept.example"))
    try store.save([existing])
    let controller = makeControllerWithCustomRules(
      store: store,
      settings: ProxySettings(
        listen: ActivationFixture.listen, preferredMode: .rule,
        ruleDefaultAction: .proxyWhenUnmatched, agentEnabled: true), proxyMode: .rule)
    try await controller.activate(seeded.server)
    let workflow = editingWorkflow(controller)
    await workflow.refresh()
    let version = workflow.snapshot.version
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let originalRuntime = try XCTUnwrap(runtimeStore.loadDocument())
    agent.onRegister = {
      try? runtimeStore.writeRuntimeReceipt(for: originalRuntime, processID: 42)
    }
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: existing.id))
    draft.content = "new-rule.example"
    let result = await workflow.saveCustomRule(draft)
    XCTAssertEqual(result, .committed(.saved))
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.load().first?.id, existing.id)
    XCTAssertEqual(
      try store.load().first?.match, try RuleMatch(domainSuffix: "new-rule.example"))
    XCTAssertNotEqual(workflow.snapshot.version, version)
    XCTAssertEqual(
      workflow.snapshot.rows.first { $0.customIDs.contains(existing.id) }?.identity,
      ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "new-rule.example")))
    XCTAssertNotEqual(runtimeStore.loadDocument(), originalRuntime)
    XCTAssertNotNil(runtimeStore.readFailure())
    XCTAssertNotEqual(controller.state, .running)
    let preview = await workflow.previewCustomRule(draft)
    XCTAssertEqual(preview.failure, .staleDraft)
    XCTAssertNotNil(controller.runtimeFacts.failure)
  }

  private func editingWorkflow(_ controller: ProxyRuntimeController) -> RulesWorkflow {
    RulesWorkflow(
      loadDocument: { try controller.ruleDocuments.load() },
      commitDocument: { await controller.commitRuleDocument($0) },
      builtinSnapshots: controller.ruleSnapshots)
  }
}
