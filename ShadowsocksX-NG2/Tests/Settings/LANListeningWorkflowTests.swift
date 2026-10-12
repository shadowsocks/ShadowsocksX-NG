import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct LANListeningWorkflowTests {
  @Test func savingDisabledLANKeepsLocalPortsAndSkipsOccupancy() async throws {
    let committing = FakeSettingsCommitter()
    committing.committedSettings.listen.socksPort = 13001
    let probe = FakeOccupancyProbe(occupiedPorts: [11088, 11089])
    let credentials = InMemoryCredentialStore()
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe,
      credentials: credentials)
    let draft = try workflow.beginLANListeningEditing()
    #expect(draft.password.count == 10)
    #expect(await workflow.saveLANListening(draft) == .persisted)
    #expect(committing.committedSettings.listen.socksPort == 13001)
    #expect(probe.callCount == 0)
    let reopened = try workflow.beginLANListeningEditing()
    #expect(reopened.password == draft.password)
  }

  @Test func editingOneLocalPortPermitsTheOtherRuntimeOwnedPort() async {
    let committing = FakeSettingsCommitter()
    committing.runtimeListenFacts = RuntimeListenFacts(listen: committing.committedSettings.listen)
    committing.runtimeListenerProcessID = 123
    let probe = FakeOccupancyProbe(occupiedPorts: [11087], occupierProcessIDs: [123])
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: probe)
    var draft = workflow.beginPortSettingsEditing()
    draft.socksPort = 13001
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .http, editorDraft: draft).occupancy != nil)
    #expect(await workflow.savePortSettings(draft) == .persisted)
    #expect(committing.committedSettings.listen.socksPort == 13001)
  }

  @Test func persistenceFailurePreservesPasswordAndDeletesTheUncommittedSecret() async throws {
    let committing = FakeSettingsCommitter()
    let credentials = InMemoryCredentialStore()
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: FakeOccupancyProbe(),
      credentials: credentials)
    let original = try workflow.beginLANListeningEditing()
    #expect(await workflow.saveLANListening(original) == .persisted)
    let saved = committing.committedSettings
    var edited = try workflow.beginLANListeningEditing()
    edited.password = "replacement"
    committing.updateError = ProxySettingsStoreError.ioFailure(detail: "disk full")
    #expect(
      await workflow.saveLANListening(edited)
        == .persistenceFailed(.store(.ioFailure(detail: "disk full"))))
    #expect(committing.committedSettings == saved)
    #expect(try workflow.beginLANListeningEditing().password == original.password)
    #expect(credentials.storageCount == 1)
  }

  @Test func savingLANLocksTheEditorBeforeTCPProbing() async throws {
    let committing = FakeSettingsCommitter()
    let probe = GatedOccupancyProbe(gatedAnswer: .free, passThroughAnswer: .free)
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe,
      credentials: InMemoryCredentialStore())
    var draft = try workflow.beginLANListeningEditing()
    draft.mode = .allIPv4Interfaces
    let submission = Task { await workflow.saveLANListening(draft) }
    await waitUntil(probe.entered > 0)
    #expect(workflow.isCommitting)
    #expect(await workflow.saveProxyExceptions("example.com") == .rejected(.inProgress))
    probe.releaseGatedCalls()
    #expect(await submission.value == .persisted)
    #expect(!workflow.isCommitting)
  }
}
