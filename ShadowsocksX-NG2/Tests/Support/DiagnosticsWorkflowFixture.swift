import XCTest

@testable import ShadowsocksX_NG2

/// 诊断工作流测试共享夹具：runtime 事实替身、投毒事件集、聚合
/// 目录事实与 workflow 构造（事实源全部注入，时钟固定，轮询 10ms）。
@MainActor
class DiagnosticsWorkflowTestCase: XCTestCase {
  let password = "SECRET-PASSWORD"
  let address = "203.0.113.7"
  let remark = "香港 01"
  let home = "/Users/SECRETUSER"
  let lanAddress = "192.0.2.77"

  /// 投毒事件 detail：白名单必须整体清洗，不得进入报告。
  let poisonDetails = [
    "SECRET-PERSIST-DETAIL", "SECRET-PROBE-DETAIL",
    "SECRET-LISTEN-DETAIL", "SECRET-AGENT-DETAIL", "SECRET-UNREADABLE-DETAIL",
  ]

  lazy var secrets: [String] = {
    [password, "SECRET-PLUGIN-OPTIONS", address, remark, home, lanAddress] + poisonDetails
  }()

  var workDir: URL!
  var facts: FakeRuntimeFacts!
  var events: RuntimeEventStore!

  override func setUp() async throws {
    try await super.setUp()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-diagwf-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    facts = FakeRuntimeFacts()
    events = RuntimeEventStore()
    // 导出完成事件经 RuntimeLog 发射：测试期间把替身缓冲注册为接收缝。
    RuntimeLog.setSink(events)
  }

  override func tearDown() async throws {
    RuntimeLog.setSink(RuntimeEventStore.shared)
    try? FileManager.default.removeItem(at: workDir)
    try await super.tearDown()
  }

  /// 标准 workflow：事实源注入替身、固定时钟（报告生成时间可精确断言）。
  func makeWorkflow(
    catalog: @escaping @MainActor () -> DiagnosticCatalogFacts? = { nil },
    agentLog: @escaping () -> String? = { nil },
    fileFacts: @escaping @MainActor () -> [DiagnosticFileFacts] = { [] },
    managedPlugins: @escaping @MainActor () -> [DiagnosticPluginFacts] = { [] },
    homePath: @escaping () -> String? = { nil },
    render: @escaping (DiagnosticSnapshot) -> String? = {
      DiagnosticReportBuilder.markdown(from: $0)
    },
    capture: ((DiagnosticSnapshot) -> Void)? = nil
  ) -> DiagnosticsWorkflow {
    DiagnosticsWorkflow(
      runtimeFacts: facts,
      events: events,
      catalogFacts: catalog,
      agentLogTail: agentLog,
      fileFacts: fileFacts,
      managedPlugins: managedPlugins,
      homePath: homePath,
      clock: { Date(timeIntervalSince1970: 1_758_000_000) },
      reportRendering: { snapshot in
        capture?(snapshot)
        return render(snapshot)
      },
      pollInterval: .milliseconds(10))
  }

  func waitUntil(
    _ condition: @autoclosure () -> Bool,
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(condition(), "等待条件超时", file: file, line: line)
  }

  func assertNoSecrets(
    _ text: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    for secret in secrets {
      XCTAssertFalse(
        text.contains(secret),
        "诊断报告不得包含敏感值「\(secret)」\n实际：\(text)",
        file: file, line: line)
    }
    XCTAssertFalse(text.contains("{"), "诊断报告不得携带 JSON 内容", file: file, line: line)
  }

  /// 投毒目录：地址、备注、分组名全为敏感值（聚合后这些值在结构上进不了
  /// facts）。
  func poisonedCatalogFacts() throws -> DiagnosticCatalogFacts {
    var catalog = ConfigurationCatalog()
    let group = try catalog.addGroup("SECRET-GROUP")
    _ = try catalog.addServer(
      ServerFields(
        address: address, port: 8388, encryptionMethod: "aes-256-gcm",
        password: password,
        remark: remark,
        pluginProgram: "v2ray-plugin",
        pluginOptions: "SECRET-PLUGIN-OPTIONS"),
      to: group)
    let subscriptionGroup = try catalog.addGroup("SECRET-GROUP-sub", source: .subscription)
    _ = try catalog.addServer(
      ServerFields(
        address: address, port: 8389, encryptionMethod: "chacha20-ietf-poly1305",
        password: password, remark: remark),
      source: .subscription,
      to: subscriptionGroup)
    return DiagnosticCatalogFacts(counts: DiagnosticReportBuilder.counts(in: catalog))
  }

  /// 投毒事件集：白名单内类别 + 自由 detail 携带敏感值。
  func appendPoisonedEvents() {
    let stamp = Date(timeIntervalSince1970: 1_758_000_000)
    events.append(event: .contractWritten(serverCount: 3), timestamp: stamp)
    events.append(
      event: .runtimePersistFailed(detail: "\(home): SECRET-PERSIST-DETAIL"), timestamp: stamp)
    events.append(
      event: .endpointProbeFailed(host: lanAddress, port: 11086, detail: "SECRET-PROBE-DETAIL"),
      timestamp: stamp)
    events.append(event: .listenNotEstablished(detail: "SECRET-LISTEN-DETAIL"), timestamp: stamp)
    events.append(
      event: .agentRegisterFailed(detail: "SECRET-AGENT-DETAIL"), timestamp: stamp)
    events.append(
      event: .settingsUnreadable(detail: "SECRET-UNREADABLE-DETAIL"), timestamp: stamp)
    // 激活原因是领域点名文案（显式白名单决策）：可在场，但只允许
    // 这类固定文本。
    events.append(
      event: .activationFailed(reason: "激活目标 leaf-9 的插件 simple-obfs 未随 app 提供"),
      timestamp: stamp)
  }

  func reportText(_ outcome: DiagnosticReportOutcome) throws -> String {
    guard case .ready(let draft) = outcome else {
      XCTFail("应产出 ready 报告，实际 \(outcome)")
      throw XCTSkip("无报告文本")
    }
    return try XCTUnwrap(String(data: draft.data, encoding: .utf8))
  }

  static func reportTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }
}

/// runtime 事实替身：可编程的安全事实值。
@MainActor
final class FakeRuntimeFacts: ProxyRuntimeDiagnosticFacts {
  var proxyState: DiagnosticProxyState = .off
  var hasActiveTarget = false
  var listen = RuntimeListenFacts(listen: ProxyListeningConfiguration())
  var contractSummary: String?
  var customRuleSummary: CustomRuleSummary?
}
