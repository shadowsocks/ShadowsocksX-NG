import SwiftUI

/// 「快速操作」卡：更新全部订阅。
struct QuickActionCard: View {
  @ObservedObject var workflow: CatalogWorkflow

  @State private var isRefreshingAll = false

  var body: some View {
    HomeCard(
      title: "快速操作",
      subtitle: nil,
      trailing: { EmptyView() },
      content: {
        VStack(spacing: 10) {
          QuickActionButton(
            icon: "arrow.triangle.2.circlepath",
            title: isRefreshingAll ? "正在更新…" : "更新全部订阅",
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
