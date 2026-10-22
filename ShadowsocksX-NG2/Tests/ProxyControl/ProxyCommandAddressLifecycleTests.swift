import Testing
import XCTest

@testable import ShadowsocksX_NG2

/// 选择生命周期与命令生成：两种 shell 共用选中地址（端口取已
/// 保存值、IPv6 方括号、no_proxy 不变）、会话保留与新会话重置、失效回退
/// （地址消失/监听方式切换/复制前刷新/枚举失败）与命令边界。
@MainActor
final class ProxyCommandAddressLifecycleTests: XCTestCase {
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

  private func setListenerMode(_ mode: ListenerMode) {
    runtime.listenFacts = RuntimeListenFacts(
      listenerMode: .disabled, socksPort: 11086, httpPort: 11087)
    runtime.listenFacts.lan.isEnabled = mode != .disabled
    if let lanMode = LANListenerMode(rawValue: mode.rawValue) {
      runtime.listenFacts.lan.mode = lanMode
    }
    runtime.emitChange()
  }

  func testSelectionDrivesBothShellsAndSavedPorts() {
    runtime.listenFacts = RuntimeListenFacts(
      listenerMode: .disabled, socksPort: 11086, httpPort: 11087)
    runtime.listenFacts.lan.isEnabled = true
    runtime.listenFacts.lan.mode = .allIPv4Interfaces
    runtime.listenFacts.lan.socksPort = 12086
    runtime.listenFacts.lan.httpPort = 12087
    runtime.emitChange()
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()

    let wifi = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(wifi)

    let commands = workflow.snapshot.terminalProxyEnvironmentCommands
    XCTAssertEqual(
      commands.zshBash,
      "export http_proxy='http://192.168.1.10:12087'; "
        + "export https_proxy='http://192.168.1.10:12087'; "
        + "export all_proxy='socks5://192.168.1.10:12086'; "
        + "export no_proxy='localhost,127.0.0.1,::1,.local';",
      "HTTP/HTTPS/SOCKS 端点共用选中地址，端口取已保存值，no_proxy 保持不变")
    XCTAssertEqual(
      commands.fish,
      "set -gx http_proxy 'http://192.168.1.10:12087'; "
        + "set -gx https_proxy 'http://192.168.1.10:12087'; "
        + "set -gx all_proxy 'socks5://192.168.1.10:12086'; "
        + "set -gx no_proxy 'localhost,127.0.0.1,::1,.local';",
      "fish 语法保持 set -gx 形式且端点共用同一地址")
    XCTAssertTrue(runtime.agentCommands.isEmpty, "命令选址不触发运行时命令")
    XCTAssertTrue(runtime.systemProxyCommands.isEmpty)
    XCTAssertTrue(runtime.modeCommands.isEmpty)
  }

  func testIPv6SelectionProducesBracketedURLs() {
    setListenerMode(.allIPv4AndIPv6Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(
        addresses: [.ipv6("2001:db8::1", flags: [.autoconf, .secured])])
    ]
    interfaceFacts.emitChange()

    let v6Candidate = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(v6Candidate)

    let commands = workflow.snapshot.terminalProxyEnvironmentCommands
    XCTAssertTrue(
      commands.zshBash.contains("export http_proxy='http://[2001:db8::1]:11089'"),
      "IPv6 URL 使用方括号与已保存 HTTP 端口")
    XCTAssertTrue(
      commands.fish.contains("set -gx all_proxy 'socks5://[2001:db8::1]:11088'"))
    XCTAssertFalse(
      commands.zshBash.contains("autoconf"), "类型注记只进标签，不进命令")
  }

  func testSelectionSurvivesLeavingAndReenteringHome() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()
    let wifi = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(wifi)

