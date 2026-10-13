import Foundation

/// Settings item editors read the committed snapshot and submit one item at a time.
/// The module exposes validation, occupancy facts, shared commit state, and typed
/// commands; editor-local drafts and presentation state remain in the UI.
///
/// Writes depend on the narrow `SettingsCommitting` seam. The module does not
/// depend on SwiftUI, persistence formats, or runtime convergence details.
@MainActor
final class SettingsWorkflow: ObservableObject {
  /// Occupancy facts for the current port editor draft. They are advisory; the
  /// authoritative bind check still belongs to runtime startup.
  @Published private var portEditorOccupancyByPort: [SettingsPortID: SettingsPortOccupancy] = [:]
  private var portEditorProbeResults: [SettingsPortID: PortOccupancy] = [:]
  private var portEditorOccupancyDraft: SettingsPortDraft?
  private var portEditorOccupancyGeneration = 0

  /// Shared gate that prevents concurrent saves across setting items.
  @Published private(set) var isCommitting = false
  /// Typed persistence failure for the editor to present.
  @Published private(set) var lastFailure: SettingsWorkflowFailure?

  let committing: SettingsCommitting
  let credentials: CredentialStoring
  let occupancyProbe: PortOccupancyProbing

  init(
    committing: SettingsCommitting,
    occupancyProbe: PortOccupancyProbing = SystemPortOccupancyProbe(),
    credentials: CredentialStoring = KeychainCredentialStore()
  ) {
    self.committing = committing
    self.occupancyProbe = occupancyProbe
    self.credentials = credentials
  }

  /// Current committed port pair; editors start from this snapshot.
  var committedPortDraft: SettingsPortDraft {
    let listen = committing.committedSettings.listen
    return SettingsPortDraft(socksPort: listen.socksPort, httpPort: listen.httpPort)
  }

  var committedProxyExceptionCount: Int {
    committing.committedSettings.proxyExceptionList.count
  }

  func beginProxyExceptionsEditing() -> String {
    lastFailure = nil
    return committing.committedSettings.proxyExceptions
  }

  /// Start a port editor from committed values and discard prior probe facts.
  func beginPortSettingsEditing() -> SettingsPortDraft {
    lastFailure = nil
    portEditorOccupancyGeneration += 1
    portEditorOccupancyDraft = nil
    portEditorOccupancyByPort = [:]
    portEditorProbeResults = [:]
    return committedPortDraft
  }

  /// Field state uses the editor group and its proposed listening mode.
  func portFieldState(
    for id: SettingsPortID, editorDraft: SettingsPortDraft
  ) -> SettingsPortFieldState {
    let exception = isRuntimePortException(for: id, editorDraft: editorDraft)
    let occupancy =
      portEditorOccupancyDraft == editorDraft
      ? portEditorOccupancyByPort[id] : nil
    let issues = portIssues(for: editorDraft).filter { $0.field == .port(id) }
    let canSuggest: Bool
    if case .occupied? = occupancy {
      canSuggest = !exception
    } else {
      canSuggest = false
    }
    return SettingsPortFieldState(
      id: id,
      draftValue: editorDraft.portValue(for: id),
      occupancy: occupancy,
      issues: issues,
      isRuntimePortException: exception,
      canSuggestFreePort: canSuggest)
  }

  /// Refresh port occupancy facts. Results from an older editor draft are ignored.
  func refreshPortEditorOccupancy(for editorDraft: SettingsPortDraft) {
    portEditorOccupancyGeneration += 1
    let generation = portEditorOccupancyGeneration
    portEditorOccupancyDraft = editorDraft
    portEditorOccupancyByPort = [:]
    portEditorProbeResults = [:]
    let facts = probeFacts(for: editorDraft)
    if editorDraft.group == .lan && editorDraft.listenerMode == .disabled {
      portEditorOccupancyByPort = [.socks: .free, .http: .free]
      return
    }
    let probe = occupancyProbe
    Task { @MainActor in
      let result = await Task.detached(priority: .utility) {
        Dictionary(
          uniqueKeysWithValues: SettingsPortID.allCases.map { id in
            let endpoint = SettingsPortAdapter.endpoint(for: id, group: editorDraft.group)
            let request = PortOccupancyProbeRequest(endpoint: endpoint, listen: facts)
            return (id, probe.occupancy(for: request))
          })
      }.value
      guard generation == portEditorOccupancyGeneration,
        portEditorOccupancyDraft == editorDraft
      else { return }
      portEditorProbeResults = result
      portEditorOccupancyByPort = result.mapValues(SettingsPortOccupancy.init)
    }
  }

  /// Invalid ports and known external occupancy block the save. Unknown
  /// occupancy remains advisory, and probing must finish for this exact draft.
  func canSavePortSettings(_ editorDraft: SettingsPortDraft) -> Bool {
    listenSettings(for: editorDraft).portValidationErrors().isEmpty
      && hasCurrentPortEditorOccupancy(for: editorDraft)
      && blockingPortIDs(for: editorDraft).isEmpty
      && !isCommitting
  }

  /// Return an available port candidate for the editor to apply. This command
  /// never persists the candidate.
  @discardableResult
  func suggestFreePort(
    for id: SettingsPortID, from editorDraft: SettingsPortDraft
  ) async -> SettingsCommandOutcome {
    guard !isCommitting else { return .rejected(.inProgress) }
    let listen = listenSettings(for: editorDraft)
    let facts = probeFacts(for: editorDraft)
    let endpoint = SettingsPortAdapter.endpoint(for: id, group: editorDraft.group)
    let generation = portEditorOccupancyGeneration
    let probe = occupancyProbe
    let candidate = await Task.detached(priority: .utility) {
      PortSuggestion.firstFree(excluding: Set(listen.configuredPorts)) { port in
        let request = PortOccupancyProbeRequest(
          endpoint: endpoint, listen: facts.replacingPort(port, for: endpoint), port: port)
        if case .free = probe.occupancy(for: request) { return true }
        return false
      }
    }.value
    guard generation == portEditorOccupancyGeneration,
      portEditorOccupancyDraft == editorDraft
    else {
      return .rejected(.superseded)
    }
    guard let candidate else {
      return .rejected(.noFreePort(id))
    }
    return .suggestedPort(port: id, value: candidate)
  }

