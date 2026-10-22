import Foundation
import Testing
import XCTest

@testable import ShadowsocksX_NG2

/// 自定义规则持久化：往返、缺失文件、损坏与诊断摘要。
final class CustomRuleStoreTests: XCTestCase {
  private var directory: URL!
  private var store: CustomRuleStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-custom-rules-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = CustomRuleStore(fileURL: directory.appendingPathComponent("custom-rules.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  func testSchemaOneMigratesAndDisablementRoundTripsInSameDocument() throws {
    let rule = CustomRule(action: .direct, match: try RuleMatch(domainExact: "private.example"))
    let legacy = Data(
      """
      {"schemaVersion":1,"rules":[{"id":"\(rule.id.uuidString)","action":"direct",
       "match":{"kind":"domainExact","value":"private.example"},
       "source":{"kind":"custom","upstreamVersion":"user","label":"自定义"}}]}
      """.utf8)
    try legacy.write(to: store.fileURL)
    let migrated = try store.loadDocument()
    XCTAssertEqual(migrated.rules, [rule])
    XCTAssertTrue(migrated.disabledIdentities.isEmpty)
    try store.saveDocument(
      CustomRuleDocument(rules: migrated.rules, disabledIdentities: [rule.identity]))
    let saved = try store.loadDocument()
    XCTAssertEqual(saved.disabledIdentities, [rule.identity])
    XCTAssertNotEqual(
      try store.summary().contentVersion, CustomRuleSummary.summarizing([rule]).contentVersion)
  }

  func testMissingFileLoadsAsEmpty() throws {
    XCTAssertEqual(try store.load(), [])
  }

  func testRoundTripPersistsActionMatchAndUUID() throws {
    let match = try RuleMatch(domainSuffix: "example.com")
    let rule = CustomRule(action: .direct, match: match)

    try store.save([rule])
    let loaded = try store.load()

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].id, rule.id)
    XCTAssertEqual(loaded[0].action, .direct)
    XCTAssertEqual(loaded[0].match, match)
  }

  func testRoundTripKeepsMultipleRuleKinds() throws {
    let rules = [
      CustomRule(action: .proxy, match: try RuleMatch(domainExact: "a.example.com")),
      CustomRule(action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
      CustomRule(action: .proxy, match: try RuleMatch(ipv6CIDR: "2001:db8::/32")),
    ]

    try store.save(rules)

    XCTAssertEqual(try store.load(), rules)
  }

  func testStoredMatchIsNormalizedWithoutChangingCustomIdentity() throws {
    let rule = CustomRule(action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.15/24"))
    try store.save([rule])
    let loaded = try XCTUnwrap(store.load().first)
    XCTAssertEqual(loaded.id, rule.id)
    XCTAssertEqual(loaded.match, try RuleMatch(ipv4CIDR: "203.0.113.0/24"))
    XCTAssertEqual(loaded.identity, rule.identity)
  }

  func testMalformedStoredCIDRReportsCorruptionWithoutRewritingDocument() throws {
    for kind in ["ipv4CIDR", "ipv6CIDR"] {
      try Data(
        """
        {"schemaVersion":3,"rules":[{"id":"A22CD040-4788-41CC-BA73-AF296C7FE410",
         "action":"direct","match":{"kind":"\(kind)","value":"/"}}],"disabledIdentities":[]}
        """.utf8
      ).write(to: store.fileURL)
      let before = try Data(contentsOf: store.fileURL)
      XCTAssertThrowsError(try store.load()) { error in
        guard case .corrupt = error as? CustomRuleStoreError else {
          return XCTFail("Expected corrupt document, got \(error)")
        }
      }
      XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
    }
  }

  func testCorruptFileThrowsCorrupt() throws {
    try Data("not-json".utf8).write(to: store.fileURL)

    XCTAssertThrowsError(try store.load()) { error in
      guard case .corrupt = error as? CustomRuleStoreError else {
        return XCTFail("应点名 corrupt，实际 \(error)")
      }
    }
  }

  func testSchemaVersionMismatchIsRejected() throws {
    let payload = """
      {"schemaVersion": 99, "rules": []}
      """
    try Data(payload.utf8).write(to: store.fileURL)

    XCTAssertThrowsError(try store.load()) { error in
      guard case .schemaVersionMismatch(let found, let expected)? = error as? CustomRuleStoreError
      else {
        return XCTFail("应点名 schema 版本不匹配，实际 \(error)")
      }
      XCTAssertEqual(found, 99)
      XCTAssertEqual(expected, CustomRuleStore.currentSchemaVersion)
    }
  }

  func testSummaryExposesCountAndStableContentVersionWithoutRawDomains() throws {
    let rules = [
      CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "secret-internal.example")),
      CustomRule(action: .direct, match: try RuleMatch(ipv4CIDR: "203.0.113.0/24")),
    ]
    try store.save(rules)

    let summary = try store.summary()

    XCTAssertEqual(summary.count, 2)
    XCTAssertEqual(summary.contentVersion.count, 12)
    XCTAssertFalse(summary.contentVersion.contains("secret"))
    // 重排不改内容版本。
    let reordered = CustomRuleSummary.summarizing(Array(rules.reversed()))
    XCTAssertEqual(reordered.contentVersion, summary.contentVersion)
    // 内容变化改版本。
    let changed = CustomRuleSummary.summarizing([
      CustomRule(action: .proxy, match: try RuleMatch(domainSuffix: "other.example"))
    ])
    XCTAssertNotEqual(changed.contentVersion, summary.contentVersion)
  }
}