    _ = workflow.refreshTerminalCommands()  // 离开再进入首页

    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.selected.identity, wifi.identity,
      "同一会话内选择跨首页离开/返回保留")
  }

  func testNewSessionResetsSelectionToDefaultLoopback() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()
    let wifi = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(wifi)

    let freshWorkflow = ProxyControlWorkflow(
      runtime: runtime,
      targetFacts: FakeTargetFacts(),
      interfaceFacts: interfaceFacts)

    XCTAssertEqual(
      freshWorkflow.snapshot.commandAddressPicker.selected.address, "127.0.0.1",
      "新会话恢复默认回环地址，不沿用先前选择")
  }

  func testDisappearedAddressFallsBackToLoopback() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()
    let wifi = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(wifi)

    interfaceFacts.interfaces = []
    interfaceFacts.emitChange()

    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.selected.address, "127.0.0.1",
      "地址消失回退默认回环")
  }

  func testListenerModeSwitchToIncompatibleFamilyFallsBack() {
    setListenerMode(.allIPv4AndIPv6Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv6("2001:db8::1")])
    ]
    interfaceFacts.emitChange()
    let v6Candidate = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(v6Candidate)

    setListenerMode(.allIPv4Interfaces)

    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.selected.address, "127.0.0.1",
      "监听方式不再支持该地址族时回退")
    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.candidates.map(\.address),
      ["127.0.0.1"],
      "切换监听方式立即重新过滤候选")
  }

  func testEnumerationFailureKeepsLoopbackCandidatesAndCopy() {
    setListenerMode(.allIPv4Interfaces)
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()
    let wifi = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(wifi)

    interfaceFacts.interfaces = nil
    interfaceFacts.emitChange()

    let picker = workflow.snapshot.commandAddressPicker
    XCTAssertEqual(
      picker.candidates.map(\.address), ["127.0.0.1"], "枚举失败仅提供兼容回环候选")
    XCTAssertEqual(picker.selected.address, "127.0.0.1")
    XCTAssertTrue(
      workflow.snapshot.terminalProxyEnvironmentCommands.zshBash.contains("127.0.0.1"),
      "枚举失败仍可复制回环命令")
  }

  func testCopyPreparationRefreshesFallsBackAndMatchesProjection() {
    runtime.listenFacts = RuntimeListenFacts(
      listenerMode: .disabled, socksPort: 11086, httpPort: 11087)
    runtime.listenFacts.lan.isEnabled = true
    runtime.listenFacts.lan.mode = .allIPv4Interfaces
    runtime.emitChange()
    interfaceFacts.interfaces = [
      FakeLocalInterfaceFacts.wifi(addresses: [.ipv4("192.168.1.10")])
    ]
    interfaceFacts.emitChange()
    let wifi = workflow.snapshot.commandAddressPicker.candidates[1]
    _ = workflow.selectCommandAddress(wifi)

    // 复制前地址消失且变化通知丢失：复制前刷新发现失效。
    interfaceFacts.interfaces = []
    let prepared = workflow.refreshTerminalCommands()

    XCTAssertFalse(
      prepared.zshBash.contains("192.168.1.10"), "复制内容不包含已消失的地址")
    XCTAssertTrue(prepared.zshBash.contains("127.0.0.1"))
    XCTAssertEqual(
      prepared, workflow.snapshot.terminalProxyEnvironmentCommands,
      "复制前刷新产生的变化同步至提示投影")
    XCTAssertEqual(
      workflow.snapshot.commandAddressPicker.selected.address, "127.0.0.1",
      "回退结果更新界面选择")
  }

  func testProxyOffStillPreparesCommands() {
    setListenerMode(.allIPv4Interfaces)
    runtime.runtimeFacts = ProxyRuntimeFacts(status: .off, isOn: false)
    runtime.emitChange()

    let prepared = workflow.refreshTerminalCommands()

    XCTAssertTrue(prepared.zshBash.contains("127.0.0.1"), "代理未运行时命令仍可准备")
    XCTAssertEqual(runtime.resyncCount, 0, "刷新不触碰运行时生命周期")
  }
}
