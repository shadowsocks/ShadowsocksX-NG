import XCTest

@testable import ShadowsocksX_NG2

/// GUI 事件环形缓冲与 RuntimeLog 接收缝：顺序保持、容量封顶、
/// emit 路由与恢复。
final class RuntimeEventStoreTests: XCTestCase {
  override func tearDown() {
    super.tearDown()
    // 恢复生产接线，避免污染同进程内其他测试。
    RuntimeLog.setSink(RuntimeEventStore.shared)
  }

  func testAppendKeepsChronologicalOrderAndRendersLine() {
    let store = RuntimeEventStore()
    let first = Date(timeIntervalSince1970: 1_000)
    let second = Date(timeIntervalSince1970: 2_000)

    store.append(event: .contractWritten(serverCount: 42), timestamp: first)
    store.append(event: .agentRegistered, timestamp: second)

    let snapshot = store.snapshot
    XCTAssertEqual(
      snapshot.map(\.text),
      ["contract written (servers=42)", "launch agent registered"])
    XCTAssertEqual(snapshot.map(\.id), [0, 1])
    // 行格式 = 固定格式时间戳 + 两空格 + 事件文本（不锚定时区，格式器随本机）。
    XCTAssertEqual(
      snapshot[0].renderedLine,
      RuntimeEventStore.Entry.timestampFormatter.string(from: first)
        + "  contract written (servers=42)")
    XCTAssertEqual(
      snapshot[1].renderedLine,
      RuntimeEventStore.Entry.timestampFormatter.string(from: second) + "  launch agent registered")
  }

  func testCapacityKeepsMostRecentEvents() {
    let store = RuntimeEventStore(capacity: 3)
    for index in 0..<5 {
      store.append(event: .contractWritten(serverCount: index), timestamp: Date())
    }

    XCTAssertEqual(
      store.snapshot.map(\.text),
      [
        "contract written (servers=2)", "contract written (servers=3)",
        "contract written (servers=4)",
      ])
  }

  func testEmitRoutesToRegisteredSink() {
    let store = RuntimeEventStore()
    RuntimeLog.setSink(store)
    defer { RuntimeLog.setSink(RuntimeEventStore.shared) }

    RuntimeLog.emit(.contractWritten(serverCount: 2))

    XCTAssertEqual(store.snapshot.last?.text, "contract written (servers=2)")
    XCTAssertEqual(store.snapshot.count, 1)
  }

  func testEmitWithoutSinkStillWritesStderrOnly() {
    RuntimeLog.setSink(nil)
    defer { RuntimeLog.setSink(RuntimeEventStore.shared) }

    // 未注册接收缝时 emit 只走 stderr，不崩溃即可（GUI 启动前的事件路径）。
    RuntimeLog.emit(.agentRegistered)
  }
}
