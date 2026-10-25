import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct SubscriptionAutoUpdateTests {
  @Test func savingSettingsPreservesPlanUntilEffectiveModeChanges() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var state = SubscriptionAutoUpdate()
    state.save(.init(userOverride: .daily, interval: .off), at: now, jitter: 0.1)
    #expect(state.interval == .daily)
    #expect(state.nextUpdateAt == now.addingTimeInterval(95_040))
    state.save(.init(userOverride: .daily, interval: .weekly), at: now, jitter: 0)
    #expect(state.interval == .weekly)
    #expect(state.nextUpdateAt == now.addingTimeInterval(95_040))
    state.save(.init(userOverride: .off, interval: .weekly), at: now, jitter: 0)
    #expect(state.nextUpdateAt == nil)
    #expect(state.interval == .weekly)
  }

  @Test func changingSourceReleasesPolicyAndRetainsTheLockedUserChoice() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var state = SubscriptionAutoUpdate()
    state.save(.init(userOverride: .weekly, interval: .weekly), at: now, jitter: 0)
    state.refreshSucceeded(
      policy: .valid(.init(mode: .daily, allowUserOverride: false)), at: now, jitter: 0)
    state.save(
      .init(userOverride: .off), sourceChanged: true,
      at: now.addingTimeInterval(100), jitter: 0)
    #expect(state.provider == nil)
    #expect(state.userOverride == .weekly)
    #expect(state.interval == .weekly)
    #expect(state.nextUpdateAt == now.addingTimeInterval(604_900))
  }

  @Test func refreshResultsDistinguishWithdrawalFromInvalidPolicyAndFailure() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let policy = SubscriptionUpdatePolicy(mode: .daily, allowUserOverride: false)
    var state = SubscriptionAutoUpdate()
    state.refreshSucceeded(policy: .valid(policy), at: now, jitter: 0)
    #expect(state.nextUpdateAt == now.addingTimeInterval(86_400))
    state.refreshSucceeded(policy: .invalid, at: now.addingTimeInterval(100), jitter: 0.1)
    #expect(state.provider == policy)
    #expect(state.nextUpdateAt == now.addingTimeInterval(95_140))
    state.refreshFailed(at: now.addingTimeInterval(200), jitter: 0)
    #expect(state.provider == policy)
    #expect(state.nextUpdateAt == now.addingTimeInterval(86_600))
    state.refreshSucceeded(policy: .absent, at: now.addingTimeInterval(300), jitter: 0)
    #expect(state.provider == nil)
    #expect(state.nextUpdateAt == nil)
  }

}