struct CustomRuleStorageMigrationTests {
  @Test func legacySourceIsDiscardedOnNextSaveWithoutLosingSavedIntent() throws {
    let data = Data(
      """
      {"schemaVersion":2,"rules":[
        {"id":"A22CD040-4788-41CC-BA73-AF296C7FE410","action":"direct",
         "match":{"kind":"ipv4CIDR","value":"203.0.113.15/24"},
         "source":{"kind":"custom","upstreamVersion":"imported","label":"Old import"}}
      ],"disabledIdentities":[
        {"action":"proxy","match":{"kind":"domainExact","value":"orphan.example"}}
      ]}
      """.utf8)
    let document = try CustomRuleStore.decode(data)
    #expect(document.rules.first?.id.uuidString == "A22CD040-4788-41CC-BA73-AF296C7FE410")
    #expect(document.disabledIdentities.count == 1)
    let encoded = try CustomRuleStore.encode(document)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(json["schemaVersion"] as? Int == 3)
    let rule = try #require((json["rules"] as? [[String: Any]])?.first)
    #expect(rule["source"] == nil)
    #expect((rule["match"] as? [String: String])?["value"] == "203.0.113.0/24")
    #expect(try CustomRuleStore.decode(encoded).disabledIdentities == document.disabledIdentities)
  }
}

extension CustomRuleStorageMigrationTests {
  @Test func loadDoesNotRewriteLegacyFileAndSaveRetainsOrphanDisablement() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomRuleStore(fileURL: directory.appendingPathComponent("rules.json"))
    let legacy = Data(
      """
      {"schemaVersion":2,"rules":[],"disabledIdentities":[
        {"action":"proxy","match":{"kind":"domainExact","value":"orphan.example"}}]}
      """.utf8)
    try legacy.write(to: store.fileURL)
    let document = try store.loadDocument()
    #expect(try Data(contentsOf: store.fileURL) == legacy)
    let rule = CustomRule(action: .direct, match: try RuleMatch(domainExact: "new.example"))
    try store.save([rule])
    let saved = try store.loadDocument()
    #expect(saved.rules == [rule])
    #expect(saved.disabledIdentities == document.disabledIdentities)
  }

  @Test(arguments: ["uuid", "identity", "disabled"])
  func duplicateRecordsRemainRejected(kind: String) throws {
    let record: [String: Any] = [
      "id": "A22CD040-4788-41CC-BA73-AF296C7FE410", "action": "direct",
      "match": ["kind": "domainExact", "value": "example.com"],
    ]
    var second = record
    if kind == "identity" { second["id"] = "B22CD040-4788-41CC-BA73-AF296C7FE410" }
    if kind == "uuid" { second["action"] = "proxy" }
    let disabled: [String: Any] = [
      "action": "proxy", "match": ["kind": "domainExact", "value": "orphan.example"],
    ]
    let json: [String: Any] = [
      "schemaVersion": 3, "rules": kind == "disabled" ? [] : [record, second],
      "disabledIdentities": kind == "disabled" ? [disabled, disabled] : [],
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: CustomRuleStoreError.self) { try CustomRuleStore.decode(data) }
  }
}
