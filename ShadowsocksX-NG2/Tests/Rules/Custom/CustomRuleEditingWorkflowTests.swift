import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class CustomRuleEditingWorkflowTests: XCTestCase {
  func testIPPreviewNormalizesWithoutSavingAndSavePublishesNewRow() async throws {
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: []) },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let version = workflow.snapshot.version
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.kind = .ipAddress
    draft.content = " 2001:DB8::1 "
    draft.action = .direct
    let preview = await workflow.previewCustomRule(draft)
    XCTAssertNil(preview.failure)
    XCTAssertEqual(preview.rule?.match, try RuleMatch(ipv6CIDR: "2001:db8::1/128"))
    XCTAssertEqual(preview.displayContent, "2001:db8::1")
    XCTAssertEqual(workflow.snapshot.version, version)
    XCTAssertFalse(workflow.snapshot.rows.contains { $0.customIDs.contains(draft.id) })
    let outcome = await workflow.saveCustomRule(draft)
    XCTAssertEqual(outcome, .committed(.saved))
    let row = try XCTUnwrap(workflow.snapshot.rows.first { $0.customIDs.contains(draft.id) })
    XCTAssertEqual(row.identity?.match, try RuleMatch(ipv6CIDR: "2001:db8::1/128"))
    XCTAssertEqual(row.sources, [.custom])
    XCTAssertNotEqual(workflow.snapshot.version, version)
  }
  func testEditingDisabledMergedRuleMovesOnlyCustomMembershipAndKeepsUUID() async throws {
    let original = CustomRule(
      action: .proxy, match: try RuleMatch(domainSuffix: "old.example"))
    let builtin = ProxyRule(action: .proxy, match: original.match)
    var saved = CustomRuleDocument(rules: [original], disabledIdentities: [original.identity])
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadDocument: { saved },
      commitDocument: {
        saved = $0
        return RuleDocumentCommit(outcome: .saved, document: saved)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: {
        rulesFixture($0, rules: $0 == .gfwlist ? [builtin] : [])
      }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: original.id))
    let unchanged = await workflow.previewCustomRule(draft)
    XCTAssertNil(unchanged.failure, "Editing excludes its own UUID")
    draft.content = "new.example"
    draft.action = .direct
    let preview = await workflow.previewCustomRule(draft)
    XCTAssertTrue(preview.inheritsDisablement)
    XCTAssertEqual(preview.row?.isEnabled, false)
    let result = await workflow.saveCustomRule(draft)
    XCTAssertEqual(result, .committed(.saved))
    XCTAssertEqual(saved.rules.count, 1)
    XCTAssertEqual(saved.rules.first?.id, original.id)
    XCTAssertEqual(
      saved.disabledIdentities,
      [
        original.identity,
        ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "new.example")),
      ])
    workflow.query(RulesQuery(source: .gfwlist))
    let oldRow = try XCTUnwrap(workflow.snapshot.rows.first { $0.identity == original.identity })
    XCTAssertEqual(oldRow.sources, [.gfwlist])
    XCTAssertTrue(oldRow.customIDs.isEmpty)
    XCTAssertFalse(oldRow.isEnabled)
    workflow.query(RulesQuery(source: .custom))
    let newRow = try XCTUnwrap(workflow.snapshot.rows.first { $0.customIDs.contains(original.id) })
    XCTAssertEqual(newRow.sources, [.custom])
    XCTAssertFalse(newRow.isEnabled)
  }

  func testCIDRRequiresAddressAndPrefixAndShowsMaskedNetwork() async throws {
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: []) },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.kind = .cidr
    draft.action = .direct
    for invalid in ["/8.8.8.8", "8.8.8.8/", "8.8.8.8", "8.8.8.8/33", "2001:db8::1/129"] {
      draft.content = invalid
      let preview = await workflow.previewCustomRule(draft)
      XCTAssertEqual(preview.failure, .invalidInput(.cidr), invalid)
    }
    for (input, expected) in [
      ("8.8.8.9/24", "8.8.8.0/24"), ("2001:db8:1::123/48", "2001:db8:1::/48"),
    ] {
      draft.content = input
      let preview = await workflow.previewCustomRule(draft)
      XCTAssertNil(preview.failure)
      XCTAssertEqual(preview.displayContent, expected)
    }
  }

  func testDuplicateAndFixedLocalConflictAreRejectedWithoutCommit() async throws {
    let existing = CustomRule(action: .direct, match: try RuleMatch(ipv4CIDR: "8.8.8.8/32"))
    var commits = 0
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: [existing]) },
      commitDocument: {
        commits += 1
        return RuleDocumentCommit(outcome: .saved, document: $0)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.kind = .ipAddress
    draft.content = "8.8.8.8"
    draft.action = .direct
    let duplicate = await workflow.previewCustomRule(draft)
    XCTAssertEqual(duplicate.failure, .duplicate)
    let duplicateSave = await workflow.saveCustomRule(draft)
    XCTAssertEqual(duplicateSave, .unavailable(.duplicate))
    draft.kind = .cidr
    draft.content = "8.8.8.8/32"
    let cidr = await workflow.previewCustomRule(draft)
    XCTAssertEqual(cidr.failure, .duplicate, "IP and full CIDR have one identity")
    draft.action = .proxy
    draft.kind = .ipAddress
    for input in ["192.168.1.1", "::ffff:192.168.1.1", "::1"] {
      draft.content = input
      let conflict = await workflow.previewCustomRule(draft)
      XCTAssertEqual(conflict.failure, .fixedLocalConflict, input)
      let save = await workflow.saveCustomRule(draft)
      XCTAssertEqual(save, .unavailable(.fixedLocalConflict))
    }
    XCTAssertEqual(commits, 0)
  }

  func testEquivalentBuiltinAndDisabledOrphanCanBeAddedWithoutEnabling() async throws {
    let builtin = ProxyRule(
      action: .proxy, match: try RuleMatch(domainSuffix: "merge.example"))
    let orphan = ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "orphan.example"))
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadDocument: {
        CustomRuleDocument(rules: [], disabledIdentities: [builtin, orphan])
      },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: {
        rulesFixture($0, rules: $0 == .gfwlist ? [builtin] : [])
      }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.content = ".MERGE.Example"
    let preview = await workflow.previewCustomRule(draft)
    XCTAssertNil(preview.failure)
    XCTAssertEqual(preview.displayContent, "merge.example")
    XCTAssertEqual(preview.row?.sources, [.custom, .gfwlist])
    XCTAssertEqual(preview.row?.isEnabled, false)
    let result = await workflow.saveCustomRule(draft)
    XCTAssertEqual(result, .committed(.saved))
    let row = try XCTUnwrap(workflow.snapshot.rows.first { $0.customIDs.contains(draft.id) })
    XCTAssertEqual(row.sources, [.custom, .gfwlist])
    XCTAssertFalse(row.isEnabled)
    var next = try XCTUnwrap(workflow.makeCustomRuleDraft())
    next.kind = .domainExact
    next.content = "orphan.example"
    let orphanPreview = await workflow.previewCustomRule(next)
    XCTAssertEqual(orphanPreview.row?.isEnabled, false)
    let orphanSave = await workflow.saveCustomRule(next)
    XCTAssertEqual(orphanSave, .committed(.saved))
    XCTAssertFalse(
      try XCTUnwrap(workflow.snapshot.rows.first { $0.customIDs.contains(next.id) }).isEnabled)
  }

  func testDomainBoundaryAndNationalSuffixUseExistingNormalization() async throws {
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: []) },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.action = .direct
    for kind in [CustomRuleDraft.Kind.domainExact, .domainSuffix] {
      draft.kind = kind
      for input in [
        "", "例子.cn", "*.example.com", "https://example.com", "example.com/path", "^example$",
      ] {
        draft.content = input
        let preview = await workflow.previewCustomRule(draft)
        XCTAssertEqual(preview.failure, .invalidInput(kind), input)
      }
      draft.content = " XN--FIQS8S.Example "
      let valid = await workflow.previewCustomRule(draft)
      XCTAssertNil(valid.failure)
      XCTAssertEqual(valid.displayContent, "xn--fiqs8s.example")
    }
    draft.kind = .domainSuffix
    draft.content = "CN"
    let national = await workflow.previewCustomRule(draft)
    XCTAssertNil(national.failure)
    XCTAssertEqual(national.rule?.match, try RuleMatch(nationalDomainSuffix: "cn"))
    draft.kind = .ipAddress
    for input in ["8.8.8.8/32", "[2001:db8::1]", "8.8.8.8:80", "example.com"] {
      draft.content = input
      let invalid = await workflow.previewCustomRule(draft)
      XCTAssertEqual(invalid.failure, .invalidInput(.ipAddress))
    }
  }

  func testPreviewExplainsAbsorptionShadowingAndPartialOverlapButAllowsSave() async throws {
    let broad = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "coverage.example"))
    let proxy = CustomRule(action: .proxy, match: try RuleMatch(domainExact: "a.coverage.example"))
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: [broad, proxy]) },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.kind = .domainExact
    draft.content = "a.coverage.example"
    draft.action = .direct
    let preview = await workflow.previewCustomRule(draft)
    XCTAssertNil(preview.failure)
    XCTAssertTrue(
      preview.row?.relationships.contains {
        $0.kind == .absorption && $0.extent == .full && $0.covering == [broad.identity]
      } == true)
    XCTAssertTrue(
      preview.row?.relationships.contains {
        $0.kind == .shadowing && $0.extent == .full && $0.covering == [proxy.identity]
      } == true)
    let saved = await workflow.saveCustomRule(draft)
    XCTAssertEqual(saved, .committed(.saved))
    await workflow.analysisTask?.value
    XCTAssertEqual(
      workflow.snapshot.rows.first { $0.customIDs.contains(draft.id) }?.relationships,
      preview.row?.relationships)
    var edited = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: broad.id))
    edited.content = "coverage.example"
    let partial = await workflow.previewCustomRule(edited)
    XCTAssertTrue(
      partial.row?.relationships.contains { $0.kind == .shadowing && $0.extent == .partial } == true
    )
  }

}

