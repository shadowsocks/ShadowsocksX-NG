import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivitySettingsTests {
  @Test func customURLPersistsWithoutCredentialsOrProxyRuntimeSettingsCommit() async throws {
    let suite = "ConnectivitySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let committer = FakeSettingsCommitter()
    committer.updateError = ProxyListeningStoreError.ioFailure(detail: "must not commit")
    let credentials = UnavailableConnectivityCredentials()
    let workflow = SettingsWorkflow(
      committing: committer, credentials: credentials, connectivityDefaults: defaults)
    var published: [URL] = []
    workflow.connectivityURLDidChange = { published.append($0) }
    let url = "http://example.com/probe?token=public"
    #expect(await workflow.saveConnectivityURL(url))
    #expect(workflow.beginConnectivityURLEditing() == url)
    #expect(committer.committedSettings == ProxyRuntimeSettings())
    #expect(published.map(\.absoluteString) == [url])
    let reopened = SettingsWorkflow(
      committing: committer, credentials: credentials, connectivityDefaults: defaults)
    #expect(reopened.beginConnectivityURLEditing() == url)
  }

  @Test func missingOrInvalidPreferencesUseDefaultURL() throws {
    let suite = "ConnectivitySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let workflow = SettingsWorkflow(
      committing: FakeSettingsCommitter(), credentials: UnavailableConnectivityCredentials(),
      connectivityDefaults: defaults)
    #expect(workflow.beginConnectivityURLEditing() == "http://www.gstatic.com/generate_204")
    for value: Any in [
      42, "", "https://example.com", "http://user:pass@example.com",
      "http://example.com/#fragment", "http://example.com:0",
    ] {
      defaults.set(value, forKey: "connectivityTestURL")
      #expect(workflow.beginConnectivityURLEditing() == "http://www.gstatic.com/generate_204")
    }
  }

  @Test func invalidSaveKeepsPreviousURLAndDefaultCanBeRestored() async throws {
    let suite = "ConnectivitySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let workflow = SettingsWorkflow(
      committing: FakeSettingsCommitter(), credentials: UnavailableConnectivityCredentials(),
      connectivityDefaults: defaults)
    var published: [URL] = []
    workflow.connectivityURLDidChange = { published.append($0) }
    #expect(await workflow.saveConnectivityURL("  http://example.com/probe?token=public \n"))
    #expect(await !workflow.saveConnectivityURL("https://example.com"))
    #expect(workflow.beginConnectivityURLEditing() == "http://example.com/probe?token=public")
    #expect(published.count == 1)
    #expect(await workflow.saveConnectivityURL("http://www.gstatic.com/generate_204"))
    #expect(workflow.beginConnectivityURLEditing() == "http://www.gstatic.com/generate_204")
    #expect(published.count == 2)
  }

  @Test func oldCredentialReferenceIsIgnoredWithoutAccessingKeychain() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("proxy-listening.json")
    try Data(
      #"{"connectivityURLReference":{"obsolete":true},"preferredMode":"global"}"#.utf8
    ).write(to: file)
    let store = ProxyListeningFileStore(fileURL: file)
    let settings = try store.load()
    #expect(settings == ProxyListeningConfiguration())
    try store.save(settings)
    #expect(try !String(contentsOf: file, encoding: .utf8).contains("connectivityURLReference"))
    let suite = "ConnectivitySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let committer = FakeSettingsCommitter()
    committer.committedSettings.listen = settings
    let workflow = SettingsWorkflow(
      committing: committer, credentials: UnavailableConnectivityCredentials(),
      connectivityDefaults: defaults)
    #expect(workflow.beginConnectivityURLEditing() == "http://www.gstatic.com/generate_204")
  }
}

private struct UnavailableConnectivityCredentials: CredentialStoring {
  func save(_ secret: String, for reference: CredentialReference) throws {
    Issue.record("Test URL must not write credentials")
    throw CredentialStoreError.secretNotUTF8
  }

  func secret(for reference: CredentialReference) throws -> String? {
    Issue.record("Test URL must not read credentials")
    throw CredentialStoreError.secretNotUTF8
  }

  func delete(_ reference: CredentialReference) throws {
    Issue.record("Test URL must not delete credentials")
    throw CredentialStoreError.secretNotUTF8
  }
}
