import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct DiagnosticLogTableRowTests {
  @Test func selectionSurvivesTailCroppingAndAppendingIdenticalLines() throws {
    try withLogFile(Data("same\nsame\n".utf8)) { url in
      let original = try entries(at: url)
      var selection: Set<DiagnosticLogEntry.ID> = [original[1].id]
      let writer = try FileHandle(forWritingTo: url)
      defer { try? writer.close() }
      try writer.seekToEnd()
      try writer.write(contentsOf: Data("same\n".utf8))

      // 读取末尾两行；窗口边界处丢弃首行，保留原来选中的第二行。
      let refreshed = try entries(at: url, maxBytes: 11)
      #expect(refreshed.count == 2)
      #expect(refreshed[0].id == original[1].id)
      #expect(refreshed[1].id != original[1].id)
      selection.formIntersection(refreshed.map(\.id))
      #expect(selection == [original[1].id])
      #expect(refreshed.filter { selection.contains($0.id) }.map(\.line.rendered) == ["same"])

      var removedSelection: Set<DiagnosticLogEntry.ID> = [original[0].id]
      removedSelection.formIntersection(refreshed.map(\.id))
      #expect(removedSelection.isEmpty)
    }
  }

  @Test func blankAndMalformedUTF8LinesKeepTheirBytePositions() throws {
    let data = Data([0xFF, 10]) + Data("\n\n末行\r\n".utf8)
    try withLogFile(data) { url in
      let original = try entries(at: url)
      let refreshed = try entries(at: url, maxBytes: data.count - 1)
      #expect(original.map(\.line.text) == ["�", "", "", "末行\r"])
      #expect(refreshed.map(\.id) == Array(original.dropFirst()).map(\.id))
      #expect(Set(original.map(\.id)).count == original.count)
    }
  }

  @Test func replacingOrRewritingFileDoesNotReuseSelectedRow() throws {
    try withLogFile(Data("same\n".utf8)) { url in
      let original = try entries(at: url)
      // 原子替换保留原文，但创建新文件；不应把旧文件的选择交给新文件。
      try Data("same\n".utf8).write(to: url, options: .atomic)
      #expect(try entries(at: url).first?.id != original[0].id)

      let replacement = try entries(at: url)
      let writer = try FileHandle(forWritingTo: url)
      defer { try? writer.close() }
      try writer.truncate(atOffset: 0)
      try writer.write(contentsOf: Data("other\n".utf8))
      #expect(try entries(at: url).first?.id != replacement[0].id)
    }
  }

  @Test func guiIdentitySurvivesRingBufferEvictionAndFiltering() {
    let events = RuntimeEventStore(capacity: 2)
    let stamp = Date(timeIntervalSince1970: 100)
    events.append(event: .agentRegistered, timestamp: stamp)
    events.append(event: .agentRegistered, timestamp: stamp)
    let original = DiagnosticLogIntake.entries(events: events.snapshot, tail: nil)
    events.append(event: .agentRegistered, timestamp: stamp)
    let refreshed = DiagnosticLogIntake.entries(events: events.snapshot, tail: nil)
    #expect(refreshed[0].id == original[1].id)
    #expect(refreshed[1].id != original[1].id)
    let filtered = refreshed.filter { DiagnosticLogFilter(source: .gui).admits($0.line) }
    #expect(filtered.map(\.id) == refreshed.map(\.id))
  }

  @Test func showsUnknownTimestampAndPreservesCompleteMessage() {
    let message = "long message\nwith a second line\r"
    let row = DiagnosticLogEntry(
      id: .gui(0),
      line: LogLine(timestamp: nil, level: .warning, source: .gui, text: message))
    #expect(row.timestampText == "—")
    #expect(row.sourceText == "GUI")
    #expect(row.line.text == message)
    #expect(row.line.rendered == message)
  }

  private func entries(at url: URL, maxBytes: Int = 64 * 1024) throws -> [DiagnosticLogEntry] {
    let tail = try #require(DiagnosticLogIntake.readTailSnapshot(of: url, maxBytes: maxBytes))
    return DiagnosticLogIntake.entries(events: [], tail: tail)
  }

  private func withLogFile(_ data: Data, perform: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("agent.log")
    try data.write(to: url)
    try perform(url)
  }
}
