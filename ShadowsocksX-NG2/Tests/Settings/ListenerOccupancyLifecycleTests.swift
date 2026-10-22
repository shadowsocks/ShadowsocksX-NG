import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ListenerOccupancyLifecycleTests {
  @Test func cachedOwnershipIsNotReinterpretedForAnotherProcess() async {
    let committing = FakeSettingsCommitter()
    committing.isProxyRunning = true
    committing.runtimeListenerProcessID = 123
    let workflow = SettingsWorkflow(
      committing: committing,
      occupancyProbe: FakeOccupancyProbe(occupiedPorts: [11086], occupierProcessIDs: [456]))
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)
    #expect(!workflow.portFieldState(for: .socks, editorDraft: draft).isRuntimePortException)

    committing.runtimeListenerProcessID = 456
    let field = workflow.portFieldState(for: .socks, editorDraft: draft)
    #expect(field.occupancy == nil)
    #expect(!field.isRuntimePortException)
    #expect(!field.canSuggestFreePort)
  }

  @Test(arguments: ContextChange.allCases)
  func changedContextDuringSuggestionDiscardsCandidate(change: ContextChange) async {
    let committing = FakeSettingsCommitter()
    let probe = SuggestionProbe()
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: probe)
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.canSavePortSettings(draft))
    let suggestion = Task { await workflow.suggestFreePort(for: .socks, from: draft) }
    await waitUntil(probe.gate.entered > 0)

    change.apply(to: committing)
    probe.gate.releaseGatedCalls()
    #expect(await suggestion.value == .rejected(.superseded))
    #expect(committing.updateCalls.isEmpty)
  }

  @Test(arguments: ContextChange.allCases)
  func changedContextDuringProbeDiscardsItsObservationAndReprobes(change: ContextChange) async {
    let committing = FakeSettingsCommitter()
    let probe = GatedOccupancyProbe(
      gatedAnswer: .occupied(PortOccupancyFacts(occupier: "old process")),
      passThroughAnswer: .free)
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: probe)
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(probe.entered > 0)

    change.apply(to: committing)
    probe.releaseGatedCalls()
    await waitUntil(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy != nil)
    #expect(workflow.portFieldState(for: .socks, editorDraft: draft).occupancy == .free)
    #expect(workflow.canSavePortSettings(draft))
  }

  @Test(arguments: ContextChange.allCases)
  func changedContextRejectsCachedSaveAndRefreshesWithoutCommitting(change: ContextChange) async {
    let committing = FakeSettingsCommitter()
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: FakeOccupancyProbe())
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.canSavePortSettings(draft))

    change.apply(to: committing)
    #expect(!workflow.canSavePortSettings(draft))
    #expect(await workflow.savePortSettings(draft) == .rejected(.superseded))
    #expect(committing.updateCalls.isEmpty)
    await waitUntil(workflow.canSavePortSettings(draft))
    #expect(committing.updateCalls.isEmpty)
    #expect(await workflow.savePortSettings(draft) == .persisted)
  }

  @Test func supersededSuggestionDoesNotReplaceTheNewerEditorPreview() async {
    let committing = FakeSettingsCommitter()
    let probe = SuggestionProbe()
    let workflow = SettingsWorkflow(committing: committing, occupancyProbe: probe)
    let draft = workflow.beginPortSettingsEditing()
    workflow.refreshPortEditorOccupancy(for: draft)
    await waitUntil(workflow.canSavePortSettings(draft))
    let suggestion = Task { await workflow.suggestFreePort(for: .socks, from: draft) }
    await waitUntil(probe.gate.entered > 0)

    var edited = draft
    edited.socksPort = 13001
    workflow.refreshPortEditorOccupancy(for: edited)
    await waitUntil(workflow.canSavePortSettings(edited))
    probe.gate.releaseGatedCalls()
    #expect(await suggestion.value == .rejected(.superseded))
    #expect(workflow.canSavePortSettings(edited))
    #expect(!workflow.canSavePortSettings(draft))
  }

  @Test(arguments: LANSaveChange.allCases)
  func changedLANSaveContextOnlyRejectsListeningChanges(change: LANSaveChange)
    async throws
  {
    let committing = FakeSettingsCommitter()
    let probe = GatedOccupancyProbe(gatedAnswer: .free, passThroughAnswer: .free)
    let workflow = SettingsWorkflow(
      committing: committing, occupancyProbe: probe)
    var draft = workflow.beginLANListeningEditing()
    draft.isEnabled = true
    let submission = Task { await workflow.saveLANListening(draft) }
    await waitUntil(probe.entered > 0)
    switch change {
    case .pid: committing.runtimeListenerProcessID = 456
    case .runtime: committing.isProxyRunning = true
    case .localPort: committing.committedSettings.listen.httpPort = 13009
    case .unrelatedSetting: committing.committedSettings.proxyExceptions = "example.com"
    }
    probe.releaseGatedCalls()

    if case .unrelatedSetting = change {
      #expect(await submission.value == .persisted)
      #expect(!workflow.isCommitting)
      #expect(committing.committedSettings.proxyExceptions == "example.com")
      #expect(committing.committedSettings.listen.lan.isEnabled)
      #expect(committing.updateCalls.count == 1)
      return
    }

    #expect(await submission.value == .rejected(.superseded))
    #expect(!workflow.isCommitting)
    #expect(committing.updateCalls.isEmpty)
    await waitUntil(workflow.canSaveLANListening(draft))
    #expect(committing.updateCalls.isEmpty)
  }

  enum LANSaveChange: CaseIterable, Sendable {
    case pid, runtime, localPort, unrelatedSetting
  }

  enum ContextChange: CaseIterable, Sendable {
    case pid, runtime, otherGroupPort, otherGroupMode, otherGroupEnabled

    @MainActor
    func apply(to committing: FakeSettingsCommitter) {
      switch self {
      case .pid: committing.runtimeListenerProcessID = 456
      case .runtime: committing.isProxyRunning = true
      case .otherGroupPort: committing.committedSettings.listen.lan.httpPort = 13009
      case .otherGroupMode: committing.committedSettings.listen.lan.mode = .allIPv6Interfaces
      case .otherGroupEnabled: committing.committedSettings.listen.lan.isEnabled = true
      }
    }
  }

}

private final class SuggestionProbe: PortOccupancyProbing, Sendable {
  let gate = GatedOccupancyProbe(gatedAnswer: .free, passThroughAnswer: .free)

  func occupancy(for request: PortOccupancyProbeRequest) async -> PortOccupancy {
    request.port >= PortSuggestion.range.lowerBound ? await gate.occupancy(for: request) : .free
  }
}
