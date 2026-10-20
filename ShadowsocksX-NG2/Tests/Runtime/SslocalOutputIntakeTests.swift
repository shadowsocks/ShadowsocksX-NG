import Foundation
import Testing
import os

@testable import ShadowsocksX_NG2

/// 记录 intake 分发行的替身去向。
private final class RecordingDestination: SslocalLineDestination, @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []

  func receive(_ line: String) {
    lock.lock()
    defer { lock.unlock() }
    lines.append(line)
  }

  var received: [String] {
    lock.lock()
    defer { lock.unlock() }
    return lines
  }
}

struct SslocalOutputIntakeTests {
  @Test func framesLinesAcrossChunkBoundaries() {
    let destination = RecordingDestination()
    let intake = SslocalOutputIntake(destinations: [destination])
    intake.write(Data("hel".utf8))
    intake.write(Data("lo wo".utf8))
    intake.write(Data("rld\nsecond\n".utf8))
    #expect(destination.received == ["hello world", "second"])
  }

  @Test func hidesPasswordBeforeDeliveringToEveryDestination() {
    let first = RecordingDestination()
    let second = RecordingDestination()
    let intake = SslocalOutputIntake(destinations: [first, second])
    intake.write(Data("authentication rejected, password: secret-one\n".utf8))
    intake.write(Data("password: sec".utf8))
    intake.write(Data("ret-two\n".utf8))
    let expected = [
      "authentication rejected, password: [redacted]",
      "password: [redacted]",
    ]
    #expect(first.received == expected)
    #expect(second.received == expected)
  }

  @Test func discardsOversizedLineAndKeepsFollowingLines() {
    let destination = RecordingDestination()
    let intake = SslocalOutputIntake(destinations: [destination])
    var oversized = Data("password: ".utf8)
    oversized.append(Data(String(repeating: "x", count: 70_000).utf8))
    intake.write(oversized)
    intake.write(Data("secret-tail\nordinary event\n".utf8))
    #expect(destination.received == ["sslocal: log line truncated", "ordinary event"])
  }

  @Test func flushesTrailingPartialLineAtEndOfStream() {
    let destination = RecordingDestination()
    let intake = SslocalOutputIntake(destinations: [destination])
    intake.write(Data("no trailing newline".utf8))
    intake.write(Data())
    #expect(destination.received == ["no trailing newline"])
    intake.write(Data())
    #expect(destination.received == ["no trailing newline"])
  }

  @Test func stderrDestinationAppendsNewlineToEachLine() throws {
    let pipe = Pipe()
    let destination = SslocalStandardErrorDestination(handle: pipe.fileHandleForWriting)
    destination.receive("hello")
    destination.receive("")
    try pipe.fileHandleForWriting.close()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    #expect(data == Data("hello\n\n".utf8))
  }

  @Test func mapsUpstreamLevelTokensToLogLevels() {
    #expect(
      SslocalUnifiedLogDestination.level(for: "2026-10-20T03:04:12Z ERROR sslocal] boom") == .error)
    // 统一日志没有 warning 级：WARN/WARNING 落持久的 .default，与 error 可区分。
    #expect(
      SslocalUnifiedLogDestination.level(for: "[2026-10-20T03:04:12Z WARN sslocal] retrying")
        == .default)
    #expect(SslocalUnifiedLogDestination.level(for: "WARNING token alone") == .default)
    #expect(SslocalUnifiedLogDestination.level(for: "connected to server") == .info)
    #expect(SslocalUnifiedLogDestination.level(for: "an error occurred") == .info)
    #expect(SslocalUnifiedLogDestination.level(for: "password: [redacted]") == .info)
    // CRLF 行尾不得吞掉级别 token（\r 也是空白）。
    #expect(SslocalUnifiedLogDestination.level(for: "2026-10-20T03:04:12Z ERROR boom\r") == .error)
    #expect(
      SslocalUnifiedLogDestination.level(for: "2026-10-20T03:04:12Z WARN retry\r") == .default)
  }
}
