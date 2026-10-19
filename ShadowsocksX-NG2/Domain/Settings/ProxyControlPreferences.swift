import Foundation

/// 当前用户的代理控制偏好；采用 UserDefaults 的即时内存更新与异步写盘语义。
struct ProxyControlPreferences {
  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  var preferredMode: ProxyModeKind {
    get {
      defaults.string(forKey: "proxyControl.preferredMode").flatMap(ProxyModeKind.init(rawValue:))
        ?? .rule
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: "proxyControl.preferredMode") }
  }

  var ruleDefaultAction: RuleDefaultAction {
    get {
      defaults.string(forKey: "proxyControl.ruleDefaultAction").flatMap(
        RuleDefaultAction.init(rawValue:)) ?? .proxyWhenUnmatched
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: "proxyControl.ruleDefaultAction") }
  }

  var agentEnabled: Bool {
    get { defaults.object(forKey: "proxyControl.agentEnabled") as? Bool ?? false }
    nonmutating set { defaults.set(newValue, forKey: "proxyControl.agentEnabled") }
  }

  var systemProxyEnabled: Bool {
    get { defaults.object(forKey: "proxyControl.systemProxyEnabled") as? Bool ?? false }
    nonmutating set { defaults.set(newValue, forKey: "proxyControl.systemProxyEnabled") }
  }

  var proxyExceptions: String {
    get { defaults.object(forKey: "proxyControl.proxyExceptions") as? String ?? "" }
    nonmutating set { defaults.set(newValue, forKey: "proxyControl.proxyExceptions") }
  }
}
