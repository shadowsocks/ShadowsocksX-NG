import Foundation
import Testing
import XCTest

@testable import ShadowsocksX_NG2

final class GeneratedRuleSnapshotTests: XCTestCase {
  func testDisablingCNSuffixDoesNotRestoreOmittedOfflineRows() throws {
    let snapshot = try generatedSnapshot("geolocation-cn")
    let collection = RulesCollection.load(
      custom: { [] },
      builtin: { source in
        source == .geolocationCN ? snapshot : rulesFixture(source)
      })
    let narrow = ProxyRule(action: .direct, match: try RuleMatch(domainSuffix: "foo.cn"))
    XCTAssertFalse(collection.rows.contains { $0.identity == narrow })
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "foo.cn").outcome, .direct)
    let disabled = collection.replacingUserDocument(
      CustomRuleDocument(
        rules: [],
        disabledIdentities: [
          ProxyRule(action: .direct, match: try RuleMatch(nationalDomainSuffix: "cn"))
        ]))
    let result = try OfflineRuleMatcher.test(collection: disabled, address: "foo.cn")
    XCTAssertEqual(result.outcome, .unmatched)
    XCTAssertTrue(result.deciding.isEmpty)
  }

  func testSnapshotLoadRejectsOldVersionsAndAbnormalCounts() throws {
    let snapshot = try generatedSnapshot("geolocation-cn")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("snapshot.json")
    let store = RuleSnapshotStore(fileURL: url)
    let encoded = try RuleSnapshotStore.encode(snapshot)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var old = original
    old["schemaVersion"] = 1
    try JSONSerialization.data(withJSONObject: old).write(to: url)
    XCTAssertThrowsError(try store.load()) {
      XCTAssertEqual($0 as? RuleSnapshotError, .schemaVersionMismatch(found: 1, expected: 2))
    }
    var obsolete = original
    var metadata = try XCTUnwrap(obsolete["metadata"] as? [String: Any])
    metadata["converterVersion"] = "1.0.0"
    obsolete["metadata"] = metadata
    try JSONSerialization.data(withJSONObject: obsolete).write(to: url)
    XCTAssertThrowsError(try store.load()) {
      XCTAssertEqual(
        $0 as? RuleSnapshotError,
        .converterVersionMismatch(found: "1.0.0", expected: "2.0.0"))
    }
    let rule = try XCTUnwrap(snapshot.rules.first)
    for count in [99, 100] {
      try store.save(
        RuleSnapshot(
          metadata: snapshot.metadata,
          rules: Array(repeating: rule, count: count)))
      if (100...200_000).contains(count) {
        XCTAssertEqual(try store.load().rules.count, count)
      } else {
        XCTAssertThrowsError(try store.load()) {
          XCTAssertEqual(
            $0 as? RuleSnapshotError,
            .abnormalRuleCount(found: count, minimum: 100, maximum: 200_000))
        }
      }
    }
  }

  func testSnapshotEncodingOmitsForensicsAndKeepsNumericReport() throws {
    let snapshot = try generatedSnapshot("geolocation-cn")
    let data = try RuleSnapshotStore.encode(snapshot)
    XCTAssertFalse(data.contains(10), "Snapshot JSON is compact")
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["schemaVersion", "metadata", "rules", "lossReport"])
    let report = try XCTUnwrap(json["lossReport"] as? [String: Any])
    XCTAssertEqual(Set(report.keys), ["convertedCount", "absorbedCount", "skipped", "rejected"])
    XCTAssertEqual(report["absorbedCount"] as? Int, 1)
    let rules = try XCTUnwrap(json["rules"] as? [[String: Any]])
    XCTAssertTrue(rules.allSatisfy { Set($0.keys) == ["action", "match"] })
  }

  func testSnapshotStoreRoundTripAndVersionGuard() throws {
    let snapshot = try generatedSnapshot("geolocation-cn")
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-rule-snapshot-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("snapshot.json")

    let store = RuleSnapshotStore(fileURL: url)
    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertEqual(error as? RuleSnapshotError, .missing)
    }
    try store.save(snapshot)
    let loaded = try store.load()
    XCTAssertEqual(loaded.rules.map(\.match), snapshot.rules.map(\.match))
    XCTAssertEqual(loaded.metadata, snapshot.metadata)

    // schema / converter 版本不匹配使加载失败。
    let rawObject = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard var raw = rawObject as? [String: Any] else {
      return XCTFail("snapshot JSON root should be an object")
    }
    raw["schemaVersion"] = 99
    try JSONSerialization.data(withJSONObject: raw).write(to: url)
    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertEqual(
        error as? RuleSnapshotError,
        .schemaVersionMismatch(found: 99, expected: RuleSnapshotStore.currentSchemaVersion))
    }
  }
}

