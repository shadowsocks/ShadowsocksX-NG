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

  @Test(arguments: [
    ListenerMode.allIPv4Interfaces, .allIPv4AndIPv6Interfaces, .allIPv6Interfaces,
  ])
  func editorProbesPreserveBothGroupsAndUseLANEndpoints(mode: ListenerMode) async throws {
    let committing = FakeSettingsCommitter()
    let probe = FakeOccupancyProbe()
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe, credentials: InMemoryCredentialStore())
    var draft = try workflow.beginLANListeningEditing()
    draft.mode = mode
    draft.ports.socksPort = 13001
    workflow.refreshPortEditorOccupancy(for: draft.ports)
    await waitUntil(workflow.portFieldState(for: .http, editorDraft: draft.ports).occupancy != nil)

    var expected = RuntimeListenFacts(listen: committing.committedSettings.listen)
    expected.lan.mode = mode
    expected.lan.socksPort = 13001
    #expect(probe.requests.count == 2)
    #expect(probe.requests.map(\.endpoint) == [.lanSocks, .lanHTTP])
    #expect(probe.requests.map(\.port) == [13001, 11089])
    #expect(probe.requests.allSatisfy { $0.listen == expected && $0.listenerMode == mode })
    #expect(probe.requests.allSatisfy { $0.bindAddress == mode.bindAddress })

    #expect(await workflow.saveLANListening(draft) == .persisted)
    #expect(probe.requests.count == 4)
    #expect(Array(probe.requests.suffix(2)).map(\.endpoint) == [.lanSocks, .lanHTTP])
    #expect(probe.requests.allSatisfy { $0.listen == expected })
  }

  @Test func suggestedLANPortKeepsLocalIdentityAndExcludesAllConfiguredPorts() async throws {
    let committing = FakeSettingsCommitter()
    committing.committedSettings.listen.socksPort = 32768
    committing.committedSettings.listen.httpPort = 32769
    let probe = FakeOccupancyProbe(occupiedPorts: [11088])
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe, credentials: InMemoryCredentialStore())
    var draft = try workflow.beginLANListeningEditing()
    draft.mode = .allIPv6Interfaces
    workflow.refreshPortEditorOccupancy(for: draft.ports)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft.ports).occupancy != nil)
    #expect(workflow.portFieldState(for: .socks, editorDraft: draft.ports).canSuggestFreePort)
    #expect(
      await workflow.suggestFreePort(for: .socks, from: draft.ports)
        == .suggestedPort(port: .socks, value: 32770))
    let request = try #require(probe.requests.last)
    #expect(request.endpoint == .lanSocks)
    #expect(request.port == 32770)
    #expect(request.listen.socksPort == 32768)
    #expect(request.listen.httpPort == 32769)
    #expect(request.listen.lan.socksPort == 32770)
    #expect(request.listen.lan.httpPort == 11089)
    #expect(request.listenerMode == .allIPv6Interfaces)
    #expect(committing.updateCalls.isEmpty)
  }

  @Test(arguments: [SettingsListeningGroup.local, .lan])
  func crossGroupDuplicatesOnlyMarkTheEditedField(group: SettingsListeningGroup) async {
    let committing = FakeSettingsCommitter()
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: FakeOccupancyProbe())
    let draft = SettingsPortDraft(
      socksPort: group == .local ? 11089 : 11087,
      httpPort: group == .local ? 11087 : 11089,
      group: group, listenerMode: .allIPv4Interfaces)
    #expect(workflow.portFieldState(for: .socks, editorDraft: draft).issues.count == 1)
    #expect(workflow.portFieldState(for: .http, editorDraft: draft).issues.isEmpty)
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .http, editorDraft: draft).occupancy != nil)
    #expect(!workflow.canSavePortSettings(draft))
  }

  @Test func ownLANPortExceptionUsesLANRuntimePortAndMode() async throws {
    let committing = FakeSettingsCommitter()
    committing.committedSettings.listen.lan.mode = .allIPv4AndIPv6Interfaces
    committing.runtimeListenFacts = RuntimeListenFacts(listen: committing.committedSettings.listen)
    committing.runtimeListenerProcessID = 123
    let probe = FakeOccupancyProbe(
      occupiedPorts: [11088], occupierIPv6ProcessIDs: [123], occupiedFamilies: [.ipv4])
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe, credentials: InMemoryCredentialStore())
    var draft = try workflow.beginLANListeningEditing()
    draft.mode = .allIPv4Interfaces
    workflow.refreshPortEditorOccupancy(for: draft.ports)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft.ports).occupancy != nil)
    #expect(workflow.portFieldState(for: .socks, editorDraft: draft.ports).isRuntimePortException)
    #expect(await workflow.saveLANListening(draft) == .persisted)
  }

  @Test func matchingPIDCannotExemptAChangedLANPort() async throws {
    let committing = FakeSettingsCommitter()
    committing.committedSettings.listen.lan.mode = .allIPv4Interfaces
    committing.runtimeListenFacts = RuntimeListenFacts(listen: committing.committedSettings.listen)
    committing.runtimeListenerProcessID = 123
    let probe = FakeOccupancyProbe(occupiedPorts: [13001], occupierProcessIDs: [123])
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe, credentials: InMemoryCredentialStore())
    var draft = try workflow.beginLANListeningEditing()
    draft.ports.socksPort = 13001
    workflow.refreshPortEditorOccupancy(for: draft.ports)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft.ports).occupancy != nil)
    #expect(!workflow.portFieldState(for: .socks, editorDraft: draft.ports).isRuntimePortException)
    #expect(await workflow.saveLANListening(draft) == .rejected(.occupied([.socks])))
  }

  @Test func invalidOtherGroupStillBlocksSavingWithoutMarkingLocalFields() async {
    let committing = FakeSettingsCommitter()
    committing.committedSettings.listen.lan.socksPort = 0
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: FakeOccupancyProbe())
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .http, editorDraft: draft).occupancy != nil)
    #expect(workflow.portFieldState(for: .socks, editorDraft: draft).issues.isEmpty)
    #expect(workflow.portFieldState(for: .http, editorDraft: draft).issues.isEmpty)
    #expect(!workflow.canSavePortSettings(draft))
    #expect(await workflow.savePortSettings(draft) == .rejected(.validation([])))
    #expect(committing.updateCalls.isEmpty)
  }

}
