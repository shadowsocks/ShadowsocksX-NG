import Foundation

extension SettingsWorkflow {
  var committedLANListening: LANListeningSettings { committing.committedSettings.listen.lan }

  func beginLANListeningEditing() throws -> LANListeningDraft {
    let lan = committedLANListening
    let password: String
    if let raw = lan.passwordReference {
      guard let saved = try credentials.secret(for: CredentialReference(rawValue: raw)) else {
        throw ProxyListeningStoreError.credentialFailure(detail: String(localized: "局域网身份验证密码不可读"))
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

  /// 凭据形状只是身份验证启用时的保存约束；关闭时凭据是保留值（字段禁用），
  /// 不拦本次保存。整快照端口门禁仍由 `canSavePortSettings` 承担（跨组互异）。
  func canSaveLANListening(_ draft: LANListeningDraft) -> Bool {
    let credentialsSatisfySave =
      !draft.authenticationEnabled
      || (RuntimeListenerAuthentication.validUsername(draft.username)
        && RuntimeListenerAuthentication.validPassword(draft.password))
    return credentialsSatisfySave && canSavePortSettings(draft.ports)
  }

  @discardableResult
  func saveLANListening(_ draft: LANListeningDraft) async -> SettingsCommandOutcome {
    guard startCommit() else { return .rejected(.inProgress) }
    defer { finishCommit() }
    guard draft.ports.group == .lan else { return .rejected(.superseded) }
    let base = committing.committedSettings.listen
    var proposed = listenSettings(for: draft.ports)
    if let rejection = await listenerOccupancy.recheck(draft.ports) { return .rejected(rejection) }
    guard base == committing.committedSettings.listen else {
      listenerOccupancy.refresh(draft.ports)
      return .rejected(.superseded)
    }
    proposed.lan.udpRelayEnabled = draft.udpRelayEnabled
    proposed.lan.authenticationEnabled = draft.authenticationEnabled
    proposed.lan.username = draft.username
    return await saveLANCredentials(
      proposed, password: draft.password,
      oldReference: base.lan.passwordReference)
  }

  private func saveLANCredentials(
    _ settings: ProxyListeningConfiguration, password: String,
    oldReference: String?
  ) async -> SettingsCommandOutcome {
    var proposed = settings
    if let old = oldReference {
      do {
        if try credentials.secret(for: CredentialReference(rawValue: old)) == password {
          return await persistListening(proposed, fieldGroup: .lan)
        }
      } catch {
        return .commitFailed(
          .store(.credentialFailure(detail: String(localized: "局域网身份验证密码不可读"))))
      }
    }
    // 身份验证启用时，新写入 keychain 的秘密必须可直接用于运行时认证文件。
    if proposed.lan.authenticationEnabled,
      !RuntimeListenerAuthentication.validPassword(password)
        || !RuntimeListenerAuthentication.validUsername(proposed.lan.username)
    {
      return .commitFailed(
        .store(.credentialFailure(detail: String(localized: "用户名或密码无效"))))
    }
    let reference = CredentialReference.fresh()
    var journal = CredentialWriteJournal(credentials: credentials)
    do {
      try journal.save(password, for: reference)
      proposed.lan.passwordReference = reference.rawValue
      let outcome = await persistListening(proposed, fieldGroup: .lan)
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
