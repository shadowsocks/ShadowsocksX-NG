import SwiftUI

/// 「运行控制」卡：agent 与系统代理两个开关并排，绑定同一
/// snapshot 的持久化意图；状态行经 StatusDisplayModel 的瞬态门控呈现——
/// 快速切换模式这类瞬间成功的操作不再闪「应用中」等中间态。两个开关
/// 互不代替：关闭系统代理清除全部系统代理配置，关闭 agent 会级联关闭仍开启
/// 的系统代理意图并先清理再停止监听；helper 待批准时呈现登录项批准路径。
struct RuntimeControlCard: View {
  @ObservedObject var control: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel

  var body: some View {
    HomeCard(
      title: String(localized: "运行控制"),
      subtitle: nil,
      trailing: { EmptyView() },
      content: {
        VStack(alignment: .leading, spacing: 6) {
          Toggle(isOn: agentBinding) {
            Text("运行后台代理客户端")
              .font(.title3)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .toggleStyle(.switch)
          statusRow(statusDisplay.agent.row)
          if let detail = statusDisplay.agent.detail {
            Text(detail.text)
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          Toggle(isOn: systemProxyBinding) {
            Text("设置系统代理")
              .font(.title3)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .toggleStyle(.switch)
          statusRow(statusDisplay.systemProxy.row)
          Text(statusDisplay.systemProxy.hint)
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
          if let systemProxyDetail = statusDisplay.systemProxy.detail,
            !statusDisplay.systemProxy.isPaused
          {
            Text(systemProxyDetail.text)
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      })
  }

  private func statusRow(_ row: StatusCardModel.Row) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor(row.tone))
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(row.text)
        .font(.body.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private func statusColor(_ tone: StatusCardModel.Tone) -> Color {
    switch tone {
    case .positive: .green
    case .attention: .orange
    case .failure: .red
    case .neutral: .secondary
    }
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
