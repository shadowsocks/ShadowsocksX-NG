import Foundation

extension ProxyRuntimeController {
  /// The choice persists in UserDefaults independently of listening configuration. ACL-backed modes (direct
  /// and global) also deploy and verify the ACL runtime even when system proxy
  /// is off, because manually connected SOCKS and HTTP clients use the same ACL.
  func setProxyMode(_ mode: ProxyMode) async {
    guard mode != proxyMode else { return }
    await transitionMode(mode, preset: settings.rulePreset)
  }

  /// 规则模式子选项：切换「未匹配时代理/直连」并重部署 ACL。
  /// 失败保留最新模式与子选项，发布后失败停止服务并暂停系统代理。
  func setRuleDefaultAction(_ action: RuleDefaultAction) async {
    await setRulePreset(RulePreset(legacy: action))
  }

  func setRulePreset(_ preset: RulePreset) async {
    guard preset != settings.rulePreset else { return }
    await transitionMode(proxyMode, preset: preset)
  }

  private func transitionMode(
    _ mode: ProxyMode,
    preset: RulePreset
  ) async {
    controlPreferences.preferredMode = mode.kind
    controlPreferences.rulePreset = preset
    settings.preferredMode = mode.kind
    settings.rulePreset = preset
    proxyMode = mode
    modeChangeGeneration += 1
    await convergeRuntime(.modeTransition)
  }
}
