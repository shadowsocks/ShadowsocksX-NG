import Foundation
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
    let rule = CustomRule(action: .direct, match: .domainExact("private.example"))
    let legacy = try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "rules": JSONSerialization.jsonObject(with: JSONEncoder().encode([rule])),
    ])
    try legacy.write(to: store.fileURL)
    let migrated = try store.loadDocument()
    XCTAssertEqual(migrated.rules, [rule])
    XCTAssertTrue(migrated.disabledIdentities.isEmpty)
    try store.saveDocument(
      CustomRuleDocument(rules: migrated.rules, disabledIdentities: [rule.identity]))
    let saved = try store.loadDocument()
    XCTAssertEqual(saved.schemaVersion, 2)
    XCTAssertEqual(saved.disabledIdentities, [rule.identity])
    XCTAssertNotEqual(
      try store.summary().contentVersion, CustomRuleSummary.summarizing([rule]).contentVersion)
  }

  func testMissingFileLoadsAsEmpty() throws {
    XCTAssertEqual(try store.load(), [])
  }

  func testRoundTripPersistsActionMatchAndSourceMetadata() throws {
    let match = try RuleMatch(domainSuffix: "example.com")
    let rule = CustomRule(action: .direct, match: match)

    try store.save([rule])
    let loaded = try store.load()

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].id, rule.id)
    XCTAssertEqual(loaded[0].action, .direct)
    XCTAssertEqual(loaded[0].match, match)
    XCTAssertEqual(loaded[0].source.kind, .custom)
    XCTAssertFalse(loaded[0].source.label.isEmpty)
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
    let rule = CustomRule(action: .direct, match: .ipv4CIDR("203.0.113.15/24"))
    try store.save([rule])
    let loaded = try XCTUnwrap(store.load().first)
    XCTAssertEqual(loaded.id, rule.id)
    XCTAssertEqual(loaded.match, .ipv4CIDR("203.0.113.0/24"))
    XCTAssertEqual(loaded.identity, rule.identity)
  }

  func testMalformedStoredCIDRReportsCorruptionWithoutRewritingDocument() throws {
    for match in [RuleMatch.ipv4CIDR("/"), .ipv6CIDR("/")] {
      try CustomRuleStore.encode(
        CustomRuleDocument(rules: [CustomRule(action: .direct, match: match)])
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
      XCTAssertEqual(expected, CustomRuleDocument.currentSchemaVersion)
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
