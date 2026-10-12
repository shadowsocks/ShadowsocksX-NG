import XCTest

@testable import ShadowsocksX_NG2

/// 纯决策层：代理开关、GUI 重同步与目录重展开
/// 共用的计划表。断言的是动作序列——执行次序即协议次序。
final class ProxyRuntimePlanTests: XCTestCase {
  private let document = ProxyRuntimeFixture.makeDocument()

  private func contractData() throws -> Data {
    try document.jsonData()
  }

  private func actions(
    _ intent: RuntimeIntent,
    agent: LaunchAgentStatus,
    wrapper: WrapperProcessState = .notRunning,
    disk: Data?? = nil
  ) throws -> [RuntimeAction] {
    let fallback = try contractData()
    let prepared: PreparedRuntimeContract?
    if case .run(let desired) = intent {
      prepared = try PreparedRuntimeContract(desired)
    } else {
      prepared = nil
    }
    return ProxyRuntimePlan.actions(
      intent: intent,
      agentStatus: agent,
      wrapper: wrapper,
      contractOnDisk: disk ?? fallback, preparedContract: prepared)
  }

  // MARK: 开启代理

  func testEnableWhenUnregisteredWritesContractThenRegisters() throws {
    XCTAssertEqual(
      try actions(.run(document), agent: .notRegistered, disk: .some(nil)),
      [.writeContract, .registerAgent],
      "启动服务前写入（D5），注册后 launchd 拉起的 wrapper 直接读新档")
  }

  func testEnableWhenNotFoundBehavesLikeUnregistered() throws {
    XCTAssertEqual(
      try actions(.run(document), agent: .notFound, disk: .some(nil)),
      [.writeContract, .registerAgent])
  }

  func testEnableWhenRequiresApprovalStillWritesAndRegisters() throws {
    XCTAssertEqual(
      try actions(.run(document), agent: .requiresApproval, disk: .some(nil)),
      [.writeContract, .registerAgent],
      "注册动作把 requiresApproval 上抛给用户批准，计划不变")
  }

  func testRunningWithIdenticalContractSkipsWrite() throws {
    XCTAssertEqual(
      try actions(
        .run(document), agent: .registered, wrapper: .running(pid: 42),
        disk: try contractData()),
      [],
      "相同内容跳过写入与信号（激活状态机幂等注记）")
  }

  func testPreparedContractForAnotherDocumentDoesNotSkipDeployment() throws {
    let other = ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9")
    let prepared = try PreparedRuntimeContract(other)

    XCTAssertEqual(
      ProxyRuntimePlan.actions(
        intent: .run(document), agentStatus: .registered, wrapper: .running(pid: 42),
        contractOnDisk: prepared.data, preparedContract: prepared),
      [.writeContract, .signalReload(pid: 42)],
      "Another document's prepared bytes cannot make this intent appear converged")
  }

  func testRunningWithStaleContractWritesThenSignalsReload() throws {
    let stale = try ProxyRuntimeFixture.makeDocument(
      serverAddress: "198.51.100.9", localPort: 1086
    ).jsonData()

    XCTAssertEqual(
      try actions(.run(document), agent: .registered, wrapper: .running(pid: 42), disk: stale),
      [.writeContract, .signalReload(pid: 42)],
      "原子替换后发 SIGUSR1 reload（D5 变更协议）")
  }

  func testRunningWithMissingContractWritesThenSignalsReload() throws {
    XCTAssertEqual(
      try actions(.run(document), agent: .registered, wrapper: .running(pid: 42), disk: .some(nil)),
      [.writeContract, .signalReload(pid: 42)])
  }

  func testACLChangeUpdatesContractAndSignalsWrapperForFullRestart() throws {
    let next = document.replacingACL(
      .direct(at: URL(fileURLWithPath: "/tmp/ssxng-tests/sslocal-active.acl")))

    XCTAssertEqual(
      ProxyRuntimePlan.actions(
        intent: .run(next), agentStatus: .registered,
        wrapper: .running(pid: 42), contractOnDisk: try contractData()),
      [.writeContract, .signalReload(pid: 42)],
      "ACL 路径/摘要变化进入 wrapper 重启判定")
  }

  func testRegisteredButWrapperDeadRelaunchesAgent() throws {
    XCTAssertEqual(
      try actions(
        .run(document), agent: .registered, wrapper: .notRunning, disk: try contractData()),
      [.writeContract, .unregisterAgent, .registerAgent],
      "已注册但 wrapper 已干净退出：写盘后强制重新拉起，让 wrapper 读新档")
  }

  // MARK: 停止代理

  func testStopWhenRegisteredUnregistersThenDeletesRuntimeFiles() throws {
    XCTAssertEqual(
      try actions(.stop, agent: .registered, wrapper: .running(pid: 42)),
      [.unregisterAgent, .deleteRuntimeFiles],
      "显式停止协议次序（D2）：注销（SIGTERM wrapper→停 sslocal）后才删文件")
  }

  func testStopWhenUnregisteredOnlyCleansResidue() throws {
    XCTAssertEqual(
      try actions(.stop, agent: .notRegistered),
      [.deleteRuntimeFiles])
  }

  func testStopWhenApprovalPendingOnlyCleansResidue() throws {
    XCTAssertEqual(
      try actions(.stop, agent: .requiresApproval),
      [.deleteRuntimeFiles])
  }

  // MARK: 服务器列表变化 vs 监听结构变化

  func testServerOnlyChangeStillTriggersSignalReload() throws {
    // 内容级差异由 plan 比对（数据不等），结构判定在 wrapper：这里只断言
    // 服务器列表变化会带来重写+信号，而不是被误判为「无需动作」。
    let otherServers = ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.1")
    let onDisk = try ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.2").jsonData()

    XCTAssertEqual(
      ProxyRuntimePlan.actions(
        intent: .run(otherServers), agentStatus: .registered,
        wrapper: .running(pid: 7), contractOnDisk: onDisk),
      [.writeContract, .signalReload(pid: 7)])
  }
}
