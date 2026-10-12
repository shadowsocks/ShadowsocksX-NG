import XCTest

@testable import ShadowsocksX_NG2

/// 日志脱敏基线：封闭事件枚举由构造保证不携带敏感值；脱敏
/// 工具按敏感信息定义收敛 URL 与运行时文档摘要。
final class RuntimeLogRedactionTests: XCTestCase {
  /// 投毒夹具：敏感值埋进文档各字段，任何一条日志事件都不得带出。
  private let poisoned = ProxyRuntimeFixture.makeDocument(
    serverAddress: "203.0.113.7",
    password: "SECRET-PASSWORD",
    pluginOpts: "obfs=http;obfs-host=SECRET-HOST"
  )

  private let secrets = [
    "SECRET-PASSWORD",
    "SECRET-HOST",
    "203.0.113.7",
    "香港 01",
  ]

  private func assertNoSecrets(
    _ text: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    for secret in secrets {
      XCTAssertFalse(
        text.contains(secret),
        "日志不得包含敏感值「\(secret)」\n实际：\(text)",
        file: file, line: line)
    }
    XCTAssertFalse(text.contains("{"), "日志不得携带 JSON 文档内容", file: file, line: line)
  }

  func testDocumentSummaryExposesOnlyCountsProtocolsAndMode() {
    let summary = Redactor.documentSummary(poisoned)

    XCTAssertEqual(summary, "servers=1 protocols=socks,http mode=tcp_and_udp")
    assertNoSecrets(summary)
  }

  func testRemoteURLKeepsOnlySchemeAndHost() {
    XCTAssertEqual(
      Redactor.remoteURL("https://user:SECRET@example.com/sub/CLASH-SECRET?token=abc&x=1"),
      "https://example.com/…",
      "完整订阅 URL 与 URL token 永不入日志（D5）")
  }

  func testRemoteURLRedactsUnparseableAndEmptyValues() {
    for bad in ["", "not a url", "https://", "ftp://"] {
      XCTAssertEqual(
        Redactor.remoteURL(bad), "<redacted-url>",
        "无法安全归约的 URL 一律占位：\(bad)")
    }
  }

  func testEveryRuntimeLogEventIsFreeOfSecretsAndJSONDumps() {
    let events: [RuntimeLogEvent] = [
      .contractWritten(serverCount: poisoned.servers.count),
      .contractUnchanged,
      .runtimeFilesDeleted,
      .runtimePersistFailed(detail: "errno 13"),
      .agentRegistered,
      .agentRegisterFailed(detail: "SMAppService error 9"),
      .agentUnregistered,
      .agentUnregisterFailed(detail: "SMAppService error 9"),
      .sslocalSpawned(pid: 42),
      .sslocalSpawnFailed,
      .sslocalExitedUnexpectedly(status: 78),
      .sslocalStopRequested,
      .contractMissing,
      .contractInvalidRemoved,
      .reloadForwarded,
      .reloadRestarted,
      .endpointProbeFailed(host: "127.0.0.1", port: 1086, detail: "Connection refused"),
      .activationFailed(
        reason: AppPresentation.message(
          for: ActivationFailure.invalidLeaf(
            node: NodeID(rawValue: "leaf-1"),
            reason: .pluginNotProvided(program: "simple-obfs")))),
      .diagnosticsExported,
    ]

    let joined = events.map(\.description).joined(separator: "\n")
    assertNoSecrets(joined)
  }
}
