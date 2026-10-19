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
    let workflow = SettingsWorkflow(
      committing: committer, connectivityDefaults: defaults)
    var published: [URL] = []
    workflow.connectivityURLDidChange = { published.append($0) }
    let url = "http://example.com/probe?token=public"
    #expect(await workflow.saveConnectivityURL(url))
    #expect(workflow.beginConnectivityURLEditing() == url)
    #expect(committer.committedSettings == ProxyRuntimeSettings())
    #expect(published.map(\.absoluteString) == [url])
    let reopened = SettingsWorkflow(
      committing: committer, connectivityDefaults: defaults)
    #expect(reopened.beginConnectivityURLEditing() == url)
  }

  @Test func missingOrInvalidPreferencesUseDefaultURL() throws {
    let suite = "ConnectivitySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let workflow = SettingsWorkflow(
      committing: FakeSettingsCommitter(),
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
      committing: FakeSettingsCommitter(),
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

  @Test func testURLIgnoresHistoricalCredentialReference() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("proxy-listening.json")
    let original = Data(#"{"connectivityURLReference":{"obsolete":true}}"#.utf8)
    try original.write(to: file)
    let suite = "ConnectivitySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let committer = FakeSettingsCommitter()
    let workflow = SettingsWorkflow(
      committing: committer,
      connectivityDefaults: defaults)
    #expect(workflow.beginConnectivityURLEditing() == "http://www.gstatic.com/generate_204")
    #expect(try Data(contentsOf: file) == original)
  }
}
