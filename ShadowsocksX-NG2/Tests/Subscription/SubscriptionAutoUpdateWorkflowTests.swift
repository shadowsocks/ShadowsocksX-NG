import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct SubscriptionAutoUpdateWorkflowTests {
  @Test func newSubscriptionsDefaultToOffAndDailyWithoutAPlan() async throws {
    try await withAutoUpdateFixture { fixture in
      let summary = try await fixture.create()
      #expect(summary.autoUpdate.effectiveMode == .off)
      #expect(summary.autoUpdate.interval == .daily)
      #expect(summary.autoUpdate.nextUpdateAt == nil)
    }
  }

  @Test func providerPolicyEnablesUpdatesWithoutAGroupTree() async throws {
    try await withAutoUpdateFixture { fixture in
      fixture.respond(mode: .daily, allowsOverride: false)
      let summary = try await fixture.create()
      #expect(summary.autoUpdate.effectiveMode == .daily)
      #expect(!summary.autoUpdate.allowsUserOverride)
      #expect(summary.autoUpdate.nextUpdateAt == fixture.now.addingTimeInterval(86_400))
    }
  }

  @Test(arguments: [SubscriptionUpdateMode.daily, .weekly], [0.0, 0.1])
  func schedulesFromCompletionAndRetainsPlanAcrossReload(
    mode: SubscriptionUpdateMode, jitter: Double
  ) async throws {
    try await withAutoUpdateFixture { fixture in
      fixture.jitter = jitter
      let first = try await fixture.create()
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub", autoUpdate: .init(userOverride: mode))
      let seconds: TimeInterval =
        mode == .daily ? (jitter == 0 ? 86_400 : 95_040) : (jitter == 0 ? 604_800 : 665_280)
      #expect(fixture.summary.autoUpdate.nextUpdateAt == fixture.now.addingTimeInterval(seconds))
      fixture.now = fixture.now.addingTimeInterval(100)
      await fixture.workflow.refreshSubscription(first.id)
      let success = fixture.summary
      #expect(success.autoUpdate.nextUpdateAt == fixture.now.addingTimeInterval(seconds))
      fixture.now = fixture.now.addingTimeInterval(200)
      fixture.fetcher.setBehavior(.failure(.httpStatus(code: 503)))
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.nextUpdateAt == fixture.now.addingTimeInterval(seconds))
      #expect(fixture.summary.lastSucceededAt == success.lastSucceededAt)
      let reloaded = fixture.makeWorkflow()
      #expect(reloaded.subscriptions == fixture.workflow.subscriptions)
    }
  }

  @Test func forcedPolicyPreservesOverrideThenFollowingClearsIt() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create()
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub",
        autoUpdate: .init(userOverride: .weekly, interval: .weekly))
      fixture.respond(mode: .off, allowsOverride: false)
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.effectiveMode == .off)
      #expect(fixture.summary.autoUpdate.userOverride == .weekly)
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub", autoUpdate: .init(userOverride: .daily))
      #expect(fixture.summary.autoUpdate.userOverride == .weekly)
      fixture.respond(mode: .daily, allowsOverride: true)
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.effectiveMode == .weekly)
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub", autoUpdate: .init())
      #expect(fixture.summary.autoUpdate.userOverride == nil)
      #expect(fixture.summary.autoUpdate.effectiveMode == .daily)
      fixture.fetcher.setBehavior(.success(SubscriptionDocs.flat(serverCount: 0)))
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.provider == nil)
      #expect(fixture.summary.autoUpdate.effectiveMode == .off)
      #expect(fixture.summary.autoUpdate.nextUpdateAt == nil)
    }
  }

  @Test func invalidOrFailedResponseRetainsPolicyButMissingPolicyWithdrawsIt() async throws {
    try await withAutoUpdateFixture { fixture in
      fixture.respond(mode: .daily, allowsOverride: false)
      let first = try await fixture.create()
      let policy = fixture.summary.autoUpdate.provider
      fixture.fetcher.setBehavior(
        .success(
          Data(
            #"{"version":1,"servers":[],"x_shadowsocksx_ng":{"schema_version":1,"auto_update":{}}}"#
              .utf8)))
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.provider == policy)
      if case .succeeded = fixture.summary.status {
      } else {
        Issue.record("Valid servers must still commit")
      }
      fixture.fetcher.setBehavior(.failure(.httpStatus(code: 503)))
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.provider == policy)
      fixture.fetcher.setBehavior(.success(SubscriptionDocs.flat(serverCount: 0)))
      await fixture.workflow.refreshSubscription(first.id)
      #expect(fixture.summary.autoUpdate.provider == nil)
    }
  }

  @Test func settingsOnlyReplanWhenEffectiveModeChangesAndNeverConvergeRuntime() async throws {
    try await withAutoUpdateFixture { fixture in
      fixture.respond(mode: .daily, allowsOverride: true)
      let first = try await fixture.create()
      for _ in 0..<100 {
        if case .syncing = fixture.coordinator.syncStatus { await Task.yield() } else { break }
      }
      if case .syncing = fixture.coordinator.syncStatus { Issue.record("Runtime did not settle") }
      let converges = fixture.runtime.convergeCount
      let plan = fixture.summary.autoUpdate.nextUpdateAt
      let requests = fixture.fetcher.requestCount
      fixture.now = fixture.now.addingTimeInterval(100)
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub", autoUpdate: .init(userOverride: .daily))
      #expect(fixture.summary.autoUpdate.nextUpdateAt == plan)
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub",
        autoUpdate: .init(userOverride: .weekly, interval: .weekly))
      #expect(fixture.summary.autoUpdate.nextUpdateAt == fixture.now.addingTimeInterval(604_800))
      try await fixture.workflow.saveSubscription(
        first.id, urlString: "https://example.com/sub",
        autoUpdate: .init(userOverride: .off, interval: .weekly))
      #expect(fixture.summary.autoUpdate.nextUpdateAt == nil)
      #expect(fixture.summary.autoUpdate.interval == .weekly)
      #expect(fixture.fetcher.requestCount == requests)
      #expect(fixture.runtime.convergeCount == converges)
    }
  }

  @Test func dueRefreshRunsOnceAfterManyMissedCyclesAndFailuresDoNotBlockOthers() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create(settings: .init(userOverride: .daily))
      let second = try await fixture.create(settings: .init(userOverride: .daily))
      let requests = fixture.fetcher.requestCount
      await fixture.workflow.refreshDueSubscriptions()
      #expect(fixture.fetcher.requestCount == requests)
      fixture.now = fixture.now.addingTimeInterval(1_000_000)
      fixture.fetcher.setBehavior(.failure(.httpStatus(code: 503)))
      await fixture.workflow.refreshDueSubscriptions()
      #expect(fixture.fetcher.requestCount == requests + 2)
      await fixture.workflow.refreshDueSubscriptions()
      #expect(fixture.fetcher.requestCount == requests + 2)
      #expect(fixture.workflow.subscriptions.map(\.id) == [first.id, second.id])
      #expect(
        fixture.workflow.subscriptions.allSatisfy {
          $0.autoUpdate.nextUpdateAt == fixture.now.addingTimeInterval(86_400)
        })
    }
  }

  @Test func legacyRecordWithoutEnvelopeLoadsDisabledWithoutFetching() async throws {
    try await withAutoUpdateFixture { fixture in
      let first = try await fixture.create()
      let record = try #require(fixture.coordinator.committedSubscriptions.first)
      var json = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
      json.removeValue(forKey: "autoUpdateState")
      let old = try JSONDecoder().decode(
        SubscriptionRecord.self, from: JSONSerialization.data(withJSONObject: json))
      #expect(old.autoUpdate.effectiveMode == .off)
      #expect(old.autoUpdate.interval == .daily)
      let requests = fixture.fetcher.requestCount
      let reload = fixture.makeWorkflow()
      reload.startSubscriptionAutomaticUpdates()
      await reload.refreshDueSubscriptions()
      reload.stopSubscriptionAutomaticUpdates()
      #expect(reload.subscriptions.first?.id == first.id)
      #expect(fixture.fetcher.requestCount == requests)
    }
  }
}

