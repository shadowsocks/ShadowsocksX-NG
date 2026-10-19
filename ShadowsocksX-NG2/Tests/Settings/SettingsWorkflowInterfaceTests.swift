import XCTest

@testable import ShadowsocksX_NG2

/// 设置项编辑器的 UI-facing interface 测试；写入缝与占用探测均注入替身，
/// 不触碰真实偏好文件、钥匙串与系统端口。
@MainActor
final class SettingsWorkflowInterfaceTests: XCTestCase {
  var committing: FakeSettingsCommitter!
  var probe: FakeOccupancyProbe!

  override func setUp() async throws {
    try await super.setUp()
    committing = FakeSettingsCommitter()
    probe = FakeOccupancyProbe()
  }

  func makeWorkflow() -> SettingsWorkflow {
    SettingsWorkflow(
      committing: committing, occupancyProbe: probe)
  }

  func testPortEditorMapsValidationIssuesToTheAffectedFields() {
    let workflow = makeWorkflow()
    let invalid = SettingsPortDraft(socksPort: 0, httpPort: 11_087)

    XCTAssertEqual(
      workflow.portFieldState(for: .socks, editorDraft: invalid).issues,
      [.port(.socks, error: .portOutOfRange(endpoint: .socks, port: 0))])
    XCTAssertTrue(workflow.portFieldState(for: .http, editorDraft: invalid).issues.isEmpty)

    let duplicate = SettingsPortDraft(socksPort: 11_086, httpPort: 11_086)
    let duplicateIssue = SettingsFieldIssue.port(
      .socks, error: .duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 11_086))
    XCTAssertEqual(
      workflow.portFieldState(for: .socks, editorDraft: duplicate).issues,
      [
        duplicateIssue
      ])
    XCTAssertEqual(
      workflow.portFieldState(for: .http, editorDraft: duplicate).issues,
      [.port(.http, error: .duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 11_086))])
  }

  func testPortEditorReportsFreeOccupiedAndUnknownFacts() async {
    probe = FakeOccupancyProbe(occupiedPorts: [11_087])
    let workflow = makeWorkflow()
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)

    XCTAssertEqual(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy, .free)
    XCTAssertEqual(
      workflow.portFieldState(for: .http, editorDraft: draft).occupancy,
      .occupied(occupier: "other-app"))

    probe = FakeOccupancyProbe(unknownPorts: [11_086])
    let unknownWorkflow = makeWorkflow()
    let unknownDraft = unknownWorkflow.beginPortSettingsEditing()
    unknownWorkflow.refreshPortEditorOccupancy(for: unknownDraft)
    await waitUntil(
      unknownWorkflow.portFieldState(for: .socks, editorDraft: unknownDraft).occupancy != nil)
    XCTAssertEqual(
      unknownWorkflow.portFieldState(for: .socks, editorDraft: unknownDraft).occupancy,
      .unknown(detail: "无法判定"))
  }

  func testPortEditorProbeUsesTheCompleteCommittedListenIdentity() async {
    committing.committedSettings.listen.listenerMode = .allIPv4Interfaces
    let workflow = makeWorkflow()
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    let expected = RuntimeListenFacts(listen: committing.committedSettings.listen)

    await waitUntil(probe.requests.contains { $0.listen == expected })

    XCTAssertEqual(probe.requests.first(where: { $0.listen == expected })?.endpoint, .socks)
    XCTAssertEqual(probe.requests.first(where: { $0.listen == expected })?.bindAddress, "127.0.0.1")
  }

  func testRuntimePortExceptionRequiresVerifiedOwnership() async {
    probe = FakeOccupancyProbe(occupiedPorts: [11_086], occupierProcessIDs: [123])
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 123
    let workflow = makeWorkflow()
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)

    XCTAssertTrue(workflow.portFieldState(for: .socks, editorDraft: draft).isRuntimePortException)
    XCTAssertFalse(workflow.portFieldState(for: .socks, editorDraft: draft).canSuggestFreePort)
    XCTAssertTrue(workflow.canSavePortSettings(draft))

    committing.runtimeListenerProcessID = 456
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)

    XCTAssertFalse(workflow.portFieldState(for: .socks, editorDraft: draft).isRuntimePortException)
    XCTAssertFalse(workflow.canSavePortSettings(draft))
  }

  func testChangedPortWithKnownExternalOccupancyBlocksPortSave() async {
    probe = FakeOccupancyProbe(occupiedPorts: [12_086])
    let workflow = makeWorkflow()
    let draft = SettingsPortDraft(socksPort: 12_086, httpPort: 12_087)
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)

    XCTAssertTrue(workflow.portFieldState(for: .socks, editorDraft: draft).canSuggestFreePort)
    XCTAssertFalse(workflow.canSavePortSettings(draft))
    let outcome = await workflow.savePortSettings(draft)
    XCTAssertEqual(outcome, .rejected(.occupied([.socks])))
    XCTAssertTrue(committing.updateCalls.isEmpty)
  }

  func testUnknownPortOccupancyAllowsPortSave() async {
    probe = FakeOccupancyProbe(unknownPorts: [12_086])
    let workflow = makeWorkflow()
    let draft = SettingsPortDraft(socksPort: 12_086, httpPort: 12_087)
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)

    XCTAssertTrue(workflow.canSavePortSettings(draft))
    let outcome = await workflow.savePortSettings(draft)
    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(committing.committedSettings.listen.socksPort, 12_086)
  }

  func testPortSuggestionReturnsACandidateWithoutSavingIt() async {
    probe = FakeOccupancyProbe(occupiedPorts: [12_086])
    let workflow = makeWorkflow()
    let draft = SettingsPortDraft(socksPort: 12_086, httpPort: 12_087)
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)

    let outcome = await workflow.suggestFreePort(for: .socks, from: draft)

    XCTAssertEqual(outcome, .suggestedPort(port: .socks, value: 32_768))
    XCTAssertTrue(committing.updateCalls.isEmpty)
    XCTAssertEqual(committing.committedSettings.listen.socksPort, 11_086)
  }

  func testPortSettingsSaveChangesOnlyTheCommittedPorts() async {
    let original = committedSettingsForItemSaveTests()
    committing.committedSettings = original
    let workflow = makeWorkflow()
    let edited = SettingsPortDraft(socksPort: 12_096, httpPort: 12_097)
    workflow.refreshPortEditorOccupancy(for: edited)
    await waitUntil(workflow.canSavePortSettings(edited))

    let outcome = await workflow.savePortSettings(edited)

    var expected = original
    expected.listen.socksPort = edited.socksPort
    expected.listen.httpPort = edited.httpPort
    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(committing.updateCalls, [expected])
    XCTAssertEqual(committing.committedSettings, expected)
  }

  /// store 是唯一强制点：探测门禁通过后，非法端口由 store 拒绝并映射回字段 issue，
  /// 不写入、不留提交锁。探测未完成时保存命令按占用门禁拒绝，不触达 store。
  func testPortSaveRejectsInvalidPortsWithoutWriting() async {
    let workflow = makeWorkflow()
    let invalid = SettingsPortDraft(socksPort: 0, httpPort: 11_087)
    workflow.refreshPortEditorOccupancy(for: invalid)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: invalid).occupancy != nil)

    let outcome = await workflow.savePortSettings(invalid)
    XCTAssertEqual(
      outcome,
      .rejected(
        .validation([
          .port(.socks, error: .portOutOfRange(endpoint: .socks, port: 0))
        ])))
    XCTAssertFalse(workflow.isCommitting)
    XCTAssertTrue(committing.updateCalls.isEmpty)
  }

  func testProxyExceptionsSaveChangesOnlyTheCommittedExceptions() async {
    let original = committedSettingsForItemSaveTests()
    committing.committedSettings = original
    let workflow = makeWorkflow()
    let edited = "localhost\nexample.com"

    let outcome = await workflow.saveProxyExceptions(edited)

    var expected = original
    expected.proxyExceptions = edited
    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(committing.updateCalls, [expected])
    XCTAssertEqual(committing.committedSettings, expected)
    XCTAssertNil(workflow.lastFailure)
  }

  func testProxyExceptionsIgnoreListeningPersistenceFailure() async {
    let original = committedSettingsForItemSaveTests()
    committing.committedSettings = original
    committing.updateError = ProxyListeningStoreError.ioFailure(detail: "disk full")
    let workflow = makeWorkflow()

    let outcome = await workflow.saveProxyExceptions("localhost")

    XCTAssertEqual(outcome, .persisted)
    XCTAssertEqual(committing.committedSettings.proxyExceptions, "localhost")
    XCTAssertEqual(committing.committedSettings.listen, original.listen)
    XCTAssertNil(workflow.lastFailure)
    XCTAssertFalse(workflow.isCommitting)
  }

  func testItemSavesSerializeWhilePersistenceIsInProgress() async {
    committing.updateGate = AsyncGate()
    let workflow = makeWorkflow()
    let first = Task { await workflow.saveProxyExceptions("localhost") }
    await waitUntil(workflow.isCommitting)

    let second = await workflow.savePortSettings(
      SettingsPortDraft(socksPort: 11_086, httpPort: 11_087))
    committing.updateGate?.release()
    let firstOutcome = await first.value

    XCTAssertEqual(second, .rejected(.inProgress))
    XCTAssertEqual(firstOutcome, .persisted)
    XCTAssertEqual(committing.updateCalls.count, 1)
  }

  func testEqualProxyExceptionsDoNotWrite() async {
    let workflow = makeWorkflow()
    committing.committedSettings.proxyExceptions = "localhost"

    let outcome = await workflow.saveProxyExceptions("localhost")
    XCTAssertEqual(outcome, .persisted)
    XCTAssertTrue(committing.updateCalls.isEmpty)
  }

  func testStalePortOccupancyCannotOverrideTheNewerEditorDraft() async {
    let gated = GatedOccupancyProbe(
      gatedAnswer: .occupied(
        PortOccupancyFacts(
          occupier: "stale", occupiedFamilies: [.ipv4], verifiedFamilies: [.ipv4])),
      passThroughAnswer: .free)
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: gated)
    let firstDraft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: firstDraft)
    await waitUntil(gated.entered > 0)

    let laterDraft = SettingsPortDraft(socksPort: 30_086, httpPort: 11_087)
    gated.passThrough(.free)
    workflow.refreshPortEditorOccupancy(for: laterDraft)
    await waitUntil(
      workflow.portFieldState(for: .socks, editorDraft: laterDraft).occupancy == .free)

    gated.releaseGatedCalls()
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(
      workflow.portFieldState(for: .socks, editorDraft: laterDraft).occupancy, .free)
  }

  func committedSettingsForItemSaveTests() -> ProxyRuntimeSettings {
    var settings = ProxyRuntimeSettings()
    settings.listen.listenerMode = .allIPv6Interfaces
    settings.listen.socksPort = 12_086
    settings.listen.httpPort = 12_087
    settings.proxyExceptions = "existing.example"
    settings.preferredMode = .global
    settings.agentEnabled = true
    settings.systemProxyEnabled = true
    return settings
  }
}
