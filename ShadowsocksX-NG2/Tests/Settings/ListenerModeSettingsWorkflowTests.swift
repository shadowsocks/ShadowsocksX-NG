import XCTest

@testable import ShadowsocksX_NG2

@MainActor
extension SettingsWorkflowInterfaceTests {
  private func saveMode(_ workflow: SettingsWorkflow, _ mode: ListenerMode) async
    -> SettingsCommandOutcome
  {
    do {
      var draft = try workflow.beginLANListeningEditing()
      draft.mode = mode
      return await workflow.saveLANListening(draft)
    } catch { return .persistenceFailed(.unknown) }
  }

  func testListenerModeAllowsReplacingItsOwnActiveListener() async {
    probe = FakeOccupancyProbe(
      occupiedPorts: [11088], occupierName: "sslocal", occupierProcessIDs: [42],
      occupiedFamilies: [.ipv4])
    committing.committedSettings.listen.listenerMode = .allIPv4Interfaces
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 42
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .allIPv4AndIPv6Interfaces)

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(
      committing.committedSettings.listen.listenerMode, .allIPv4AndIPv6Interfaces)
  }

  func testListenerModeDoesNotTreatAnotherSslocalAsItsOwnListener() async {
    probe = FakeOccupancyProbe(
      occupiedPorts: [11088], occupierName: "sslocal", occupierProcessIDs: [43],
      occupiedFamilies: [.ipv4])
    committing.committedSettings.listen.listenerMode = .allIPv4Interfaces
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 42
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .allIPv4AndIPv6Interfaces)

    XCTAssertEqual(outcome, .rejected(.occupied([.socks])))
    XCTAssertEqual(committing.committedSettings.listen.listenerMode, .allIPv4Interfaces)
    XCTAssertTrue(committing.updateCalls.isEmpty)
  }

  func testListenerModeIgnoresUnrelatedIPv6OccupantWhenSavingIPv4Mode() async {
    probe = FakeOccupancyProbe(
      occupiedPorts: [11088], occupierName: "sslocal", occupierProcessIDs: [42],
      occupierIPv6ProcessIDs: [43], occupiedFamilies: [.ipv4])
    committing.committedSettings.listen.listenerMode = .allIPv4Interfaces
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 42
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .disabled)

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(committing.committedSettings.listen.listenerMode, .disabled)
  }

  func testListenerModeCanReplaceItsOwnDualStackSocketWithIPv4Mode() async {
    probe = FakeOccupancyProbe(
      occupiedPorts: [11088], occupierName: "sslocal", occupierIPv6ProcessIDs: [42],
      occupiedFamilies: [.ipv4])
    committing.committedSettings.listen.listenerMode = .allIPv4AndIPv6Interfaces
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 42
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .allIPv4Interfaces)

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(
      committing.committedSettings.listen.listenerMode, .allIPv4Interfaces)
  }

  func testListenerModeReportsUnknownDualStackFamilyAlongsideOwnListener() async {
    probe = FakeOccupancyProbe(
      occupiedPorts: [11088], occupierName: "sslocal", occupierProcessIDs: [42],
      occupiedFamilies: [.ipv4],
      unverifiedFamilyDetail: "IPv4 地址族无法判定")
    committing.committedSettings.listen.listenerMode = .allIPv4Interfaces
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 42
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .allIPv4AndIPv6Interfaces)

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(
      committing.committedSettings.listen.listenerMode, .allIPv4AndIPv6Interfaces)
  }

  func testListenerModeSavePreservesOtherCommittedSettings() async {
    committing.committedSettings.listen.socksPort = 12_086
    committing.committedSettings.listen.httpPort = 12_087
    committing.committedSettings.proxyExceptions = "existing.example"
    committing.committedSettings.preferredMode = .global
    committing.committedSettings.agentEnabled = true
    committing.committedSettings.systemProxyEnabled = true
    let original = committing.committedSettings
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .allIPv4AndIPv6Interfaces)

    var expected = original
    expected.listen.listenerMode = .allIPv4AndIPv6Interfaces
    expected.listen.lan.passwordReference =
      committing.committedSettings.listen.lan.passwordReference
    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(committing.updateCalls, [expected])
    XCTAssertEqual(committing.committedSettings, expected)
  }

  func testListenerModePersistenceFailurePreservesCommittedSettings() async {
    let original = committing.committedSettings
    committing.updateError = ProxySettingsStoreError.ioFailure(detail: "disk full")
    let workflow = makeWorkflow()

    let outcome = await saveMode(workflow, .allIPv6Interfaces)

    XCTAssertEqual(
      outcome,
      .persistenceFailed(.store(.ioFailure(detail: "disk full"))))
    XCTAssertEqual(workflow.lastFailure, .store(.ioFailure(detail: "disk full")))
    XCTAssertEqual(committing.committedSettings, original)
    XCTAssertTrue(committing.updateCalls.isEmpty)
    XCTAssertFalse(workflow.isCommitting)
  }
}
