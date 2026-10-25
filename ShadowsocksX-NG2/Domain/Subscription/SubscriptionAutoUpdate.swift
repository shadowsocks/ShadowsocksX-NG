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

/// Provider constraints hide, but never erase, the user's saved override.
struct SubscriptionAutoUpdate: Codable, Equatable, Sendable {
  var provider: SubscriptionUpdatePolicy?
  var userOverride: SubscriptionUpdateMode?
  var interval: SubscriptionUpdateMode = .daily
  var nextUpdateAt: Date?

  var allowsUserOverride: Bool { provider?.allowUserOverride != false }

  var effectiveMode: SubscriptionUpdateMode {
    if let provider, !provider.allowUserOverride { return provider.mode }
    return userOverride ?? provider?.mode ?? .off
  }

  mutating func apply(_ result: SubscriptionUpdatePolicyResult) {
    switch result {
    case .absent: provider = nil
    case .valid(let policy): provider = policy
    case .invalid: break
    }
  }

  mutating func schedule(from date: Date, jitter: Double) {
    nextUpdateAt = effectiveMode.interval.map {
      date.addingTimeInterval($0 * (1 + min(max(jitter, 0), 0.1)))
    }
  }
}