extension CustomRuleEditingWorkflowTests {
  func testPendingSaveBlocksRepeatsAndFailureKeepsSnapshotAvailableForRetry() async throws {
    let original = CustomRuleDocument(rules: [])
    let started = expectation(description: "save awaiting adapter")
    var continuation: CheckedContinuation<Void, Never>?
    var commits = 0
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { original },
      commitDocument: { _ in
        commits += 1
        await withCheckedContinuation {
          continuation = $0
          started.fulfill()
        }
        return RuleDocumentCommit(outcome: .persistenceFailed, document: original)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    let version = workflow.snapshot.version
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft())
    draft.content = "pending.example"
    let pending = Task { await workflow.saveCustomRule(draft) }
    await fulfillment(of: [started], timeout: 3)
    XCTAssertTrue(workflow.snapshot.isCommitting)
    XCTAssertEqual(workflow.snapshot.operationStatus, .updating)
    let repeated = await workflow.saveCustomRule(draft)
    XCTAssertEqual(repeated, .unavailable(.busy))
    XCTAssertNil(workflow.makeCustomRuleDraft())
    continuation?.resume()
    let result = await pending.value
    XCTAssertEqual(result, .committed(.persistenceFailed))
    XCTAssertEqual(commits, 1)
    XCTAssertEqual(workflow.snapshot.version, version)
    XCTAssertEqual(workflow.snapshot.commitOutcome, .persistenceFailed)
    XCTAssertFalse(workflow.snapshot.rows.contains { $0.customIDs.contains(draft.id) })
    let retry = await workflow.previewCustomRule(draft)
    XCTAssertNil(retry.failure)
  }

