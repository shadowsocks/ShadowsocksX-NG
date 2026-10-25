import XCTest

@testable import ShadowsocksX_NG2

final class RuleEnablementControllerTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  private func makeRuleEnablementController(
    store: CustomRuleStore,
    settings: ProxyRuntimeSettings,
    proxyMode: ProxyMode? = nil,
    launchHealthTimeoutSeconds: TimeInterval = 0.05,
    ruleSnapshots: BuiltinRuleSnapshots? = nil,
    launchHealthRetryDelay: @escaping () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(1))
    },
    ruleApplicationDelay: @escaping () async throws -> Void = { await Task.yield() }
  ) -> ProxyRuntimeController {
    makeControllerWithCustomRules(
      store: store, settings: settings, proxyMode: proxyMode,
      launchHealthTimeoutSeconds: launchHealthTimeoutSeconds,
      launchHealthRetryDelay: launchHealthRetryDelay,
      ruleApplicationDelay: ruleApplicationDelay,
      ruleSnapshots: ruleSnapshots)
  }

  func testRapidRuleSavesCoalesceIntoOneLatestACLDeployment() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let first = CustomRule(action: .direct, match: try RuleMatch(domainExact: "first-save.example"))
    let latest = CustomRule(
      action: .direct, match: try RuleMatch(domainExact: "latest-save.example"))
    let applicationStarted = expectation(description: "rule application paused")
    let applicationGate = RuleRuntimeDelayGate(started: applicationStarted)
    defer { applicationGate.resume() }
    let controller = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .rule,
        rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .rule, ruleApplicationDelay: { try await applicationGate.wait() })
    try await controller.activate(seeded.server)
    let before = agent.registerCount
    let one = await controller.commitRuleDocument(CustomRuleDocument(rules: [first]))
    try await withRuleApplicationTask(
      try XCTUnwrap(controller.ruleApplicationTask), controller: controller,
      release: applicationGate.resume,
      body: {
        try await requireTestPhase([applicationStarted], timeout: 3)
        let two = await controller.commitRuleDocument(CustomRuleDocument(rules: [latest]))
        XCTAssertEqual(one.outcome, .saved)
        XCTAssertEqual(two.outcome, .saved)
        XCTAssertEqual(try store.load(), [latest])
        XCTAssertEqual(
          agent.registerCount, before, "Saving does not wait for or start deployment inline")
        applicationGate.resume()
        await controller.ruleApplicationTask?.value
        XCTAssertEqual(agent.registerCount, before + 1)
        let content = try activeACLContent(RuntimeFileStore(fileURL: runtime.contract))
        XCTAssertTrue(content.contains("latest-save.example"))
        XCTAssertFalse(content.contains("first-save.example"))
      })
  }

  func testSaveDuringDeploymentIsAcceptedAndLatestDocumentConvergesAfterIt() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let first = CustomRule(action: .direct, match: try RuleMatch(domainExact: "in-flight.example"))
    let latest = CustomRule(
      action: .direct, match: try RuleMatch(domainExact: "after-flight.example"))
    let healthWaiting = expectation(description: "health retry paused")
    let healthGate = RuleRuntimeDelayGate(started: healthWaiting)
    defer { healthGate.resume() }
    let controller = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .rule,
        rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .rule, launchHealthTimeoutSeconds: 0.3,
      launchHealthRetryDelay: { try await healthGate.wait() })
    try await controller.activate(seeded.server)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let started = expectation(description: "first deployment awaiting receipt")
    let before = agent.registerCount
    var firstDocument: PublishedRuntimeConfiguration?
    agent.onRegister = { [agent] in
      guard let document = runtimeStore.loadDocument() else { return }
      if agent?.registerCount == before + 1 {
        firstDocument = document
        try? FileManager.default.removeItem(at: runtimeStore.runtimeStatusFileURL)
        started.fulfill()
      } else {
        try? runtimeStore.writeRuntimeReceipt(for: document, processID: 42)
      }
    }
    let one = await controller.commitRuleDocument(CustomRuleDocument(rules: [first]))
    XCTAssertEqual(one.outcome, .saved)
    try await withRuleApplicationTask(
      try XCTUnwrap(controller.ruleApplicationTask), controller: controller,
      release: healthGate.resume,
      body: {
        try await requireTestPhase([started, healthWaiting], timeout: 3)
        let two = await controller.commitRuleDocument(CustomRuleDocument(rules: [latest]))
        XCTAssertEqual(two.outcome, .saved)
        XCTAssertEqual(try store.load(), [latest])
        XCTAssertEqual(
          agent.registerCount, before + 1, "A new save cannot overlap rule deployments")
        try runtimeStore.writeRuntimeReceipt(for: XCTUnwrap(firstDocument), processID: 42)
        healthGate.resume()
        try await assertLatestRuleDeployment(
          LatestRuleDeploymentAssertion(
            controller: controller, store: store, runtimeStore: runtimeStore,
            expectedRule: latest, expectedRegistrations: before + 2, agent: agent))
      })
  }

  func testNewPreparationStopsRemainingActionsOfAnAwaitingRuntimeOperation() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let started = expectation(description: "new source preparation")
    let loader = PausedRuntimeRuleSource(started: started)
    defer { loader.resume() }
    let controller = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .global,
        rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .global, ruleSnapshots: BuiltinRuleSnapshots(loader: { await loader.load($0) }))
    try await controller.activate(seeded.server)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let previous = try XCTUnwrap(runtimeStore.loadDocument())
    try Data("42".utf8).write(to: runtimeStore.pidFileURL)
    let unregistered = expectation(description: "old operation waiting for wrapper exit")
    agent.onUnregister = { unregistered.fulfill() }
    let oldOperation = Task { await controller.execute(.stop, document: nil) }
    try await withTestTask(
      oldOperation, release: { loader.resume() },
      body: {
        try await requireTestPhase([unregistered], timeout: 3)
        let newMode = Task { await controller.setProxyMode(.rule) }
        try await withTestTask(
          newMode, release: { loader.resume() },
          body: {
            try await requireTestPhase([started], timeout: 3)
            try FileManager.default.removeItem(at: runtimeStore.pidFileURL)
            let completed = await oldOperation.value
            XCTAssertFalse(completed.succeeded)
            XCTAssertEqual(
              runtimeStore.loadDocument(), previous, "Stale stop must not delete the contract")
            loader.resume()
            await newMode.value
            XCTAssertEqual(controller.runtimeObservation?.aclSummary, "rule-proxy-default")
            XCTAssertEqual(controller.state, .running)
          })
      })
  }

  func testSystemProxyToggleDoesNotDiscardPendingRuleModePreparation() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let started = expectation(description: "background source preparation")
    let loader = PausedRuntimeRuleSource(started: started)
    defer { loader.resume() }
    let controller = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .global,
        rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .global, ruleSnapshots: BuiltinRuleSnapshots(loader: { await loader.load($0) }))
    try await controller.activate(seeded.server)
    let modeSwitch = Task { await controller.setProxyMode(.rule) }
    try await withTestTask(
      modeSwitch, release: { loader.resume() },
      body: {
        try await requireTestPhase([started], timeout: 3)
        await controller.setSystemProxyEnabled(true)
        loader.resume()
        await modeSwitch.value
        XCTAssertEqual(controller.proxyMode, .rule)
        XCTAssertTrue(controller.settings.systemProxyEnabled)
        XCTAssertEqual(controller.runtimeObservation?.aclSummary, "rule-proxy-default")
        XCTAssertEqual(controller.state, .running)
      })
  }

  func testOffIntentDuringSharedSourcePreparationCannotBeOverwritten() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let started = expectation(description: "background source preparation")
    let loader = PausedRuntimeRuleSource(started: started)
    defer { loader.resume() }
    let snapshots = BuiltinRuleSnapshots(loader: { await loader.load($0) })
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen, preferredMode: .global,
      rulePreset: .chinaDirect, agentEnabled: true)
    let controller = makeRuleEnablementController(
      store: store, settings: settings, proxyMode: .global, ruleSnapshots: snapshots)
    try await controller.activate(seeded.server)
    let modeSwitch = Task { await controller.setProxyMode(.rule) }
    try await withTestTask(
      modeSwitch, release: { loader.resume() },
      body: {
        try await requireTestPhase([started], timeout: 3)
        let identity = ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "kept.example"))
        let ruleCommit = Task {
          await controller.commitRuleDocument(
            CustomRuleDocument(rules: [], disabledIdentities: [identity]))
        }
        try await withRuleApplicationTask(
          ruleCommit, controller: controller, release: loader.resume,
          body: {
            // Persistence happens before the awaited source. Observe the owner, not timing.
            try await requireTestCondition("rule document persisted") {
              controller.ruleDocuments.current?.disabledIdentities.contains(identity) == true
            }
            await controller.setAgentEnabled(false)
            let registrationsAfterStop = agent.registerCount
            loader.resume()
            await modeSwitch.value
            let result = await ruleCommit.value
            XCTAssertEqual(result.outcome, .saved)
            await controller.ruleApplicationTask?.value
            XCTAssertEqual(result.document?.disabledIdentities, [identity])
            XCTAssertEqual(try store.loadDocument().disabledIdentities, [identity])
            XCTAssertEqual(controller.state, .off)
            XCTAssertFalse(controller.settings.agentEnabled)
            XCTAssertEqual(agent.registerCount, registrationsAfterStop)
            XCTAssertNil(RuntimeFileStore(fileURL: runtime.contract).loadDocument())
          })
      })
  }

  func testNewModeSupersedesRulePreparationWithoutRestoringOldMode() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let started = expectation(description: "background source preparation")
    let loader = PausedRuntimeRuleSource(started: started)
    defer { loader.resume() }
    let controller = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, preferredMode: .global,
        rulePreset: .chinaDirect, agentEnabled: true),
      proxyMode: .global, ruleSnapshots: BuiltinRuleSnapshots(loader: { await loader.load($0) }))
    try await controller.activate(seeded.server)
    let old = Task { await controller.setProxyMode(.rule) }
    try await withTestTask(
      old, release: { loader.resume() },
      body: {
        try await requireTestPhase([started], timeout: 3)
        await controller.setProxyMode(.direct)
        loader.resume()
        await old.value
        XCTAssertEqual(controller.proxyMode, .direct)
        XCTAssertEqual(controller.state, .running)
        XCTAssertEqual(
          RuntimeFileStore(fileURL: runtime.contract).loadDocument()?.aclRuntime?.summary, "direct")
      })
  }

}

