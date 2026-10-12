import Combine
import Foundation

/// 生产运行时 adapter：现有 `ProxyRuntimeController` 与其系统代理
/// 观察机（`SystemProxyObserver`，ADR-0022 策略机）的唯一包装，由应用组合根
/// 接线。只把既有能力与观察投影到 workflow 缝上，不复制状态机、generation、
/// 健康门禁与系统代理生命周期语义。
@MainActor
final class ControllerProxyRuntimeAdapter: ProxyRuntimeAdapting {
  private let controller: ProxyRuntimeController

  init(controller: ProxyRuntimeController) {
    self.controller = controller
  }

  var runtimeFacts: ProxyRuntimeFacts { controller.runtimeFacts }

  var agentIntentEnabled: Bool { controller.agentIntentEnabled }

  var activationFailure: ActivationFailure? { controller.lastActivationFailure }

  var systemProxyIntentEnabled: Bool { controller.systemProxyIntentEnabled }

  var systemProxyApplication: SystemProxyApplicationFacts {
    controller.systemProxyState
  }

  var systemProxyInspection: SystemProxyInspectionFacts { controller.systemProxyInspection }

  var systemProxyApprovalRequired: Bool { controller.systemProxyApprovalRequired }

  var proxyMode: ProxyMode { controller.proxyMode }

  var ruleDefaultAction: RuleDefaultAction { controller.ruleDefaultAction }

  var skippedInvalidServerCount: Int { controller.skippedServers.count }

  var activeTargetID: NodeID? { controller.activeTargetID }

  var httpExportCapability: HTTPExportCapability {
    HTTPExportCapability(listen: controller.listenSettings)
  }

  var listenFacts: RuntimeListenFacts {
    RuntimeListenFacts(listen: controller.listenSettings)
  }

  /// 控制器与系统代理观察机各持一条 didChange 事实通道（同一主队列轮内多次
  /// 写合并为一次，冲洗晚于同步轮）：合并后交 workflow 整体重观察，不会读到
  /// 半程状态。系统代理呈现事实的存储与发布在观察机上，其通道并入同一链。
  var changes: AnyPublisher<Void, Never> {
    Publishers.Merge(
      controller.factChanges.changes,
      controller.systemProxyObserver.factChanges.changes
    )
    .eraseToAnyPublisher()
  }

  func resyncOnLaunch() async {
    await controller.resyncOnLaunch()
  }

  func setAgentEnabled(_ enabled: Bool) async {
    await controller.setAgentEnabled(enabled)
  }

  func setSystemProxyEnabled(_ enabled: Bool) async {
    await controller.setSystemProxyEnabled(enabled)
  }

  func openSystemProxyHelperApproval() async {
    await controller.systemProxyObserver.openSystemProxyHelperApproval()
  }

  func repairSystemProxy() async { await controller.systemProxyObserver.repairSystemProxy() }
  func retrySystemProxyClear() async {
    await controller.systemProxyObserver.retrySystemProxyClear()
  }
  func recheckSystemProxy() async { await controller.systemProxyObserver.recheckSystemProxy() }

  func setProxyMode(_ mode: ProxyMode) async {
    await controller.setProxyMode(mode)
  }

  func setRuleDefaultAction(_ action: RuleDefaultAction) async {
    await controller.setRuleDefaultAction(action)
  }
}

/// HTTP 导出能力的唯一派生点：监听设置 → 可复制的 http/https 双导出行。
/// 此导出行始终指向回环地址（与首页完整命令的命令地址选择无关）。
extension HTTPExportCapability {
  init(listen: SslocalListenSettings) {
    let urlHost = listen.proxyLoopbackURLHost
    let endpoint = "http://\(urlHost):\(listen.httpPort)"
    self.init(copyableLine: "export http_proxy=\(endpoint);export https_proxy=\(endpoint);")
  }
}

/// 终端代理环境变量命令的唯一派生点：已保存监听事实 + 生效
/// 命令地址 → 两种 shell 的可复制命令。HTTP/HTTPS 用已保存 HTTP 端口，
/// SOCKS 用已保存 SOCKS 端口；变量集合、小写变量名、单引号转义、socks5
/// 协议与 no_proxy 内容保持不变；IPv6 URL 使用方括号。
extension TerminalProxyEnvironmentCommands {
  init(listen: RuntimeListenFacts, commandAddress: TerminalCommandAddress) {
    let host = commandAddress.address
    let urlHost = host.contains(":") ? "[\(host)]" : host
    let httpEndpoint = "'http://\(urlHost):\(listen.httpPort)'"
    let socksEndpoint = "'socks5://\(urlHost):\(listen.socksPort)'"
    let noProxy = "'localhost,127.0.0.1,::1,.local'"
    let zshBash =
      [
        "export http_proxy=\(httpEndpoint)",
        "export https_proxy=\(httpEndpoint)",
        "export all_proxy=\(socksEndpoint)",
        "export no_proxy=\(noProxy)",
      ].joined(separator: "; ") + ";"
    let fish =
      [
        "set -gx http_proxy \(httpEndpoint)",
        "set -gx https_proxy \(httpEndpoint)",
        "set -gx all_proxy \(socksEndpoint)",
        "set -gx no_proxy \(noProxy)",
      ].joined(separator: "; ") + ";"
    self.init(
      zshBash: zshBash,
      fish: fish)
  }
}

extension SslocalListenSettings {
  fileprivate var proxyLoopbackURLHost: String {
    let host = listenerMode.proxyLoopbackAddress
    return host.contains(":") ? "[\(host)]" : host
  }
}

/// 目录侧唯一的目标事实出口（窄缝）：存在性 + 显示名路径摘要；
/// 完整目录树、订阅对象与凭据不出此接口。
extension CatalogWorkflow: ProxyTargetFactsReading {
  func activeTargetFacts(for targetID: NodeID?) -> ProxyActiveTargetFacts? {
    guard let targetID else { return nil }
    return ProxyActiveTargetFacts(id: targetID, pathSummary: tree.pathSummary(for: targetID))
  }
}
