import Foundation
import Testing
import os

@testable import ShadowsocksX_NG2

/// 统一日志行模型：渲染/解析往返、旧格式降级与级别口径。
struct LogLineTests {
  @Test func rendersAndParsesUniformRows() {
    let stamp = Date(timeIntervalSince1970: 1_758_000_000)
    for level in [LogLineLevel.error, .warning, .info] {
      for source in [LogLineSource.gui, .wrapper, .sslocal] {
        let row = LogLine(
          timestamp: stamp, level: level, source: source, text: "body [with] brackets")
        let rendered = row.rendered
        #expect(rendered.hasPrefix("\(LogLine.timestampFormatter.string(from: stamp)) "))
        #expect(
          rendered.hasSuffix(" [\(level.rawValue)] [\(source.rawValue)] body [with] brackets"))
        #expect(LogLine.parse(rendered) == row, "渲染/解析往返必须无损：\(rendered)")
      }
    }
  }

  @Test func parseRejectsUnstructuredText() {
    #expect(LogLine.parse("") == nil)
    #expect(LogLine.parse("plain line without metadata") == nil)
    #expect(LogLine.parse("2026-10-20 12:00:00.123 [bogus] [gui] text") == nil)
    #expect(LogLine.parse("2026-10-20 12:00:00.123 [info] [nowhere] text") == nil)
    // 时间戳位置必须是可解析的固定格式（上游 ISO 时间是原文，不是行元数据）。
    #expect(LogLine.parse("2026-10-20T03:04:12.123456Z [info] [gui] text") == nil)
  }

  @Test func offsetTimestampsPreserveRepeatedLocalTimes() throws {
    let first = try #require(
      LogLine.parse("2026-11-01 01:30:00.000 -0400 [info] [wrapper] first"))
    let second = try #require(
      LogLine.parse("2026-11-01 01:30:00.000 -0500 [info] [wrapper] second"))
    let firstTime = try #require(first.timestamp)
    let secondTime = try #require(second.timestamp)
    #expect(secondTime.timeIntervalSince(firstTime) == 3600)
    #expect(LogLine.parse(first.rendered) == first)
    #expect(LogLine.parse(second.rendered) == second)
    #expect(
      first.rendered.range(of: " [+-][0-9]{4} \\[info\\]", options: .regularExpression) != nil)
  }

  @Test func readsUniformRowsWithoutTimezoneFromEarlierVersions() throws {
    let row = try #require(
      LogLine.parse("2026-10-20 12:00:00.123 [error] [wrapper] older event"))
    #expect(row.timestamp != nil)
    #expect(row.level == .error)
    #expect(row.source == .wrapper)
    #expect(row.text == "older event")
  }

  @Test func legacyRowsKeepRawTextAndGuessSource() {
    let event = LogLine.legacy("ssxng: listen not established within deadline: a 127.0.0.1:1")
    #expect(event.timestamp == nil)
    #expect(event.source == .wrapper)
    #expect(event.text == "ssxng: listen not established within deadline: a 127.0.0.1:1")
    #expect(event.rendered == event.text, "旧格式行保留原文（raw capture 不改写）")

    let upstream = LogLine.legacy("2026-10-20T03:04:12Z ERROR sslocal] boom")
    #expect(upstream.source == .sslocal)
    #expect(upstream.level == .error)
  }

  @Test func detectsUpstreamLevelTokens() {
    #expect(LogLineLevel.detect(in: "2026-10-20T03:04:12Z ERROR sslocal] boom") == .error)
    #expect(LogLineLevel.detect(in: "[2026-10-20T03:04:12Z WARN sslocal] retrying") == .warning)
    #expect(LogLineLevel.detect(in: "WARNING token alone") == .warning)
    #expect(LogLineLevel.detect(in: "connected to server") == .info)
    #expect(LogLineLevel.detect(in: "an error occurred") == .info)
    #expect(LogLineLevel.detect(in: "password: [redacted]") == .info)
    // CRLF 行尾不得吞掉级别 token（\r 也是空白）。
    #expect(LogLineLevel.detect(in: "2026-10-20T03:04:12Z ERROR boom\r") == .error)
    #expect(LogLineLevel.detect(in: "2026-10-20T03:04:12Z WARN retry\r") == .warning)
  }

  @Test func projectsLevelsToUnifiedLogScale() {
    // 统一日志没有 warning 级：WARN/WARNING 落持久的 .default，与 error 可区分。
    #expect(OSLogType(LogLineLevel.error) == .error)
    #expect(OSLogType(LogLineLevel.warning) == .default)
    #expect(OSLogType(LogLineLevel.info) == .info)
    #expect(LogLineLevel(os: .error) == .error)
    #expect(LogLineLevel(os: .fault) == .error)
    #expect(LogLineLevel(os: .default) == .info)
    #expect(LogLineLevel(os: .info) == .info)
    #expect(LogLineLevel(os: .debug) == .info)
  }
}