  /// Save the SOCKS5 and HTTP ports as one item.
  @discardableResult
  func savePortSettings(_ editorDraft: SettingsPortDraft) async -> SettingsCommandOutcome {
    guard !isCommitting else { return .rejected(.inProgress) }
    guard editorDraft.group == .local else { return .rejected(.superseded) }
    let errors = listenSettings(for: editorDraft).portValidationErrors()
      .map(ProxySettingsValidationError.init)
    guard errors.isEmpty else {
      return .rejected(
        .validation(SettingsPortAdapter.fieldIssues(from: errors, group: editorDraft.group)))
    }
    guard hasCurrentPortEditorOccupancy(for: editorDraft) else {
      return .rejected(.inProgress)
    }
    let blockedPorts = blockingPortIDs(for: editorDraft)
    guard blockedPorts.isEmpty else {
      return .rejected(.occupied(blockedPorts))
    }

    var proposed = committing.committedSettings
    proposed.listen.socksPort = editorDraft.socksPort
    proposed.listen.httpPort = editorDraft.httpPort
    return await commitPortSettings(proposed)
  }

  /// Save only user-added system-proxy exceptions.
  @discardableResult
  func saveProxyExceptions(_ rawValue: String) async -> SettingsCommandOutcome {
    guard !isCommitting else { return .rejected(.inProgress) }
    let value =
      rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rawValue
    guard value != committing.committedSettings.proxyExceptions else {
      lastFailure = nil
      return .persisted
    }

    var proposed = committing.committedSettings
    proposed.proxyExceptions = value
    isCommitting = true
    lastFailure = nil
    do {
      try await committing.updateSettings(proposed)
      isCommitting = false
      lastFailure = nil
      return .persisted
    } catch {
      isCommitting = false
      lastFailure = Self.workflowFailure(for: error)
      return .persistenceFailed(Self.persistenceFailure(for: error))
    }
  }

  func listenSettings(for editorDraft: SettingsPortDraft) -> SslocalListenSettings {
    var listen = committing.committedSettings.listen
    if editorDraft.group == .local {
      listen.socksPort = editorDraft.socksPort
      listen.httpPort = editorDraft.httpPort
    } else {
      listen.lan.socksPort = editorDraft.socksPort
      listen.lan.httpPort = editorDraft.httpPort
      listen.lan.mode = editorDraft.listenerMode
    }
    return listen
  }

  private func portIssues(for editorDraft: SettingsPortDraft) -> [SettingsFieldIssue] {
    let errors = listenSettings(for: editorDraft).portValidationErrors()
      .map(ProxySettingsValidationError.init)
    return SettingsPortAdapter.fieldIssues(from: errors, group: editorDraft.group)
  }

  private func occupancyContext(for draft: SettingsPortDraft) -> ListenerModeOccupancyContext {
    ListenerModeOccupancyContext(
      group: draft.group,
      proposedListen: probeFacts(for: draft),
      runtimeListen: committing.runtimeListenFacts,
      runtimeProcessID: committing.runtimeListenerProcessID)
  }

  private func isRuntimePortException(for id: SettingsPortID, editorDraft: SettingsPortDraft)
    -> Bool
  {
    guard portEditorOccupancyDraft == editorDraft,
      case .occupied? = portEditorProbeResults[id]
    else { return false }
    return !ListenerModeOccupancyGate.blockedPortIDs(
      results: portEditorProbeResults,
      context: occupancyContext(for: editorDraft)
    ).contains(id)
  }

  private func blockingPortIDs(for editorDraft: SettingsPortDraft) -> [SettingsPortID] {
    ListenerModeOccupancyGate.blockedPortIDs(
      results: portEditorProbeResults,
      context: occupancyContext(for: editorDraft))
  }

  private func hasCurrentPortEditorOccupancy(for editorDraft: SettingsPortDraft) -> Bool {
    portEditorOccupancyDraft == editorDraft
      && portEditorOccupancyByPort.count == SettingsPortID.allCases.count
  }

  func startCommit() -> Bool {
    guard !isCommitting else { return false }
    isCommitting = true
    lastFailure = nil
    return true
  }

  func finishCommit() { isCommitting = false }

  func commitPortSettings(_ proposed: ProxySettings) async -> SettingsCommandOutcome {
    guard startCommit() else { return .rejected(.inProgress) }
    defer { finishCommit() }
    return await persistSettings(proposed)
  }

  /// 调用方持有共享提交锁；持久化结果与运行状态分别报告。
  func persistSettings(_ proposed: ProxySettings) async -> SettingsCommandOutcome {
    do {
      try await committing.updateSettings(proposed)
      lastFailure = nil
      return .persisted
    } catch {
      lastFailure = Self.workflowFailure(for: error)
      return .persistenceFailed(Self.persistenceFailure(for: error))
    }
  }

  private static func persistenceFailure(for error: Error) -> SettingsPersistenceFailure {
    if let error = error as? ProxySettingsStoreError {
      return .store(error)
    }
    return .unknown
  }

  private static func workflowFailure(for error: Error) -> SettingsWorkflowFailure {
    if let error = error as? ProxySettingsStoreError {
      return .store(error)
    }
    return .unknown
  }
}
