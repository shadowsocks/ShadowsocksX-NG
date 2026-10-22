import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 日志视图 intake：tail 窗口、行归一、时间归并与过滤。
struct DiagnosticLogIntakeTests {
  // MARK: - tail 窗口

  @Test func readsWholeTailWithinLimit() throws {
    let url = try temporaryLogFile(content: "AAAA\nBBBB\nCC\n")
    #expect(DiagnosticLogIntake.readTail(of: url, maxBytes: 1024) == "AAAA\nBBBB\nCC\n")
  }

  @Test func dropsPartialFirstLineAtWindowBoundary() throws {
    let url = try temporaryLogFile(content: "AAAA\nBBBB\nCC\n")  // 共 13 字节
    // 窗口切在第二行中间：末 6 字节是 "BB\nCC\n"，起始半行「BB」应丢弃。
    #expect(DiagnosticLogIntake.readTail(of: url, maxBytes: 6) == "CC\n")
  }

  @Test func dropsPartialCRLFLineAtWindowBoundary() throws {
    let url = try temporaryLogFile(content: "AAAA\r\nBBBB\r\nCC\r\n")
    #expect(DiagnosticLogIntake.readTail(of: url, maxBytes: 8) == "CC\r\n")
  }

  @Test func missingFileReturnsNil() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-tail-\(UUID().uuidString)/agent.log")
    #expect(DiagnosticLogIntake.readTail(of: url) == nil)
  }

  // MARK: - 行归一与归并

  @Test func CRLFOutputKeepsFollowingErrorsVisible() throws {
    let pipe = Pipe()
    let intake = SslocalOutputIntake(
      destinations: [SslocalStandardErrorDestination(handle: pipe.fileHandleForWriting)])
    intake.write(Data("INFO first\r\nERROR second\r\n".utf8))
    try pipe.fileHandleForWriting.close()
    let tail = try #require(
      String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
    try pipe.fileHandleForReading.close()

    let rows = DiagnosticLogIntake.rows(events: [], tail: tail)
    #expect(rows.map(\.text) == ["INFO first\r", "ERROR second\r"])
    #expect(rows.map(\.level) == [.info, .error])
    #expect(DiagnosticLogFilter(level: .errors).apply(rows).map(\.text) == ["ERROR second\r"])
  }

  @Test func mergesAcrossDaylightSavingFallback() throws {
    let clock = ISO8601DateFormatter()
    let store = RuntimeEventStore()
    store.append(
      event: .agentRegistered,
      timestamp: try #require(clock.date(from: "2026-11-01T06:00:00Z")))
    let tail = """
      2026-11-01 01:59:00.000 -0400 [info] [wrapper] before fallback
      2026-11-01 01:01:00.000 -0500 [error] [wrapper] after fallback
      """

    let rows = DiagnosticLogIntake.rows(events: store.snapshot, tail: tail)
    #expect(rows.map(\.text) == ["before fallback", "launch agent registered", "after fallback"])
    #expect(rows.allSatisfy { $0.timestamp != nil })
  }

  @Test func mergesRowsByTimestamp() {
    let store = RuntimeEventStore()
    store.append(
      event: .contractWritten(serverCount: 1), timestamp: Date(timeIntervalSince1970: 3_000))
    store.append(event: .agentRegistered, timestamp: Date(timeIntervalSince1970: 5_000))
    let tail = [
      LogLine(
        timestamp: Date(timeIntervalSince1970: 4_000), level: .warning, source: .sslocal,
        text: "retry"
      ).rendered,
      LogLine(
        timestamp: Date(timeIntervalSince1970: 1_000), level: .error, source: .sslocal,
        text: "boom"
      ).rendered,
    ].joined(separator: "\n")

    let rows = DiagnosticLogIntake.rows(events: store.snapshot, tail: tail)

    #expect(
      rows.map(\.text) == [
        "boom", "contract written (servers=1)", "retry", "launch agent registered",
      ])
    #expect(rows.map(\.source) == [.sslocal, .gui, .sslocal, .gui])
    #expect(rows.map(\.level) == [.error, .info, .warning, .info], "GUI 行级别取自事件路由级别")
  }

  @Test func legacyRowsSortFirstAndKeepRawText() {
    let store = RuntimeEventStore()
    store.append(event: .agentRegistered, timestamp: Date(timeIntervalSince1970: 5_000))
    let tail = [
      "ssxng: old event without timestamp",
      LogLine(
        timestamp: Date(timeIntervalSince1970: 2_000), level: .info, source: .sslocal,
        text: "recent"
      ).rendered,
    ].joined(separator: "\n")

    let rows = DiagnosticLogIntake.rows(events: store.snapshot, tail: tail)

    #expect(
      rows.map(\.text) == [
        "ssxng: old event without timestamp", "recent", "launch agent registered",
      ])
    #expect(rows.first?.source == .wrapper)
    #expect(rows.first?.timestamp == nil, "旧格式行时间未知，排在最前保持文件内顺序")
  }

  @Test func emptyTailYieldsOnlyEventRows() {
    let store = RuntimeEventStore()
    store.append(event: .agentRegistered, timestamp: Date(timeIntervalSince1970: 5_000))
    #expect(DiagnosticLogIntake.rows(events: store.snapshot, tail: nil).count == 1)
    #expect(DiagnosticLogIntake.rows(events: store.snapshot, tail: "").count == 1)
  }

  @Test func keepsBlankLinesFromTailForRawFidelity() {
    let rows = DiagnosticLogIntake.rows(events: [], tail: "first\n\nthird\n")
    #expect(rows.map(\.text) == ["first", "", "third"], "空行是行内容，只排除结尾行分隔符")
  }

  // MARK: - 过滤

  @Test func filterCombinesLevelAndSource() {
    let rows = [
      LogLine(timestamp: nil, level: .error, source: .gui, text: "a"),
      LogLine(timestamp: nil, level: .warning, source: .wrapper, text: "b"),
      LogLine(timestamp: nil, level: .info, source: .sslocal, text: "c"),
      LogLine(timestamp: nil, level: .error, source: .sslocal, text: "d"),
    ]
    #expect(DiagnosticLogFilter().apply(rows).count == 4)
    #expect(
      DiagnosticLogFilter(level: .warnings).apply(rows).map(\.text) == ["a", "b", "d"],
      "警告+错误 = warning 与 error")
    #expect(DiagnosticLogFilter(level: .errors).apply(rows).map(\.text) == ["a", "d"])
    #expect(DiagnosticLogFilter(source: .sslocal).apply(rows).map(\.text) == ["c", "d"])
    #expect(
      DiagnosticLogFilter(level: .errors, source: .sslocal).apply(rows).map(\.text) == ["d"])
  }

  // MARK: - 夹具

  private func temporaryLogFile(content: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-tail-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("agent.log")
    try Data(content.utf8).write(to: url)
    return url
  }
}
