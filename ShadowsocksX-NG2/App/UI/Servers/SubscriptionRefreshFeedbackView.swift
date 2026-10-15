import SwiftUI

/// 调用方提供给通用详情插槽的订阅提示；计时任务随视图退出取消。
struct SubscriptionRefreshFeedbackView: View {
  let isRefreshing: Bool
  let completion: SubscriptionRefreshCompletion?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isRefreshing {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(String(localized: "正在更新订阅…", table: "ServerDetails"))
        }
        .foregroundStyle(.secondary)
      }
      DetailFeedback(completion: completion) { result in
        if !isRefreshing {
          HStack(alignment: .top, spacing: 8) {
            Image(
              systemName: result.failure == nil
                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(result.failure == nil ? Color.green : Color.red)
            Text(message(for: result))
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
    .font(.callout)
  }

  private func message(for result: SubscriptionRefreshCompletion) -> String {
    if let failure = result.failure {
      let reason = AppPresentation.message(for: failure)
      return String(localized: "订阅更新失败：\(reason)", table: "ServerDetails")
    }
    return String(localized: "订阅更新成功", table: "ServerDetails")
  }
}
