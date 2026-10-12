import XCTest

@testable import ShadowsocksX_NG2

/// Presentation edge coverage: typed facts are asserted independently from the
/// wording owned by the App layer, and unknown descriptions never leak through.
final class AppPresentationTests: XCTestCase {
  func testSubscriptionFailureFactsAllHaveSafePresentation() {
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
      .recordValidation(index: 2, field: .address),
      .recordValidation(index: 2, field: .port),
      .recordValidation(index: 2, field: .method),
      .recordValidation(index: 2, field: .password),
      .recordValidation(index: 2, field: .identity),
      .duplicateIdentity,
      .credential(category: .missing),
      .credential(category: .read),
      .credential(category: .write),
      .commit(category: .persistence, rollback: .notNeeded),
      .commit(category: .persistence, rollback: .restored),
      .commit(category: .persistence, rollback: .incomplete),
      .commit(category: .credentials, rollback: .notNeeded),
      .commit(category: .credentials, rollback: .restored),
      .commit(category: .credentials, rollback: .incomplete),
      .legacy,
      .unknown,
    ]

    for failure in failures {
      let message = AppPresentation.message(for: failure)
      XCTAssertFalse(message.isEmpty, "每个 durable failure fact 都应有呈现：\(failure)")
      XCTAssertFalse(message.contains("https://"))
      XCTAssertFalse(message.contains("credential"))
      XCTAssertFalse(message.contains("reference"))
    }

    XCTAssertTrue(
      AppPresentation.message(
        for: .commit(category: .credentials, rollback: .incomplete)
      )
      .contains("恢复不完整"))
  }

  func testRuntimeAndSettingsFactsUseCentralPresentation() {
    // 系统代理应用状态：独立状态面同样走中央呈现。
    let systemProxyApplications: [SystemProxyApplicationFacts] = [
      .idle,
      .pending,
      .applied,
      .failed(.operation(.applyFailed)),
      .failed(.mode(.invalidSOCKSPort(0))),
      .failed(.operation(.helperUnavailable)),
      .failed(.unknown),
    ]
    for application in systemProxyApplications {
      let message = AppPresentation.message(for: application)
      XCTAssertFalse(message.isEmpty, "每个系统代理应用态都应有呈现：\(application)")
    }

    let runtimeFailures: [RuntimeFailureFacts] = [
      .firewallBlocked(FirewallBlockedFacts(executableName: "sslocal")),
      .launch(
        .localEndpoint(endpoint: "SOCKS", host: "127.0.0.1", port: 11086, cause: .refused)),
      .launch(.missingRuntimeDocument),
      .launch(.unreadableSettings),
      .service(.runtimeFile),
      .service(.agent),
      .service(.missingDocument),
      .service(.persistence),
      .service(.unknown),
      .requiresApproval,
    ]
    for failure in runtimeFailures {
      XCTAssertFalse(
        AppPresentation.message(for: failure).isEmpty,
        "每个 typed runtime failure fact 都应有呈现：\(failure)")
    }

    let issues: [SettingsFieldIssue] = [
      .port(.socks, error: .portOutOfRange(endpoint: .socks, port: 0))
    ]
    for issue in issues {
      XCTAssertFalse(AppPresentation.message(for: issue).isEmpty)
    }
  }

  func testUnknownErrorUsesFixedFallback() {
    struct SecretError: Error, CustomStringConvertible {
      var description: String { "secret-token https://provider.example/sub.json" }
    }

    XCTAssertEqual(AppPresentation.message(for: SecretError()), AppPresentation.unknownError)
  }

  func testPlatformEffectFailuresHaveStableSafePresentation() {
    let failures: [Error] = [
      TextClipboardFailure.writeFailed,
      DiagnosticReportFailure.encodingFailed,
      DiagnosticReportExportFailure.writeFailed,
    ]

    for failure in failures {
      let message = AppPresentation.message(for: failure)
      XCTAssertFalse(message.isEmpty, "平台 effect failure 必须有安全呈现：\(failure)")
      XCTAssertFalse(message.contains("secret"))
      XCTAssertFalse(message.contains("/Users/"))
    }
  }
}
