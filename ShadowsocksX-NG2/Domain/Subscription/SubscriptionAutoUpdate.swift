import Foundation

enum SubscriptionUpdateMode: String, Codable, CaseIterable, Sendable {
  case off, daily, weekly

  var interval: TimeInterval? {
    switch self {
    case .off: nil
    case .daily: 86_400
    case .weekly: 604_800
    }
  }
}

struct SubscriptionUpdatePolicy: Codable, Equatable, Sendable {
  var mode: SubscriptionUpdateMode
  var allowUserOverride: Bool

  enum CodingKeys: String, CodingKey {
    case mode
    case allowUserOverride = "allow_user_override"
  }
}

enum SubscriptionUpdatePolicyResult: Equatable, Sendable {
  case absent, invalid
  case valid(SubscriptionUpdatePolicy)
}

/// Editable choices; provider facts and the persisted deadline are not form input.
struct SubscriptionAutoUpdateSettings: Equatable, Sendable {
  var userOverride: SubscriptionUpdateMode?
  var interval: SubscriptionUpdateMode = .daily
}

/// Provider constraints hide, but never erase, the user's saved override.
struct SubscriptionAutoUpdate: Codable, Equatable, Sendable {
  private(set) var provider: SubscriptionUpdatePolicy?
  private(set) var userOverride: SubscriptionUpdateMode?
  private(set) var interval: SubscriptionUpdateMode = .daily
  private(set) var nextUpdateAt: Date?

  var allowsUserOverride: Bool { provider?.allowUserOverride != false }

  var effectiveMode: SubscriptionUpdateMode {
    if let provider, !provider.allowUserOverride { return provider.mode }
    return userOverride ?? provider?.mode ?? .off
  }

  var settings: SubscriptionAutoUpdateSettings {
    .init(userOverride: userOverride, interval: interval)
  }

  /// A source change releases its policy only after applying the old constraints.
  mutating func save(
    _ settings: SubscriptionAutoUpdateSettings?, sourceChanged: Bool = false,
    at date: Date, jitter: Double
  ) {
    let previousMode = effectiveMode
    if let settings, allowsUserOverride {
      userOverride = settings.userOverride
      interval = settings.interval == .weekly ? .weekly : .daily
    }
    if sourceChanged { provider = nil }
    if previousMode != effectiveMode { schedule(from: date, jitter: jitter) }
  }

  mutating func refreshSucceeded(
    policy: SubscriptionUpdatePolicyResult, at date: Date, jitter: Double
  ) {
    switch policy {
    case .absent: provider = nil
    case .valid(let policy): provider = policy
    case .invalid: break
    }
    schedule(from: date, jitter: jitter)
  }

  mutating func refreshFailed(at date: Date, jitter: Double) {
    schedule(from: date, jitter: jitter)
  }

  private mutating func schedule(from date: Date, jitter: Double) {
    nextUpdateAt = effectiveMode.interval.map {
      date.addingTimeInterval($0 * (1 + min(max(jitter, 0), 0.1)))
    }
  }
}
