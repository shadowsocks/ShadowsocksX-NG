import SwiftUI

/// 「快速操作」卡：更新全部订阅。
struct QuickActionCard: View {
  @ObservedObject var workflow: CatalogWorkflow

  @State private var isRefreshingAll = false

  var body: some View {
    HomeCard(
      title: String(localized: "快速操作"),
      subtitle: nil,
      trailing: { EmptyView() },
      content: {
        VStack(spacing: 10) {
          QuickActionButton(
            icon: "arrow.triangle.2.circlepath",
            title: isRefreshingAll ? String(localized: "正在更新…") : String(localized: "更新全部订阅"),
            help: nil,
            action: refreshAll
          )
          .disabled(workflow.subscriptions.isEmpty || isRefreshingAll)
          if isRefreshingAll {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.top, 6)
      })
  }

  private func refreshAll() {
    isRefreshingAll = true
    Task {
      await workflow.refreshAllSubscriptions()
      isRefreshingAll = false
    }
  }

}

/// 快速操作行按钮。
struct QuickActionButton: View {
  let icon: String
  let title: String
  var help: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .foregroundStyle(.tint)
        Text(title)
          .font(.callout.weight(.medium))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "arrow.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .help(help ?? title)
  }
}
