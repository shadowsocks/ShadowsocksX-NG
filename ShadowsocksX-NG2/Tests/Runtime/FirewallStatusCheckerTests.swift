import XCTest

@testable import ShadowsocksX_NG2

final class FirewallStatusCheckerTests: XCTestCase {
  func testGetAppBlockedOutputMapsToBlockedStatus() {
    var capturedExecutable: URL?
    var capturedArguments: [String] = []
    let checker = SocketFilterFirewallChecker { executable, arguments in
      capturedExecutable = executable
      capturedArguments = arguments
      return "Incoming connection to /bundle/Helpers/sslocal is blocked.\n"
    }
    let target = URL(fileURLWithPath: "/bundle/Helpers/sslocal")

    XCTAssertEqual(checker.status(for: target), .blocked)
    XCTAssertEqual(
      capturedExecutable?.path,
      "/usr/libexec/ApplicationFirewall/socketfilterfw")
    XCTAssertEqual(capturedArguments, ["--getappblocked", target.path])
  }

  func testPermittedAndUnknownResultsDegradeWithoutFalseBlock() {
    let permitted = SocketFilterFirewallChecker { _, _ in
      "Incoming connection to /bundle/Helpers/sslocal is permitted.\n"
    }
    let unavailable = SocketFilterFirewallChecker { _, _ in
      throw CocoaError(.fileNoSuchFile)
    }
    let target = URL(fileURLWithPath: "/bundle/Helpers/sslocal")

    XCTAssertEqual(permitted.status(for: target), .permitted)
    XCTAssertEqual(unavailable.status(for: target), .unknown)
  }
}
