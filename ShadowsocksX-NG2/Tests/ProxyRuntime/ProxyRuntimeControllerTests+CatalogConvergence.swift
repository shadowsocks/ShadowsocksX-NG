import XCTest

@testable import ShadowsocksX_NG2

/// 目录提交 → 运行时收敛语义与 GLOSSARY.md「有效值未变的提交不做
/// 运行时收敛」）：与主测试类同构扩展，按既有模式独立成文件。
final class ProxyRuntimeCatalogConvergenceTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  // MARK: 目录重展开消费

  /// 模拟 wrapper 在跑（pid 指向本测试进程，kill(pid, 0) 判活通过）。
  private func simulateRunningWrapper() throws {
    try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8).write(to: runtime.pidFile)
  }

  private func committedCatalog() throws -> ConfigurationCatalog {
    try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
  }

  private func replacedFields(
    _ fields: ServerFields, address: String? = nil, remark: String? = nil
  ) -> ServerFields {
    ServerFields(
      address: address ?? fields.address,
      port: fields.port,
      encryptionMethod: fields.encryptionMethod,
      password: fields.password,
      remark: remark ?? fields.remark,
      pluginProgram: fields.pluginProgram,
      pluginOptions: fields.pluginOptions)
  }

  func testCatalogValueEditOfActiveTargetRewritesAndSignalsRunningWrapper() async throws {
    let seeded = try makeSeededCatalog()
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    try simulateRunningWrapper()

    // 修改激活服务器的连接地址（契约有效值变化），提交目录变更。
    var catalog = try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
    let fields = try ActivationFixture.serverFields(of: seeded.server, in: catalog)
    try catalog.updateServer(
      seeded.server, with: replacedFields(fields, address: "203.0.113.9"))
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))

    // 协调器生产适配入口：以刚提交的内存快照重展开。
    _ = await controller.catalogDidCommit(snapshot: try committedCatalog())

    XCTAssertEqual(controller.state, .running)
    let onDisk = try XCTUnwrap(RuntimeFileStore(fileURL: runtime.contract).loadDocument())
    XCTAssertEqual(onDisk.servers.first?.server, "203.0.113.9", "运行时文档已原子更新")
    let signalsSent = signals.signalsSent.filter { $0.signal != 0 }
    XCTAssertEqual(signalsSent.count, 1, "代理运行中：重写后应发一次 SIGUSR1")
    XCTAssertEqual(signalsSent.first?.signal, SIGUSR1)
  }

  func testCatalogRemarkOnlyEditOfActiveTargetKeepsRuntimeUntouched() async throws {
    let seeded = try makeSeededCatalog()
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let controller = makeController(probe: probe)
    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)
    try simulateRunningWrapper()
    let contractDataBefore = try Data(contentsOf: runtime.contract)

    // 修改激活服务器的备注：显示名是目录元数据，不进契约 → 零收敛
    // （不写盘、不发信号、不闪 starting、不重走健康门）。
    var catalog = try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
    let fields = try ActivationFixture.serverFields(of: seeded.server, in: catalog)
    try catalog.updateServer(
      seeded.server, with: replacedFields(fields, remark: "新加坡 01"))
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))

    let outcome = await controller.catalogDidCommit(snapshot: try committedCatalog())

    XCTAssertEqual(outcome, .converged(skippedServers: []))
    XCTAssertEqual(controller.state, .running, "状态面原地不动，不闪回 starting")
    XCTAssertEqual(try Data(contentsOf: runtime.contract), contractDataBefore, "契约逐字节未变")
    XCTAssertEqual(
      signals.signalsSent.filter { $0.signal != 0 }.count, 0, "不向 wrapper 发信号")
    XCTAssertEqual(probe.callCount, 2, "不重走健康门（初始部署探测过 SOCKS+HTTP 各一次）")
  }

  func testCatalogValueEditOutsideActiveSubtreeKeepsRuntimeUntouched() async throws {
    var catalog = ConfigurationCatalog()
    let activeServer = try ActivationFixture.addPlainServer(
      "香港 01", in: &catalog)
    let idleServer = try ActivationFixture.addPlainServer(
      "备用 02", in: &catalog)
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))
    let probe = ProxyRuntimeFixture.FakeProbe.reachable()
    let controller = makeController(probe: probe)
    try await controller.activate(activeServer)
    await controller.setAgentEnabled(true)
    try simulateRunningWrapper()
    let contractDataBefore = try Data(contentsOf: runtime.contract)

    // 修改目标子树之外服务器的连接地址：派生契约不变 → 零收敛。
    var working = try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
    let fields = try ActivationFixture.serverFields(of: idleServer, in: working)
    try working.updateServer(idleServer, with: replacedFields(fields, address: "198.51.100.9"))
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: working))

    let outcome = await controller.catalogDidCommit(snapshot: try committedCatalog())

    XCTAssertEqual(outcome, .converged(skippedServers: []))
    XCTAssertEqual(controller.state, .running, "状态面原地不动，不闪回 starting")
    XCTAssertEqual(try Data(contentsOf: runtime.contract), contractDataBefore, "契约逐字节未变")
    XCTAssertEqual(signals.signalsSent.filter { $0.signal != 0 }.count, 0, "不向 wrapper 发信号")
    XCTAssertEqual(probe.callCount, 2, "不重走健康门")
  }

  func testCatalogGroupMemberValueEditRewritesAndSignalsRunningWrapper() async throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("分组")
    let member = try ActivationFixture.addPlainServer(
      "香港 01", to: group, in: &catalog)
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: catalog))
    let controller = makeController(probe: ProxyRuntimeFixture.FakeProbe.reachable())
    try await controller.activate(group)
    await controller.setAgentEnabled(true)
    try simulateRunningWrapper()

    // 激活目标是分组：成员连接值变化是活动子树的真实值变化 → 正常收敛。
    var working = try makeTestCatalogStore(fileURL: catalogFileURL).load().catalog
    let fields = try ActivationFixture.serverFields(of: member, in: working)
    try working.updateServer(member, with: replacedFields(fields, address: "203.0.113.9"))
    try makeTestCatalogStore(fileURL: catalogFileURL).save(CatalogDocument(catalog: working))

    _ = await controller.catalogDidCommit(snapshot: try committedCatalog())

    XCTAssertEqual(controller.state, .running)
    let onDisk = try XCTUnwrap(RuntimeFileStore(fileURL: runtime.contract).loadDocument())
    XCTAssertEqual(onDisk.servers.first?.server, "203.0.113.9", "成员值变化进入运行时文档")
    XCTAssertEqual(signals.signalsSent.filter { $0.signal != 0 }.count, 1, "转发一次 SIGUSR1")
  }
}
