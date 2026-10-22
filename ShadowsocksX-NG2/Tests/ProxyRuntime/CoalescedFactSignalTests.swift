import Combine
import XCTest

@testable import ShadowsocksX_NG2

/// 每主队列轮合并器的契约：同一同步轮多次标记只发一次；冲洗晚于同步轮，
/// 订阅方读到最终事实。
final class CoalescedFactSignalTests: XCTestCase {
  @MainActor
  func testMarksWithinSameTurnCoalesceIntoSingleChange() async {
    let signal = CoalescedFactSignal()
    var changeCount = 0
    let cancellable = signal.changes.sink { _ in changeCount += 1 }
    defer { cancellable.cancel() }

    signal.markChanged()
    signal.markChanged()
    signal.markChanged()
    await Task.yield()

    XCTAssertEqual(changeCount, 1, "同一同步轮的多次标记只发一次")
  }

  @MainActor
  func testFlushReadsFinalFactsNotMidTurnState() async {
    @MainActor
    final class FactHolder {
      let signal = CoalescedFactSignal()
      var fact = 0 {
        didSet { signal.markChanged() }
      }
    }
    let holder = FactHolder()
    var observed: [Int] = []
    let cancellable = holder.signal.changes.sink { @MainActor _ in
      observed.append(holder.fact)
    }
    defer { cancellable.cancel() }

    holder.fact = 1
    holder.fact = 2
    await Task.yield()

    XCTAssertEqual(observed, [2], "冲洗发生在同步轮结束后，读到最终事实")
  }

  @MainActor
  func testLaterMarksAfterFlushEmitAgain() async {
    let signal = CoalescedFactSignal()
    var changeCount = 0
    let cancellable = signal.changes.sink { _ in changeCount += 1 }
    defer { cancellable.cancel() }

    signal.markChanged()
    await Task.yield()
    signal.markChanged()
    await Task.yield()

    XCTAssertEqual(changeCount, 2, "跨轮的标记各自冲洗一次")
  }
}
