import Foundation

extension SettingsWorkflow {
  var committedLANListening: LANListeningFacts {
    LANListeningFacts(committing.committedSettings.listen.lan)
  }

  func beginLANListeningEditing() -> LANListeningDraft {
    let lan = committing.committedSettings.listen.lan
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    let password =
      lan.password ?? String((0..<10).map { _ in alphabet[Int.random(in: alphabet.indices)] })
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
    proposed.lan.password = draft.password
    return await persistListening(proposed, fieldGroup: .lan)
  }
}
