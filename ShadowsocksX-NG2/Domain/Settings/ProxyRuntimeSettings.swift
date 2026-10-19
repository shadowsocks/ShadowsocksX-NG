import Foundation

/// 运行计算捕获的内存快照，不代表统一持久化文档。监听配置独立保存，
/// 控制偏好由各命令更新；代理启动前从此快照派生完整运行配置。
struct ProxyRuntimeSettings: Equatable, Sendable {
  static let defaultProxyExceptions = ""

  var listen: ProxyListeningConfiguration
  /// User-added system-proxy exceptions; these entries do not become ACL rules.
  var proxyExceptions: String
  /// The persisted current mode: the mode selector's choice survives GUI
  /// restarts. First run defaults to rule mode.
  var preferredMode: ProxyModeKind
  /// 规则模式子选项：未匹配默认动作，出厂「未匹配时代理」。
  var ruleDefaultAction: RuleDefaultAction
  /// 用户保存的代理服务意图，默认关闭，与当前运行健康状态独立。
  var agentEnabled: Bool
  /// 系统代理意图：默认关闭；与 agent 意图相互独立，开关关闭
  /// 关闭时清理匹配 NG2 端点的系统代理配置，不影响本地监听。
  var systemProxyEnabled: Bool

  init(
    listen: ProxyListeningConfiguration = ProxyListeningConfiguration(),
    proxyExceptions: String = ProxyRuntimeSettings.defaultProxyExceptions,
    preferredMode: ProxyModeKind = .rule,
    ruleDefaultAction: RuleDefaultAction = .proxyWhenUnmatched,
    agentEnabled: Bool = false,
    systemProxyEnabled: Bool = false
  ) {
    self.listen = listen
    self.proxyExceptions = proxyExceptions
    self.preferredMode = preferredMode
    self.ruleDefaultAction = ruleDefaultAction
    self.agentEnabled = agentEnabled
    self.systemProxyEnabled = systemProxyEnabled
  }

  init(listen: ProxyListeningConfiguration, preferences: ProxyControlPreferences) {
    self.init(
      listen: listen, proxyExceptions: preferences.proxyExceptions,
      preferredMode: preferences.preferredMode, ruleDefaultAction: preferences.ruleDefaultAction,
      agentEnabled: preferences.agentEnabled, systemProxyEnabled: preferences.systemProxyEnabled)
  }

  /// 系统代理的 ExceptionsList；输入顺序保留，重复项只保留第一次出现的值。
  var proxyExceptionList: [String] {
    var result: [String] = []
    var seen = Set<String>()
    for value in proxyExceptions.split(whereSeparator: { character in
      character == "," || character == "、" || character.isWhitespace
    }) {
      let item = String(value)
      let identity = item.lowercased()
      guard !item.isEmpty, seen.insert(identity).inserted else { continue }
      result.append(item)
    }
    return result
  }

  var validationErrors: [PortSettingError] {
    listen.portValidationErrors()
  }

}

struct RestoredProxyRuntimeSettings: Equatable {
  let settings: ProxyRuntimeSettings
  let unreadableError: ProxyListeningStoreError?
}