struct RuleSnapshotCountTests {
  @Test func geolocationCountBoundaries() throws {
    try checkBoundaries(source: .geolocationCN, maximum: 200_000)
  }

  @Test(arguments: [RuleSourceKind.chinaIPv4, .gfwlist, .custom])
  func otherSourceCountBoundaries(source: RuleSourceKind) throws {
    try checkBoundaries(source: source, maximum: 50_000)
  }

  private func checkBoundaries(source: RuleSourceKind, maximum: Int) throws {
    for count in [0, 99, maximum + 1] {
      #expect(
        throws: RuleSnapshotError.abnormalRuleCount(found: count, minimum: 100, maximum: maximum)
      ) {
        try RuleSnapshotStore.validateRuleCount(count, source: source)
      }
    }
    for count in [100, maximum] {
      try RuleSnapshotStore.validateRuleCount(count, source: source)
    }
  }
}

private func generatedSnapshot(_ name: String) throws -> RuleSnapshot {
  let url = try XCTUnwrap(
    Bundle(for: GeneratedRuleSnapshotTests.self)
      .url(forResource: name, withExtension: "json", subdirectory: "RuleSnapshots"))
  return try RuleSnapshotStore(fileURL: url).load()
}

extension GeneratedRuleSnapshotTests {
  func testAllGeneratedSourcesLoadAndCompileIntoACL() throws {
    let snapshots = try ["geolocation-cn", "china-ipv4", "gfwlist"].map(generatedSnapshot)
    let acl = ProxyACLDocument.rule(
      at: URL(fileURLWithPath: "/tmp/generated-fixture.acl"),
      defaultAction: .directWhenUnmatched, rules: snapshots.flatMap(\.rules))
    XCTAssertTrue(acl.content.contains("||example.com"))
    XCTAssertTrue(acl.content.contains("1.0.0.0/24"))
    XCTAssertFalse(acl.content.contains("||safe.example.com"))
    let collection = RulesCollection.load(
      custom: { [] },
      builtin: { source in
        try XCTUnwrap(
          [
            RulesSource.geolocationCN: snapshots[0], .chinaIPv4: snapshots[1],
            .gfwlist: snapshots[2],
          ][source])
      })
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "1.0.0.42").outcome, .direct)
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "example.com").outcome, .proxy)
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "api.example.org").outcome,
      .direct)
  }
}

extension GeneratedRuleSnapshotTests {
  func testDisablingBlockerDoesNotRestoreOmittedOfflineException() throws {
    let snapshot = try generatedSnapshot("gfwlist")
    let collection = RulesCollection.load(
      custom: { [] },
      builtin: { source in
        source == .gfwlist ? snapshot : rulesFixture(source)
      })
    let exception = ProxyRule(
      action: .direct, match: try RuleMatch(domainSuffix: "safe.example.com"))
    XCTAssertFalse(collection.rows.contains { $0.identity == exception })
    XCTAssertEqual(
      try OfflineRuleMatcher.test(collection: collection, address: "safe.example.com").outcome,
      .proxy)
    let disabled = collection.replacingUserDocument(
      CustomRuleDocument(
        rules: [],
        disabledIdentities: [
          ProxyRule(action: .proxy, match: try RuleMatch(domainSuffix: "example.com"))
        ]))
    let result = try OfflineRuleMatcher.test(collection: disabled, address: "safe.example.com")
    XCTAssertEqual(result.outcome, .unmatched)
    XCTAssertTrue(result.deciding.isEmpty)
  }
}
