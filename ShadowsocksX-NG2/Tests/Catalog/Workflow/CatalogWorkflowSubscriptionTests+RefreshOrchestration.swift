import Foundation
import Security
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
extension CatalogWorkflowSubscriptionTests {
  // MARK: 批量刷新与持久化

  func testRefreshAllRefreshesEverySubscription() async throws {
    _ = try await seedSuccessfulSubscription()
    _ = try await createOnly(urlString: "https://q.example.com/t.json")
    let requestsBefore = fetcher.requestCount
    let convergesBefore = runtime.convergeCount

    await workflow.refreshAllSubscriptions()

    XCTAssertEqual(fetcher.requestCount - requestsBefore, 2, "每个订阅各刷一次")
    for summary in workflow.subscriptions {
      guard case .succeeded = summary.status else {
        return XCTFail("全部订阅都应记成功态：\(summary.id)")
      }
    }
    await waitUntilRuntimeSettles(runtime.convergeCount - convergesBefore == 2)
    XCTAssertEqual(runtime.convergeCount - convergesBefore, 2)
  }

  func testSubscriptionsPersistAcrossWorkflowReload() async throws {
    let record = try await seedSuccessfulSubscription()

    let reloaded = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: fileURL), runtime: FakeCatalogRuntime()))
    XCTAssertEqual(reloaded.subscriptions.count, 1)
    XCTAssertEqual(reloaded.subscriptions[0].id, record.id)
    guard case .succeeded = reloaded.subscriptions[0].status else {
      return XCTFail("刷新状态跨持久化保留")
    }
    XCTAssertNotNil(reloaded.tree.node(withID: serverAID), "订阅子树跨持久化保留")
  }

  // MARK: 并发守卫

  func testConcurrentRefreshOnSameSubscriptionDoesNotReenter() async throws {
    let record = try await seedSuccessfulSubscription()
    // 用门控获取器重建工作流：刷新停在 fetch 内部，验证并发守卫。
    let gated = GatedFetcher()
    let refreshWorkflow = makeWorkflow(fetcher: gated)
    workflow = refreshWorkflow

    async let first: Void = refreshWorkflow.refreshSubscription(record.id)
    // 轮询而非阻塞等待：主线程阻塞会饿死继承 MainActor 的 async let 子任务。
    while !gated.didEnterFetch {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    await refreshWorkflow.refreshSubscription(record.id)

    XCTAssertEqual(gated.requestCount, 1, "同一订阅刷新进行中不重入")
    gated.releaseAll()
    await first
    XCTAssertTrue(refreshWorkflow.refreshingSubscriptionIDs.isEmpty, "完成后守卫释放")
  }
}

/// 可门控获取缝：让第一次刷新停在 fetch 内部，验证并发守卫。fetch 挂起等待
/// 异步门闩，不阻塞 MainActor 或协作线程池。
final class GatedFetcher: SubscriptionFetching, @unchecked Sendable {
  private let lock = NSLock()
  private let release = AsyncGate()
  private let entry = AsyncGate()
  private var count = 0
  private var entered = false

  var requestCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  var didEnterFetch: Bool {
    lock.lock()
    defer { lock.unlock() }
    return entered
  }

  func fetch(_ url: URL) async throws -> Data {
    lock.withLock {
      count += 1
      entered = true
    }
    entry.release()
    await release.wait()
    return SubscriptionDocs.flat(serverCount: 0)
  }

  func waitUntilEntered() async { await entry.wait() }

  func releaseAll() {
    release.release()
  }
}
