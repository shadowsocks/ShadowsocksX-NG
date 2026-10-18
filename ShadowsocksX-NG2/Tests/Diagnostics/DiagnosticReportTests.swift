import XCTest

@testable import ShadowsocksX_NG2

/// 诊断导出脱敏验收：投毒夹具把敏感值埋进目录、
/// 契约与状态字段，验证导出报告只含 允许的元数据类目，且导出动作自身
/// 不带出任何敏感值。
final class DiagnosticReportTests: XCTestCase {
  private let password = "SECRET-PASSWORD"
  private let pluginOpts = "obfs=http;obfs-host=SECRET-HOST"
  private let address = "203.0.113.7"
  private let remark = "香港 01"
  private let groupName = "SECRET-GROUP"
  private let subURL = "https://user:SECRET@example.com/sub/CLASH-SECRET?token=TOKEN-SECRET"

  private var secrets: [String] {
    [password, pluginOpts, address, remark, groupName, "CLASH-SECRET", "TOKEN-SECRET"]
  }

  /// 投毒目录：分组名、服务器地址、备注、插件参数全为敏感值；含订阅子树、
  /// 插件节点，用于覆盖数量统计分支。
  private func poisonedCatalog() throws -> ConfigurationCatalog {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup(groupName)
    _ = try catalog.addServer(
      ServerFields(
        address: address,
        port: 8388,
        encryptionMethod: "aes-256-gcm",
        password: password,
        remark: remark,
        pluginProgram: "v2ray-plugin",
        pluginOptions: pluginOpts
      ),
      to: group)
    let subscriptionGroup = try catalog.addGroup(groupName + "-sub", source: .subscription)
    _ = try catalog.addServer(
      ServerFields(
        address: address,
        port: 8389,
        encryptionMethod: "chacha20-ietf-poly1305",
        password: password,
        remark: remark
      ),
      source: .subscription,
      to: subscriptionGroup)
    return catalog
  }

  private func poisonedSnapshot(catalog: ConfigurationCatalog) -> DiagnosticSnapshot {
    var snapshot = DiagnosticSnapshot()
    snapshot.appVersion = "版本 2.0.0，构建 2"
    snapshot.systemSummary = "macOS Version 15.0（Build 24A335），arm64"
    snapshot.proxyState = .activationFailed(
      reason: AppPresentation.message(
        for: ActivationFailure.invalidLeaf(
          node: NodeID(rawValue: "leaf-1"),
          reason: .pluginNotProvided(program: "simple-obfs"))))
    snapshot.hasActiveTarget = true
    snapshot.listen = SslocalListenSettings()
    snapshot.runtimeDocumentSummary = Redactor.documentSummary(
      ProxyRuntimeFixture.makeDocument(
        serverAddress: address, password: password, pluginOpts: pluginOpts))
    snapshot.catalogFacts = DiagnosticCatalogFacts(
      counts: DiagnosticReportBuilder.counts(in: catalog))
    snapshot.fileFacts = [
      DiagnosticFileFacts(
        label: "sslocal-active.json", exists: true, isDirectory: false,
        permissionsOctal: "0600", sizeBytes: 512,
        modifiedAt: Date(timeIntervalSince1970: 1_758_000_000)),
      DiagnosticFileFacts(
        label: "agent.pid", exists: false, isDirectory: false,
        permissionsOctal: nil, sizeBytes: nil, modifiedAt: nil),
    ]
    snapshot.eventLines = [
      RuntimeLogEvent.contractWritten(serverCount: 2).description,
      RuntimeLogEvent.endpointProbeFailed(
        host: "127.0.0.1", port: 1086, detail: "Connection refused"
      ).description,
      RuntimeLogEvent.diagnosticsExported.description,
    ]
    snapshot.homePathForRedaction = "/Users/SECRETUSER"
    return snapshot
  }

  private func assertNoSecrets(
    _ text: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    for secret in secrets {
      XCTAssertFalse(
        text.contains(secret),
        "诊断导出不得包含敏感值「\(secret)」\n实际：\(text)",
        file: file, line: line)
    }
    XCTAssertFalse(
      text.contains("{"), "诊断导出不得携带 JSON 文档内容", file: file, line: line)
  }

  /// 验收标准「导出文件经夹具验证不含任何敏感类目」。
  func testPoisonedFixtureExportContainsOnlyAllowedCategories() throws {
    let catalog = try poisonedCatalog()
    let report = DiagnosticReportBuilder.markdown(from: poisonedSnapshot(catalog: catalog))

    assertNoSecrets(report)

    // 允许类目的事实必须在场：状态、数量、权限、存在性、脱敏元数据。
    XCTAssertTrue(report.contains("激活失败"), "缺少代理状态行：\n\(report)")
    XCTAssertTrue(report.contains("活动目标：已设置"))
    XCTAssertTrue(report.contains("局域网监听：关闭"))
    XCTAssertTrue(report.contains("SOCKS5 端口 11086"))
    XCTAssertTrue(report.contains("HTTP 端口 11087"))
    XCTAssertTrue(report.contains("servers=1 protocols=socks,http mode=tcp_and_udp"), "缺少契约脱敏摘要")
    XCTAssertFalse(report.contains("UDP 中继"), "诊断不应呈现已移除的 UDP 偏好开关")
    XCTAssertTrue(report.contains("服务器：2（配置插件 1；手动 1 / 订阅 1）"))
    XCTAssertTrue(report.contains("分组：2"))
    XCTAssertTrue(report.contains("| sslocal-active.json | 是 | 0600 | 512 |"))
    XCTAssertTrue(report.contains("| agent.pid | 否 | — | — |"))
    XCTAssertTrue(report.contains("contract written (servers=2)"))
    XCTAssertTrue(report.contains("diagnostics report exported (redacted)"))
  }

