import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class RulesWorkflowPublicationTests: XCTestCase {
  func testNativeControlsWritingTheSameQueryDoNotRepublishThePage() async {
    let workflow = RulesWorkflow(
      loadCustom: { [] }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.query(RulesQuery(source: .gfwlist))
    var changes = 0
    let observation = workflow.$snapshot.dropFirst().sink { _ in changes += 1 }
    workflow.query(workflow.snapshot.query)
    observation.cancel()
    XCTAssertEqual(changes, 0)
  }

  func testNativeControlsWritingTheSameVisibleSelectionDoNotRepublishThePage() async {
    let workflow = RulesWorkflow(
      loadCustom: { [] }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    workflow.select([.noDotHostname])
    var changes = 0
    let observation = workflow.$snapshot.dropFirst().sink { _ in changes += 1 }
    workflow.select([.noDotHostname])
    observation.cancel()
    XCTAssertEqual(changes, 0)
  }
}
