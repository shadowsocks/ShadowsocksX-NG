import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct RulePresetWorkflowTests {
  @Test(arguments: RulePreset.allCases)
  func chinaTargetsUsePresetActionAndUnmatchedUsesDefault(_ preset: RulePreset) async throws {
    let workflow = RulesWorkflow(
      preset: preset, loadCustom: { [] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { source in
        rulesFixture(
          source,
          rules: source == .geolocationCN
            ? [ProxyRule(action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))] : [])
      }))
    await workflow.refresh()
    #expect(workflow.snapshot.query.source == .custom)
    let expectedSources: Set<RulesSource> =
      preset == .gfwlist
      ? [.custom, .gfwlist, .fixed] : [.custom, .geolocationCN, .chinaIPv4, .fixed]
    #expect(Set(workflow.snapshot.sources.map(\.id)) == expectedSources)
    workflow.setTestTarget("new-service.cn")
    await workflow.testAddress()
    #expect(
      workflow.snapshot.addressTest.result?.outcome == (preset == .chinaProxy ? .proxy : .direct))
    #expect(workflow.snapshot.addressTest.result?.deciding.isEmpty == (preset == .gfwlist))
    workflow.setTestTarget("unlisted.example")
    await workflow.testAddress()
    #expect(
      workflow.snapshot.addressTest.result?.outcome == (preset == .chinaDirect ? .proxy : .direct))
    #expect(workflow.snapshot.addressTest.result?.explanation == .defaultAction)
    workflow.setTestTarget("127.0.0.1")
    await workflow.testAddress()
    #expect(workflow.snapshot.addressTest.result?.outcome == .direct)
    #expect(workflow.snapshot.addressTest.result?.explanation == .fixedLocal)
  }
}

extension RulePresetWorkflowTests {
  @Test func workspacesKeepRulesDisablementAndBrowsingStateAcrossSwitchesAndReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let baseURL = directory.appendingPathComponent("rules.json")
    let legacy = CustomRuleStore(fileURL: baseURL)
    let old = CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "legacy.example"))
    try legacy.saveDocument(CustomRuleDocument(rules: [old], disabledIdentities: [old.identity]))
    let workspaces = makeWorkspaces(baseURL: baseURL)
    let shared = ProxyRule(action: .proxy, match: try RuleMatch(domainSuffix: "shared.example"))
    let scenarios: [(RulePreset, RulesQuery)] = [
      (.gfwlist, RulesQuery(search: "shared", action: .proxy, source: .custom, enabled: false)),
      (.chinaDirect, RulesQuery(action: .direct, source: .fixed, enabled: true)),
      (.chinaProxy, RulesQuery(search: "proxy", source: .chinaIPv4)),
    ]
    for (preset, query) in scenarios {
      workspaces.selectedPreset = preset
      let workflow = workspaces.current
      await workflow.refresh()
      #expect(workflow.snapshot.rows.isEmpty)
      var draft = try #require(workflow.makeCustomRuleDraft())
      draft.kind = .domainSuffix
      draft.content = "shared.example"
      draft.action = .proxy
      let saved = await workflow.saveCustomRule(draft)
      #expect(saved == .committed(.saved))
      #expect(workflow.snapshot.rows.first?.identity == shared)
      if preset == .gfwlist { await workflow.setEnabled(false, identities: [shared]) }
      workflow.query(query)
      workflow.setTestTarget("\(preset.rawValue).shared.example")
      await workflow.testAddress()
    }
    for (preset, query) in scenarios {
      workspaces.selectedPreset = preset
      let page = workspaces.current.snapshot
      let target = "\(preset.rawValue).shared.example"
      #expect(page.query == query)
      #expect(page.addressTest.target == target)
      #expect(page.addressTest.result?.target == target)
      #expect(page.addressTest.result?.outcome == (preset == .gfwlist ? .direct : .proxy))
      workspaces.current.query(RulesQuery(source: .custom))
      #expect(workspaces.current.snapshot.rows.first?.isEnabled == (preset != .gfwlist))
      let loaded = try CustomRuleStore(preset: preset, baseURL: baseURL).loadDocument()
      #expect(loaded.rules.count == 1)
      #expect(loaded.rules.first?.identity == shared)
      #expect(loaded.disabledIdentities == (preset == .gfwlist ? [shared] : []))
    }
    #expect(
      try legacy.loadDocument()
        == CustomRuleDocument(rules: [old], disabledIdentities: [old.identity]))
  }
}

extension RulePresetWorkflowTests {
  @Test func delayedSaveAndAnalysisPublishOnlyToTheirOwningWorkspace() async throws {
    let started = TestAsyncGate("save started")
    let release = TestAsyncGate("save release")
    let workspaces = RulesWorkspaces { preset in
      RulesWorkflow(
        preset: preset, loadDocument: { CustomRuleDocument(rules: []) },
        commitDocument: { document in
          started.release()
          _ = await release.wait()
          return RuleDocumentCommit(outcome: .saved, document: document)
        }, builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    }
    let originalPreset = workspaces.selectedPreset
    let original = workspaces.current
    await original.refresh()
    var draft = try #require(original.makeCustomRuleDraft())
    draft.content = "delayed.example"
    draft.action = .direct
    let captured = draft
    let save = Task { await original.saveCustomRule(captured) }
    defer { release.release() }
    #expect(await started.wait())
    workspaces.selectedPreset = .chinaProxy
    let other = workspaces.current
    await other.refresh()
    other.setTestTarget("unlisted.example")
    await other.testAddress()
    let untouched = other.snapshot
    release.release()
    #expect(await save.value == .committed(.saved))
    await original.analysisTask?.value
    #expect(other.snapshot == untouched)
    workspaces.selectedPreset = originalPreset
    #expect(workspaces.current.snapshot.rows.first?.content == "delayed.example")
    #expect(workspaces.current.snapshot.rows.first?.action == .direct)
    #expect(workspaces.current.snapshot.commitOutcome == .saved)
  }
}

extension RulePresetWorkflowTests {
  private func makeWorkspaces(baseURL: URL) -> RulesWorkspaces {
    return RulesWorkspaces { preset in
      let session = RuleDocumentSession(store: CustomRuleStore(preset: preset, baseURL: baseURL))
      return RulesWorkflow(
        preset: preset, loadDocument: { try session.load() },
        commitDocument: { session.commit($0) },
        builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    }
  }
}

extension RulePresetWorkflowTests {
  @Test func chinaDirectExplanationUsesOnlyActionsExpressedByItsACL() async throws {
    let direct = ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "example.cn"))
    let custom = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "www.example.cn"))
    let workflow = RulesWorkflow(
      preset: .chinaDirect, loadCustom: { [custom] },
      builtinSnapshots: BuiltinRuleSnapshots(loader: {
        rulesFixture($0, rules: $0 == .geolocationCN ? [direct] : [])
      }))
    await workflow.refresh()
    workflow.setTestTarget("www.example.cn")
    await workflow.testAddress()
    #expect(workflow.snapshot.addressTest.result?.outcome == .direct)
    #expect(workflow.snapshot.addressTest.result?.deciding.map(\.identity) == [direct])
    workflow.query(RulesQuery(source: .geolocationCN))
    #expect(workflow.snapshot.rows.first?.relationships.isEmpty == true)
    workflow.setTestTarget("unlisted.example")
    await workflow.testAddress()
    #expect(workflow.snapshot.addressTest.result?.explanation == .defaultAction)
    workflow.setTestTarget("www.example.cn")
    workflow.query(RulesQuery(source: .custom))
    #expect(workflow.snapshot.rows.first?.action == .proxy)
  }
}
