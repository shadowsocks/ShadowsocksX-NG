import Foundation
import Testing

@testable import ShadowsocksX_NG2

extension SubscriptionAutoUpdateWorkflowTests {
  @Test(arguments: [true, false])
  func failedSaveWaitsForWakeOrCommittedChangesBeforeRetry(wake: Bool) async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(1_000)
      let second = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(85_400)
      let scheduled = TestAsyncGate("future plan scheduled after failed save")
      let workflow = fixture.makeWorkflow(wait: { delay in
        if delay > 0 {
          scheduled.release()
          try await Task.sleep(for: .seconds(delay))
        }
      })
      defer { workflow.stopSubscriptionAutomaticUpdates() }
      let before = workflow.subscriptions
      let requests = fixture.fetcher.requestCount
      try FileManager.default.removeItem(at: fixture.directory)
      try Data().write(to: fixture.directory)
      workflow.startSubscriptionAutomaticUpdates()
      try #require(await scheduled.wait())
      #expect(workflow.subscriptions == before)
      #expect(workflow.subscriptionRefreshFailure(for: first.id) == .commit)
      #expect(fixture.fetcher.requestCount == requests + 1)
      #expect(workflow.refreshingSubscriptionIDs.isEmpty)

      try FileManager.default.removeItem(at: fixture.directory)
      try FileManager.default.createDirectory(
        at: fixture.directory, withIntermediateDirectories: true)
      if wake {
        workflow.subscriptionAutomaticUpdatesDidWake()
      } else {
        try await workflow.saveSubscription(second.id, urlString: "https://example.com/sub")
      }
      try await requireTestCondition("overdue plan succeeds after external event") {
        workflow.subscriptions.first?.autoUpdate.nextUpdateAt
          == fixture.now.addingTimeInterval(86_400)
          && workflow.refreshingSubscriptionIDs.isEmpty
      }
      #expect(fixture.fetcher.requestCount == requests + 2)
      #expect(workflow.subscriptionRefreshFailure(for: first.id) == nil)
    }
  }

  @Test func stoppingCancelsManualRequestsAndPreservesTheirCommittedPlan() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create(settings: .init(userOverride: .daily))
      let fetcher = GatedFetcher()
      let waiting = TestAsyncGate("automatic update waiting")
      var waitCount = 0
      let workflow = fixture.makeWorkflow(
        fetcher: fetcher,
        wait: { delay in
          waitCount += 1
          waiting.release()
          try await Task.sleep(for: .seconds(delay))
        })
      defer { workflow.stopSubscriptionAutomaticUpdates() }
      workflow.startSubscriptionAutomaticUpdates()
      try #require(await waiting.wait())
      let before = workflow.subscriptions
      let request = Task { await workflow.refreshSubscription(first.id) }
      try await withTestTask(request, release: fetcher.releaseAll) {
        try await requireTestCondition("manual refresh entered") { fetcher.didEnterFetch }
        #expect(workflow.refreshingSubscriptionIDs == [first.id])
        workflow.stopSubscriptionAutomaticUpdates()
        workflow.stopSubscriptionAutomaticUpdates()
        workflow.subscriptionAutomaticUpdatesDidWake()
        #expect(workflow.refreshingSubscriptionIDs.isEmpty)
      }
      #expect(workflow.subscriptions == before)
      #expect(workflow.subscriptionRefreshCompletions.isEmpty)
      #expect(workflow.subscriptionRefreshFailure(for: first.id) == nil)
      #expect(waitCount == 1)
    }
  }

  @Test func stoppedBatchDoesNotReadTheClockAfterItsRequestReturns() async throws {
    try await withAutoUpdateFixture { fixture in
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(1_000)
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(85_400)
      let fetcher = GatedFetcher()
      var clockReads = 0
      var workflow: CatalogWorkflow? = makeCatalogWorkflow(
        coordinator: fixture.coordinator, subscriptionFetcher: fetcher,
        subscriptionNow: {
          clockReads += 1
          return fixture.now
        })
      let workflowIsReleased = { [weak workflow] in workflow == nil }
      defer {
        workflow?.stopSubscriptionAutomaticUpdates()
        fetcher.releaseAll()
      }
      workflow?.startSubscriptionAutomaticUpdates()
      try await requireTestCondition("automatic request entered") { fetcher.didEnterFetch }
      let readsBeforeStop = clockReads
      workflow?.stopSubscriptionAutomaticUpdates()
      workflow = nil
      fetcher.releaseAll()
      try await requireTestCondition(
        "stopped batch released its workflow", condition: workflowIsReleased)
      #expect(clockReads == readsBeforeStop)
    }
  }

}
