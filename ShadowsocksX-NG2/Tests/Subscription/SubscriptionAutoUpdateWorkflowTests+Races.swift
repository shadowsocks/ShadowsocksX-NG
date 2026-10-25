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
      await fetcher.waitUntilEntered()
      await workflow.refreshSubscription(first.id)
      #expect(fetcher.requestCount == 1)
      fixture.now = fixture.now.addingTimeInterval(100)
      try workflow.saveSubscriptionAutoUpdate(first.id, settings: .init(userOverride: .weekly))
      fixture.now = fixture.now.addingTimeInterval(200)
      fetcher.releaseAll()
      await request.value
      #expect(
        workflow.subscriptions.first?.autoUpdate.nextUpdateAt
          == fixture.now.addingTimeInterval(604_800))
      let cancelling = GatedFetcher()
      let reloaded = fixture.makeWorkflow(fetcher: cancelling)
      let before = reloaded.subscriptions
      let cancelled = Task { await reloaded.refreshSubscription(first.id) }
      await cancelling.waitUntilEntered()
      cancelled.cancel()
      cancelling.releaseAll()
      await cancelled.value
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
      await fetcher.entered.wait()
      try await workflow.editSubscriptionURL(first.id, urlString: "https://new.example.com/sub")
      #expect(workflow.subscriptions.first?.id == first.id)
      #expect(workflow.subscriptions.first?.groupID == first.groupID)
      #expect(workflow.subscriptions.first?.autoUpdate.provider == nil)
      #expect(workflow.subscriptions.first?.autoUpdate.userOverride == .weekly)
      #expect(workflow.subscriptions.first?.lastSucceededAt == first.lastSucceededAt)
      let current = workflow.subscriptions
      fetcher.release.release()
      await request.value
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
      await fetcher.waitUntilEntered()
      _ = try await workflow.removeSubscription(first.id)
      fetcher.releaseAll()
      await request.value
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
      await fetcher.waitUntilEntered()
      #expect(fetcher.requestCount == 1)
      await workflow.refreshSubscription(first.id)
      #expect(fetcher.requestCount == 1)
      fetcher.releaseAll()
      await batch.value
      #expect(fetcher.requestCount == 2)
    }
  }

  @Test func schedulerStartsWithOverduePlanAndStopsBeforeFurtherRequests() async throws {
    try await withAutoUpdateFixture { fixture in
      _ = try await fixture.create(settings: .init(userOverride: .daily))
      fixture.now = fixture.now.addingTimeInterval(1_000_000)
      let fetcher = GatedFetcher()
      let scheduled = AsyncGate()
      let workflow = fixture.makeWorkflow(
        fetcher: fetcher,
        wait: { delay in
          if delay > 0 {
            scheduled.release()
            try await Task.sleep(for: .seconds(delay))
          }
        })
      workflow.startSubscriptionAutomaticUpdates()
      await fetcher.waitUntilEntered()
      workflow.subscriptionAutomaticUpdatesDidWake()
      #expect(fetcher.requestCount == 1)
      fetcher.releaseAll()
      await scheduled.wait()
      let plan = workflow.subscriptions.first?.autoUpdate.nextUpdateAt
      #expect(plan == fixture.now.addingTimeInterval(86_400))
      workflow.stopSubscriptionAutomaticUpdates()
      fixture.now = fixture.now.addingTimeInterval(1_000_000)
      workflow.subscriptionAutomaticUpdatesDidWake()
      #expect(fetcher.requestCount == 1)
    }
  }
}

private struct URLChangeFetcher: SubscriptionFetching {
  let entered = AsyncGate()
  let release = AsyncGate()

  func fetch(_ url: URL) async throws -> Data {
    if url.host == "new.example.com" { throw SubscriptionFetchError.httpStatus(code: 503) }
    entered.release()
    await release.wait()
    return Data(
      #"""
      {"version":1,
      "servers":[],
      "x_shadowsocksx_ng":{"schema_version":1,
      "auto_update":{"mode":"daily",
      "allow_user_override":false}}}
      """#
      .utf8)
  }
}
