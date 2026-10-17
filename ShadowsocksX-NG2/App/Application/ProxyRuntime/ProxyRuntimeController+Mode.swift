import Foundation

extension ProxyRuntimeController {
  /// The choice persists with the settings snapshot. ACL-backed modes (direct
  /// and global) also deploy and verify the ACL runtime even when system proxy
  /// is off, because manually connected SOCKS and HTTP clients use the same ACL.
  func setProxyMode(_ mode: ProxyMode) async {
    guard mode != proxyMode else { return }
    await transitionMode(mode, ruleDefaultAction: settings.ruleDefaultAction)
  }

  /// 规则模式子选项：切换「未匹配时代理/直连」并重部署 ACL。
  /// 失败保留旧模式、旧子选项与旧系统代理应用状态。
  func setRuleDefaultAction(_ action: RuleDefaultAction) async {
    guard action != settings.ruleDefaultAction else { return }
    await transitionMode(proxyMode, ruleDefaultAction: action)
  }

  private func transitionMode(
    _ mode: ProxyMode,
    ruleDefaultAction: RuleDefaultAction
  ) async {
    let snapshot = ModeTransitionSnapshot(
      settings: settings, mode: proxyMode, document: lastDocument, state: state)
    var next = settings
    next.preferredMode = mode.kind
    next.ruleDefaultAction = ruleDefaultAction
    guard persistSettings(next) else { return }
    settings = next
    proxyMode = mode
    modeChangeGeneration += 1
    await convergeRuntime(.modeTransition(snapshot))
  }
}
