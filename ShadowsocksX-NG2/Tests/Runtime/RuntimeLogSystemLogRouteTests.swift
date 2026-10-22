import Foundation
import Testing
import os

@testable import ShadowsocksX_NG2

/// 系统日志路由基线：level 三分（失败 error / 里程碑 default / 冗长测量
/// info）、category 五分、公开文本与 private detail 的拆分。映射是封闭枚举
/// 上的纯数据，测数据不测转发。
@Suite struct RuntimeLogSystemLogRouteTests {
  private let detail = "SECRET-DETAIL"

  private struct Expectation {
    var event: RuntimeLogEvent
    var level: OSLogType
    var category: String
    var detail: String?
  }

  /// 全部事件的路由事实；新增事件漏路由由穷举 switch 兜底，本表锁定
  /// level / category / detail 拆分不随重构漂移。
  private var expectations: [Expectation] {
    let trace = ConnectivityTrace(phase: .sample, status: .success)
    return [
      Expectation(
        event: .contractWritten(serverCount: 2), level: .default, category: "runtime", detail: nil),
      Expectation(event: .contractUnchanged, level: .default, category: "runtime", detail: nil),
      Expectation(event: .runtimeFilesDeleted, level: .default, category: "runtime", detail: nil),
      Expectation(event: .contractMissing, level: .error, category: "runtime", detail: nil),
      Expectation(event: .contractInvalid, level: .error, category: "runtime", detail: nil),
      Expectation(
        event: .activationFailed(reason: "no usable server"), level: .error, category: "runtime",
        detail: nil),
      Expectation(
        event: .runtimePersistFailed(detail: detail), level: .error, category: "runtime",
        detail: detail),
      Expectation(
        event: .settingsUnreadable(detail: detail), level: .error, category: "runtime",
        detail: detail),
      Expectation(event: .agentRegistered, level: .default, category: "supervision", detail: nil),
      Expectation(event: .agentUnregistered, level: .default, category: "supervision", detail: nil),
      Expectation(
        event: .sslocalSpawned(pid: 1), level: .default, category: "supervision", detail: nil),
      Expectation(
        event: .sslocalStopRequested, level: .default, category: "supervision", detail: nil),
      Expectation(event: .reloadForwarded, level: .default, category: "supervision", detail: nil),
      Expectation(event: .reloadDeferred, level: .default, category: "supervision", detail: nil),
      Expectation(event: .reloadRestarted, level: .default, category: "supervision", detail: nil),
      Expectation(event: .sslocalSpawnFailed, level: .error, category: "supervision", detail: nil),
      Expectation(
        event: .sslocalExitedUnexpectedly(status: 1), level: .error, category: "supervision",
        detail: nil),
      Expectation(
        event: .listenNotEstablished(detail: "socks 127.0.0.1:11086"),
        level: .error, category: "supervision", detail: nil),
      Expectation(
        event: .agentRegisterFailed(detail: detail), level: .error, category: "supervision",
        detail: detail),
      Expectation(
        event: .agentUnregisterFailed(detail: detail), level: .error, category: "supervision",
        detail: detail),
      Expectation(
        event: .systemProxyUnchanged, level: .default, category: "system-proxy", detail: nil),
      Expectation(
        event: .systemProxyHelperRegisterFailed(detail: detail),
        level: .error, category: "system-proxy", detail: detail),
      Expectation(
        event: .systemProxyWriteFailed(detail: detail), level: .error, category: "system-proxy",
        detail: detail),
      Expectation(
        event: .connectivityMeasurement(id: UUID(), entry: trace),
        level: .info, category: "connectivity", detail: trace.description),
      Expectation(
        event: .endpointProbeFailed(host: "127.0.0.1", port: 11086, detail: detail),
        level: .error, category: "connectivity", detail: detail),
      Expectation(
        event: .diagnosticsExported, level: .default, category: "diagnostics", detail: nil),
    ]
  }

  @Test func everyEventRoutesToLevelCategoryAndPrivacySplit() {
    for row in expectations {
      let route = row.event.systemLogRoute
      #expect(route.level == row.level, "level 漂移：\(row.event)")
      #expect(route.category == row.category, "category 漂移：\(row.event)")
      #expect(route.privateDetail == row.detail, "detail 拆分漂移：\(row.event)")
    }
  }

  @Test func publicTextPlusPrivateDetailMatchesDescription() {
    for row in expectations {
      let route = row.event.systemLogRoute
      // 公开文本只到分隔符为止；detail（含连通性测量的目标 IP）只进 private 段。
      #expect(
        route.text + (route.privateDetail ?? "") == row.event.description, "公开文本漂移：\(row.event)")
      if let detail = route.privateDetail {
        #expect(!route.text.contains(detail), "公开文本不得携带 private detail：\(row.event)")
      }
    }
  }
}
