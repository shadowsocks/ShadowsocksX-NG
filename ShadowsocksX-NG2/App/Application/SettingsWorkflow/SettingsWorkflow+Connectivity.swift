import Foundation

extension SettingsWorkflow {
  private static let connectivityURLKey = "connectivityTestURL"

  func beginConnectivityURLEditing() -> String {
    let url =
      (connectivityDefaults.object(forKey: Self.connectivityURLKey) as? String)
      .flatMap(ServerConnectivity.validURL) ?? ServerConnectivity.defaultURL
    return url.absoluteString
  }

  func saveConnectivityURL(_ raw: String) async -> Bool {
    guard let url = ServerConnectivity.validURL(raw), startCommit() else { return false }
    defer { finishCommit() }
    connectivityDefaults.set(url.absoluteString, forKey: Self.connectivityURLKey)
    connectivityURLDidChange?(url)
    return true
  }
}
