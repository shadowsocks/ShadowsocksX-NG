import XCTest

@testable import ShadowsocksX_NG2

extension ProxyControlWorkflowIntegrationTests {
  func enabledSystemProxyComposition(
    probe: ProxyRuntimeFixture.FakeProbe = .reachable()
  ) async throws -> Composition {
    let server = try makeSeededCatalog()
    let composition = makeProxies(probe: probe)
    _ = try await composition.catalog.activate(server)
    _ = await composition.control.setAgentEnabled(true)
    _ = await composition.control.setSystemProxyEnabled(true)
    return composition
  }

  func waitForSnapshot(
    _ composition: Composition, matching predicate: (ProxyControlSnapshot) -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !predicate(composition.control.snapshot) && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(predicate(composition.control.snapshot), "实际快照：\(composition.control.snapshot)")
  }

  func waitForSystemProxyObservationCycle(_ composition: Composition) async throws {
    systemProxyHelper.setStatus(.requiresApproval)
    try await waitForSnapshot(composition) { $0.systemProxyApprovalRequired }
    systemProxyHelper.setStatus(.approved)
    try await waitForSnapshot(composition) { !$0.systemProxyApprovalRequired }
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

  func testSteadyObservationDoesNotProbeOrInferFailureFromReceiptState() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    let store = composition.controller.runtimeFileStore
    let callsAfterLaunch = probe.callCount
    probe.setOutcomes([.refused(detail: "must not probe while running")])
    try JSONEncoder().encode(
      RuntimeDeploymentFailure(deploymentID: UUID().uuidString, reason: "older deployment failed")
    ).write(to: store.failureFileURL)

    for receipt in [
      nil,
      RuntimeDeploymentReceipt(processID: 42, deploymentID: UUID().uuidString),
      RuntimeDeploymentReceipt(
        processID: 9999,
        deploymentID: try XCTUnwrap(store.readRuntimeReceipt()).deploymentID),
    ] {
      if let receipt {
        try JSONEncoder().encode(receipt).write(to: store.runtimeStatusFileURL)
      } else {
        try FileManager.default.removeItem(at: store.runtimeStatusFileURL)
      }
      // Two approval transitions prove that observation continues across complete iterations.
      try await waitForSystemProxyObservationCycle(composition)
      XCTAssertEqual(systemProxy.clearCount, 0)
      XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
      XCTAssertEqual(composition.control.snapshot.runtime.status, .running)
    }
    let metadata = try XCTUnwrap(RuntimePublication.metadata(at: store.supervisionFileURL))
    try store.recordFailure(reason: "unattributable after identity loss")
    try FileManager.default.removeItem(
      at: store.directoryURL.appendingPathComponent(metadata.intentMetadata))
    try await waitForSystemProxyObservationCycle(composition)
    XCTAssertEqual(systemProxy.clearCount, 0, "无法匹配部署身份时不推断当前故障")
    try FileManager.default.removeItem(at: store.supervisionFileURL)
    try await waitForSystemProxyObservationCycle(composition)
    XCTAssertEqual(systemProxy.clearCount, 0, "缺失监管资料不能把旧部署失败变成当前故障")
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .applied)
    XCTAssertEqual(probe.callCount, callsAfterLaunch)
  }

  func testDeploymentFailureClearsOnceAndExplicitRetryApplies() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    try composition.controller.runtimeFileStore.recordFailure(reason: "Agent confirmed failure")
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .paused }
    XCTAssertTrue(composition.control.snapshot.systemProxyIntentEnabled)
    XCTAssertEqual(systemProxy.clearCount, 1)
    await emitAndWaitForInspection(.networkPath, in: composition)
    XCTAssertEqual(systemProxy.clearCount, 1, "失效期间不循环重试")
    try composition.controller.runtimeFileStore.clearFailure()
    try await waitForSystemProxyObservationCycle(composition)
    XCTAssertEqual(composition.control.snapshot.systemProxyApplication, .paused)
    XCTAssertEqual(systemProxy.applied.count, 1, "删除失败记录本身不是恢复证明")
    _ = await composition.control.setAgentEnabled(true)
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .applied }
    XCTAssertEqual(systemProxy.applied.count, 2)
  }

  func testPausedIntentOffPreventsRecoveryApply() async throws {
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let composition = try await enabledSystemProxyComposition(probe: probe)
    try composition.controller.runtimeFileStore.recordFailure(reason: "Agent confirmed failure")
    try await waitForSnapshot(composition) { $0.systemProxyApplication == .paused }
    let healthObservation = composition.controller.systemProxyObserver.systemProxyHealthTask
    XCTAssertNotNil(healthObservation)
    _ = await composition.control.setSystemProxyEnabled(false)
    try composition.controller.runtimeFileStore.clearFailure()
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
}
