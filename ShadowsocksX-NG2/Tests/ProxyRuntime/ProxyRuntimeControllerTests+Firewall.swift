import Combine
import XCTest

@testable import ShadowsocksX_NG2

final class ProxyRuntimeFirewallTests: ProxyRuntimeControllerTests {
  override func makeDefaultRuleSnapshots() -> BuiltinRuleSnapshots {
    BuiltinRuleSnapshots(loader: ProxyRuntimeFixture.controlFlowRuleSnapshot)
  }

  func testLocalhostModeNeverQueriesApplicationFirewall() async throws {
    let seeded = try makeSeededCatalog()
    let firewall = ProxyRuntimeFixture.FakeFirewallChecker(.blocked)
    var listen = SslocalListenSettings()
    listen.lan.mode = .allIPv6Interfaces
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(), listen: listen, firewallChecker: firewall)

    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    XCTAssertEqual(controller.state, .running)
    XCTAssertTrue(firewall.checkedURLs.isEmpty, "回环态与应用防火墙零交互")
    XCTAssertEqual(controller.effectiveRuntimeListenFacts?.lan.isEnabled, false)
    XCTAssertEqual(controller.effectiveRuntimeListenFacts?.lan.mode, .allIPv6Interfaces)
  }

  func testAllIPv4InterfacesBlockedByFirewallPresentsTargetedRepair() async throws {
    let seeded = try makeSeededCatalog()
    let firewall = ProxyRuntimeFixture.FakeFirewallChecker(.blocked)
    let listen = SslocalListenSettings(
      listenerMode: .allIPv4Interfaces,
      socksPort: 1086,
      httpPort: 1087)
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listen: listen,
      firewallChecker: firewall)

    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    guard case .firewallBlocked(let facts) = controller.state else {
      XCTFail("主机态被拒应呈现防火墙状态，实际 \(controller.state)")
      return
    }
    XCTAssertEqual(facts.executableName, "sslocal")
    XCTAssertTrue(
      AppPresentation.message(for: RuntimeFailureFacts.firewallBlocked(facts)).contains("允许传入连接"))
    XCTAssertEqual(firewall.checkedURLs.map(\.lastPathComponent), ["sslocal"])
    XCTAssertEqual(
      controller.effectiveRuntimeListenFacts?.lan.mode,
      .allIPv4Interfaces)
  }

  func testAllInterfaceModeDetectsFirewallRefusalAfterInitialHealthyPresentation() async throws {
    let seeded = try makeSeededCatalog()
    let firewall = ProxyRuntimeFixture.FakeFirewallChecker(outcomes: [.permitted, .blocked])
    let listen = SslocalListenSettings(listenerMode: .allIPv4Interfaces)
    let controller = makeController(
      probe: ProxyRuntimeFixture.FakeProbe.reachable(),
      listen: listen,
      firewallChecker: firewall)

    try await controller.activate(seeded.server)
    await controller.setAgentEnabled(true)

    let deadline = Date().addingTimeInterval(1)
    while controller.state == .running && Date() < deadline {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    guard case .firewallBlocked(let facts) = controller.state else {
      XCTFail("稍后发生的拒绝也必须被检测，实际 \(controller.state)")
      return
    }
    XCTAssertEqual(facts.executableName, "sslocal")
    XCTAssertTrue(
      AppPresentation.message(for: RuntimeFailureFacts.firewallBlocked(facts)).contains("允许传入连接"))
    XCTAssertGreaterThanOrEqual(firewall.checkedURLs.count, 2)
  }
}
