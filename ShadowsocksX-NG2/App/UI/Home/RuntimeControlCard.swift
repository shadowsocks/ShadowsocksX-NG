import SwiftUI

/// 「运行控制」卡：agent 与系统代理两个开关并排，绑定同一
/// snapshot 的持久化意图；各自呈现运行状态/实际应用与点名原因。两个开关
/// 互不代替：关闭系统代理清除全部系统代理配置，关闭 agent 会级联关闭仍开启
/// 的系统代理意图并先清理再停止监听；helper 待批准时呈现登录项批准路径。
struct RuntimeControlCard: View {
  @ObservedObject var control: ProxyControlWorkflow

  var body: some View {
    let summary = StatusMenuModel.summary(from: control.snapshot)
    HomeCard(
      title: String(localized: "运行控制"),
      subtitle: String(localized: "后台代理客户端与系统代理设置相互独立控制"),
      trailing: { EmptyView() },
      content: {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Toggle("后台代理客户端", isOn: agentBinding)
                .toggleStyle(.switch)
              Spacer(minLength: 0)
              Text(summary.status)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            if let detail = summary.detail {
              Text(detail)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          Divider()
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Toggle("设置系统代理", isOn: systemProxyBinding)
                .toggleStyle(.switch)
              Spacer(minLength: 0)
              Text(summary.systemProxyStateLabel)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Text(systemProxyHint)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if systemProxyApprovalNeeded {
              Button("在登录项中批准…") {
                Task { await control.openSystemProxyHelperApproval() }
              }
              .controlSize(.small)
            }
            SystemProxyDifferenceView(control: control)
            if let systemProxyDetail = summary.systemProxyDetail,
              control.snapshot.systemProxyApplication != .paused
            {

              Text(systemProxyDetail)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.top, 6)
      })
  }

  private var agentBinding: Binding<Bool> {
    Binding(
      get: { control.snapshot.agentIntentEnabled },
      set: { enabled in Task { await control.setAgentEnabled(enabled) } })
  }

  private var systemProxyBinding: Binding<Bool> {
    Binding(
      get: { control.snapshot.systemProxyIntentEnabled },
      set: { enabled in Task { await control.setSystemProxyEnabled(enabled) } })
  }

  private var systemProxyApprovalNeeded: Bool {
    control.snapshot.systemProxyApprovalRequired
  }

  private var systemProxyHint: String {
    let exitRequirement =
      control.snapshot.proxyMode == .direct
      ? String(localized: "直连模式不依赖活动服务器")
      : String(localized: "其他模式需要可用的活动服务器")
    if systemProxyApprovalNeeded {
      return String(localized: "系统代理助手等待批准。请在系统设置 → 登录项与扩展中允许。")
    }
    return switch control.snapshot.systemProxyApplication {
    case .idle:
      String(localized: "开启后让 macOS 系统代理指向本地入口；\(exitRequirement)")
    case .pending:
      String(localized: "已请求应用系统代理，等待本地入口就绪；\(exitRequirement)")
    case .applied:
      String(localized: "系统代理已指向本地入口")
    case .failed, .repairFailed, .clearFailed:
      String(localized: "操作失败，原因见下方")
    case .paused:
      AppPresentation.systemProxyPausedNotice
    case .changed:
      String(localized: "当前系统代理配置与预期存在差异")
    case .unreadable:
      String(localized: "无法检查当前系统代理配置")
    case .applying:
      String(localized: "正在应用系统代理配置…")
    case .repairing:
      String(localized: "正在修复系统代理配置…")
    }
  }
}

/// Names and commands come from current workflow facts; no configuration decisions in SwiftUI.
private struct SystemProxyDifferenceView: View {
  @ObservedObject var control: ProxyControlWorkflow

  var body: some View {
    let facts = control.snapshot.systemProxyInspection
    VStack(alignment: .leading, spacing: 6) {
      ForEach([SystemProxyDifference.Kind.changed, .notApplied, .remaining], id: \.self) { kind in
        let names = facts.differences.filter { $0.kind == kind }.map(\.name)
        if !names.isEmpty {
          Label {
            Text(differenceMessage(kind) + "\n" + names.joined(separator: "\n"))
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }
      if control.snapshot.systemProxyApplication == .repairing {
        HStack {
          ProgressView().controlSize(.small)
          Text("修复中…").font(.caption)
        }
      }
      if let failure = facts.readFailure,
        control.snapshot.systemProxyApplication != .unreadable(failure)
      {
        Text(
          AppPresentation.systemProxyUnreadablePrefix
            + AppPresentation.message(for: RuntimeFailureFacts.systemProxy(failure))
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }
      if facts.canRepair {
        Button("修复") { Task { await control.repairSystemProxy() } }
          .controlSize(.small)
      }
      if facts.canRetryClear {
        Button("重试清除") { Task { await control.retrySystemProxyClear() } }
          .controlSize(.small)
      }
      if facts.readFailure != nil && !facts.isBusy {
        Button("重新检查") { Task { await control.recheckSystemProxy() } }
          .controlSize(.small)
      }
    }
  }

  private func differenceMessage(_ kind: SystemProxyDifference.Kind) -> String {
    switch kind {
    case .changed: String(localized: "以下网络接口的代理配置已被改变：")
    case .notApplied: String(localized: "以下网络接口尚未应用当前系统代理配置：")
    case .remaining: String(localized: "以下网络接口的代理配置仍有差异：")
    }
  }
}
