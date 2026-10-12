import Darwin
import XCTest

@testable import ShadowsocksX_NG2

extension AgentLifecycleChangeProtocolTests {
  // MARK: 崩溃恢复

  func testSslocalCrashExitsNonZeroForKeepAliveReplay() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "crash")

    let exitStatus = try waitForExit(wrapper)

    XCTAssertNotEqual(exitStatus, 0, "sslocal 崩溃 → wrapper 非零退出 → KeepAlive 重启重放")

    // KeepAlive 重放语义：同一份契约再拉起一次即恢复（stub 换回常驻行为）。
    let replay = try launchWrapper(behavior: "run")
    XCTAssertTrue(
      try waitUntil { self.stateLog().components(separatedBy: "invoked:").count >= 3 },
      "重放应再次拉起 sslocal")
    try cleanupWrappers()
    XCTAssertFalse(replay.isRunning, "统一清理应停止重放实例")
    XCTAssertEqual(try waitForExit(replay), 0)
    XCTAssertTrue(stateLog().contains("SIGTERM"), "统一清理应先走优雅停止链")
  }

  func testUnexpectedCleanChildExitAlsoCountsAsLoss() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "exit0")

    let exitStatus = try waitForExit(wrapper)

    XCTAssertNotEqual(
      exitStatus, 0, "sslocal 自行退出（即使干净）也应触发重放而非静默下线")
  }
}
