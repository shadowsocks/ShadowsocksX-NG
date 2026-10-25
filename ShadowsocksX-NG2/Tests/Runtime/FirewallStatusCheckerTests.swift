import XCTest

@testable import ShadowsocksX_NG2

final class FirewallStatusCheckerTests: XCTestCase {
  func testGetAppBlockedOutputMapsToBlockedStatus() async {
    var capturedExecutable: URL?
    var capturedArguments: [String] = []
    let checker = SocketFilterFirewallChecker { executable, arguments in
      capturedExecutable = executable
      capturedArguments = arguments
      return "Incoming connection to /bundle/Helpers/sslocal is blocked.\n"
    }
    let target = URL(fileURLWithPath: "/bundle/Helpers/sslocal")

    let blocked = await checker.status(for: target)
    XCTAssertEqual(blocked, .blocked)
    XCTAssertEqual(
      capturedExecutable?.path,
      "/usr/libexec/ApplicationFirewall/socketfilterfw")
    XCTAssertEqual(capturedArguments, ["--getappblocked", target.path])
  }

  func testPermittedAndUnknownResultsDegradeWithoutFalseBlock() async {
    let permitted = SocketFilterFirewallChecker { _, _ in
      "Incoming connection to /bundle/Helpers/sslocal is permitted.\n"
    }
    let unavailable = SocketFilterFirewallChecker { _, _ in
      throw CocoaError(.fileNoSuchFile)
    }
    let target = URL(fileURLWithPath: "/bundle/Helpers/sslocal")

    let permittedStatus = await permitted.status(for: target)
    let unavailableStatus = await unavailable.status(for: target)
    XCTAssertEqual(permittedStatus, .permitted)
    XCTAssertEqual(unavailableStatus, .unknown)
  }
}
