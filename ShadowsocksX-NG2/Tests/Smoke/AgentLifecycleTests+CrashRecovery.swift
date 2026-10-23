import Darwin
import XCTest

@testable import ShadowsocksX_NG2

extension AgentLifecycleChangeProtocolTests {
  // MARK: 崩溃恢复

  func testStartupFailurePersistsAndAgentRestartCannotRetrySameDeployment() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let store = RuntimeFileStore(fileURL: contractURL)
    let wrapper = try launchWrapper(behavior: "crash")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    let failure = try XCTUnwrap(store.readFailure())
    let launches = stateLog().components(separatedBy: "invoked:").count
    let replay = try launchWrapper(behavior: "run")
    XCTAssertEqual(try waitForExit(replay), 0)
    XCTAssertEqual(stateLog().components(separatedBy: "invoked:").count, launches)
    XCTAssertEqual(store.readFailure(), failure)
    try writeContract(ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9"))
    let next = try launchWrapper(behavior: "run")
    XCTAssertTrue(
      try waitUntil { self.stateLog().components(separatedBy: "invoked:").count > launches })
    kill(next.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(next), 0)
  }

  func testUnexpectedExitBeforeHealthyIsPersistentFailureEvenWithZeroExitCode() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "exit0")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    XCTAssertNotNil(RuntimeFileStore(fileURL: contractURL).readFailure())
  }
}

extension AgentLifecycleChangeProtocolTests {
  func testUnconfirmedLivingChildPreventsAnySecondLaunch() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    // 模拟 Agent 崩溃后子进程仍活着；监管者不得冒险拉起第二实例或杀错进程。
    let pidURL = workDir.appendingPathComponent("sslocal.pid")
    try Data(String(getpid()).utf8).write(to: pidURL)
    let wrapper = try launchWrapper(behavior: "run")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    XCTAssertFalse(stateLog().contains("invoked:"))
    XCTAssertNotNil(RuntimeFileStore(fileURL: contractURL).readFailure())
    XCTAssertTrue(FileManager.default.fileExists(atPath: pidURL.path))
  }

  func testOnlyOneAgentCanOwnTheChildLifecycle() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let owner = try launchWrapper(behavior: "run")
    XCTAssertTrue(try waitUntil { self.stateLog().contains("invoked:") })
    let second = try launchWrapper(behavior: "run")
    XCTAssertEqual(try waitForExit(second), 0)
    XCTAssertEqual(stateLog().components(separatedBy: "invoked:").count, 2)
    XCTAssertTrue(owner.isRunning)
    kill(owner.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(owner), 0)
  }
}

extension AgentLifecycleChangeProtocolTests {
  func testReloadWaitsForTermIgnoringChildBeforeStartingReplacement() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "ignore-term-once")
    XCTAssertTrue(try waitUntil { self.stateLog().contains("invoked:") })
    try writeContract(ProxyRuntimeFixture.makeDocument(localPort: 2086))
    kill(wrapper.processIdentifier, SIGUSR1)
    XCTAssertTrue(try waitUntil { self.stateLog().contains("SIGTERM ignored") })
    XCTAssertEqual(
      stateLog().components(separatedBy: "invoked:").count, 2,
      "优雅停止尚未成功时不能拉起新实例")
    XCTAssertTrue(
      try waitUntil(timeout: 16) {
        self.stateLog().components(separatedBy: "invoked:").count == 3
      })
    XCTAssertFalse(stateLog().contains("OVERLAPPING CHILD"))
    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper, timeout: 16), 0)
  }
}

extension AgentLifecycleChangeProtocolTests {
  func testResourceLossDuringStartupStillPersistsDeploymentFailure() throws {
    let store = RuntimeFileStore(fileURL: contractURL)
    try writeContract(
      ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL)))
    let wrapper = try launchWrapper(behavior: "drop-acl")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    XCTAssertNotNil(store.readFailure(), "资源丢失不能阻止明确失败落盘")
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.aclFileURL.path))
    let replay = try launchWrapper(behavior: "run")
    XCTAssertEqual(try waitForExit(replay), 0)
    XCTAssertEqual(stateLog().components(separatedBy: "invoked:").count, 2)
  }
}
