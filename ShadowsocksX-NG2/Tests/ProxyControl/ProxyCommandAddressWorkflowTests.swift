import Testing
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
struct LANCommandEnablementTests {
  @Test(arguments: [false, true])
  func copyRejectsLostIPIncludingAButtonRenderedBeforeNetworkNotification(
    notificationDelivered: Bool
  ) {
    let runtime = FakeProxyRuntime()
    let interfaces = FakeLocalInterfaceFacts()
    runtime.listenFacts.lan.isEnabled = true
    interfaces.interfaces = [FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.0.2.2")])]
    let workflow = ProxyControlWorkflow(
      runtime: runtime, targetFacts: FakeTargetFacts(), interfaceFacts: interfaces)
    let address = workflow.snapshot.commandAddressPicker.candidates[1]
    workflow.selectCommandAddress(address)
    interfaces.interfaces = []
    if notificationDelivered { interfaces.emitChange() }
    #expect(throws: TerminalCommandFailure.addressUnavailable) {
      try workflow.prepareTerminalCommandsForCopy(expectedAddress: address.identity)
    }
    #expect(workflow.snapshot.commandAddressPicker.selected.address == "127.0.0.1")
    #expect(workflow.snapshot.terminalCommandShells == [.zshBash, .fish, .nushell])
    #expect(runtime.agentCommands.isEmpty)
    #expect(runtime.systemProxyCommands.isEmpty)
  }

  @Test func windowsFormatsRequireEnabledLANAndSelectedNetworkIPWithoutRequiringRunningProxy() {
    let runtime = FakeProxyRuntime()
    let interfaces = FakeLocalInterfaceFacts()
    let workflow = ProxyControlWorkflow(
      runtime: runtime, targetFacts: FakeTargetFacts(), interfaceFacts: interfaces)
    #expect(workflow.snapshot.terminalCommandShells == [.zshBash, .fish, .nushell])
    runtime.listenFacts.lan.isEnabled = true
    interfaces.interfaces = [FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.0.2.2")])]
    runtime.emitChange()
    #expect(workflow.snapshot.terminalCommandShells == [.zshBash, .fish, .nushell])
    workflow.selectCommandAddress(workflow.snapshot.commandAddressPicker.candidates[1])
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .off, isOn: false)
    runtime.emitChange()
    #expect(
      workflow.snapshot.terminalCommandShells == [
        .zshBash, .fish, .nushell, .windowsCMD, .windowsPowerShell,
      ])
    runtime.listenFacts.lan.isEnabled = false
    runtime.emitChange()
    #expect(workflow.snapshot.terminalCommandShells == [.zshBash, .fish, .nushell])
    #expect(runtime.agentCommands.isEmpty)
    #expect(runtime.systemProxyCommands.isEmpty)
  }

  @Test func disablingLANRetainsIPv6ModeAndFallsBackFromSelectedNetworkAddress() {
    let runtime = FakeProxyRuntime()
    let interfaces = FakeLocalInterfaceFacts()
    let workflow = ProxyControlWorkflow(
      runtime: runtime, targetFacts: FakeTargetFacts(), interfaceFacts: interfaces)
    runtime.listenFacts.lan.isEnabled = true
    runtime.listenFacts.lan.mode = .allIPv6Interfaces
    interfaces.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv6("2001:db8::1")])
    ]
    runtime.emitChange()
    let address = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(address)
    #expect(workflow.snapshot.commandAddressPicker.selected.address == "2001:db8::1")
    runtime.listenFacts.lan.isEnabled = false
    runtime.emitChange()
    #expect(runtime.listenFacts.lan.mode == .allIPv6Interfaces)
    let picker = workflow.snapshot.commandAddressPicker
    #expect(!picker.isVisible)
    #expect(picker.candidates.map(\.address) == ["127.0.0.1"])
    #expect(picker.selected.address == "127.0.0.1")
    #expect(
      workflow.snapshot.terminalProxyEnvironmentCommands.zshBash.contains("http://127.0.0.1:11087"))
  }
}

/// 首页命令地址选择器 contract。候选派生：启用状态与三种监听方式的地址族
/// 过滤与默认值、严格接口类型过滤、名称回退、排序合并与网络变化刷新。选择
/// 生命周期与命令生成见 `ProxyCommandAddressLifecycleTests`。复用
/// ProxyControlWorkflowTests 的可编程替身。
@MainActor
final class ProxyCommandAddressWorkflowTests: XCTestCase {
  private var runtime: FakeProxyRuntime!
  private var interfaceFacts: FakeLocalInterfaceFacts!
  private var workflow: ProxyControlWorkflow!

  override func setUp() async throws {
    try await super.setUp()
    runtime = FakeProxyRuntime()
    interfaceFacts = FakeLocalInterfaceFacts()
    workflow = ProxyControlWorkflow(
      runtime: runtime, targetFacts: FakeTargetFacts(), interfaceFacts: interfaceFacts)
  }

  /// 把已保存监听事实切到指定方式并触发重观察。
  private func setListenerMode(_ mode: ListenerMode) {
    runtime.listenFacts = RuntimeListenFacts(
      listenerMode: .disabled, socksPort: 11086, httpPort: 11087)
    runtime.listenFacts.lan.isEnabled = mode != .disabled
    if let lanMode = LANListenerMode(rawValue: mode.rawValue) {
      runtime.listenFacts.lan.mode = lanMode
    }
    runtime.emitChange()
  }

