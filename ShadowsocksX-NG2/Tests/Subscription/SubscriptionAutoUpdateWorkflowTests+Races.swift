import Foundation
import Testing

@testable import ShadowsocksX_NG2

extension SubscriptionAutoUpdateWorkflowTests {
  @Test func inFlightSettingsUseLatestModeAndCancellationPreservesPlan() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create(settings: .init(userOverride: .daily))
      let fetcher = GatedFetcher()
      let workflow = fixture.makeWorkflow(fetcher: fetcher)
      let request = Task { await workflow.refreshSubscription(first.id) }
      try await withTestTask(request, release: fetcher.releaseAll) {
        try await requireTestCondition("fetch entered") { fetcher.didEnterFetch }
        await workflow.refreshSubscription(first.id)
        #expect(fetcher.requestCount == 1)
        fixture.now = fixture.now.addingTimeInterval(100)
        try workflow.saveSubscriptionAutoUpdate(first.id, settings: .init(userOverride: .weekly))
        fixture.now = fixture.now.addingTimeInterval(200)
      }
      #expect(
        workflow.subscriptions.first?.autoUpdate.nextUpdateAt
          == fixture.now.addingTimeInterval(604_800))
      let cancelling = GatedFetcher()
      let reloaded = fixture.makeWorkflow(fetcher: cancelling)
      let before = reloaded.subscriptions
      let cancelled = Task { await reloaded.refreshSubscription(first.id) }
      try await withTestTask(cancelled, release: cancelling.releaseAll) {
        try await requireTestCondition("cancelled fetch entered") { cancelling.didEnterFetch }
        cancelled.cancel()
      }
      #expect(reloaded.subscriptions == before)
    }
  }

  @Test func changingURLRejectsOldResponseAndClearsPolicyEvenWhenNewFetchFails() async throws {
    try await withAutoUpdateFixture { fixture in
      fixture.respond(mode: .daily, allowsOverride: false)
      let first = try await fixture.create(
        settings: .init(userOverride: .weekly, interval: .weekly))
      let fetcher = URLChangeFetcher()
      let workflow = fixture.makeWorkflow(fetcher: fetcher)
      let request = Task { await workflow.refreshSubscription(first.id) }
      var current: [SubscriptionSummary] = []
      try await withTestTask(request, release: fetcher.release.release) {
        try #require(await fetcher.entered.wait())
        try await workflow.editSubscriptionURL(first.id, urlString: "https://new.example.com/sub")
        #expect(workflow.subscriptions.first?.id == first.id)
        #expect(workflow.subscriptions.first?.groupID == first.groupID)
        #expect(workflow.subscriptions.first?.autoUpdate.provider == nil)
        #expect(workflow.subscriptions.first?.autoUpdate.userOverride == .weekly)
        #expect(workflow.subscriptions.first?.lastSucceededAt == first.lastSucceededAt)
        current = workflow.subscriptions
      }
      #expect(workflow.subscriptions == current)
      #expect(try workflow.subscriptionURL(for: first.id) == "https://new.example.com/sub")
    }
  }

  @Test func deletionRejectsLateResponse() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create()
      let fetcher = GatedFetcher()
      let workflow = fixture.makeWorkflow(fetcher: fetcher)
      let request = Task { await workflow.refreshSubscription(first.id) }
      try await withTestTask(request, release: fetcher.releaseAll) {
        try await requireTestCondition("deleting fetch entered") { fetcher.didEnterFetch }
        _ = try await workflow.removeSubscription(first.id)
      }
      #expect(workflow.subscriptions.isEmpty)
      #expect(workflow.refreshingSubscriptionIDs.isEmpty)
    }
  }

  @Test func dueSubscriptionsRunSequentiallyAndOverlapWithManualRefreshIsSkipped() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create(settings: .init(userOverride: .daily))
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(100_000)
      let fetcher = GatedFetcher()
      let workflow = fixture.makeWorkflow(fetcher: fetcher)
      let batch = Task { await workflow.refreshDueSubscriptions() }
      try await withTestTask(batch, release: fetcher.releaseAll) {
        try await requireTestCondition("batch fetch entered") { fetcher.didEnterFetch }
        #expect(fetcher.requestCount == 1)
        await workflow.refreshSubscription(first.id)
        #expect(fetcher.requestCount == 1)
      }
      #expect(fetcher.requestCount == 2)
    }
  }

  @Test func subscriptionsBecomingDueDuringABatchAreNotMissed() async throws {
    try await withAutoUpdateFixture { fixture in
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(1_000)
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(85_400)
      let fetcher = GatedFetcher()
      let workflow = fixture.makeWorkflow(fetcher: fetcher)
      let batch = Task { await workflow.refreshDueSubscriptions() }
      try await withTestTask(batch, release: fetcher.releaseAll) {
        try await requireTestCondition("first due fetch entered") { fetcher.didEnterFetch }
        #expect(fetcher.requestCount == 1)
        fixture.now = fixture.now.addingTimeInterval(1_000)
      }
      #expect(fetcher.requestCount == 2)
    }
  }

  @Test func schedulerStartsWithOverduePlanAndStopsBeforeFurtherRequests() async throws {
    try await withAutoUpdateFixture { fixture in
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(1_000_000)
      let fetcher = GatedFetcher()
      let scheduled = TestAsyncGate("next automatic update scheduled")
      let workflow = fixture.makeWorkflow(
        fetcher: fetcher,
        wait: { delay in
          if delay > 0 {
            scheduled.release()
            try await Task.sleep(for: .seconds(delay))
          }
        })
      defer {
        fetcher.releaseAll()
        workflow.stopSubscriptionAutomaticUpdates()
      }
      workflow.startSubscriptionAutomaticUpdates()
      try await requireTestCondition("automatic fetch entered") { fetcher.didEnterFetch }
      workflow.subscriptionAutomaticUpdatesDidWake()
      #expect(fetcher.requestCount == 1)
      fetcher.releaseAll()
      try #require(await scheduled.wait())
      #expect(
        workflow.subscriptions.first?.autoUpdate.nextUpdateAt
          == fixture.now.addingTimeInterval(86_400))
      workflow.stopSubscriptionAutomaticUpdates()
      fixture.now = fixture.now.addingTimeInterval(1_000_000)
      workflow.subscriptionAutomaticUpdatesDidWake()
      #expect(fetcher.requestCount == 1)
    }
  }

  @Test func timerAndWakeRefreshOnlyAfterThePersistedDeadline() async throws {
    try await withAutoUpdateFixture { fixture in
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      let sleeping = TestAsyncGate("scheduler waiting for deadline")
      let advance = TestAsyncGate("clock advances")
      let fetcher = GatedFetcher()
      let workflow = fixture.makeWorkflow(
        fetcher: fetcher,
        wait: { _ in
          sleeping.release()
          _ = await advance.wait()
        })
      defer {
        advance.release()
        fetcher.releaseAll()
        workflow.stopSubscriptionAutomaticUpdates()
      }
      workflow.startSubscriptionAutomaticUpdates()
      try #require(await sleeping.wait())
      #expect(fetcher.requestCount == 0)
      fixture.now = fixture.now.addingTimeInterval(86_400)
      advance.release()
      try await requireTestCondition("timer fires at deadline") { fetcher.didEnterFetch }
      workflow.stopSubscriptionAutomaticUpdates()
      fetcher.releaseAll()
      // A fresh workflow resumes the still-overdue persisted plan on wake.
      let resumedFetcher = GatedFetcher()
      let resumed = fixture.makeWorkflow(fetcher: resumedFetcher)
      defer {
        resumedFetcher.releaseAll()
        resumed.stopSubscriptionAutomaticUpdates()
      }
      resumed.startSubscriptionAutomaticUpdates()
      resumed.subscriptionAutomaticUpdatesDidWake()
      try await requireTestCondition("wake fetch entered") { resumedFetcher.didEnterFetch }
      #expect(resumedFetcher.requestCount == 1)
    }
  }
}

private struct URLChangeFetcher: SubscriptionFetching {
  let entered = TestAsyncGate("old URL request entered")
  let release = TestAsyncGate("old URL response released")

  func fetch(_ url: URL) async throws -> Data {
    if url.host == "new.example.com" { throw SubscriptionFetchError.httpStatus(code: 503) }
    entered.release()
    _ = await release.wait()
    return Data(
      #"""
      {"version":1,"servers":[],"x_shadowsocksx_ng":{"schema_version":1,
      "auto_update":{"mode":"daily","allow_user_override":false}}}
      """#.utf8)
  }
}
