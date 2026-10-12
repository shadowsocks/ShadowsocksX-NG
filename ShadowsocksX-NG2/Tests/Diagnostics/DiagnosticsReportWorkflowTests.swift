import XCTest

@testable import ShadowsocksX_NG2

/// 诊断报告准备的安全验收：投毒夹具验证导出只含白名单清洗后的
/// 事件与聚合事实；raw 日志视图与报告严格分离；safe projection 无法构造时
/// 返回 typed failure 且不产生报告（ADR-0006）。
@MainActor
final class DiagnosticsReportWorkflowTests: DiagnosticsWorkflowTestCase {
  // MARK: - 报告安全验收

  func testReportContainsSafeFactsAndExcludesPoisonedSources() throws {
    appendPoisonedEvents()
    let workflow = makeWorkflow(
      catalog: { try? self.poisonedCatalogFacts() },
      agentLog: {
        "sslocal ERROR: connect to \(self.address):8388 failed: auth \(self.password)\n"
      },
      fileFacts: {
        [
          DiagnosticFileFacts(
            label: "sslocal-active.json", exists: true, isDirectory: false,
            permissionsOctal: "0600", sizeBytes: 512,
            modifiedAt: Date(timeIntervalSince1970: 1_758_000_000)),
          DiagnosticFileFacts(
            label: "agent.pid", exists: false, isDirectory: false,
            permissionsOctal: nil, sizeBytes: nil, modifiedAt: nil),
        ]
      },
      managedPlugins: {
        [
          DiagnosticPluginFacts(program: "v2ray-plugin", version: "v1.3.2", present: true),
          DiagnosticPluginFacts(program: "shadow-tls", version: "v3", present: false),
        ]
      },
      homePath: { self.home })
    facts.proxyState = .running
    facts.hasActiveTarget = true
    facts.contractSummary = "servers=1 protocols=socks mode=tcp_and_udp"

    let report = try reportText(workflow.prepareReport())

    assertNoSecrets(report)

    // 允许类目的事实必须在场：状态、端口、契约摘要、数量、插件、文件行、生成时间。
    XCTAssertTrue(report.contains("- 代理状态：运行中"))
    XCTAssertTrue(report.contains("- 活动目标：已设置"))
    XCTAssertTrue(report.contains("- 局域网监听：关闭"))
    XCTAssertTrue(report.contains("SOCKS5 端口 11086"))
    XCTAssertTrue(report.contains("servers=1 protocols=socks mode=tcp_and_udp"))
    XCTAssertTrue(report.contains("服务器：2（配置插件 1；手动 1 / 订阅 1）"))
    XCTAssertTrue(report.contains("分组：2"))
    XCTAssertTrue(report.contains("- v2ray-plugin v1.3.2：已提供"))
    XCTAssertTrue(report.contains("- shadow-tls v3：缺失"))
    XCTAssertTrue(report.contains("| sslocal-active.json | 是 | 0600 | 512 |"))
    XCTAssertTrue(report.contains("| agent.pid | 否 | — | — |"))
    let expectedTime = Self.reportTimestamp(Date(timeIntervalSince1970: 1_758_000_000))
    XCTAssertTrue(report.contains("生成时间：\(expectedTime)"), "报告应携带生成时间")
  }

  // MARK: - 事件白名单

  func testEventAllowlistKeepsCountsAndPortsButDropsFreeDetail() throws {
    appendPoisonedEvents()
    let workflow = makeWorkflow(homePath: { self.home })

    let report = try reportText(workflow.prepareReport())

    // 白名单允许的类别与安全字段（数量、端口、领域点名原因）保留。
    XCTAssertTrue(report.contains("contract written (servers=3)"))
    XCTAssertTrue(report.contains("local endpoint not ready (port=11086)"))
    XCTAssertTrue(report.contains("launch agent register failed"))
    XCTAssertTrue(report.contains("listen not established within deadline"))
    XCTAssertTrue(report.contains("runtime metadata persist failed"))
    XCTAssertTrue(report.contains("listen settings unreadable, falling back to factory defaults"))
    XCTAssertTrue(
      report.contains("activation failed: 激活目标 leaf-9 的插件 simple-obfs 未随 app 提供"),
      "领域点名原因按白名单决策进入报告")
    assertNoSecrets(report)
  }

