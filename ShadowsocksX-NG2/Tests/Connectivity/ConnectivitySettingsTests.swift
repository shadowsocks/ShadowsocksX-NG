import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivitySettingsTests {
  @Test func customURLIsSecretAndFailureDoesNotPublishOrChangeSavedURL() async throws {
    let committer = FakeSettingsCommitter()
    let credentials = InMemoryCredentialStore()
    let workflow = SettingsWorkflow(committing: committer, credentials: credentials)
    var published = 0
    workflow.connectivityURLDidChange = { _ in published += 1 }
    let secretURL = "http://example.com/probe?token=private"
    #expect(await workflow.saveConnectivityURL(secretURL))
    #expect(try workflow.beginConnectivityURLEditing() == secretURL)
    #expect(credentials.storageCount == 1)
    let saved = committer.committedSettings
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = directory.appendingPathComponent("settings.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProxySettingsFileStore(fileURL: file)
    try store.save(saved)
    #expect(try store.load() == saved)
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(!text.contains("private"))
    #expect(!text.contains("example.com"))
    committer.updateError = ProxySettingsStoreError.ioFailure(detail: "fixture")
    #expect(await !workflow.saveConnectivityURL("http://example.com/new"))
    #expect(committer.committedSettings == saved)
    #expect(credentials.storageCount == 1)
    #expect(published == 1)
    #expect(try workflow.beginConnectivityURLEditing() == secretURL)
    committer.updateError = nil
    #expect(await workflow.saveConnectivityURL(ServerConnectivity.defaultURL.absoluteString))
    #expect(committer.committedSettings.connectivityURLReference == nil)
    #expect(credentials.storageCount == 0)
  }
  @Test func previouslySavedHTTPSURLCanBeOpenedAndReplacedWithHTTP() async throws {
    let committer = FakeSettingsCommitter()
    let credentials = InMemoryCredentialStore()
    let reference = CredentialReference.fresh()
    try credentials.save("https://example.com/old?token=private", for: reference)
    committer.committedSettings.connectivityURLReference = reference
    let workflow = SettingsWorkflow(committing: committer, credentials: credentials)
    #expect(try workflow.beginConnectivityURLEditing() == "https://example.com/old?token=private")
    #expect(await !workflow.saveConnectivityURL("https://example.com/new"))
    #expect(await workflow.saveConnectivityURL("http://example.com/new"))
    #expect(try workflow.beginConnectivityURLEditing() == "http://example.com/new")
    #expect(try credentials.secret(for: reference) == nil)
  }

}
