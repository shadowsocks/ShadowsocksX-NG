import XCTest

@testable import ShadowsocksX_NG2

/// 诊断工作流的读取生命周期与导出登记测试：安全摘要共用
/// projection、只读收集、读取代际与取消语义、导出完成只在显式确认后登记、
/// 目录事实缝只输出聚合事实。
@MainActor
final class DiagnosticsWorkflowLifecycleTests: DiagnosticsWorkflowTestCase {
  // MARK: - 安全摘要

  func testSummaryTracksRuntimeFactsWhileReading() async throws {
    let workflow = makeWorkflow()
    XCTAssertEqual(workflow.summary.proxyState, .off)
    XCTAssertFalse(workflow.summary.hasActiveTarget)

    let task = Task { await workflow.readWhileActive() }
    facts.proxyState = .running
    facts.hasActiveTarget = true
    await waitUntil(
      workflow.summary == DiagnosticSummary(proxyState: .running, hasActiveTarget: true))
    task.cancel()
    await task.value
  }

  // MARK: - 导出完成登记

  func testExportCompletionRecordedOnlyAfterExplicitConfirmation() throws {
    let workflow = makeWorkflow(catalog: { DiagnosticCatalogFacts() })

    guard case .ready = workflow.prepareReport() else {
      XCTFail("标准事实源应产出 ready 报告")
      return
    }
    XCTAssertTrue(
      events.snapshot.isEmpty, "打开面板/准备报告不得登记导出完成")

    workflow.noteExportCompleted()

    XCTAssertEqual(events.snapshot.last?.event, .diagnosticsExported)
  }

  // MARK: - 只读与读取生命周期

  func testCollectionIsReadOnly() async throws {
    let fileURL = workDir.appendingPathComponent("catalog.json")
    try Data("{\"servers\":1}".utf8).write(to: fileURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    let fileFacts: @MainActor @Sendable () -> [DiagnosticFileFacts] = {
      [DiagnosticFileCollector.collect(label: "catalog.json", url: fileURL)]
    }
    let beforeFacts = fileFacts()
    let beforeContents = try Data(contentsOf: fileURL)

    var counter = 0
    let workflow = makeWorkflow(
      catalog: { DiagnosticCatalogFacts() },
      agentLog: {
        counter += 1
        return "tail-\(counter)"
      },
      fileFacts: fileFacts)
    let initialSummary = workflow.summary
    let task = Task { await workflow.readWhileActive() }
    // 计数闭包每次轮询都产生新值：等待「首个 tail 投影到达」而非具体值。
    await waitUntil(workflow.logView.rows.contains { $0.text.hasPrefix("tail-") })
    _ = workflow.prepareReport()
    task.cancel()
    await task.value

    XCTAssertEqual(fileFacts(), beforeFacts, "收集不得改变文件元数据")
    XCTAssertEqual(try Data(contentsOf: fileURL), beforeContents, "收集不得改变文件内容")
    XCTAssertEqual(workflow.summary, initialSummary, "收集不得改变 runtime 事实")
    // 凭据与系统代理设置不在 workflow 的依赖面内：module 结构上不可触达。
  }

  /// 读取代际：新一代读取进入后，旧循环必须退场，不得再发布
  /// 旧代结果覆盖最新 projection。
  func testNewerReadGenerationSupersedesOlderLoop() async throws {
    var counter = 0
    let workflow = makeWorkflow(agentLog: {
      counter += 1
      return "tail-\(counter)"
    })

    let older = Task { await workflow.readWhileActive() }
    await waitUntil(workflow.logView.rows.contains { $0.text.hasPrefix("tail-") })

    let newer = Task { await workflow.readWhileActive() }
    // 旧循环最迟在下一个轮询间隔随代际守卫退出。
    let olderExited = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        await older.value
        return true
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(2))
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
    XCTAssertTrue(olderExited, "旧一代读取循环应在新一代进入后退场")

    newer.cancel()
    await newer.value
    XCTAssertTrue(
      workflow.logView.rows.contains { $0.text.hasPrefix("tail-") }, "最新 projection 保持")
  }

  func testCancellingReadStopsPublishingNewProjections() async throws {
    var counter = 0
    let workflow = makeWorkflow(agentLog: {
      counter += 1
      return "tail-\(counter)"
    })

    let task = Task { await workflow.readWhileActive() }
    await waitUntil(workflow.logView.rows.contains { $0.text.hasPrefix("tail-") })
    task.cancel()
    await task.value
    let frozen = workflow.logView

    events.append(event: .agentRegistered, timestamp: Date())
    try await Task.sleep(for: .milliseconds(100))

    XCTAssertEqual(workflow.logView, frozen, "取消读取后不得再发布新 projection")
  }

  // MARK: - 目录事实缝

  func testCatalogWorkflowProvidesAggregateDiagnosticFactsOnly() async throws {
    let fileURL = workDir.appendingPathComponent("catalog.json")
    let coordinator = CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(fileURL: fileURL), runtime: FakeCatalogRuntime())
    let catalogWorkflow = makeCatalogWorkflow(
      coordinator: coordinator,
      plugins: ActivationFixture.TestManagedPlugins(pathsByProgram: [:]))
    // 带受管插件引用的服务器：程序在集内但可执行文件缺失 → 已知无效。
    let uri =
      "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@\(address):8388"
      + "/?plugin=v2ray-plugin%3Bmode%3Dwebsocket"
    _ = await catalogWorkflow.importServers(from: [.clipboardText(uri)], into: nil)

    let facts = catalogWorkflow.diagnosticCatalogFacts

    XCTAssertEqual(facts.counts.servers, 1)
    XCTAssertEqual(facts.counts.groups, 0)
    XCTAssertEqual(facts.counts.serversWithPlugin, 1)
    XCTAssertEqual(facts.counts.manualServers, 1)
    XCTAssertEqual(facts.counts.subscriptionServers, 0)
    XCTAssertEqual(facts.knownInvalidServerCount, 1, "插件缺失的服务器计为已知无效")
  }
}
