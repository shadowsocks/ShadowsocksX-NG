import Foundation

extension CatalogWorkflow {
  enum AutomaticUpdateState {
    case stopped, idle
    case waiting(id: UUID, task: Task<Void, Never>)
    case updating(id: UUID, task: Task<Void, Never>)

    var task: Task<Void, Never>? {
      switch self {
      case .stopped, .idle: nil
      case .waiting(_, let task), .updating(_, let task): task
      }
    }

    var id: UUID? {
      switch self {
      case .stopped, .idle: nil
      case .waiting(let id, _), .updating(let id, _): id
      }
    }
  }

  /// Owned by the GUI process, independently of workspace presentation.
  func startSubscriptionAutomaticUpdates() {
    if case .stopped = automaticUpdateState { automaticUpdateState = .idle }
    scheduleAutomaticUpdateCheck()
  }

  func stopSubscriptionAutomaticUpdates() {
    let task = automaticUpdateState.task
    automaticUpdateState = .stopped
    task?.cancel()
    for id in Array(subscriptionRequests.keys) { cancelSubscriptionRequest(id) }
  }

  /// Startup and wake use the persisted deadline directly, without catch-up jitter.
  func subscriptionAutomaticUpdatesDidWake() {
    scheduleAutomaticUpdateCheck()
  }

  private func refreshDueSubscriptions() async {
    var attempted: Set<NodeID> = []
    while !Task.isCancelled,
      let due = subscriptions.first(where: {
        !attempted.contains($0.id) && subscriptionRequests[$0.id] == nil
          && $0.autoUpdate.effectiveMode != .off
          && ($0.autoUpdate.nextUpdateAt.map { $0 <= dependencies.subscriptionNow() } ?? false)
      })
    {
      attempted.insert(due.id)
      await refreshSubscription(due.id)
    }
  }

  func scheduleAutomaticUpdateCheck(includeOverdue: Bool = true) {
    switch automaticUpdateState {
    case .stopped, .updating: return
    case .idle, .waiting:
      automaticUpdateState.task?.cancel()
      automaticUpdateState = .idle
    }
    let now = dependencies.subscriptionNow()
    guard
      let deadline = subscriptions.filter({
        $0.autoUpdate.effectiveMode != .off && subscriptionRequests[$0.id] == nil
      }).compactMap(\.autoUpdate.nextUpdateAt).filter({
        includeOverdue || $0 > now
      }).min()
    else { return }
    let delay = max(0, deadline.timeIntervalSince(now))
    let wait = dependencies.subscriptionWait
    let id = UUID()
    let task = Task { [weak self] in
      do {
        try await wait(delay)
        try Task.checkCancellation()
      } catch { return }
      guard let self, case .waiting(let currentID, let task) = self.automaticUpdateState,
        currentID == id
      else { return }
      self.automaticUpdateState = .updating(id: id, task: task)
      await self.refreshDueSubscriptions()
      guard self.automaticUpdateState.id == id, !Task.isCancelled else { return }
      self.automaticUpdateState = .idle
      // An unchanged overdue plan (for example a failed save) is not a retry loop.
      self.scheduleAutomaticUpdateCheck(includeOverdue: false)
    }
    automaticUpdateState = .waiting(id: id, task: task)
  }
}
