import Combine
import Foundation

/// Owns probe identity, observation lifetime and runtime ownership interpretation.
/// Cached observations are never reinterpreted using a different runtime context.
@MainActor
final class ListenerOccupancy: ObservableObject {
  private struct Context: Equatable, Sendable {
    let draft: SettingsPortDraft
    let proposedListen: RuntimeListenFacts
    let runtimeListen: RuntimeListenFacts?
    let runtimeProcessID: Int32?

    func ownsListener(_ result: PortOccupancy, for id: SettingsPortID) -> Bool {
      let endpoint = SettingsPortAdapter.endpoint(for: id, group: draft.group)
      guard runtimeListen?.port(for: endpoint) == proposedListen.port(for: endpoint),
        let processID = runtimeProcessID, case .occupied(let facts) = result
      else { return false }
      let isVerifiedOwner =
        facts.occupiedProcessIDs == Set([processID])
        && facts.occupiedFamilies.isSubset(of: facts.verifiedFamilies)
      if isVerifiedOwner { return true }

      let proposedMode = PortOccupancyProbeRequest(
        endpoint: endpoint, listen: proposedListen
      ).listenerMode
      let runtimeMode = runtimeListen.map {
        PortOccupancyProbeRequest(endpoint: endpoint, listen: $0).listenerMode
      }
      // A dual-stack IPv6 socket can own the IPv4 listener without an IPv4 PID.
      return (proposedMode == .disabled || proposedMode == .allIPv4Interfaces)
        && facts.occupiedFamilies == [.ipv4]
        && runtimeMode == .allIPv4AndIPv6Interfaces
        && facts.processIDs(for: .ipv4).isEmpty
        && facts.processIDs(for: .ipv6).contains(processID)
        && Set(PortOccupancyAddressFamily.allCases).isSubset(of: facts.verifiedFamilies)
    }
  }

  private struct Preview {
    let context: Context
    var results: [SettingsPortID: PortOccupancy]?

    var blockedPortIDs: [SettingsPortID] {
      SettingsPortID.allCases.filter { id in
        guard let result = results?[id], case .occupied = result else { return false }
        return !context.ownsListener(result, for: id)
      }
    }
  }

  @Published private var preview: Preview?
  private var generation = 0
  private let committing: SettingsCommitting
  private let probe: PortOccupancyProbing

  init(committing: SettingsCommitting, probe: PortOccupancyProbing) {
    self.committing = committing
    self.probe = probe
  }

  func listenSettings(for draft: SettingsPortDraft) -> ProxyListeningConfiguration {
    var listen = committing.committedSettings.listen
    switch draft.group {
    case .local:
      listen.socksPort = draft.socksPort
      listen.httpPort = draft.httpPort
    case .lan:
      listen.lan.socksPort = draft.socksPort
      listen.lan.httpPort = draft.httpPort
      listen.lan.mode = draft.listenerMode
      listen.lan.isEnabled = draft.isEnabled
    }
    return listen
  }

  func reset() {
    generation += 1
    preview = nil
  }

  func refresh(_ draft: SettingsPortDraft) {
    generation += 1
    let epoch = generation
    let context = context(for: draft)
    preview = Preview(context: context)
    if draft.group == .lan && !draft.isEnabled {
      preview = Preview(context: context, results: [.socks: .free, .http: .free])
      return
    }
    let probe = probe
    Task { [weak self] in
      let results = await Self.probe(context, using: probe)
      guard let self, epoch == generation else { return }
      guard context == self.context(for: draft) else {
        refresh(draft)
        return
      }
      preview = Preview(context: context, results: results)
    }
  }

  func fieldFacts(for id: SettingsPortID, draft: SettingsPortDraft)
    -> (occupancy: SettingsPortOccupancy?, isRuntimeException: Bool)
  {
    guard let preview = currentPreview(for: draft), let result = preview.results?[id] else {
      return (nil, false)
    }
    return (SettingsPortOccupancy(result), preview.context.ownsListener(result, for: id))
  }

