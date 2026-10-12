import Foundation

extension SettingsWorkflow {
  var committedLANListening: LANListeningSettings { committing.committedSettings.listen.lan }

  func beginLANListeningEditing() throws -> LANListeningDraft {
    let lan = committedLANListening
    let password: String
    if let raw = lan.passwordReference {
      guard let saved = try credentials.secret(for: CredentialReference(rawValue: raw)) else {
        throw ProxySettingsStoreError.credentialFailure(detail: "局域网身份验证密码不可读")
      }
      password = saved
    } else {
      let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
      password = String((0..<10).map { _ in alphabet[Int.random(in: alphabet.indices)] })
    }
    return LANListeningDraft(
      ports: SettingsPortDraft(
        socksPort: lan.socksPort, httpPort: lan.httpPort,
        group: .lan, listenerMode: lan.mode),
      udpRelayEnabled: lan.udpRelayEnabled, authenticationEnabled: lan.authenticationEnabled,
      username: lan.username, password: password)
  }

  func canSaveLANListening(_ draft: LANListeningDraft) -> Bool {
    RuntimeListenerAuthentication.validUsername(draft.username)
      && RuntimeListenerAuthentication.validPassword(draft.password)
      && canSavePortSettings(draft.ports)
  }

  @discardableResult
  func saveLANListening(_ draft: LANListeningDraft) async -> SettingsCommandOutcome {
    guard startCommit() else { return .rejected(.inProgress) }
    defer { finishCommit() }
    guard draft.ports.group == .lan else { return .rejected(.superseded) }
    guard RuntimeListenerAuthentication.validUsername(draft.username),
      RuntimeListenerAuthentication.validPassword(draft.password)
    else {
      return .persistenceFailed(.store(.credentialFailure(detail: "用户名或密码无效")))
    }
    let base = committing.committedSettings
    var proposed = base
    proposed.listen = listenSettings(for: draft.ports)
    let errors = proposed.validationErrors
    guard errors.isEmpty else {
      return .rejected(.validation(SettingsPortAdapter.fieldIssues(from: errors)))
    }
    if let rejection = await probeLAN(draft, base: base) { return .rejected(rejection) }
    proposed.listen.lan.udpRelayEnabled = draft.udpRelayEnabled
    proposed.listen.lan.authenticationEnabled = draft.authenticationEnabled
    proposed.listen.lan.username = draft.username
    return await saveLANCredentials(
      proposed, password: draft.password,
      oldReference: base.listen.lan.passwordReference)
  }

  private func probeLAN(_ draft: LANListeningDraft, base: ProxySettings) async
    -> SettingsCommandRejection?
  {
    guard draft.mode != .disabled else { return nil }
    let facts = probeFacts(for: draft.ports)
    let runtime = committing.runtimeListenFacts.map { focusedFacts($0, group: .lan) }
    let processID = committing.runtimeListenerProcessID
    let probe = occupancyProbe
    let results = await Task.detached(priority: .utility) {
      Dictionary(
        uniqueKeysWithValues: SettingsPortID.allCases.map { id in
          (
            id,
            probe.occupancy(
              for: PortOccupancyProbeRequest(
                endpoint: SettingsPortAdapter.endpoint(for: id), listen: facts))
          )
        })
    }.value
    guard base == committing.committedSettings,
      processID == committing.runtimeListenerProcessID,
      runtime == committing.runtimeListenFacts.map({ focusedFacts($0, group: .lan) })
    else { return .superseded }
    let blocked = ListenerModeOccupancyGate.blockedPortIDs(
      results: results,
      context: ListenerModeOccupancyContext(
        listenerMode: draft.mode, proposedListen: facts,
        runtimeListen: runtime, runtimeProcessID: processID))
    return blocked.isEmpty ? nil : .occupied(blocked)
  }

  private func saveLANCredentials(
    _ settings: ProxySettings, password: String,
    oldReference: String?
  ) async -> SettingsCommandOutcome {
    var proposed = settings
    if let old = oldReference {
      do {
        if try credentials.secret(for: CredentialReference(rawValue: old)) == password {
          return await persistSettings(proposed)
        }
      } catch {
        return .persistenceFailed(.store(.credentialFailure(detail: "局域网身份验证密码不可读")))
      }
    }
    let reference = CredentialReference.fresh()
    var journal = CredentialWriteJournal(credentials: credentials)
    do {
      try journal.save(password, for: reference)
      proposed.listen.lan.passwordReference = reference.rawValue
      let outcome = await persistSettings(proposed)
      if case .persisted = outcome {
        if let old = oldReference {
          try? credentials.delete(CredentialReference(rawValue: old))
        }
        return outcome
      }
      if case .partial = journal.rollback() {
        return .persistenceFailed(.store(.credentialFailure(detail: "凭据回滚失败")))
      }
      return outcome
    } catch {
      let rollback = journal.rollback()
      return .persistenceFailed(
        .store(
          .credentialFailure(
            detail: rollback.isPartial ? "凭据回滚失败" : "凭据保存失败")))
    }
  }

  func focusedFacts(_ facts: RuntimeListenFacts, group: SettingsListeningGroup)
    -> RuntimeListenFacts
  {
    if group == .local {
      return RuntimeListenFacts(
        listenerMode: .disabled, socksPort: facts.socksPort,
        httpPort: facts.httpPort)
    }
    return RuntimeListenFacts(
      listenerMode: facts.lan.mode, socksPort: facts.lan.socksPort,
      httpPort: facts.lan.httpPort)
  }

  func probeFacts(for draft: SettingsPortDraft) -> RuntimeListenFacts {
    focusedFacts(RuntimeListenFacts(listen: listenSettings(for: draft)), group: draft.group)
  }

}

extension CredentialRollbackOutcome {
  fileprivate var isPartial: Bool {
    if case .partial = self { return true }
    return false
  }
}