@MainActor
func withAutoUpdateFixture(_ body: (AutoUpdateFixture) async throws -> Void) async throws {
  let fixture = AutoUpdateFixture()
  defer {
    fixture.workflow.stopSubscriptionAutomaticUpdates()
    try? FileManager.default.removeItem(at: fixture.directory)
  }
  try await body(fixture)
}

@MainActor
final class AutoUpdateFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var now = Date(timeIntervalSince1970: 1_700_000_000)
  var jitter = 0.0
  let runtime = FakeCatalogRuntime()
  let fetcher = FakeSubscriptionFetcher(behavior: .success(SubscriptionDocs.flat(serverCount: 0)))
  lazy var store = makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json"))
  lazy var coordinator = CatalogCommitCoordinator(fileStore: store, runtime: runtime)
  lazy var workflow = makeWorkflow(coordinator: coordinator)
  var summary: SubscriptionSummary { workflow.subscriptions[0] }

  func makeWorkflow(
    coordinator: CatalogCommitCoordinator? = nil, fetcher: SubscriptionFetching? = nil,
    wait: @escaping (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) -> CatalogWorkflow {
    makeCatalogWorkflow(
      coordinator: coordinator
        ?? CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()),
      subscriptionFetcher: fetcher ?? self.fetcher,
      subscriptionNow: { [unowned self] in self.now },
      subscriptionJitter: { [unowned self] in self.jitter }, subscriptionWait: wait)
  }

  func create(settings: SubscriptionAutoUpdateSettings = .init()) async throws
    -> SubscriptionSummary
  {
    try await workflow.createSubscription(
      urlString: "https://example.com/sub", autoUpdate: settings)
  }

  func respond(mode: SubscriptionUpdateMode, allowsOverride: Bool) {
    fetcher.setBehavior(
      .success(
        Data(
          """
          {"version":1,"servers":[],"x_shadowsocksx_ng":{"schema_version":1,
          "auto_update":{"mode":"\(mode.rawValue)","allow_user_override":\(allowsOverride)}}}
          """.utf8)))
  }
}
