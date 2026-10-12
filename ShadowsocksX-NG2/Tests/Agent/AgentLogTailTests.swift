import XCTest

@testable import ShadowsocksX_NG2

/// agent.log 尾部读取：有限窗口、行对齐、缺失文件返回 nil。
final class AgentLogTailTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-tail-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  func testReadsWholeContentWithinLimit() throws {
    let url = directory.appendingPathComponent("agent.log")
    try Data("AAAA\nBBBB\nCC\n".utf8).write(to: url)

    let tail = AgentLogTail.readLastLines(of: url, maxBytes: 1024)

    XCTAssertEqual(tail, "AAAA\nBBBB\nCC\n")
  }

  func testDropsPartialFirstLineAtWindowBoundary() throws {
    let url = directory.appendingPathComponent("agent.log")
    let content = "AAAA\nBBBB\nCC\n"  // 共 13 字节
    try Data(content.utf8).write(to: url)
    // 窗口切在第二行中间：末 6 字节是 "BB\nCC\n"，起始半行「BB」应丢弃。
    let window = 6

    let tail = AgentLogTail.readLastLines(of: url, maxBytes: window)

    XCTAssertEqual(tail, "CC\n")
  }

  func testMissingFileReturnsNil() {
    XCTAssertNil(
      AgentLogTail.readLastLines(of: directory.appendingPathComponent("missing")))
  }
}
