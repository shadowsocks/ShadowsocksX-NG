import XCTest

@testable import ShadowsocksX_NG2

final class CustomRuleDeletionControllerTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: { source in
      // Keep the covering rule used by the unchanged-ACL deletion scenario.
      if source == .geolocationCN {
        return rulesFixture(
          source,
          rules: [
            ProxyRule(action: .direct, match: .domainSuffix("cn"))
          ])
      }
      return try ProxyRuntimeFixture.controlFlowRuleSnapshot(source)
    })
  }

  func testDeletionWhileOffPersistsBatchAndDisabledOrphansWithoutStarting() async throws {
    let (store, _) = try makeCustomRuleStore()
    let rules = [
      CustomRule(action: .direct, match: .domainExact("one.example")),
      CustomRule(action: .direct, match: .domainExact("two.example")),
    ]
    let original = CustomRuleDocument(rules: rules, disabledIdentities: [rules[0].identity])
    try store.saveDocument(original)
    let controller = makeDeletionController(
      store: store, settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: false))
    let workflow = deletionWorkflow(controller)
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(
      try store.loadDocument(),
      CustomRuleDocument(rules: [], disabledIdentities: original.disabledIdentities))
    XCTAssertEqual(controller.state, .off)
    XCTAssertEqual(agent.registerCount, 0)
    var query = workflow.snapshot.query
    query.enabled = false
    workflow.query(query)
    let orphan = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == rules[0].identity })
    XCTAssertFalse(orphan.hasCurrentSource)
    await workflow.setEnabled(true, identities: [rules[0].identity])
    XCTAssertFalse(workflow.snapshot.rows.contains { $0.identity == rules[0].identity })
    XCTAssertTrue(try store.loadDocument().disabledIdentities.isEmpty)
  }

  func testBatchDeletionDeploysOnceAndInvalidatesAddressTest() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let rules = [
      CustomRule(action: .direct, match: .domainExact("one-delete.example")),
      CustomRule(action: .direct, match: .domainExact("two-delete.example")),
    ]
    try store.save(rules)
    let controller = makeDeletionController(
      store: store,
      settings: ProxySettings(
        listen: ActivationFixture.listen, preferredMode: .rule,
        ruleDefaultAction: .proxyWhenUnmatched, agentEnabled: true), proxyMode: .rule)
    try await controller.activate(seeded.server)
    let workflow = deletionWorkflow(controller)
    await workflow.refresh()
    workflow.setTestTarget("one-delete.example")
    await workflow.testAddress()
    XCTAssertNotNil(workflow.snapshot.addressTest.result)
    workflow.select(Set(workflow.snapshot.rows.filter { !$0.customIDs.isEmpty }.map(\.id)))
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    let registrations = agent.registerCount
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(agent.registerCount, registrations + 1)
    XCTAssertTrue(try store.load().isEmpty)
    let content = try activeACLContent(RuntimeFileStore(fileURL: runtime.contract))
    XCTAssertFalse(content.contains("one-delete.example"))
    XCTAssertFalse(content.contains("two-delete.example"))
    XCTAssertNil(workflow.snapshot.addressTest.result)
    XCTAssertTrue(workflow.snapshot.selection.isEmpty)
    XCTAssertEqual(workflow.snapshot.commitFeedback?.operation, .delete)
  }

  func testDeletionInNonRuleModesOnlySavesAndCoveredRuleDoesNotRestart() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let rule = CustomRule(action: .direct, match: .domainExact("covered.cn"))
    for mode in [ProxyMode.global, .direct, .rule] {
      try store.save([rule])
      let controller = makeDeletionController(
        store: store,
        settings: ProxySettings(
          listen: ActivationFixture.listen, preferredMode: mode.kind,
          ruleDefaultAction: .proxyWhenUnmatched, agentEnabled: true), proxyMode: mode)
      try await controller.activate(seeded.server)
      let workflow = deletionWorkflow(controller)
      await workflow.refresh()
      workflow.select(Set(workflow.snapshot.rows.filter { !$0.customIDs.isEmpty }.map(\.id)))
      let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
      let registrations = agent.registerCount
      await workflow.deleteCustomRules(confirmation)
      XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
      await controller.ruleApplicationTask?.value
      XCTAssertEqual(agent.registerCount, registrations)
      XCTAssertTrue(try store.load().isEmpty)
      await controller.setAgentEnabled(false)
    }
  }

  func testDeletionDeploymentFailureKeepsSavedDeletionAndStopsRuntime() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let rule = CustomRule(action: .direct, match: .domainExact("keep-one.example"))
    let orphan = RuleIdentity(action: .proxy, match: .domainExact("orphan.example"))
    try store.saveDocument(CustomRuleDocument(rules: [rule], disabledIdentities: [orphan]))
    let controller = makeDeletionController(
      store: store,
      settings: ProxySettings(
        listen: ActivationFixture.listen, preferredMode: .rule,
        ruleDefaultAction: .proxyWhenUnmatched, agentEnabled: true), proxyMode: .rule)
    try await controller.activate(seeded.server)
    let workflow = deletionWorkflow(controller)
    await workflow.refresh()
    workflow.select([.rule(rule.identity)])
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let previousRuntime = try XCTUnwrap(runtimeStore.loadDocument())
    agent.onRegister = {
      try? runtimeStore.writeRuntimeReceipt(for: previousRuntime, processID: 42)
    }
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    let saved = CustomRuleDocument(rules: [], disabledIdentities: [orphan])
    XCTAssertEqual(try store.loadDocument(), saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.loadDocument(), saved)
    XCTAssertNotEqual(runtimeStore.loadDocument(), previousRuntime)
    XCTAssertNotNil(runtimeStore.readFailure())
    XCTAssertNotEqual(controller.state, .running)
    XCTAssertNotNil(controller.runtimeFacts.failure)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .saved)
    XCTAssertTrue(workflow.snapshot.rows.allSatisfy { $0.customIDs.isEmpty })
    agent.onRegister = {
      try? FileManager.default.removeItem(at: runtimeStore.runtimeStatusFileURL)
    }
    await controller.setAgentEnabled(true)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(try store.loadDocument(), saved)
    XCTAssertNotEqual(controller.state, .running)
  }

  func testDeletionPersistenceFailureRetainsOwnedDocumentAndDoesNotStartRuntime() async throws {
    let (store, directory) = try makeCustomRuleStore()
    let rule = CustomRule(action: .direct, match: .domainExact("kept.example"))
    let original = CustomRuleDocument(rules: [rule], disabledIdentities: [rule.identity])
    try store.saveDocument(original)
    let controller = makeDeletionController(
      store: store, settings: ProxySettings(listen: ActivationFixture.listen, agentEnabled: false))
    let workflow = deletionWorkflow(controller)
    await workflow.refresh()
    workflow.select(Set(workflow.snapshot.rows.map(\.id)))
    let confirmation = try XCTUnwrap(workflow.prepareCustomRuleDeletion())
    let originalData = try Data(contentsOf: store.fileURL)
    let backupDirectory = directory.appendingPathExtension("backup")
    try FileManager.default.moveItem(at: directory, to: backupDirectory)
    try Data("blocks parent directory".utf8).write(to: directory)
    let backup = backupDirectory.appendingPathComponent(store.fileURL.lastPathComponent)
    await workflow.deleteCustomRules(confirmation)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .persistenceFailed)
    XCTAssertEqual(controller.ruleDocuments.current, original)
    XCTAssertEqual(try Data(contentsOf: backup), originalData)
    XCTAssertEqual(workflow.snapshot.version, confirmation.version)
    XCTAssertEqual(workflow.deletableSelection, [rule.id])
    XCTAssertEqual(agent.registerCount, 0)
  }

  private func makeDeletionController(
    store: CustomRuleStore, settings: ProxySettings, proxyMode: ProxyMode? = nil
  ) -> ProxyRuntimeController {
    makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: proxyMode,
      launchHealthRetryDelay: { try await Task.sleep(for: .milliseconds(1)) },
      ruleApplicationDelay: { await Task.yield() })
  }

  private func deletionWorkflow(_ controller: ProxyRuntimeController) -> RulesWorkflow {
    RulesWorkflow(
      loadDocument: { try controller.ruleDocuments.load() },
      commitDocument: { await controller.commitRuleDocument($0) },
      builtinSnapshots: controller.ruleSnapshots)
  }
}
