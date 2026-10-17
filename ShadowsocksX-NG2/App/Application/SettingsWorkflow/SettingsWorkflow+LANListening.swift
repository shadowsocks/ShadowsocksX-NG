import Foundation

extension SettingsWorkflow {
  var committedLANListening: LANListeningSettings { committing.committedSettings.listen.lan }

  func beginLANListeningEditing() throws -> LANListeningDraft {
    let lan = committedLANListening
    let password: String
    if let raw = lan.passwordReference {
      guard let saved = try credentials.secret(for: CredentialReference(rawValue: raw)) else {
        throw ProxySettingsStoreError.credentialFailure(detail: String(localized: "局域网身份验证密码不可读"))
      }
      password = saved
    } else {
      let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
      password = String((0..<10).map { _ in alphabet[Int.random(in: alphabet.indices)] })
    }
    listenerOccupancy.reset()
    return LANListeningDraft(
      ports: SettingsPortDraft(
        socksPort: lan.socksPort, httpPort: lan.httpPort,
        group: .lan, listenerMode: lan.mode, isEnabled: lan.isEnabled),
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
      return .commitFailed(.store(.credentialFailure(detail: String(localized: "用户名或密码无效"))))
    }
    let base = committing.committedSettings
    var proposed = base
    proposed.listen = listenSettings(for: draft.ports)
    let errors = proposed.validationErrors
    guard errors.isEmpty else {
      return .rejected(.validation(SettingsPortAdapter.fieldIssues(from: errors, group: .lan)))
    }
    if let rejection = await listenerOccupancy.recheck(draft.ports) { return .rejected(rejection) }
    guard base == committing.committedSettings else {
      listenerOccupancy.refresh(draft.ports)
      return .rejected(.superseded)
    }
    proposed.listen.lan.udpRelayEnabled = draft.udpRelayEnabled
    proposed.listen.lan.authenticationEnabled = draft.authenticationEnabled
    proposed.listen.lan.username = draft.username
    return await saveLANCredentials(
      proposed, password: draft.password,
      oldReference: base.listen.lan.passwordReference)
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
        return .commitFailed(
          .store(.credentialFailure(detail: String(localized: "局域网身份验证密码不可读"))))
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
        return .commitFailed(.store(.credentialFailure(detail: String(localized: "凭据回滚失败"))))
      }
      return outcome
    } catch {
      let rollback = journal.rollback()
      return .commitFailed(
        .store(
          .credentialFailure(
            detail: rollback.isPartial ? String(localized: "凭据回滚失败") : String(localized: "凭据保存失败")))
      )
    }
  }

}

extension CredentialRollbackOutcome {
  fileprivate var isPartial: Bool {
    if case .partial = self { return true }
    return false
  }
}
