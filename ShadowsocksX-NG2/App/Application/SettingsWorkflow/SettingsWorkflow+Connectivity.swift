import Foundation

extension SettingsWorkflow {
  func beginConnectivityURLEditing() throws -> String {
    guard let reference = committing.committedSettings.connectivityURLReference else {
      return ServerConnectivity.defaultURL.absoluteString
    }
    guard let secret = try credentials.secret(for: reference),
      ServerConnectivity.validURL(secret) != nil
    else {
      throw ServerFormLoadError.credentialsUnavailable
    }
    return secret
  }

  /// Each custom URL gets a fresh secret; failed preference saves roll it back.
  func saveConnectivityURL(_ raw: String) async -> Bool {
    guard let url = ServerConnectivity.validURL(raw), startCommit() else { return false }
    defer { finishCommit() }
    let previous = committing.committedSettings.connectivityURLReference
    let reference: CredentialReference? = url == ServerConnectivity.defaultURL ? nil : .fresh()
    do {
      if let reference { try credentials.save(url.absoluteString, for: reference) }
      var proposed = committing.committedSettings
      proposed.connectivityURLReference = reference
      let outcome = await persistSettings(proposed)
      guard outcome == .persisted else {
        if let reference { try? credentials.delete(reference) }
        return false
      }
      connectivityURLDidChange?(url)
      if let previous { try? credentials.delete(previous) }
      return true
    } catch {
      if let reference { try? credentials.delete(reference) }
      return false
    }
  }
}