extension RuleEnablementControllerTests {
  func testAgentOffDuringDeploymentCannotBeOverwrittenByOldRuleTransaction() async throws {
    try await interruptRuleDeployment(switchMode: false)
  }

  func testModeSwitchDuringDeploymentCannotBeOverwrittenByOldRuleTransaction() async throws {
    try await interruptRuleDeployment(switchMode: true)
  }

  private func interruptRuleDeployment(switchMode: Bool) async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let rule = CustomRule(action: .direct, match: try RuleMatch(domainExact: "kept.example"))
    try store.save([rule])
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen, preferredMode: .rule,
      rulePreset: .chinaDirect, agentEnabled: true)
    let deploymentWaiting = expectation(description: "deployment health retry paused")
    let deploymentGate = RuleRuntimeDelayGate(started: deploymentWaiting)
    defer { deploymentGate.resume() }
    var deploymentIsRunning = false
    let controller = makeRuleEnablementController(
      store: store, settings: settings, proxyMode: .rule,
      launchHealthTimeoutSeconds: 0.05,
      launchHealthRetryDelay: {
        if deploymentIsRunning {
          try await deploymentGate.wait()
        } else {
          try await Task.sleep(for: .milliseconds(1))
        }
      })
    try await controller.activate(seeded.server)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    let initialRegistrations = agent.registerCount
    configureDeploymentReceipts(runtimeStore, initialRegistrations: initialRegistrations) {
      deploymentIsRunning = true
    }
    let disabledDocument = CustomRuleDocument(rules: [rule], disabledIdentities: [rule.identity])
    let pending = Task { await controller.updateRuleDocument(disabledDocument) }
    try await withRuleApplicationTask(
      pending, controller: controller, release: deploymentGate.resume,
      body: {
        try await requireTestPhase([deploymentWaiting], timeout: 5)
        if switchMode {
          await controller.setProxyMode(.global)
        } else {
          await controller.setAgentEnabled(false)
        }
        let registrations = agent.registerCount
        deploymentGate.resume()
        let outcome = await pending.value
        XCTAssertEqual(outcome, .saved)
        await controller.ruleApplicationTask?.value
        try assertInterruptedDeploymentState(
          InterruptedDeploymentAssertion(
            controller: controller, store: store, runtimeStore: runtimeStore, rule: rule,
            switchMode: switchMode, expectedRegistrations: registrations, agent: agent))
      })
  }

  private func configureDeploymentReceipts(
    _ runtimeStore: RuntimeFileStore,
    initialRegistrations: Int,
    onDeployment: @escaping () -> Void
  ) {
    agent.onRegister = { [agent] in
      if agent?.registerCount == initialRegistrations + 1 {
        onDeployment()
        try? FileManager.default.removeItem(at: runtimeStore.runtimeStatusFileURL)
      } else {
        try? runtimeStore.writePublishedRuntimeReceipt(processID: 42)
      }
    }
  }

  func testFailedDisableKeepsSavedIntentAndReportsDeploymentFailure() async throws {
    let seeded = try makeSeededCatalog()
    let (store, _) = try makeCustomRuleStore()
    let rule = CustomRule(action: .direct, match: try RuleMatch(domainExact: "kept.example"))
    try store.save([rule])
    let settings = ProxyRuntimeSettings(
      listen: ActivationFixture.listen, preferredMode: .rule,
      rulePreset: .chinaDirect, agentEnabled: true)
    let controller = makeRuleEnablementController(
      store: store, settings: settings, proxyMode: .rule)
    try await controller.activate(seeded.server)
    let runtimeStore = RuntimeFileStore(fileURL: runtime.contract)
    agent.onRegister = {
      try? FileManager.default.removeItem(at: runtimeStore.runtimeStatusFileURL)
    }
    let result = await controller.commitRuleDocument(
      CustomRuleDocument(rules: [rule], disabledIdentities: [rule.identity]))
    XCTAssertEqual(result.outcome, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(
      result.document, CustomRuleDocument(rules: [rule], disabledIdentities: [rule.identity]))
    XCTAssertEqual(try store.loadDocument().disabledIdentities, [rule.identity])
    XCTAssertNotNil(controller.runtimeFacts.failure)
    XCTAssertNotEqual(controller.state, .running)
  }
}

extension RuleEnablementControllerTests {
  func testOffSaveUsesOwnedDocumentAndNewSessionRejectsCorruption() async throws {
    let (store, _) = try makeCustomRuleStore()
    let controller = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, rulePreset: .chinaDirect, agentEnabled: false))
    let identity = ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "saved.example"))
    let outcome = await controller.updateRuleDocument(
      CustomRuleDocument(rules: [], disabledIdentities: [identity]))
    XCTAssertEqual(outcome, .saved)
    await controller.ruleApplicationTask?.value
    XCTAssertEqual(agent.registerCount, 0)
    XCTAssertEqual(try store.loadDocument().disabledIdentities, [identity])
    let broken = Data("broken".utf8)
    try broken.write(to: store.fileURL)
    let newSession = makeRuleEnablementController(
      store: store,
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, rulePreset: .chinaDirect, agentEnabled: false))
    let rejected = await newSession.updateRuleDocument(CustomRuleDocument(rules: []))
    XCTAssertEqual(rejected, .persistenceFailed)
    XCTAssertEqual(try Data(contentsOf: store.fileURL), broken)
    XCTAssertEqual(agent.registerCount, 0)
  }
}