  func testSavedEditRejectsStaleDraftAndIncompleteCollection() async throws {
    let rule = CustomRule(
      action: .direct, match: try RuleMatch(domainSuffix: "old.example"))
    let original = CustomRuleDocument(rules: [rule])
    let outcome = CustomRuleUpdateOutcome.saved
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { original },
      commitDocument: { RuleDocumentCommit(outcome: outcome, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    XCTAssertNil(workflow.makeCustomRuleDraft())
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: rule.id))
    draft.content = "new.example"
    let result = await workflow.saveCustomRule(draft)
    XCTAssertEqual(result, .committed(outcome))
    XCTAssertEqual(workflow.snapshot.commitOutcome, outcome)
    XCTAssertEqual(
      workflow.snapshot.rows.first { $0.customIDs.contains(rule.id) }?.content, "new.example")
    let stale = await workflow.previewCustomRule(draft)
    XCTAssertEqual(stale.failure, .staleDraft)
    let incomplete = RulesWorkflow(
      preset: .gfwlist,
      loadDocument: { throw CustomRuleStoreError.corrupt(detail: "fixture error") },
      commitDocument: { RuleDocumentCommit(outcome: .saved, document: $0) },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await incomplete.refresh()
    XCTAssertNil(incomplete.makeCustomRuleDraft())
    let refused = await incomplete.saveCustomRule(draft)
    XCTAssertEqual(refused, .unavailable(.incompleteCollection))
  }
}

extension CustomRuleEditingWorkflowTests {
  func testDisabledEditCannotInheritDisablementOntoImmutableFixedIdentity() async throws {
    let original = CustomRule(
      action: .direct, match: try RuleMatch(domainExact: "disabled.example"))
    var commits = 0
    let workflow = RulesWorkflow(
      preset: .gfwlist,
      loadDocument: {
        CustomRuleDocument(rules: [original], disabledIdentities: [original.identity])
      },
      commitDocument: {
        commits += 1
        return RuleDocumentCommit(outcome: .saved, document: $0)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    var draft = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: original.id))
    draft.kind = .cidr
    draft.content = "127.0.0.0/8"
    let preview = await workflow.previewCustomRule(draft)
    XCTAssertEqual(preview.failure, .fixedPolicyDisablement)
    XCTAssertNil(preview.document)
    let result = await workflow.saveCustomRule(draft)
    guard case .unavailable = result else { return XCTFail("Must reject fixed-policy disablement") }
    XCTAssertEqual(commits, 0)
    XCTAssertFalse(workflow.snapshot.rows.filter(\.isFixed).contains { !$0.isEnabled })
  }
}

extension CustomRuleEditingWorkflowTests {
  func testStaleDraftCannotOverwriteAnotherSavedChangeAndDiscardingDraftDoesNothing() async throws {
    let rule = CustomRule(action: .direct, match: try RuleMatch(domainExact: "kept.example"))
    var commits = 0
    let workflow = RulesWorkflow(
      preset: .gfwlist, loadDocument: { CustomRuleDocument(rules: [rule]) },
      commitDocument: {
        commits += 1
        return RuleDocumentCommit(outcome: .saved, document: $0)
      },
      builtinSnapshots: BuiltinRuleSnapshots(loader: { rulesFixture($0) }))
    await workflow.refresh()
    var discarded = try XCTUnwrap(workflow.makeCustomRuleDraft(editing: rule.id))
    discarded.content = "discarded.example"
    _ = await workflow.previewCustomRule(discarded)
    XCTAssertEqual(commits, 0)
    XCTAssertEqual(
      workflow.snapshot.rows.first { $0.customIDs.contains(rule.id) }?.identity, rule.identity)
    var stale = try XCTUnwrap(workflow.makeCustomRuleDraft())
    stale.content = "new.example"
    await workflow.setEnabled(false, identities: [rule.identity])
    let result = await workflow.saveCustomRule(stale)
    XCTAssertEqual(result, .unavailable(.staleDraft))
    XCTAssertEqual(commits, 1)
    XCTAssertFalse(workflow.snapshot.rows.contains { $0.customIDs.contains(stale.id) })
  }
}
