import XCTest

@testable import ShadowsocksX_NG2

@MainActor
extension SettingsWorkflowInterfaceTests {
  func testPortSettingsPersistenceFailurePreservesCommittedSnapshot() async {
    let original = committedSettingsForItemSaveTests()
    committing.committedSettings = original
    committing.updateError = ProxyListeningStoreError.ioFailure(detail: "disk full")
    let workflow = makeWorkflow()
    let edited = SettingsPortDraft(socksPort: 12_096, httpPort: 12_097)
    workflow.refreshPortEditorOccupancy(for: edited)
    await waitUntil(workflow.canSavePortSettings(edited))

    let outcome = await workflow.savePortSettings(edited)

    XCTAssertEqual(
      outcome, .commitFailed(.store(.ioFailure(detail: "disk full"))))
    XCTAssertEqual(workflow.lastFailure, .store(.ioFailure(detail: "disk full")))
    XCTAssertTrue(workflow.lastFailure?.presentableMessage.contains("偏好文件") == true)
    XCTAssertEqual(committing.committedSettings, original)
    XCTAssertFalse(workflow.isCommitting)
  }
}
