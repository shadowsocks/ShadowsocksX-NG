import Security
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
extension CatalogWorkflowSubscriptionTests {
  // MARK: 失败保留语义

  func testFailedRefreshKeepsSnapshotAndStatus() async throws {
    fetcher = FakeSubscriptionFetcher(behavior: .success(treeDoc))
    workflow = makeWorkflow()
    let record = try await workflow.createSubscription(urlString: "https://p.example.com/s.json")
    let convergesBefore = runtime.convergeCount
    let treeBefore = workflow.tree

    fetcher.setBehavior(.failure(.httpStatus(code: 503)))
    await workflow.refreshSubscription(record.id)

    // 快照原样保留。
    XCTAssertEqual(workflow.tree, treeBefore, "传输失败不动最后成功快照（projection 等价）")
    XCTAssertEqual(findNode(withSuffix: "aaaaaaaa-0000-4000-8000-00000000000a")?.name, "香港 01")
    // 状态点名失败且原因脱敏。
    guard case .failed(_, let failure) = workflow.subscriptions[0].status else {
      return XCTFail("应记失败态")
    }
    XCTAssertEqual(failure, .httpStatus(code: 503))
    // 仅状态提交了一次（快照未动）。
    await waitUntilRuntimeSettles(runtime.convergeCount - convergesBefore == 1)
    XCTAssertEqual(runtime.convergeCount - convergesBefore, 1)
  }

  func testDuplicateIDFailureKeepsSnapshot() async throws {
    let record = try await seedSuccessfulSubscription()
    let treeBefore = workflow.tree

    fetcher.setBehavior(.success(SubscriptionDocs.duplicateIDs()))
    await workflow.refreshSubscription(record.id)

    guard case .failed(_, let failure) = workflow.subscriptions[0].status else {
      return XCTFail("应记失败态")
    }
    XCTAssertEqual(failure, .duplicateIdentity)
    XCTAssertEqual(workflow.tree, treeBefore)
  }

  func testRecordValidationFailureKeepsSnapshot() async throws {
    let record = try await seedSuccessfulSubscription()
    let treeBefore = workflow.tree

    fetcher.setBehavior(.success(SubscriptionDocs.invalidRecord()))
    await workflow.refreshSubscription(record.id)

    guard case .failed(_, let failure) = workflow.subscriptions[0].status else {
      return XCTFail("应记失败态")
    }
    XCTAssertEqual(failure, .recordValidation(index: 0, field: .port))
    XCTAssertEqual(workflow.tree, treeBefore)
  }

  // MARK: 空快照与扁平回退

  func testEmptySnapshotIsSuccessAndClearsSubtree() async throws {
    let record = try await seedSuccessfulSubscription()

    fetcher.setBehavior(.success(SubscriptionDocs.flat(serverCount: 0)))
    await workflow.refreshSubscription(record.id)

    let group = try XCTUnwrap(workflow.tree.node(withID: record.groupID))
    XCTAssertTrue(group.isGroup)
    XCTAssertEqual(group.childCount, 0, "合法空快照清空子树")
    guard case .succeeded = workflow.subscriptions[0].status else {
      return XCTFail("空快照按成功处理")
    }
  }

  func testCycleDocumentFallsBackToFlatAndSucceeds() async throws {
    let record = try await seedSuccessfulSubscription()

    fetcher.setBehavior(.success(SubscriptionDocs.cycleExtension()))
    await workflow.refreshSubscription(record.id)

    let group = try XCTUnwrap(workflow.tree.node(withID: record.groupID))
    XCTAssertEqual(group.childCount, 2, "回退扁平：标准服务器直接进固定分组")
    XCTAssertEqual(group.name, "p.example.com", "扁平回退以 host 兜底名称")
    guard case .succeeded = workflow.subscriptions[0].status else {
      return XCTFail("回退扁平仍是成功刷新")
    }
  }
}

@MainActor
extension CatalogWorkflowSubscriptionTests {
  // MARK: Typed failure projection

  func testDecodeAndSchemaFailuresMarkFailedWithoutTouchingSnapshot() async throws {
    let record = try await seedSuccessfulSubscription()

    for (behavior, expected) in [
      (
        FakeSubscriptionFetcher.Behavior.failure(.contentType(received: "text/plain")),
        SubscriptionRefreshFailure.contentType(.unsupported)
      ),
      (
        FakeSubscriptionFetcher.Behavior.success(Data("not json".utf8)),
        SubscriptionRefreshFailure.decodingFailure
      ),
      (
        FakeSubscriptionFetcher.Behavior.success(Data(#"{"version": 9, "servers": []}"#.utf8)),
        SubscriptionRefreshFailure.unsupportedSchemaVersion
      ),
    ] {
      let treeBefore = workflow.tree
      fetcher.setBehavior(behavior)
      await workflow.refreshSubscription(record.id)

      guard case .failed(_, let failure) = workflow.subscriptions[0].status else {
        return XCTFail("应记失败态：\(behavior)")
      }
      XCTAssertEqual(failure, expected)
      XCTAssertEqual(workflow.tree, treeBefore, "解析类失败不动快照（projection 等价）")
    }
  }

  func testSubscriptionSummaryReflectsStatusAndCounts() async throws {
    _ = try await seedSuccessfulSubscription()
    let healthy = try XCTUnwrap(workflow.subscriptions.first)
    XCTAssertEqual(healthy.name, "Example subscription")
    XCTAssertEqual(healthy.host, "p.example.com", "卡片展示 host，不展示完整 URL（story 23）")
    guard case .succeeded = healthy.status else { return XCTFail("应记成功态") }
    XCTAssertEqual(healthy.serverCount, 2)

    fetcher.setBehavior(.failure(.transport(detail: "URLError.cannotConnectToHost")))
    await workflow.refreshSubscription(healthy.id)

    let failed = try XCTUnwrap(workflow.subscriptions.first)
    guard case .failed(_, let failure) = failed.status else {
      return XCTFail("应保留 typed 失败事实")
    }
    XCTAssertEqual(failure, .transport(.connection))
    XCTAssertEqual(failed.serverCount, 2, "失败保留最后成功的服务器数")
  }

}
