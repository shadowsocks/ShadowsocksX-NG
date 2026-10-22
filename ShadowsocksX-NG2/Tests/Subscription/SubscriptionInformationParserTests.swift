import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct SubscriptionInformationParserTests {
  @Test func subscriptionInformationIsParsedFromRootFields() throws {
    let snapshot = try SubscriptionDocumentParser.parse(
      Data(
        #"""
        {"version":1,
        "servers":[],
        "bytes_used":25,
        "bytes_remaining":75,
        "expires_at":"2026-10-04T08:30:00+08:00",
        "traffic_reset_at":"2026-10-05T00:00:00.125Z"}
        """#
        .utf8),
      subscriptionID: .fresh())

    #expect(snapshot.information.bytesUsed == 25)
    #expect(snapshot.information.bytesRemaining == 75)
    #expect(snapshot.information.expiresAt == Date(timeIntervalSince1970: 1_791_073_800))
    #expect(snapshot.information.trafficResetAt == Date(timeIntervalSince1970: 1_791_158_400.125))
  }
  @Test func rfc3339OffsetOutsideTimeZoneFactoryRangeIsAccepted() throws {
    let snapshot = try SubscriptionDocumentParser.parse(
      Data(#"{"version":1,"servers":[],"expires_at":"2026-10-04T23:59:00+23:59"}"#.utf8),
      subscriptionID: .fresh())
    #expect(snapshot.information.expiresAt == Date(timeIntervalSince1970: 1_791_072_000))
  }
  @Test(arguments: [
    "true", "false", "\"25\"", "-1", "1.5", "1.0", "1e3", "1e999", "18446744073709551616", "null",
    "[]",
    "{}",
  ])
  func invalidByteCountsDoNotDiscardValidInformation(_ literal: String) throws {
    let snapshot = try parse(
      #""bytes_used":\#(literal),"bytes_remaining":75,"expires_at":"1970-01-01T00:00:00Z""#)
    #expect(snapshot.information.bytesUsed == nil)
    #expect(snapshot.information.bytesRemaining == 75)
    #expect(snapshot.information.expiresAt == Date(timeIntervalSince1970: 0))
  }

  @Test func fullUnsignedRangeAndZeroAreAccepted() throws {
    let snapshot = try parse(#""bytes_used":18446744073709551615,"bytes_remaining":0"#)
    #expect(snapshot.information.bytesUsed == UInt64.max)
    #expect(snapshot.information.bytesRemaining == 0)
  }

  @Test(arguments: [
    #""2026-02-30T12:30:00Z""#, #""2026-10-04T24:00:00Z""#,
    #""2026-10-04T00:00:00""#, #""2026-10-04T00:00:00Zjunk""#,
    #""2026-10-04""#, #""2026-10-04T23:59:60Z""#, #""not a date""#,
    "1791072000", "null", "true", "{}", "[]",
  ])
  func invalidDateDoesNotAffectOtherFields(_ literal: String) throws {
    let snapshot = try parse(
      #""expires_at":\#(literal),"traffic_reset_at":"2026-10-04T00:00:00Z","bytes_used":0"#)
    #expect(snapshot.information.expiresAt == nil)
    #expect(snapshot.information.trafficResetAt == Date(timeIntervalSince1970: 1_791_072_000))
    #expect(snapshot.information.bytesUsed == 0)
  }

  @Test func rfc3339CaseOffsetsAndLeapSecondPreserveInstants() throws {
    let snapshot = try parse(
      #""expires_at":"2026-10-03t19:00:00-05:00","traffic_reset_at":"2016-12-31T23:59:60Z""#)
    #expect(snapshot.information.expiresAt == Date(timeIntervalSince1970: 1_791_072_000))
    #expect(snapshot.information.trafficResetAt == Date(timeIntervalSince1970: 1_483_228_800))
  }

  @Test func informationAndGroupingValidityAreIndependent() throws {
    let treeText = try #require(String(bytes: SubscriptionDocs.tree(), encoding: .utf8))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let validTree = try SubscriptionDocumentParser.parse(
      Data((treeText.dropLast() + #","bytes_used":25,"expires_at":123}"#).utf8),
      subscriptionID: .fresh())
    #expect(validTree.root.name == "Example subscription")
    #expect(validTree.information.bytesUsed == 25)
    #expect(validTree.information.expiresAt == nil)

    let invalidTree = try parse(#""bytes_remaining":75,"x_shadowsocksx_ng":{"schema_version":99}"#)
    #expect(invalidTree.root.name.isEmpty)
    #expect(invalidTree.information.bytesRemaining == 75)
  }

  @Test func onlyRootFieldsAreReadAcrossNestedEscapedAndUnrepresentableValues() throws {
    let snapshot = try SubscriptionDocumentParser.parse(
      Data(
        #"""
        {"version":1,"servers":[{"server":"203.0.113.7","server_port":8388,
        "password":"{\"bytes_used\":999},\\tail","method":"aes-256-gcm","bytes_remaining":999}],
        "ignored":1e999,"other":{"expires_at":"1970-01-01T00:00:00Z"},
        "bytes_\u0075sed":25,"bytes_remaining":75,"expires_at":"2026-10-04T00:00:00Z"}
        """#.utf8), subscriptionID: .fresh())
    #expect(snapshot.information.bytesUsed == 25)
    #expect(snapshot.information.bytesRemaining == 75)
    #expect(snapshot.information.expiresAt == Date(timeIntervalSince1970: 1_791_072_000))
    #expect(snapshot.root.children.count == 1)
  }

  @Test func utf8BOMPreservesValidSubscriptionInformation() throws {
    let data =
      Data([0xEF, 0xBB, 0xBF])
      + Data(#"{"version":1,"servers":[],"bytes_used":25,"bytes_remaining":75}"#.utf8)
    let snapshot = try SubscriptionDocumentParser.parse(data, subscriptionID: .fresh())
    #expect(snapshot.information.bytesUsed == 25)
    #expect(snapshot.information.bytesRemaining == 75)
  }

  private func parse(_ fields: String) throws -> SubscriptionSnapshot {
    try SubscriptionDocumentParser.parse(
      Data("{\"version\":1,\"servers\":[],\(fields)}".utf8), subscriptionID: .fresh())
  }

}
