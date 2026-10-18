import Combine
import Foundation

/// Settings item editors read the committed snapshot and submit one item at a time.
/// The module exposes validation, occupancy facts, shared commit state, and typed
/// commands; editor-local drafts and presentation state remain in the UI.
///
/// Proxy setting writes use `SettingsCommitting`; the independent test URL
/// preference uses UserDefaults. Runtime convergence stays behind the commit seam.
@MainActor
final class SettingsWorkflow: ObservableObject {
  let listenerOccupancy: ListenerOccupancy
  private var occupancyChanges: AnyCancellable?

  /// Shared gate that prevents concurrent saves across setting items.
  @Published private(set) var isCommitting = false
  /// Typed persistence failure for the editor to present.
  @Published private(set) var lastFailure: SettingsWorkflowFailure?

  var connectivityURLDidChange: ((URL) -> Void)?

  let committing: SettingsCommitting
  let credentials: CredentialStoring
  let connectivityDefaults: UserDefaults

  init(
    committing: SettingsCommitting,
    occupancyProbe: PortOccupancyProbing = SystemPortOccupancyProbe(),
    credentials: CredentialStoring = KeychainCredentialStore(),
    connectivityDefaults: UserDefaults = .standard
  ) {
    self.committing = committing
    self.credentials = credentials
    self.connectivityDefaults = connectivityDefaults
    listenerOccupancy = ListenerOccupancy(committing: committing, probe: occupancyProbe)
    occupancyChanges = listenerOccupancy.objectWillChange.sink { [weak self] in
      self?.objectWillChange.send()
    }
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
    listenerOccupancy.reset()
    return committedPortDraft
  }

  /// Field state uses the editor group and its proposed listening mode.
  func portFieldState(
    for id: SettingsPortID, editorDraft: SettingsPortDraft
  ) -> SettingsPortFieldState {
    let facts = listenerOccupancy.fieldFacts(for: id, draft: editorDraft)
    let exception = facts.isRuntimeException
    let occupancy = facts.occupancy
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
    listenerOccupancy.refresh(editorDraft)
  }

  /// Invalid ports and known external occupancy block the save. Unknown
  /// occupancy remains advisory, and probing must finish for this exact draft.
  func canSavePortSettings(_ editorDraft: SettingsPortDraft) -> Bool {
    listenSettings(for: editorDraft).portValidationErrors().isEmpty
      && listenerOccupancy.canSave(editorDraft)
      && !isCommitting
  }

  /// Return an available port candidate for the editor to apply. This command
  /// never persists the candidate.
  @discardableResult
  func suggestFreePort(
    for id: SettingsPortID, from editorDraft: SettingsPortDraft
  ) async -> SettingsCommandOutcome {
    guard !isCommitting else { return .rejected(.inProgress) }
    return await listenerOccupancy.suggestFreePort(for: id, draft: editorDraft)
  }

  /// Save the SOCKS5 and HTTP ports as one item. Validity is enforced at the
  /// store seam; this command only maps a store rejection back to field issues.
  @discardableResult
  func savePortSettings(_ editorDraft: SettingsPortDraft) async -> SettingsCommandOutcome {
    guard !isCommitting else { return .rejected(.inProgress) }
    guard editorDraft.group == .local else { return .rejected(.superseded) }
    if let rejection = listenerOccupancy.cachedSaveRejection(for: editorDraft) {
      return .rejected(rejection)
    }

    var proposed = committing.committedSettings
    proposed.listen.socksPort = editorDraft.socksPort
    proposed.listen.httpPort = editorDraft.httpPort
    return await commitPortSettings(proposed, fieldGroup: editorDraft.group)
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
      return commitFailure(for: error)
    }
  }

  func listenSettings(for editorDraft: SettingsPortDraft) -> SslocalListenSettings {
    listenerOccupancy.listenSettings(for: editorDraft)
  }

  private func portIssues(for editorDraft: SettingsPortDraft) -> [SettingsFieldIssue] {
    let errors = listenSettings(for: editorDraft).portValidationErrors()
    return SettingsPortAdapter.fieldIssues(from: errors, group: editorDraft.group)
  }

  func startCommit() -> Bool {
    guard !isCommitting else { return false }
    isCommitting = true
    lastFailure = nil
    return true
  }

  func finishCommit() { isCommitting = false }

  func commitPortSettings(
    _ proposed: ProxySettings, fieldGroup: SettingsListeningGroup? = nil
  ) async -> SettingsCommandOutcome {
    guard startCommit() else { return .rejected(.inProgress) }
    defer { finishCommit() }
    return await persistSettings(proposed, fieldGroup: fieldGroup)
  }

  /// 调用方持有共享提交锁；持久化结果与运行状态分别报告。
  /// store 的 `.invalid` 按编辑组归位成字段 issue；其余失败保持持久化形状。
  func persistSettings(
    _ proposed: ProxySettings, fieldGroup: SettingsListeningGroup? = nil
  ) async -> SettingsCommandOutcome {
    do {
      try await committing.updateSettings(proposed)
      lastFailure = nil
      return .persisted
    } catch {
      if let fieldGroup,
        let error = error as? ProxySettingsStoreError,
        case .invalid(let portErrors) = error
      {
        return .rejected(
          .validation(SettingsPortAdapter.fieldIssues(from: portErrors, group: fieldGroup)))
      }
      return commitFailure(for: error)
    }
  }

  private func commitFailure(for error: Error) -> SettingsCommandOutcome {
    let failure = Self.workflowFailure(for: error)
    lastFailure = failure
    return .commitFailed(failure)
  }

  private static func workflowFailure(for error: Error) -> SettingsWorkflowFailure {
    if let error = error as? ProxySettingsStoreError {
      return .store(error)
    }
    return .unknown
  }
}
