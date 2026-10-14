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

  func terminalLANPassword() throws -> String {
    guard let raw = controller.listenSettings.lan.passwordReference,
      let password = try controller.credentials.secret(for: CredentialReference(rawValue: raw)),
      RuntimeListenerAuthentication.validPassword(password)
    else {
      throw TerminalCommandFailure.credentialUnreadable
    }
    return password
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
/// 命令地址 → 各种 shell 的可复制命令。HTTP/HTTPS 用已保存 HTTP 端口，
/// SOCKS 用已保存 SOCKS 端口；变量集合、小写变量名、socks5
/// 协议与 no_proxy 内容保持不变；IPv6 URL 使用方括号。
extension TerminalProxyEnvironmentCommands {
  init(
    listen: RuntimeListenFacts, commandAddress: TerminalCommandAddress,
    password: () throws -> String = { throw TerminalCommandFailure.credentialUnreadable }
  ) {
    let host = commandAddress.address
    let urlHost = host.contains(":") ? "[\(host)]" : host
    let isLAN = host != "127.0.0.1"
    let httpPort = isLAN ? listen.lan.httpPort : listen.httpPort
    let socksPort = isLAN ? listen.lan.socksPort : listen.socksPort
    var userInfo = ""
    if isLAN && listen.lan.authenticationEnabled {
      do {
        let secret = try password()
        guard RuntimeListenerAuthentication.validUsername(listen.lan.username),
          RuntimeListenerAuthentication.validPassword(secret)
        else {
          throw TerminalCommandFailure.credentialUnreadable
        }
        let allowed = CharacterSet(
          charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard
          let username = listen.lan.username.addingPercentEncoding(withAllowedCharacters: allowed),
          let encodedPassword = secret.addingPercentEncoding(withAllowedCharacters: allowed)
        else {
          throw TerminalCommandFailure.credentialUnreadable
        }
        userInfo = "\(username):\(encodedPassword)@"
      } catch {
        self.init(
          zshBash: "", fish: "", nushell: "", windowsCMD: "", windowsPowerShell: "",
          failure: .credentialUnreadable)
        return
      }
    }
    let httpEndpoint = "http://\(userInfo)\(urlHost):\(httpPort)"
    let socksEndpoint = "socks5://\(userInfo)\(urlHost):\(socksPort)"
    let variables = [
      (name: "http_proxy", value: httpEndpoint),
      (name: "https_proxy", value: httpEndpoint),
      (name: "all_proxy", value: socksEndpoint),
      (name: "no_proxy", value: "localhost,127.0.0.1,::1,.local"),
    ]
    let windowsAssignments = variables.map { "set \"\($0.name)=\($0.value)\"" }
    // CMD 会把 %XX% 当作环境变量展开。用交互 FOR 变量插入字面百分号，
    // 不写临时环境变量；逐行赋值使最长允许凭据仍不超过单行长度限制。
    let windowsCMD =
      userInfo.contains("%")
      ? windowsAssignments.map { assignment in
        assignment.contains("%")
          ? "for %P in (\"%\") do \(assignment.replacingOccurrences(of: "%", with: "%~P"))"
          : assignment
      }.joined(separator: "\r\n")
      : windowsAssignments.joined(separator: " & ")
    self.init(
      zshBash: variables.map { "export \($0.name)='\($0.value)'" }.joined(separator: "; ") + ";",
      fish: variables.map { "set -gx \($0.name) '\($0.value)'" }.joined(separator: "; ") + ";",
      nushell: variables.map { "$env.\($0.name) = '\($0.value)'" }.joined(separator: "; ") + ";",
      windowsCMD: windowsCMD,
      windowsPowerShell:
        variables.map { "$env:\($0.name) = '\($0.value)'" }.joined(separator: "; ") + ";")
  }
}

extension SslocalListenSettings {
  fileprivate var proxyLoopbackURLHost: String {
    let host = "127.0.0.1"
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
