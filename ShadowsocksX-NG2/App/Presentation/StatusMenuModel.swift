import Foundation

/// 状态菜单的呈现模型：从代理控制工作流
/// 的整体 snapshot 派生菜单数据。agent 与系统代理是两个独立状态面；不持有
/// AppKit 类型，纯逻辑可测；视觉与交互细节（勾选标记、禁用态）在
/// ProxyStatusMenu 呈现，不建自动测试。
enum StatusMenuModel {
  /// 头部状态摘要：agent 运行状态、当前模式、活动目标（含点名失败细节）与
  /// 系统代理实际应用状态。
  struct Summary: Equatable {
    /// Agent 开关意图（开关勾选态的绑定来源）。
    let agentIntentEnabled: Bool
    /// Agent 运行状态的「在跑」投影。
    let isOn: Bool
    /// Agent 运行状态文本。
    let status: String
    /// Agent 侧点名原因：运行失败或激活拒绝/目标清除（独立于运行状态）。
    let detail: String?
    /// 系统代理开关意图（开关勾选态的绑定来源）。
    let systemProxyIntentEnabled: Bool
    /// 系统代理实际应用状态文本（与 agent 运行状态分开呈现）。
    let systemProxyStatus: String
    /// 同上但不带「系统代理：」前缀（首页等已有上下文的呈现面用）。
    let systemProxyStateLabel: String
    /// 系统代理写入/清理失败的点名原因；非失败态为 nil。
    let systemProxyDetail: String?
    let modeLabel: String
    /// 活动目标从根到节点的显示名路径；未激活为 nil。
    let targetPath: String?
  }

  /// 运行状态 → 摘要映射（与主窗口诊断区口径一致）：输入是代理控制工作流
  /// 的整体 snapshot，菜单不再拆装控制器或运行时字段。
  static func summary(from snapshot: ProxyControlSnapshot) -> Summary {
    let agentDetail =
      snapshot.runtime.failure.map { AppPresentation.message(for: $0) }
      ?? snapshot.activationFailure.map { AppPresentation.message(for: $0) }
    let systemProxy = systemProxyPresentation(
      for: snapshot.systemProxyApplication,
      approvalRequired: snapshot.systemProxyApprovalRequired,
      backgroundUnavailable: snapshot.systemProxyInspection.backgroundUnavailable)
    return Summary(
      agentIntentEnabled: snapshot.agentIntentEnabled,
      isOn: snapshot.runtime.isOn,
      status: statusText(for: snapshot.runtime.status),
      detail: agentDetail,
      systemProxyIntentEnabled: snapshot.systemProxyIntentEnabled,
      systemProxyStatus: "系统代理：\(systemProxy.label)",
      systemProxyStateLabel: systemProxy.label,
      systemProxyDetail: systemProxy.detail,
      modeLabel: modeLabel(for: snapshot),
      targetPath: snapshot.activeTarget?.pathSummary)
  }

  /// 模式标签：规则模式带上子选项。
  private static func modeLabel(for snapshot: ProxyControlSnapshot) -> String {
    let mode = snapshot.proxyMode
    if mode == .rule {
      return "\(mode.label) · \(snapshot.ruleDefaultAction.label)"
    }
    return mode.label
  }

  private static func statusText(for status: ProxyRuntimeStatus) -> String {
    switch status {
    case .off:
      return "代理未运行"
    case .starting:
      return "正在启动代理…"
    case .running:
      return "代理运行中"
    case .firewallBlocked:
      return "代理运行中（局域网受阻）"
    case .launchFailed:
      return "启动失败"
    case .requiresApproval:
      return "等待允许后台代理"
    case .serviceFailed:
      return "服务管理失败"
    }
  }

  // 系统代理应用状态 → 菜单文本；批准阻塞独立于操作结果。
  // Exhaustive presentation mapping for the closed state family.
  // swiftlint:disable:next cyclomatic_complexity
  private static func systemProxyPresentation(
    for application: SystemProxyApplicationFacts,
    approvalRequired: Bool,
    backgroundUnavailable: Bool
  ) -> (label: String, detail: String?) {
    switch application {
    case .idle:
      return ("未应用", nil)
    case .pending:
      return approvalRequired ? ("待批准", nil) : ("待应用", nil)
    case .changed: return ("配置已改变", nil)
    case .applying: return ("应用中", nil)
    case .repairing: return ("修复中", nil)
    case .paused:
      return ("已暂停", AppPresentation.systemProxyPausedNotice)
    case .unreadable(let facts):
      return (
        "无法检查",
        AppPresentation.systemProxyUnreadablePrefix
          + AppPresentation.message(for: RuntimeFailureFacts.systemProxy(facts))
      )
    case .repairFailed(let facts):
      return (
        "修复失败", failureDetail(facts, prefix: "无法修复系统代理配置：", approvalRequired: approvalRequired)
      )
    case .clearFailed(let facts):
      return (
        "清除失败",
        failureDetail(
          facts,
          prefix: backgroundUnavailable ? "后台代理不可用，系统代理配置未能清除。\n" : "系统代理配置未能清除：",
          approvalRequired: approvalRequired)
      )
    case .applied:
      return ("已应用", nil)
    case .failed(let facts):
      return ("应用失败", failureDetail(facts, prefix: "", approvalRequired: approvalRequired))
    }
  }
  private static func failureDetail(
    _ facts: SystemProxyFailureFacts, prefix: String, approvalRequired: Bool
  ) -> String? {
    if approvalRequired && facts == .operation(.helperUnavailable) { return nil }
    return prefix + AppPresentation.message(for: RuntimeFailureFacts.systemProxy(facts))
  }
}