  // MARK: - raw 日志视图与报告的分离（ADR-0006）

  func testRawLogViewServesExplicitViewButReportExcludesIt() async throws {
    appendPoisonedEvents()
    let rawTail = "wrapper stderr \(password) \(address)\n"
    let workflow = makeWorkflow(agentLog: { rawTail }, homePath: { self.home })

    // 读取循环提供 raw 投影（显式查看/复制的唯一来源）。
    let task = Task { await workflow.readWhileActive() }
    await waitUntil(workflow.logView.agentLogTail == rawTail)
    XCTAssertTrue(
      workflow.logView.guiEventLines.joined().contains("SECRET-PROBE-DETAIL"),
      "raw 事件行保留 detail 供本地排障")
    task.cancel()
    await task.value

    let report = try reportText(workflow.prepareReport())
    XCTAssertFalse(report.contains("wrapper stderr"), "raw wrapper 日志不得进入报告")
    assertNoSecrets(report)
  }

  // MARK: - best-effort 缺失标注

  func testUnavailableFactSourcesAreMarkedAndOthersRemain() throws {
    facts.proxyState = .running
    facts.contractSummary = nil
    let workflow = makeWorkflow(
      agentLog: { nil },
      fileFacts: {
        [
          DiagnosticFileFacts(
            label: "agent.pid", exists: false, isDirectory: false,
            permissionsOctal: nil, sizeBytes: nil, modifiedAt: nil)
        ]
      })

    let report = try reportText(workflow.prepareReport())

    XCTAssertTrue(report.contains("- 配置目录不可用"), "目录缺失须明确标注")
    XCTAssertTrue(report.contains("- 运行时契约摘要：不可用"), "契约缺失须明确标注")
    XCTAssertTrue(report.contains("| agent.pid | 否 | — | — |"))
    XCTAssertTrue(report.contains("- 代理状态：运行中"), "其余可用事实保留")
  }

  // MARK: - 报告 builder 只接受已裁剪事实

  func testRenderingReceivesTrimmedFactsOnly() throws {
    appendPoisonedEvents()
    var captured: [DiagnosticSnapshot] = []
    let workflow = makeWorkflow(
      catalog: { try? self.poisonedCatalogFacts() },
      agentLog: { "SECRET raw tail" },
      homePath: { self.home },
      capture: { captured.append($0) })

    _ = workflow.prepareReport()

    XCTAssertEqual(captured.count, 1)
    let snapshot = try XCTUnwrap(captured.first)
    // 快照只携带聚合事实：计数不含任何敏感值，事件行是白名单清洗文本。
    XCTAssertEqual(snapshot.catalogFacts?.counts.servers, 2)
    XCTAssertEqual(snapshot.catalogFacts?.counts.groups, 2)
    XCTAssertEqual(snapshot.eventLines.count, events.snapshot.count)
    for line in snapshot.eventLines {
      for secret in secrets {
        XCTAssertFalse(line.contains(secret), "快照事件行不得携带「\(secret)」")
      }
    }
    XCTAssertEqual(snapshot.homePathForRedaction, home, "脱敏基准随事实源注入")
  }

  func testRenderingFailureYieldsTypedFailureWithoutCompletion() {
    let workflow = makeWorkflow(render: { _ in nil })

    guard case .failed(.encodingFailed) = workflow.prepareReport() else {
      XCTFail("safe projection 无法构造时应返回 typed failure")
      return
    }
    XCTAssertFalse(
      events.snapshot.contains {
        if case .diagnosticsExported = $0.event { return true } else { return false }
      },
      "报告未生成就不得登记导出完成")
  }
}
