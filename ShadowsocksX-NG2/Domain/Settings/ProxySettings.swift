import Foundation

/// 用户偏好快照。监听端点仍是运行时契约的输入，但不会把偏好文件
/// 当作运行时文件使用；代理启动前由控制器从快照重新派生完整契约。
struct ProxySettings: Equatable, Sendable {
  static let defaultProxyExceptions = ""

  var listen: SslocalListenSettings
  /// User-added system-proxy exceptions; these entries do not become ACL rules.
  var proxyExceptions: String
  /// The persisted current mode: the mode selector's choice survives GUI
  /// restarts. First run defaults to rule mode.
  var preferredMode: ProxyModeKind
  /// 规则模式子选项：未匹配默认动作，出厂「未匹配时代理」。
  var ruleDefaultAction: RuleDefaultAction
  /// 代理 agent 意图（ADR-0011）：默认关闭——全新用户没有服务器
  /// 配置，默认启动没有意义；用户显式打开的选择持久化，且偏好重置不改变它。
  var agentEnabled: Bool
  /// 系统代理意图：默认关闭；与 agent 意图相互独立，开关关闭
  /// 关闭时清理匹配 NG2 端点的系统代理配置，不影响本地监听。
  var systemProxyEnabled: Bool

  init(
    listen: SslocalListenSettings = SslocalListenSettings(),
    proxyExceptions: String = ProxySettings.defaultProxyExceptions,
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

  /// 持久化强制点：整快照端口互异，且身份验证启用时凭据形状有效、密码引用存在。
  /// 身份验证关闭时凭据是保留值，不是保存约束。
  func enforcePersistenceConstraints() throws {
    let lan = listen.lan
    if lan.authenticationEnabled
      && (!RuntimeListenerAuthentication.validUsername(lan.username)
        || lan.passwordReference == nil)
    {
      throw ProxySettingsStoreError.credentialFailure(detail: String(localized: "局域网身份验证凭据无效"))
    }
    let errors = validationErrors
    guard errors.isEmpty else { throw ProxySettingsStoreError.invalid(errors) }
  }
}

protocol ProxySettingsStoring {
  func load() throws -> ProxySettings
  func save(_ settings: ProxySettings) throws
}

enum ProxySettingsStoreError: Error, Equatable {
  case corrupt(detail: String)
  case invalid([PortSettingError])
  case ioFailure(detail: String)
  case credentialFailure(detail: String)
}

struct RestoredProxySettings: Equatable {
  let settings: ProxySettings
  let unreadableError: ProxySettingsStoreError?
}
