import Foundation

// MARK: - 只读事实投影与静态缝

extension ProxyRuntimeController {
  var isActiveTargetPresent: Bool { machine.activeTargetID != nil }

  /// Agent 开关意图（持久化事实；开关 UI 的绑定来源）。
  var agentIntentEnabled: Bool { settings.agentEnabled }

  /// 系统代理开关意图（持久化事实；开关 UI 的绑定来源）。
  var systemProxyIntentEnabled: Bool { settings.systemProxyEnabled }

  /// 系统代理观察机的呈现事实门面：存储与发布在 `SystemProxyObserver`，
  /// 此处只读投影供既有测试与诊断面沿用原名。
  var systemProxyState: SystemProxyApplicationFacts { systemProxyObserver.systemProxyState }
  var systemProxyApprovalRequired: Bool { systemProxyObserver.systemProxyApprovalRequired }
  var systemProxyInspection: SystemProxyInspectionFacts {
    systemProxyObserver.systemProxyInspection
  }

  /// Desired system proxy configuration：当前保存设置要求的代理值（ADR-0022）。
  /// 观察机经 init 闭包读取同一事实源。`nil` 只表示尚无运行时文档。
  var desiredSystemProxyConfiguration: SystemProxyConfiguration? {
    guard let document = lastDocument else { return nil }
    return proxyMode.systemProxyConfiguration(
      for: document, exceptions: settings.proxyExceptionList)
  }

  /// Stable app-facing projection for status-menu presentation. The menu does
  /// not depend on this controller's nested state representation.
  var runtimeFacts: ProxyRuntimeFacts {
    let facts = ProxyRuntimeFacts(state: state)
    return ProxyRuntimeFacts(
      status: facts.status, isOn: facts.isOn,
      failure: facts.failure
        ?? (proxyMode == .rule && settings.agentEnabled ? ruleApplicationFailure : nil))
  }

  static var defaultFirewallExecutableURLs: [URL] {
    let bundle = Bundle.main.bundleURL
    return [
      bundle.appendingPathComponent("Contents/MacOS/ShadowsocksX-NG2Agent"),
      bundle.appendingPathComponent("Contents/Helpers/sslocal"),
    ]
  }

  /// 诊断只读面：当前监听设置；监听地址在导出中只以回环/非回环
  /// 两态呈现。
  var listenSettings: ProxyListeningConfiguration { settings.listen }

  /// 当前已部署 runtime 的完整监听身份。已停止或启动失败时没有有效的
  /// runtime 例外，不能拿最后一次设置快照冒充仍在监听。
  var effectiveRuntimeListenFacts: RuntimeListenFacts? {
    let isListening: Bool
    switch state {
    case .running, .firewallBlocked:
      isListening = true
    case .off, .starting, .launchFailed, .requiresApproval, .serviceFailed:
      isListening = false
    }
    guard isListening, let lastDocument else { return nil }
    return RuntimeListenFacts(document: lastDocument)
  }

  /// PID of the sslocal child that owns the active runtime document. A process
  /// name alone is not sufficient to treat an occupied listener as replaceable.
  var effectiveRuntimeListenerProcessID: Int32? {
    guard effectiveRuntimeListenFacts != nil,
      let lastDocument,
      let receipt = runtimeFileStore.readRuntimeReceipt(),
      receipt.deploymentID == runtimeFileStore.receiptIdentity(for: lastDocument),
      processIsAlive(receipt.processID)
    else { return nil }
    return receipt.processID
  }

  /// 运行时契约的脱敏摘要（数量与协议元数据）；契约缺失或无效返回 nil。
  /// 诊断导出不读契约内容，只携带此摘要。
  func runtimeDocumentSummary() -> String? {
    runtimeFileStore.loadDocument().map { Redactor.documentSummary($0) }
  }
}

extension ProxyRuntimeController.AgentRunState {
  /// Agent 运行状态的「在跑」投影（状态摘要与诊断口径）：启动失败等未运行
  /// 态视为未跑。
  var isOn: Bool {
    switch self {
    case .off, .launchFailed, .serviceFailed:
      false
    case .starting, .running, .firewallBlocked, .requiresApproval:
      true
    }
  }
}

extension ProxyRuntimeController: Activating {}

extension ProxyRuntimeController {
  static func makeProxyMode(from settings: ProxyRuntimeSettings) -> ProxyMode {
    ProxyMode.availableModes.first { $0.kind == settings.preferredMode } ?? .rule
  }
}