  func testLocalhostModeHidesPickerWithLoopbackOnlyCandidates() {
    setListenerMode(.disabled)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")]),
      FakeLocalInterfaceFacts.loopback(),
    ]
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertFalse(picker.isVisible, "仅本机监听方式隐藏下拉框")
    XCTAssertEqual(
      picker.candidates,
      [TerminalCommandAddress(bsdName: "lo0", address: "127.0.0.1", displayName: "lo0")],
      "仅本机方式候选只有 IPv4 回环")
    XCTAssertEqual(picker.selected.address, "127.0.0.1")
  }

  func testIPv4ModeFiltersFamiliesAndAllowedInterfaceTypes() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(
        addresses: [.ipv4("192.168.1.10"), .ipv6("2001:db8::1"), .ipv6("fe80::1", linkLocal: true)]
      ),
      FakeLocalInterfaceFacts.ethernet(addresses: [.ipv4("10.0.0.5")]),
      FakeLocalInterfaceFacts.vpn(),
      FakeLocalInterfaceFacts.virtual(),
      FakeLocalInterfaceFacts.loopback(),
    ]
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertTrue(picker.isVisible)
    XCTAssertEqual(
      picker.candidates.map(\.address),
      ["127.0.0.1", "10.0.0.5", "192.168.1.10"],
      "回环置顶，其余按接口名称排序；IPv6、VPN、其他类型与回环事实不进候选")
    XCTAssertEqual(picker.selected.address, "127.0.0.1", "默认兼容回环地址")
  }

  func testDualStackModeIncludesBothLoopbacksAndBothFamilies() {
    setListenerMode(.allIPv4AndIPv6Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(
        addresses: [
          .ipv6("2001:db8::1"), .ipv4("192.168.1.10"), .ipv4("169.254.9.9"),
          .ipv6("fe80::1", linkLocal: true),
        ])
    ]
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertEqual(
      picker.candidates.map(\.address),
      ["127.0.0.1", "169.254.9.9", "192.168.1.10", "2001:db8::1"],
      "双栈提供两个回环（127.0.0.1 在前）、允许 IPv4 链路本地、排除 IPv6 链路本地，同接口 IPv4 先于 IPv6")
    XCTAssertEqual(picker.selected.address, "127.0.0.1")
  }

  func testTemporaryIPv6ExcludedAndAnnotationsKeptAsSeparateFacts() {
    setListenerMode(.allIPv4AndIPv6Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(
        addresses: [
          .ipv6("240e::8150", flags: [.autoconf, .secured]),
          .ipv6("240e::855", flags: [.autoconf, .temporary]),
          .ipv6("240e::17", flags: [.dynamic]),
        ])
    ]
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertEqual(
      picker.candidates.map(\.address),
      ["127.0.0.1", "240e::17", "240e::8150"],
      "RFC 4941 隐私临时地址被过滤（会轮换）；其余按地址稳定排序")
    let secured = picker.candidates.first { $0.address == "240e::8150" }
    XCTAssertEqual(secured?.displayName, "Wi-Fi")
    XCTAssertEqual(secured?.annotation, "autoconf secured", "注记作为独立呈现事实")
    XCTAssertEqual(
      picker.candidates.first { $0.address == "240e::17" }?.annotation,
      "dynamic", "DHCPv6 地址注记 dynamic")
  }

  func testIPv6OnlyModeDefaultsToV1AndFiltersFamilies() {
    setListenerMode(.allIPv6Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(
        addresses: [.ipv4("192.168.1.10"), .ipv6("2001:db8::1")])
    ]
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertEqual(
      picker.candidates.map(\.address), ["127.0.0.1", "2001:db8::1"],
      "仅 IPv6 方式默认 ::1 且候选只有 IPv6")
    XCTAssertEqual(picker.selected.address, "127.0.0.1")
  }

  func testDisplayNamesUseLocalizedNameWithBSDNameFallback() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(localizedName: "Wi-Fi", addresses: [.ipv4("192.168.1.10")]),
      FakeLocalInterfaceFacts.ethernet(localizedName: nil, addresses: [.ipv4("10.0.0.5")]),
    ]
    interfaceFacts.emitChange()

    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.candidates.map(\.displayName),
      ["lo0", "en1", "Wi-Fi"],
      "名称缺失回退 BSD 名，回环显示 lo0")
  }

  func testSameInterfaceDuplicateIPMergesAcrossInterfacesKept() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(
        localizedName: "Wi-Fi",
        addresses: [.ipv4("192.168.1.10"), .ipv4("192.168.1.10")]),
      FakeLocalInterfaceFacts.ethernet(
        bsdName: "en2", localizedName: "Ethernet 2", addresses: [.ipv4("192.168.1.10")]),
    ]
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertEqual(
      picker.candidates.map(\.identity),
      [
        TerminalCommandAddressIdentity(bsdName: "lo0", address: "127.0.0.1"),
        TerminalCommandAddressIdentity(bsdName: "en2", address: "192.168.1.10"),
        TerminalCommandAddressIdentity(bsdName: "en0", address: "192.168.1.10"),
      ],
      "同接口重复 IP 合并；不同接口同 IP 保留接口身份")
  }

  func testInterfaceChangeNotificationRepublishesCandidates() {
    setListenerMode(.allIPv4Interfaces)

    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()

    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.candidates.map(\.address),
      ["127.0.0.1", "192.168.1.10"], "接口事实变化后候选随网络刷新")
  }
}
