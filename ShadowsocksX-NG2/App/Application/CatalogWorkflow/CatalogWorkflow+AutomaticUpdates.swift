import Foundation

extension CatalogWorkflow {
  /// Owned by the GUI process, independently of workspace presentation.
  func startSubscriptionAutomaticUpdates() {
    automaticUpdatesRunning = true
    scheduleAutomaticUpdateCheck()
  }

  func stopSubscriptionAutomaticUpdates() {
    automaticUpdatesRunning = false
    automaticUpdateTimer?.cancel()
    automaticUpdateTimer = nil
    automaticUpdateBatch?.cancel()
    for id in Array(subscriptionRequests.keys) { cancelSubscriptionRequest(id) }
  }

  /// Startup and wake use the persisted deadline directly, without catch-up jitter.
  func subscriptionAutomaticUpdatesDidWake() {
    guard automaticUpdatesRunning else { return }
    scheduleAutomaticUpdateCheck()
  }

  func refreshDueSubscriptions() async {
    guard !checkingDueSubscriptions else { return }
    checkingDueSubscriptions = true
    defer { checkingDueSubscriptions = false }
    var attempted: Set<NodeID> = []
    while let due = subscriptions.first(where: {
      !attempted.contains($0.id) && !refreshingSubscriptionIDs.contains($0.id)
        && $0.autoUpdate.effectiveMode != .off
        && ($0.autoUpdate.nextUpdateAt.map { $0 <= dependencies.subscriptionNow() } ?? false)
    }) {
      guard !Task.isCancelled else { return }
      attempted.insert(due.id)
      await refreshSubscription(due.id)
    }
  }

  func scheduleAutomaticUpdateCheck(includeOverdue: Bool = true) {
    automaticUpdateTimer?.cancel()
    automaticUpdateTimer = nil
    guard automaticUpdatesRunning, automaticUpdateBatch == nil,
      let deadline = subscriptions.filter({
        $0.autoUpdate.effectiveMode != .off && !refreshingSubscriptionIDs.contains($0.id)
      }).compactMap(\.autoUpdate.nextUpdateAt).filter({
        includeOverdue || $0 > dependencies.subscriptionNow()
      }).min()
    else { return }
    let delay = max(0, deadline.timeIntervalSince(dependencies.subscriptionNow()))
    let wait = dependencies.subscriptionWait
    automaticUpdateTimer = Task { [weak self] in
      do {
        try await wait(delay)
        try Task.checkCancellation()
      } catch { return }
      guard let self, self.automaticUpdatesRunning else { return }
      self.automaticUpdateBatch = Task { [weak self] in
        guard let self else { return }
        await self.refreshDueSubscriptions()
        self.automaticUpdateBatch = nil
        // An unchanged overdue plan (for example a failed save) is not a retry loop.
        self.scheduleAutomaticUpdateCheck(includeOverdue: false)
      }
    }
  }
}
