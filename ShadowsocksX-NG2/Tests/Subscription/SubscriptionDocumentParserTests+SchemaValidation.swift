import XCTest

@testable import ShadowsocksX_NG2

extension SubscriptionDocumentParserTests {
  // MARK: schema 与记录校验失败（整份拒绝）

  func testUnsupportedVersionThrows() {
    let data = Data(#"{"version": 2, "servers": []}"#.utf8)

    XCTAssertThrowsError(try parse(data)) { error in
      XCTAssertEqual(error as? SubscriptionParseError, .unsupportedSchemaVersion)
    }
  }

  func testMissingVersionThrows() {
    XCTAssertThrowsError(try parse(Data(#"{"servers": []}"#.utf8))) { error in
      XCTAssertEqual(error as? SubscriptionParseError, .unsupportedSchemaVersion)
    }
  }

  func testMissingServersThrows() {
    XCTAssertThrowsError(try parse(Data(#"{"version": 1}"#.utf8))) { error in
      XCTAssertEqual(error as? SubscriptionParseError, .missingServers)
    }
  }

  func testMalformedJSONThrowsDecodingFailure() {
    XCTAssertThrowsError(try parse(Data(#"{"version": 1, "servers": ["#.utf8))) { error in
      XCTAssertEqual(error as? SubscriptionParseError, .decodingFailure)
    }
  }

  func testServersNotAnArrayThrowsDecodingFailure() {
    XCTAssertThrowsError(try parse(Data(#"{"version": 1, "servers": "nope"}"#.utf8))) { error in
      XCTAssertEqual(error as? SubscriptionParseError, .decodingFailure)
    }
  }

  func testRecordValidationFailuresThrowWithIndex() {
    let cases: [(String, String)] = [
      (#"{"server": "h", "server_port": 8388, "password": "p"}"#, "method"),
      (#"{"server": "h", "server_port": 8388, "method": "m"}"#, "password"),
      (#"{"server_port": 8388, "password": "p", "method": "m"}"#, "server"),
      (#"{"server": "", "server_port": 8388, "password": "p", "method": "m"}"#, "server"),
      (#"{"server": "h", "server_port": 0, "password": "p", "method": "m"}"#, "server_port"),
      (#"{"server": "h", "server_port": 65536, "password": "p", "method": "m"}"#, "server_port"),
      (#"{"server": "h", "server_port": 8388, "password": "", "method": "m"}"#, "password"),
      (
        #"{"id": "not-a-uuid", "server": "h", "server_port": 8388, "password": "p", "method": "m"}"#,
        "id",
      ),
    ]
    for (record, expectedField) in cases {
      let data = Data("{\"version\": 1, \"servers\": [\(record)]}".utf8)
      XCTAssertThrowsError(try parse(data), expectedField) { error in
        guard case .recordValidation(let index, let reason) = error as? SubscriptionParseError
        else {
          return XCTFail("\(expectedField): 应报 recordValidation，实际 \(error)")
        }
        XCTAssertEqual(index, 0)
        XCTAssertTrue(reason.contains(expectedField), "\(expectedField): \(reason)")
      }
    }
  }

  func testDuplicateServerIDThrows() {
    let data = Data(
      """
      {"version": 1, "servers": [
        {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "server": "203.0.113.1", "server_port": 8388,
         "password": "p", "method": "m"},
        {"id": "aaaaaaaa-0000-4000-8000-00000000000a", "server": "203.0.113.9", "server_port": 9999,
         "password": "q", "method": "n"}]}
      """.utf8)

    XCTAssertThrowsError(try parse(data)) { error in
      XCTAssertEqual(
        error as? SubscriptionParseError,
        .duplicateServerID(id: "id:aaaaaaaa-0000-4000-8000-00000000000a"))
    }
  }

  func testIdenticalIdLessRecordsAreDuplicateIdentity() {
    let record =
      #"{"server": "203.0.113.1", "server_port": 8388, "password": "p", "method": "m"}"#
    let data = Data("{\"version\": 1, \"servers\": [\(record), \(record)]}".utf8)

    XCTAssertThrowsError(try parse(data)) { error in
      guard case .duplicateServerID(let id) = error as? SubscriptionParseError else {
        return XCTFail("应报 duplicateServerID，实际 \(error)")
      }
      XCTAssertTrue(id.hasPrefix("content:"), "无稳定 ID 用内容指纹判重")
    }
  }
}
