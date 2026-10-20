import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 记录 intake 分发行的替身去向。
private final class RecordingDestination: SslocalLineDestination, @unchecked Sendable {
  private let lock = NSLock()
  private var rows: [LogLine] = []

  func receive(_ row: LogLine) {
    lock.lock()
    defer { lock.unlock() }
    rows.append(row)
  }

  var received: [LogLine] {
    lock.lock()
    defer { lock.unlock() }
    return rows
  }
}

struct SslocalOutputIntakeTests {
  /// 固定时钟：行时间戳可精确断言。
  private static let stamp = Date(timeIntervalSince1970: 1_758_000_000)

  private func makeIntake(_ destinations: [any SslocalLineDestination]) -> SslocalOutputIntake {
    SslocalOutputIntake(destinations: destinations, now: { Self.stamp })
  }

  @Test func framesLinesAcrossChunkBoundaries() {
    let destination = RecordingDestination()
    let intake = makeIntake([destination])
    intake.write(Data("hel".utf8))
    intake.write(Data("lo wo".utf8))
    intake.write(Data("rld\nsecond\n".utf8))
    #expect(destination.received.map(\.text) == ["hello world", "second"])
    #expect(
      destination.received.allSatisfy {
        $0.timestamp == Self.stamp && $0.level == .info && $0.source == .sslocal
      }, "intake 产出行：时间戳来自注入时钟，来源固定 sslocal")
  }

  @Test func hidesPasswordBeforeDeliveringToEveryDestination() {
    let first = RecordingDestination()
    let second = RecordingDestination()
    let intake = makeIntake([first, second])
    intake.write(Data("authentication rejected, password: secret-one\n".utf8))
    intake.write(Data("password: sec".utf8))
    intake.write(Data("ret-two\n".utf8))
    let expected = [
      "authentication rejected, password: [redacted]",
      "password: [redacted]",
    ]
    #expect(first.received.map(\.text) == expected)
    #expect(second.received.map(\.text) == expected)
  }

  @Test func discardsOversizedLineAndKeepsFollowingLines() {
    let destination = RecordingDestination()
    let intake = makeIntake([destination])
    var oversized = Data("password: ".utf8)
    oversized.append(Data(String(repeating: "x", count: 70_000).utf8))
    intake.write(oversized)
    intake.write(Data("secret-tail\nordinary event\n".utf8))
    #expect(destination.received.map(\.text) == ["log line truncated", "ordinary event"])
    // 截断标记是 info：agent.log 才是持久面，统一日志侧不落盘。
    #expect(destination.received.first?.level == .info)
  }

  @Test func flushesTrailingPartialLineAtEndOfStream() {
    let destination = RecordingDestination()
    let intake = makeIntake([destination])
    intake.write(Data("no trailing newline".utf8))
    intake.write(Data())
    #expect(destination.received.map(\.text) == ["no trailing newline"])
    intake.write(Data())
    #expect(destination.received.map(\.text) == ["no trailing newline"])
  }

  @Test func detectsUpstreamLevelIntoRow() {
    let destination = RecordingDestination()
    let intake = makeIntake([destination])
    intake.write(
      Data(
        "2026-10-20T03:04:12Z ERROR sslocal] boom\n2026-10-20T03:04:12Z WARN retry\r\nok\n".utf8))
    #expect(destination.received.map(\.level) == [.error, .warning, .info])
  }

  @Test func stderrDestinationRendersUniformRows() throws {
    let pipe = Pipe()
    let destination = SslocalStandardErrorDestination(handle: pipe.fileHandleForWriting)
    destination.receive(
      LogLine(timestamp: Self.stamp, level: .warning, source: .sslocal, text: "hello"))
    destination.receive(LogLine(timestamp: Self.stamp, level: .info, source: .sslocal, text: ""))
    try pipe.fileHandleForWriting.close()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let stamp = LogLine.timestampFormatter.string(from: Self.stamp)
    #expect(
      data
        == Data(
          "\(stamp) [warning] [sslocal] hello\n\(stamp) [info] [sslocal] \n".utf8))
  }
}
