import XCTest

@testable import ShadowsocksX_NG2

extension ProxyControlWorkflowIntegrationTests {
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

  func testDeploymentFailureClearErrorPreservesIntentAndNeedsExplicitRetry() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    systemProxy.clearError = SystemProxyError.commitFailed("busy")
    try composition.controller.runtimeFileStore.recordFailure(reason: "Agent confirmed failure")
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
    try composition.controller.runtimeFileStore.recordFailure(reason: "Agent confirmed failure")
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
    try composition.controller.runtimeFileStore.recordFailure(reason: "Agent confirmed failure")
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
    try composition.controller.runtimeFileStore.recordFailure(reason: "Agent confirmed failure")
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