  /// 受管插件清单：名称与版本入导出；插件参数仍是敏感值不入。
  func testManagedPluginSectionListsNameAndVersionWithoutOptions() throws {
    var snapshot = poisonedSnapshot(catalog: try poisonedCatalog())
    snapshot.managedPlugins = [
      DiagnosticPluginFacts(program: "v2ray-plugin", version: "v1.3.2", present: true),
      DiagnosticPluginFacts(program: "shadow-tls", version: "v3", present: false),
    ]

    let report = DiagnosticReportBuilder.markdown(from: snapshot)

    XCTAssertTrue(report.contains("## 受管插件"), "缺少受管插件清单：\n\(report)")
    XCTAssertTrue(report.contains("- v2ray-plugin v1.3.2：已提供"))
    XCTAssertTrue(report.contains("- shadow-tls v3：缺失"))
    assertNoSecrets(report)
  }

  func testEmptyManagedPluginSectionStatesExplicitNone() {
    let report = DiagnosticReportBuilder.markdown(from: DiagnosticSnapshot())
    XCTAssertTrue(report.contains("（本版本未打包任何插件）"))
  }

  /// 监听方式与实际绑定地址进入报告；设置不再收集单独的 LAN 地址。
  func testAllIPv4ListenerModeReportsItsBindingAddress() {
    var snapshot = DiagnosticSnapshot()
    snapshot.listen = SslocalListenSettings(listenerMode: .allIPv4Interfaces)
    snapshot.homePathForRedaction = nil

    let report = DiagnosticReportBuilder.markdown(from: snapshot)

    XCTAssertTrue(report.contains("局域网监听：所有 IPv4 接口（0.0.0.0）"))
  }

  /// 契约摘要走 Redactor：完整订阅 URL 只保留 scheme+host。
  func testSubscriptionURLIsReducedToSchemeAndHost() {
    let summary = Redactor.remoteURL(subURL)
    let report = DiagnosticReportBuilder.markdown(from: DiagnosticSnapshot())

    XCTAssertFalse(report.contains(subURL))
    XCTAssertEqual(summary, "https://example.com/…")
  }

  /// 家目录前缀改写是报告渲染的兜底防线（后自由 detail 已被上游
  /// 白名单清洗，此防御保留给任何仍携带路径的文本）。
  func testHomePathRedactionRewritesPrefix() {
    let text = RuntimeLogEvent.runtimePersistFailed(
      detail: "/Users/SECRETUSER/Library/Application Support/ShadowsocksX-NG2: errno 13"
    ).description

    let redacted = DiagnosticReportBuilder.redactingHomePaths(text, home: "/Users/SECRETUSER")

    XCTAssertTrue(redacted.contains("~/Library/Application Support"))
    XCTAssertFalse(redacted.contains("/Users/SECRETUSER"))
    XCTAssertEqual(
      DiagnosticReportBuilder.redactingHomePaths(text, home: nil), text)
  }

  /// 原始错误文本不属于白名单类目：serviceFailed 只呈现固定状态文案。
  func testServiceFailedExportsLabelOnly() {
    var snapshot = DiagnosticSnapshot()
    snapshot.proxyState = .serviceFailed
    snapshot.homePathForRedaction = "/Users/SECRETUSER"

    let report = DiagnosticReportBuilder.markdown(from: snapshot)

    XCTAssertTrue(report.contains("- 代理状态：服务管理失败"))
    XCTAssertFalse(report.contains("服务失败详情"))
    XCTAssertFalse(report.contains("errno"))
  }

  /// 空快照（所有可选输入缺省）优雅降级，不崩溃、无占位泄漏。
  func testEmptySnapshotRendersGracefully() {
    let report = DiagnosticReportBuilder.markdown(from: DiagnosticSnapshot())

    XCTAssertTrue(report.contains("应用版本：未提供"))
    XCTAssertTrue(report.contains("配置目录不可用"))
    XCTAssertTrue(report.contains("（无事件）"))
    XCTAssertTrue(report.contains("活动目标：未设置"))
    assertNoSecrets(report)
  }

  func testCountsCoverServerAndPluginPresence() throws {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("g")
    _ = try catalog.addServer(
      ServerFields(
        address: address, port: 1, encryptionMethod: "aes-256-gcm",
        password: password
      ),
      to: group)
    let counts = DiagnosticReportBuilder.counts(in: catalog)

    XCTAssertEqual(
      counts,
      DiagnosticReportBuilder.CatalogCounts(
        servers: 1, groups: 1,
        serversWithPlugin: 0, manualServers: 1, subscriptionServers: 0))
  }

  /// 自定义规则诊断摘要：只含数量与内容版本，无原始域名。
  func testCustomRuleSummaryExportsCountAndVersionWithoutRawDomains() throws {
    var snapshot = DiagnosticSnapshot()
    snapshot.customRuleSummary = CustomRuleSummary(
      count: 3, contentVersion: "abc123def456")

    let report = DiagnosticReportBuilder.markdown(from: snapshot)

    XCTAssertTrue(report.contains("自定义规则：3 条（版本 abc123def456）"))
    assertNoSecrets(report)
  }

  /// 自定义规则摘要缺失时明确标注不可用。
  func testMissingCustomRuleSummaryIsMarkedUnavailable() {
    let report = DiagnosticReportBuilder.markdown(from: DiagnosticSnapshot())
    XCTAssertTrue(report.contains("自定义规则：不可用"))
  }
}
