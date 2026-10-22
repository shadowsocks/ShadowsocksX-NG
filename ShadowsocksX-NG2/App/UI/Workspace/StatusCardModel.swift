import Foundation

/// 菜单栏面板代理状态卡的呈现模型：从代理控制
/// 工作流的整体 snapshot 派生卡片数据——行结构（哪些行、条件 detail、顺序）、
/// 活动目标回退文案与语义色调政策全部在此决定；文本复用 StatusMenuModel 的
/// 同一映射（配色与文本同源）。不持有 SwiftUI/AppKit 类型，纯逻辑可测；视觉
/// 细节（tone→语义色、排版）在 StatusCardView 呈现，不建自动测试。
enum StatusCardModel {
  /// 语义色调：呈现层映射为系统语义色（positive=green、attention=orange、
  /// failure=red、neutral=secondary）。
  enum Tone: Equatable {
    case positive
    case attention
    case failure
    case neutral
  }

  struct Row: Equatable {
    let label: String
    let text: String
    let tone: Tone
  }

  struct DetailLine: Equatable {
    let text: String
    let tone: Tone
  }

  /// 活动目标行：正文与悬停/辅助说明（未激活时按模式区分回退文案）。
  struct TargetPresentation: Equatable {
    let text: String
    let help: String
  }

  struct Card: Equatable {
    let runtimeRow: Row
    /// agent 侧点名原因（运行失败或激活拒绝）；无则 nil。
    let runtimeDetail: DetailLine?
    let systemProxyRow: Row
    /// 系统代理写入/清理失败点名；非失败态为 nil。
    let systemProxyDetail: DetailLine?
    let target: TargetPresentation
    /// 模式行文本（规则模式带子选项，与状态菜单同口径）。
    let modeText: String
  }

  static func card(from snapshot: ProxyControlSnapshot) -> Card {
    let summary = StatusMenuModel.summary(from: snapshot)
    let runtimeTone = runtimeTone(for: snapshot.runtime.status)
    return Card(
      runtimeRow: Row(label: String(localized: "后台代理"), text: summary.status, tone: runtimeTone),
      runtimeDetail: summary.detail.map {
        DetailLine(text: $0, tone: runtimeDetailTone(snapshot: snapshot, runtimeTone: runtimeTone))
      },
      systemProxyRow: Row(
        label: String(localized: "系统代理设置"),
        text: summary.systemProxyStateLabel,
        tone: systemProxyTone(for: snapshot.systemProxyApplication)),
      systemProxyDetail: summary.systemProxyDetail.map {
        DetailLine(text: $0, tone: .failure)
      },
      target: targetPresentation(summary: summary, proxyMode: snapshot.proxyMode),
      modeText: summary.modeLabel)
  }

  private static func runtimeTone(for status: ProxyRuntimeStatus) -> Tone {
    switch status {
    case .running: .positive
    case .starting, .off: .neutral
    case .firewallBlocked, .requiresApproval: .attention
    case .launchFailed, .serviceFailed: .failure
    }
  }

  /// agent 点名原因色调：运行失败跟随运行状态色调；激活点名失败独立显红；
  /// 其余中性。
  private static func runtimeDetailTone(snapshot: ProxyControlSnapshot, runtimeTone: Tone) -> Tone {
    if snapshot.runtime.failure != nil {
      return runtimeTone
    }
    return snapshot.activationFailure == nil ? .neutral : .failure
  }

  private static func systemProxyTone(for application: SystemProxyApplicationFacts) -> Tone {
    switch application {
    case .idle: .neutral
    case .pending, .changed, .applying, .repairing, .paused: .attention
    case .applied: .positive
    case .failed, .repairFailed, .clearFailed, .unreadable: .failure
    }
  }

  /// 活动目标回退：有目标用路径；未激活时直连模式无需目标，其余模式提示
  /// 未激活。
  private static func targetPresentation(
    summary: StatusMenuModel.Summary, proxyMode: ProxyMode
  ) -> TargetPresentation {
    if let targetPath = summary.targetPath {
      return TargetPresentation(text: targetPath, help: String(localized: "活动目标：\(targetPath)"))
    }
    if proxyMode == .direct {
      return TargetPresentation(
        text: String(localized: "直连模式（无需服务器）"), help: String(localized: "直连模式无需选择活动目标"))
    }
    return TargetPresentation(
      text: String(localized: "未激活"), help: String(localized: "未设置活动目标；在首页或服务器目录中激活"))
  }
}
