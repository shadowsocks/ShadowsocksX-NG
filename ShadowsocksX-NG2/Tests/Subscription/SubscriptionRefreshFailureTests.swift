import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 订阅刷新失败的 durable seam：只观察可演进的安全事实，不观察文案或
/// transient Error 的实现细节。
final class SubscriptionRefreshFailureTests: XCTestCase {
  func testAllDurableFailureFactsRoundTrip() throws {
    let failures: [SubscriptionRefreshFailure] = [
      .invalidURL,
      .unsupportedScheme,
      .insecureRedirect,
      .transport(.timedOut),
      .transport(.tls),
      .transport(.connection),
      .transport(.unknown),
      .httpStatus(code: 503),
      .contentType(.missing),
      .contentType(.unsupported),
      .decodingFailure,
      .unsupportedSchemaVersion,
      .missingServers,
      .recordValidation(index: 3, field: .address),
      .recordValidation(index: 3, field: .port),
      .recordValidation(index: 3, field: .method),
      .recordValidation(index: 3, field: .password),
      .recordValidation(index: 3, field: .identity),
      .duplicateIdentity,
      .commit,
      .unknown,
    ]

    for failure in failures {
      let data = try JSONEncoder().encode(failure)
      XCTAssertEqual(try JSONDecoder().decode(SubscriptionRefreshFailure.self, from: data), failure)
    }
  }

  func testHTTPStatusFailurePayloadOmitsInternalReason() throws {
    let failure = SubscriptionRefreshFailure.httpStatus(code: 503)

    let data = try JSONEncoder().encode(failure)

    let json = String(bytes: data, encoding: .utf8) ?? ""
    XCTAssertFalse(json.contains("reason"))
  }

  func testPartialRollbackIsCoarseAndContainsNoCredentialReferences() throws {
    let failure = SubscriptionRefreshFailure.commit

    let data = try JSONEncoder().encode(failure)

    let json = String(bytes: data, encoding: .utf8) ?? ""
    XCTAssertFalse(json.contains("credential"))
    XCTAssertFalse(json.contains("reference"))
  }

}