  func canSave(_ draft: SettingsPortDraft) -> Bool {
    guard let preview = currentPreview(for: draft), preview.results != nil else { return false }
    return preview.blockedPortIDs.isEmpty
  }

  func cachedSaveRejection(for draft: SettingsPortDraft) -> SettingsCommandRejection? {
    guard let preview else {
      refresh(draft)
      return .inProgress
    }
    guard preview.context == context(for: draft) else {
      refreshIfEditing(draft)
      return .superseded
    }
    guard preview.results != nil else { return .inProgress }
    return preview.blockedPortIDs.isEmpty ? nil : .occupied(preview.blockedPortIDs)
  }

  /// Save-time checks remain distinct from editor previews and never commit.
  func recheck(_ draft: SettingsPortDraft) async -> SettingsCommandRejection? {
    guard draft.group != .lan || draft.isEnabled else { return nil }
    let context = context(for: draft)
    let epoch = generation
    let results = await Self.probe(context, using: probe)
    guard !Task.isCancelled, epoch == generation, context == self.context(for: draft) else {
      refreshIfEditing(draft)
      return .superseded
    }
    let blocked = Preview(context: context, results: results).blockedPortIDs
    return blocked.isEmpty ? nil : .occupied(blocked)
  }

  func suggestFreePort(for id: SettingsPortID, draft: SettingsPortDraft) async
    -> SettingsCommandOutcome
  {
    let context = context(for: draft)
    guard preview?.context == context else {
      refreshIfEditing(draft)
      return .rejected(.superseded)
    }
    let epoch = generation
    let endpoint = SettingsPortAdapter.endpoint(for: id, group: draft.group)
    let excluded = Set(ProxyEndpointKind.allCases.map { context.proposedListen.port(for: $0) })
    let probe = probe
    let candidate = await Task.detached(priority: .utility) {
      PortSuggestion.firstFree(excluding: excluded) { port in
        let request = PortOccupancyProbeRequest(
          endpoint: endpoint,
          listen: context.proposedListen.replacingPort(port, for: endpoint), port: port)
        if case .free = probe.occupancy(for: request) { return true }
        return false
      }
    }.value
    guard !Task.isCancelled, epoch == generation, preview?.context == context,
      context == self.context(for: draft)
    else {
      refreshIfEditing(draft)
      return .rejected(.superseded)
    }
    guard let candidate else { return .rejected(.noFreePort(id)) }
    return .suggestedPort(port: id, value: candidate)
  }

  private func context(for draft: SettingsPortDraft) -> Context {
    Context(
      draft: draft, proposedListen: RuntimeListenFacts(listen: listenSettings(for: draft)),
      runtimeListen: committing.runtimeListenFacts,
      runtimeProcessID: committing.runtimeListenerProcessID)
  }

  private func currentPreview(for draft: SettingsPortDraft) -> Preview? {
    guard let preview, preview.context.draft == draft else { return nil }
    guard preview.context == context(for: draft) else {
      // Queries may run during view rendering. Publish the refresh on a later turn.
      let epoch = generation
      Task { [weak self] in
        guard let self, epoch == generation else { return }
        refreshIfEditing(draft)
      }
      return nil
    }
    return preview
  }

  private func refreshIfEditing(_ draft: SettingsPortDraft) {
    guard preview == nil || preview?.context.draft == draft else { return }
    refresh(draft)
  }

  private static func probe(_ context: Context, using probe: PortOccupancyProbing) async
    -> [SettingsPortID: PortOccupancy]
  {
    await Task.detached(priority: .utility) {
      Dictionary(
        uniqueKeysWithValues: SettingsPortID.allCases.map { id in
          let endpoint = SettingsPortAdapter.endpoint(for: id, group: context.draft.group)
          return (
            id,
            probe.occupancy(
              for: PortOccupancyProbeRequest(endpoint: endpoint, listen: context.proposedListen))
          )
        })
    }.value
  }
}
