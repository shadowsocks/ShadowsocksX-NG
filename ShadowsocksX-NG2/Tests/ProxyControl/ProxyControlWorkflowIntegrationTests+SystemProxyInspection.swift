import XCTest

@testable import ShadowsocksX_NG2

extension ProxyControlWorkflowIntegrationTests {
  private func enabledSystemProxyComposition(
    probe: ProxyRuntimeFixture.FakeProbe = .reachable()
  ) async throws -> Composition {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: probe)
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    _ = await composition.control.setSystemProxyEnabled(true)
    return composition
  }

  private func waitForSnapshot(
    _ composition: Composition, matching predicate: (ProxyControlSnapshot) -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !predicate(composition.control.snapshot) && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(predicate(composition.control.snapshot), "实际快照：\(composition.control.snapshot)")
  }

  func testCurrentDifferencesIncludeChangedAndNewServicesAndDisappearWhenRestored() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    systemProxy.services = [
      SystemProxyServiceState(
        identifier: original.identifier, configuration: nil, name: "很长的办公室 Wi-Fi 网络接口名称"),
      SystemProxyServiceState(
        identifier: .init(locationID: "home", serviceID: "ethernet"), configuration: nil,
        name: "USB Ethernet"),
    ]
    networkMonitor.emit(.proxyConfiguration)
    try await waitForSnapshot(composition) { $0.systemProxyInspection.differences.count == 2 }
    XCTAssertEqual(
      composition.control.snapshot.systemProxyInspection.differences.map(\.kind),
      [.changed, .notApplied])
    XCTAssertEqual(
      composition.control.snapshot.systemProxyInspection.differences.map(\.name),
      ["很长的办公室 Wi-Fi 网络接口名称", "USB Ethernet"])
    XCTAssertEqual(systemProxy.applied.count, 1)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.canRepair)

    systemProxy.services[0] = original
    networkMonitor.emit(.proxyConfiguration)
    try await waitForSnapshot(composition) { $0.systemProxyInspection.differences.count == 1 }
    _ = await composition.control.repairSystemProxy()
    XCTAssertEqual(systemProxy.repairedServices, [.init(locationID: "home", serviceID: "ethernet")])
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.differences.isEmpty)
  }

  func testRepairReadsLatestLocationAndSkipsAlreadyConsistentServices() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier, configuration: nil, name: original.name)
    _ = await composition.control.recheckSystemProxy()
    systemProxy.services = [
      SystemProxyServiceState(
        identifier: .init(locationID: "work", serviceID: "vpn"), configuration: nil, name: "VPN"),
      SystemProxyServiceState(
        identifier: .init(locationID: "work", serviceID: "wifi"),
        configuration: original.configuration, name: "Wi-Fi"),
    ]
    _ = await composition.control.repairSystemProxy()
    XCTAssertEqual(systemProxy.repairedServices, [.init(locationID: "work", serviceID: "vpn")])
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
    await emitAndWaitForInspection(.networkPath, in: composition)
    XCTAssertEqual(systemProxy.applied.count, 2, "被动事件不重写")
  }

  func testRepairSuccessResponseCannotHideRemainingDifference() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier, configuration: nil, name: original.name)
    _ = await composition.control.recheckSystemProxy()
    systemProxy.preserveConfigurationOnApply = true
    _ = await composition.control.repairSystemProxy()
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .changed)
    XCTAssertEqual(
      composition.control.snapshot.systemProxyInspection.differences.map(\.kind), [.remaining])
  }

  func testDuplicateRepairDoesNotWriteTwiceAndKeepsNamesDuringProgress() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier, configuration: nil, name: original.name)
    _ = await composition.control.recheckSystemProxy()
    let gate = ProxyControlOperationGate(started: expectation(description: "repair paused"))
    defer { gate.resume() }
    systemProxy.beforeRepair = { await gate.wait() }
    let first = Task { await composition.control.repairSystemProxy() }
    await fulfillment(of: [gate.started], timeout: 2)
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .repairing)
    XCTAssertEqual(
      composition.control.snapshot.systemProxyInspection.differences.map(\.name), ["Wi-Fi"])
    XCTAssertFalse(composition.control.snapshot.systemProxyInspection.canRepair)
    _ = await composition.control.repairSystemProxy()
    gate.resume()
    _ = await first.value
    XCTAssertEqual(systemProxy.applied.count, 2)
  }

  func testReadFailureIsUnknownAndRecheckNeverWrites() async throws {
    let composition = try await enabledSystemProxyComposition()
    systemProxy.readError = SystemProxyError.preferencesUnavailable
    let failed = await composition.control.recheckSystemProxy()
    XCTAssertEqual(failed.systemProxyApplication, .unreadable(.operation(.preferencesUnavailable)))
    XCTAssertFalse(failed.systemProxyInspection.canRepair)
    XCTAssertEqual(systemProxy.applied.count, 1)
    systemProxy.readError = nil
    let restored = await composition.control.recheckSystemProxy()
    XCTAssertEqual(restored.systemProxyApplication, .applied)
    XCTAssertEqual(systemProxy.applied.count, 1)
  }

  func testHealthLossClearsOnceAndRecoveryAutomaticallyApplies() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    probe.setOutcomes([.refused(detail: "local stopped")])
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .paused }
    XCTAssertTrue(composition.control.snapshot.systemProxyIntentEnabled)
    XCTAssertEqual(systemProxy.clearCount, 1)
    await emitAndWaitForInspection(.networkPath, in: composition)
    XCTAssertEqual(systemProxy.clearCount, 1, "失效期间不循环重试")
    probe.setOutcomes([.reachable])
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .applied }
    XCTAssertEqual(systemProxy.applied.count, 2)
  }

  func testPausedIntentOffPreventsRecoveryApply() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    probe.setOutcomes([.refused(detail: "stopped")])
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .paused }
    let healthObservation = composition.controller.systemProxyObserver.systemProxyHealthTask
    XCTAssertNotNil(healthObservation)
    _ = await composition.control.setSystemProxyEnabled(false)
    probe.setOutcomes([.reachable])
    await healthObservation?.value
    XCTAssertFalse(networkMonitor.isObserving, "关闭意图后应停止观察与自动恢复")
    XCTAssertEqual(systemProxy.applied.count, 1)
    XCTAssertFalse(composition.control.snapshot.systemProxyIntentEnabled)
  }

  func testClearFailureAndApprovalCoexistAfterIntentOffWithoutAutomaticRetry() async throws {
    let composition = try await enabledSystemProxyComposition()
    systemProxy.clearError = SystemProxyError.helperUnavailable("approval missing")
    systemProxyHelper.setStatus(.requiresApproval)
    let failed = await composition.control.setSystemProxyEnabled(false)
    XCTAssertEqual(failed.systemProxyApplication, .clearFailed(.operation(.helperUnavailable)))
    XCTAssertTrue(failed.systemProxyApprovalRequired)
    XCTAssertFalse(failed.systemProxyInspection.canRetryClear)
    XCTAssertNil(StatusMenuModel.summary(from: failed).systemProxyDetail, "批准原因不重复说明")
    systemProxyHelper.setStatus(.approved)
    _ = await composition.control.openSystemProxyHelperApproval()
    XCTAssertEqual(systemProxy.clearCount, 1)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.canRetryClear)
    systemProxy.clearError = nil
    let restored = await composition.control.retrySystemProxyClear()
    XCTAssertEqual(restored.systemProxyApplication, .idle)
    XCTAssertEqual(systemProxy.clearCount, 2)
  }

  func testFailedApplyApprovalDoesNotRetryButUnattemptedEnableContinues() async throws {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    systemProxyHelper.setStatus(.requiresApproval)
    _ = await composition.control.setSystemProxyEnabled(true)
    XCTAssertTrue(systemProxy.applied.isEmpty)
    systemProxy.applyError = SystemProxyError.helperUnavailable("connection failed")
    systemProxyHelper.setStatus(.approved)
    _ = await composition.control.openSystemProxyHelperApproval()
    XCTAssertEqual(
      composition.control.snapshot.systemProxyApplication, .failed(.operation(.helperUnavailable)))
    systemProxyHelper.setStatus(.requiresApproval)
    _ = await composition.control.recheckSystemProxy()
    XCTAssertTrue(composition.control.snapshot.systemProxyApprovalRequired)
    XCTAssertFalse(composition.control.snapshot.systemProxyInspection.canRepair)
    systemProxy.applyError = nil
    systemProxyHelper.setStatus(.approved)
    _ = await composition.control.openSystemProxyHelperApproval()
    XCTAssertTrue(systemProxy.applied.isEmpty)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.canRepair)
    _ = await composition.control.repairSystemProxy()
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
  }

  func testHealthyStartupOnlyReadsAndNewLocationIsNotAppliedCategory() async throws {
    _ = try makeSeededCatalog()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true),
      proxyMode: .direct)
    let before = systemProxy.applied.count
    await composition.control.resyncOnLaunch()
    XCTAssertEqual(systemProxy.applied.count, before)
    XCTAssertEqual(systemProxy.clearCount, 0)
    systemProxy.services = [
      SystemProxyServiceState(
        identifier: .init(locationID: "new", serviceID: "wifi"), configuration: nil, name: "Airport"
      )
    ]
    networkMonitor.emit(.networkConfiguration)
    try await waitForSnapshot(composition) {
      $0.systemProxyInspection.differences.map(\.name) == ["Airport"]
    }
    XCTAssertEqual(
      composition.control.snapshot.systemProxyInspection.differences.map(\.kind), [.notApplied])
    XCTAssertEqual(systemProxy.applied.count, before)
  }

  func testUnhealthyStartupClearsAndPreservesIntentWithoutApplying() async throws {
    _ = try makeSeededCatalog()
    let composition = makeProxies(
      probe: ProxyRuntimeFixture.FakeProbe.refusing(),
      settings: ProxyRuntimeSettings(
        listen: ActivationFixture.listen, agentEnabled: true, systemProxyEnabled: true))
    await composition.control.resyncOnLaunch()
    XCTAssertEqual(systemProxy.clearCount, 1)
    XCTAssertTrue(systemProxy.applied.isEmpty)
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .paused)
    XCTAssertTrue(composition.control.snapshot.systemProxyIntentEnabled)
  }

  func testSavedExceptionsAutomaticallyApplyButDraftAndDisabledIntentDoNot() async throws {
    let composition = try await enabledSystemProxyComposition()
    let editor = SettingsWorkflow(committing: composition.controller)
    _ = editor.beginProxyExceptionsEditing()
    XCTAssertEqual(systemProxy.applied.count, 1, "草稿不写系统设置")
    _ = await editor.saveProxyExceptions("example.com")
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .applied }
    XCTAssertEqual(systemProxy.applied.count, 2)
    XCTAssertTrue(try XCTUnwrap(systemProxy.applied.last).exceptions.contains("example.com"))
    _ = await composition.control.setSystemProxyEnabled(false)
    _ = await editor.saveProxyExceptions("example.org")
    XCTAssertEqual(systemProxy.applied.count, 2, "关闭意图下保存不应用")
  }

  func testHealthClearFailurePreservesIntentAndNeedsExplicitRetry() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    systemProxy.clearError = SystemProxyError.commitFailed("busy")
    probe.setOutcomes([.refused(detail: "local stopped")])
    try await waitForSnapshot(composition) { $0.systemProxyApplication.isClearFailure }
    XCTAssertTrue(composition.control.snapshot.systemProxyIntentEnabled)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.canRetryClear)
    XCTAssertFalse(composition.control.snapshot.systemProxyInspection.canRepair)
    await emitAndWaitForInspection(.networkConfiguration, in: composition)
    XCTAssertEqual(systemProxy.clearCount, 1)
    systemProxy.clearError = nil
    _ = await composition.control.retrySystemProxyClear()
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .paused)
    XCTAssertEqual(systemProxy.clearCount, 2)
  }

  func testRepairFailureKeepsDifferenceAndApprovalPathUntilExplicitRetry() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier, configuration: nil, name: original.name)
    _ = await composition.control.recheckSystemProxy()
    systemProxy.beforeRepair = { [systemProxyHelper] in
      systemProxyHelper?.setStatus(.requiresApproval)
    }
    systemProxy.applyError = SystemProxyError.helperUnavailable("approval")
    let failed = await composition.control.repairSystemProxy()
    XCTAssertEqual(failed.systemProxyApplication, .repairFailed(.operation(.helperUnavailable)))
    XCTAssertEqual(failed.systemProxyInspection.differences.map(\.name), ["Wi-Fi"])
    XCTAssertTrue(failed.systemProxyApprovalRequired)
    XCTAssertFalse(failed.systemProxyInspection.canRepair)
    systemProxyHelper.setStatus(.approved)
    systemProxy.beforeRepair = nil
    systemProxy.applyError = nil
    try await waitForSnapshot(composition) { $0.systemProxyInspection.canRepair }
    XCTAssertEqual(systemProxy.applied.count, 1, "批准后失败操作不自动重试")
    _ = await composition.control.repairSystemProxy()
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
  }

  func testUnmanagedFieldChangeAndEquivalentWritesStayAppliedWithoutWrites() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    var dictionary = try SystemProxyPlanner.dictionary(
      from: original.configuration, serviceID: "wifi")
    dictionary["ExternalMetadata"] = "unmanaged"
    dictionary.removeValue(forKey: "ProxyAutoDiscoveryEnable")
    dictionary["ExceptionsList"] = (dictionary["ExceptionsList"] as? [String])?.reversed().map {
      $0
    }
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier,
      configuration: try SystemProxyPlanner.propertyListData(from: dictionary, serviceID: "wifi"),
      name: original.name)
    let result = await composition.control.recheckSystemProxy()
    XCTAssertEqual(result.systemProxyApplication, .applied)
    XCTAssertTrue(result.systemProxyInspection.differences.isEmpty)
    XCTAssertEqual(systemProxy.applied.count, 1)
  }

  func testPassiveReadCannotOverwriteHealthSuspension() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    let gate = ProxyControlOperationGate(started: expectation(description: "read paused"))
    defer { gate.resume() }
    systemProxy.beforeRead = { await gate.wait() }
    let read = Task { await composition.control.recheckSystemProxy() }
    await fulfillment(of: [gate.started], timeout: 2)
    probe.setOutcomes([.refused(detail: "stopped")])
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .paused }
    gate.resume()
    _ = await read.value
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .paused)
    XCTAssertEqual(systemProxy.clearCount, 1)
  }

  func testPassiveReadCannotOverwriteHealthClearFailure() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    systemProxy.clearError = SystemProxyError.commitFailed("busy")
    let gate = ProxyControlOperationGate(started: expectation(description: "read paused"))
    defer { gate.resume() }
    systemProxy.beforeRead = { await gate.wait() }
    let read = Task { await composition.control.recheckSystemProxy() }
    await fulfillment(of: [gate.started], timeout: 2)
    probe.setOutcomes([.refused(detail: "stopped")])
    try await waitForSnapshot(composition) { $0.systemProxyApplication.isClearFailure }
    gate.resume()
    _ = await read.value
    XCTAssertEqual(
      composition.control.snapshot.systemProxyApplication, .clearFailed(.operation(.commitFailed)))
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.canRetryClear)
  }

  func testIntentOffDuringRepairPreflightPreventsWrite() async throws {
    let composition = try await enabledSystemProxyComposition()
    let original = systemProxy.services[0]
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier, configuration: nil, name: original.name)
    _ = await composition.control.recheckSystemProxy()
    let gate = ProxyControlOperationGate(started: expectation(description: "read paused"))
    defer { gate.resume() }
    systemProxy.beforeRead = { await gate.wait() }
    let repair = Task { await composition.control.repairSystemProxy() }
    await fulfillment(of: [gate.started], timeout: 2)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.isBusy)
    let off = Task { await composition.control.setSystemProxyEnabled(false) }
    try await waitForSnapshot(composition) { !$0.systemProxyIntentEnabled }
    gate.resume()
    _ = await repair.value
    _ = await off.value
    XCTAssertEqual(systemProxy.applied.count, 1)
    XCTAssertEqual(systemProxy.clearCount, 1)
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .idle)
  }

  func testHealthLossDuringRepairPreflightPreventsWrite() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    let original = systemProxy.services[0]
    systemProxy.services[0] = SystemProxyServiceState(
      identifier: original.identifier, configuration: nil, name: original.name)
    _ = await composition.control.recheckSystemProxy()
    let gate = ProxyControlOperationGate(started: expectation(description: "read paused"))
    defer { gate.resume() }
    systemProxy.beforeRead = { await gate.wait() }
    let repair = Task { await composition.control.repairSystemProxy() }
    await fulfillment(of: [gate.started], timeout: 2)
    XCTAssertTrue(composition.control.snapshot.systemProxyInspection.isBusy)
    probe.setOutcomes([.refused(detail: "stopped")])
    try await waitForSnapshot(composition) { $0.runtime.status != .running }
    gate.resume()
    _ = await repair.value
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .paused }
    XCTAssertEqual(systemProxy.applied.count, 1)
    XCTAssertEqual(systemProxy.clearCount, 1)
  }
  func testAgentOffClearFailureKeepsApprovalEntryAfterCascade() async throws {
    let composition = try await enabledSystemProxyComposition()
    systemProxyHelper.setStatus(.requiresApproval)
    systemProxy.clearError = SystemProxyError.helperUnavailable("approval")
    let failed = await composition.control.setAgentEnabled(false)
    XCTAssertFalse(failed.systemProxyIntentEnabled)
    XCTAssertFalse(failed.agentIntentEnabled)
    XCTAssertEqual(failed.systemProxyApplication, .clearFailed(.operation(.helperUnavailable)))
    XCTAssertTrue(failed.systemProxyApprovalRequired)
    XCTAssertFalse(failed.systemProxyInspection.canRetryClear)
  }
}
