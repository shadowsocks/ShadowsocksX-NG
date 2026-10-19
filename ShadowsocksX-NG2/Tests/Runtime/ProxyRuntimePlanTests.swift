import XCTest

@testable import ShadowsocksX_NG2

/// 发布 module 提供意图是否一致；计划只决定进程动作及其顺序。
final class ProxyRuntimePlanTests: XCTestCase {
  private let document = ProxyRuntimeFixture.makeDocument()

  private func actions(
    agent: LaunchAgentStatus,
    wrapper: WrapperProcessState = .notRunning,
    current: Bool = false
  ) -> [RuntimeAction] {
    ProxyRuntimePlan.actions(
      intent: .run(document), agentStatus: agent, wrapper: wrapper,
      configurationIsCurrent: current)
  }

  func testEnableWhenUnregisteredWritesContractThenRegisters() {
    XCTAssertEqual(actions(agent: .notRegistered), [.writeContract, .registerAgent])
  }

  func testEnableWhenNotFoundBehavesLikeUnregistered() {
    XCTAssertEqual(actions(agent: .notFound), [.writeContract, .registerAgent])
  }

  func testEnableWhenRequiresApprovalStillWritesAndRegisters() {
    XCTAssertEqual(actions(agent: .requiresApproval), [.writeContract, .registerAgent])
  }

  func testRunningWithCurrentPublicationSkipsWriteAndSignal() {
    XCTAssertEqual(actions(agent: .registered, wrapper: .running(pid: 42), current: true), [])
  }

  func testRunningWithChangedOrMissingPublicationWritesThenSignals() {
    XCTAssertEqual(
      actions(agent: .registered, wrapper: .running(pid: 42)),
      [.writeContract, .signalReload(pid: 42)])
  }

  func testRegisteredButWrapperDeadRelaunchesAgentEvenWhenIntentMatches() {
    XCTAssertEqual(
      actions(agent: .registered, current: true),
      [.writeContract, .unregisterAgent, .registerAgent])
  }

  func testStopWhenRegisteredUnregistersThenDeletesRuntimeFiles() {
    XCTAssertEqual(
      ProxyRuntimePlan.actions(
        intent: .stop, agentStatus: .registered, wrapper: .running(pid: 42),
        configurationIsCurrent: false),
      [.unregisterAgent, .deleteRuntimeFiles])
  }

  func testStopWhenUnregisteredOrApprovalPendingOnlyCleansResidue() {
    for status: LaunchAgentStatus in [.notRegistered, .requiresApproval] {
      XCTAssertEqual(
        ProxyRuntimePlan.actions(
          intent: .stop, agentStatus: status, wrapper: .notRunning,
          configurationIsCurrent: false),
        [.deleteRuntimeFiles])
    }
  }
}
