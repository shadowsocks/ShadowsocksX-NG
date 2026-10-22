import XCTest

@testable import ShadowsocksX_NG2

@MainActor
struct LatestRuleDeploymentAssertion {
  let controller: ProxyRuntimeController
  let store: CustomRuleStore
  let runtimeStore: RuntimeFileStore
  let expectedRule: CustomRule
  let expectedRegistrations: Int
  let agent: ProxyRuntimeFixture.FakeLaunchAgent
}

@MainActor
func assertLatestRuleDeployment(_ assertion: LatestRuleDeploymentAssertion) async throws {
  await assertion.controller.ruleApplicationTask?.value
  XCTAssertEqual(try assertion.store.load(), [assertion.expectedRule])
  XCTAssertEqual(assertion.agent.registerCount, assertion.expectedRegistrations)
  let data = try Data(contentsOf: assertion.runtimeStore.aclFileURL)
  let content = String(bytes: data, encoding: .utf8) ?? ""
  XCTAssertTrue(content.contains("after-flight.example"))
  XCTAssertFalse(content.contains("in-flight.example"))
  XCTAssertEqual(assertion.controller.state, .running)
}

@MainActor
struct InterruptedDeploymentAssertion {
  let controller: ProxyRuntimeController
  let store: CustomRuleStore
  let runtimeStore: RuntimeFileStore
  let rule: CustomRule
  let switchMode: Bool
  let expectedRegistrations: Int
  let agent: ProxyRuntimeFixture.FakeLaunchAgent
}

@MainActor
func assertInterruptedDeploymentState(_ assertion: InterruptedDeploymentAssertion) throws {
  XCTAssertEqual(try assertion.store.loadDocument().disabledIdentities, [assertion.rule.identity])
  XCTAssertEqual(assertion.agent.registerCount, assertion.expectedRegistrations)
  if assertion.switchMode {
    XCTAssertEqual(assertion.controller.proxyMode, .global)
    XCTAssertEqual(assertion.runtimeStore.loadDocument()?.aclRuntime?.summary, "global")
  } else {
    XCTAssertFalse(assertion.controller.settings.agentEnabled)
    XCTAssertEqual(assertion.controller.state, .off)
    XCTAssertNil(assertion.runtimeStore.loadDocument())
  }
}
