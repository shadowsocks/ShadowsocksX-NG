import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct SubscriptionRefreshFeedbackTests {
  @Test func failureLastsTenSecondsAndOldExpirationCannotClearNewResult() {
    let date = Date(timeIntervalSince1970: 100)
    let first = SubscriptionRefreshCompletion(completedAt: date)
    let next = SubscriptionRefreshCompletion(completedAt: date, failure: .httpStatus(code: 503))
    let state = SubscriptionRefreshFeedbackState()
    state.present(first, now: date)
    state.present(next, now: date.addingTimeInterval(3))
    state.expire(first.id)
    #expect(state.completion == next)
    #expect(state.expiresAt == date.addingTimeInterval(10))
    state.present(next, now: date.addingTimeInterval(10))
    #expect(state.completion == nil)
  }

  @Test func successExpiresThreeSecondsAfterCompletionWithoutRestartingOnReturn() {
    let date = Date(timeIntervalSince1970: 100)
    let completion = SubscriptionRefreshCompletion(completedAt: date)
    let state = SubscriptionRefreshFeedbackState()
    state.present(completion, now: date.addingTimeInterval(2))
    #expect(state.completion == completion)
    #expect(state.expiresAt == date.addingTimeInterval(3))
    state.present(completion, now: date.addingTimeInterval(3))
    #expect(state.completion == nil)
  }

  @Test func successfulRefreshPublishesSessionResultWithoutReplayingOnReload() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let summary = try await fixture.workflow.createSubscription(
      urlString: "https://example.com/sub.json")
    let completion = try #require(fixture.workflow.subscriptionRefreshCompletions[summary.id])
    #expect(completion.failure == nil)
    #expect(fixture.workflow.refreshingSubscriptionIDs.isEmpty)
    #expect(fixture.reload().subscriptionRefreshCompletions.isEmpty)
    await fixture.workflow.refreshAllSubscriptions()
    let next = try #require(fixture.workflow.subscriptionRefreshCompletions[summary.id])
    #expect(next.id != completion.id)
  }

  @Test func failedRefreshPublishesSafeFailureAndNextRefreshReplacesIt() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let summary = try await fixture.workflow.createSubscription(
      urlString: "https://example.com/sub.json")
    fixture.fetcher.setBehavior(.failure(.httpStatus(code: 503)))
    await fixture.workflow.refreshSubscription(summary.id)
    let failure = try #require(fixture.workflow.subscriptionRefreshCompletions[summary.id])
    #expect(failure.failure == .httpStatus(code: 503))
    fixture.fetcher.setBehavior(.success(SubscriptionDocs.flat(serverCount: 1)))
    try await fixture.workflow.editSubscriptionURL(
      summary.id, urlString: "https://example.com/new.json")
    let success = try #require(fixture.workflow.subscriptionRefreshCompletions[summary.id])
    #expect(success.failure == nil)
    #expect(success.id != failure.id)
    _ = try await fixture.workflow.removeSubscription(summary.id)
    #expect(fixture.workflow.subscriptionRefreshCompletions[summary.id] == nil)
  }

  @Test func failureFeedbackSurvivesFailureToPersistStatus() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let summary = try await fixture.workflow.createSubscription(
      urlString: "https://example.com/sub.json")
    try FileManager.default.removeItem(at: fixture.directory)
    try Data("not a directory".utf8).write(to: fixture.directory)
    fixture.fetcher.setBehavior(.failure(.httpStatus(code: 503)))
    await fixture.workflow.refreshSubscription(summary.id)
    #expect(
      fixture.workflow.subscriptionRefreshCompletions[summary.id]?.failure == .httpStatus(code: 503)
    )
    #expect(fixture.workflow.subscriptions.first?.status == summary.status)
  }

  @Test func cancellationAndDuplicateRequestDoNotPublishCompletion() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let summary = try await fixture.workflow.createSubscription(
      urlString: "https://example.com/sub.json")
    let gated = GatedFetcher()
    let workflow = fixture.reload(fetcher: gated)
    let task = Task { await workflow.refreshSubscription(summary.id) }
    for _ in 0..<1000 {
      if gated.didEnterFetch { break }
      await Task.yield()
    }
    #expect(gated.didEnterFetch)
    #expect(workflow.refreshingSubscriptionIDs.contains(summary.id))
    #expect(workflow.subscriptionRefreshCompletions[summary.id] == nil)
    await workflow.refreshSubscription(summary.id)
    #expect(gated.requestCount == 1)
    task.cancel()
    gated.releaseAll()
    await task.value
    #expect(workflow.subscriptionRefreshCompletions[summary.id] == nil)
    #expect(workflow.refreshingSubscriptionIDs.isEmpty)
  }

  @MainActor
  private final class Fixture {
    let directory: URL
    let credentials = InMemoryCredentialStore()
    let fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.flat(serverCount: 1)))
    let workflow: CatalogWorkflow

    init() throws {
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("subscription-feedback-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      workflow = makeCatalogWorkflow(
        coordinator: CatalogCommitCoordinator(
          fileStore: CatalogFileStore(fileURL: directory.appendingPathComponent("catalog.json")),
          runtime: FakeCatalogRuntime()),
        credentials: credentials, subscriptionFetcher: fetcher)
    }

    func reload(fetcher override: SubscriptionFetching? = nil) -> CatalogWorkflow {
      makeCatalogWorkflow(
        coordinator: CatalogCommitCoordinator(
          fileStore: CatalogFileStore(fileURL: directory.appendingPathComponent("catalog.json")),
          runtime: FakeCatalogRuntime()),
        credentials: credentials, subscriptionFetcher: override ?? fetcher)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
  }
}
