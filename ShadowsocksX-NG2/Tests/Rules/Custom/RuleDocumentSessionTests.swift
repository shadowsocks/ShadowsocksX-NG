import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct RuleDocumentSessionTests {
  @Test(arguments: RulePreset.allCases)
  func reverseActionCommitIsRejectedWithoutChangingSavedFacts(_ preset: RulePreset) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(
      preset: preset, baseURL: directory.appendingPathComponent("rules.json"))
    let session = RuleDocumentSession(store: store)
    let original = CustomRuleDocument(rules: [
      CustomRule(
        action: preset == .chinaDirect ? .direct : .proxy,
        match: try RuleMatch(domainExact: "kept.example"))
    ])
    #expect(session.commit(original).outcome == .saved)
    let bytes = try Data(contentsOf: store.fileURL)
    let invalid = CustomRuleDocument(rules: [
      CustomRule(
        action: preset == .chinaDirect ? .proxy : .direct,
        match: try RuleMatch(domainExact: "reverse.example"))
    ])
    let result = session.commit(invalid)
    #expect(
      result.outcome == .invalidDocument(detail: "Custom rule action must match its rule scheme"))
    #expect(result.document == original)
    #expect(session.revision == 1)
    #expect(try Data(contentsOf: store.fileURL) == bytes)
    #expect(throws: CustomRuleStoreError.self) { try store.saveDocument(invalid) }
    #expect(try Data(contentsOf: store.fileURL) == bytes)
  }

  @Test func successfulCommitPublishesSavedFactsAndOnlyChangedContentAdvancesRevision() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(
      preset: .chinaProxy, baseURL: directory.appendingPathComponent("rules.json"))
    let session = RuleDocumentSession(store: store)
    let document = CustomRuleDocument(rules: [
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: "saved.example"))
    ])

    let result = session.commit(document)

    #expect(result.outcome == .saved)
    #expect(result.document == document)
    #expect(try session.load() == document)
    #expect(session.revision == 1)
    #expect(session.commit(document).outcome == .saved)
    #expect(session.revision == 1)
    #expect(try RuleDocumentSession(store: store).load() == document)
  }
}

extension RuleDocumentSessionTests {
  @Test(arguments: ["fixedConflict", "duplicate", "fixedDisabled"])
  func invalidCommitRetainsSavedFactsAndRevision(reason: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let session = RuleDocumentSession(store: store)
    let kept = CustomRule(action: .direct, match: try RuleMatch(domainExact: "kept.example"))
    let original = CustomRuleDocument(rules: [kept])
    #expect(session.commit(original).outcome == .saved)
    let proposal: CustomRuleDocument
    switch reason {
    case "fixedConflict":
      proposal = CustomRuleDocument(rules: [
        kept,
        CustomRule(action: .proxy, match: try RuleMatch(ipv4CIDR: "127.0.0.0/8")),
      ])
    case "duplicate":
      proposal = CustomRuleDocument(rules: [
        kept,
        CustomRule(action: kept.action, match: kept.rule.match),
      ])
    default:
      proposal = CustomRuleDocument(
        rules: [kept],
        disabledIdentities: [
          ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "127.0.0.0/8"))
        ])
    }

    let result = session.commit(proposal)

    if reason == "fixedDisabled" {
      #expect(result.outcome == .invalidDocument(detail: "Fixed local policy cannot be disabled"))
    } else {
      guard case .rejected(let rejected) = result.outcome else {
        Issue.record("Expected whole-document rejection, got \(result.outcome)")
        return
      }
      #expect(
        rejected.map(\.reason).allSatisfy {
          $0 == (reason == "duplicate" ? .duplicate : .conflictsWithFixedLocalScope)
        })
      #expect(!rejected.isEmpty)
    }
    #expect(result.document == original)
    #expect(session.current == original)
    #expect(session.revision == 1)
    #expect(try RuleDocumentSession(store: store).load() == original)
  }
}

extension RuleDocumentSessionTests {
  @Test func corruptFirstLoadRejectsCommitWithoutOverwritingFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let corrupt = Data("broken".utf8)
    try corrupt.write(to: store.fileURL)
    let session = RuleDocumentSession(store: store)

    let result = session.commit(CustomRuleDocument(rules: []))

    #expect(result.outcome == .persistenceFailed)
    #expect(result.document == nil)
    #expect(session.current == nil)
    #expect(session.revision == 0)
    #expect(try Data(contentsOf: store.fileURL) == corrupt)
  }

  @Test func failedWriteRetainsOwnedFactsAndRevision() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("storage")
    let store = CustomRuleStore(fileURL: storage.appendingPathComponent("rules.json"))
    let session = RuleDocumentSession(store: store)
    let original = CustomRuleDocument(rules: [
      CustomRule(action: .direct, match: try RuleMatch(domainExact: "kept.example"))
    ])
    #expect(session.commit(original).outcome == .saved)
    let backup = directory.appendingPathComponent("backup")
    try FileManager.default.moveItem(at: storage, to: backup)
    try Data("blocked".utf8).write(to: storage)

    let result = session.commit(CustomRuleDocument(rules: []))

    #expect(result.outcome == .persistenceFailed)
    #expect(result.document == original)
    #expect(try session.load() == original)
    #expect(session.revision == 1)
    try FileManager.default.removeItem(at: storage)
    try FileManager.default.moveItem(at: backup, to: storage)
    #expect(try RuleDocumentSession(store: store).load() == original)
  }

  @Test func overlappingOppositeActionsAndOrphanedDisablementRemainSavedIntent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let session = RuleDocumentSession(store: store)
    let document = CustomRuleDocument(
      rules: [
        CustomRule(action: .direct, match: try RuleMatch(domainSuffix: "example.com")),
        CustomRule(action: .proxy, match: try RuleMatch(domainExact: "a.example.com")),
        CustomRule(action: .direct, match: try RuleMatch(domainExact: "a.example.com")),
      ],
      disabledIdentities: [
        ProxyRule(action: .proxy, match: try RuleMatch(domainExact: "orphan.example"))
      ])

    let result = session.commit(document)

    #expect(result.outcome == .saved)
    #expect(result.document == document)
    #expect(try RuleDocumentSession(store: store).load() == document)
  }
}
