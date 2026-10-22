import Foundation

extension ProxyRuntimeController {
  /// The choice persists in UserDefaults independently of listening configuration. ACL-backed modes (direct
  /// and global) also deploy and verify the ACL runtime even when system proxy
  /// is off, because manually connected SOCKS and HTTP clients use the same ACL.
  func setProxyMode(_ mode: ProxyMode) async {
    guard mode != proxyMode else { return }
    await transitionMode(mode, ruleDefaultAction: settings.ruleDefaultAction)
  }

  /// 规则模式子选项：切换「未匹配时代理/直连」并重部署 ACL。
  /// 失败保留最新模式与子选项，发布后失败停止服务并暂停系统代理。
  func setRuleDefaultAction(_ action: RuleDefaultAction) async {
    guard action != settings.ruleDefaultAction else { return }
    await transitionMode(proxyMode, ruleDefaultAction: action)
  }

  private func transitionMode(
    _ mode: ProxyMode,
    ruleDefaultAction: RuleDefaultAction
  ) async {
    controlPreferences.preferredMode = mode.kind
    controlPreferences.ruleDefaultAction = ruleDefaultAction
    settings.preferredMode = mode.kind
    settings.ruleDefaultAction = ruleDefaultAction
    proxyMode = mode
    modeChangeGeneration += 1
    await convergeRuntime(.modeTransition)
  }
}
