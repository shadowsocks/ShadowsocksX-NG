import SwiftUI

/// 激活条件常驻，命令结果计时；调用方仅传入展示值。
struct ActivationDetailFeedbackView: View {
  let messages: [String]
  let completion: ActivationFeedbackState.Completion?
  @StateObject private var feedback = ActivationDetailFeedbackState()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(messages, id: \.self) { message in
        feedbackRow(message, symbol: "exclamationmark.triangle.fill", color: .orange)
      }
      if let result = feedback.completion, result.id == completion?.id {
        feedbackRow(
          message(for: result.feedback),
          symbol: result.feedback.isSuccess
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
          color: result.feedback.isSuccess ? .green : .red)
      }
    }
    .font(.callout)
    .task(id: completion?.id) {
      feedback.present(completion)
      guard let completion, let expiresAt = feedback.expiresAt else { return }
      do {
        try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
      } catch { return }
      guard !Task.isCancelled else { return }
      feedback.expire(completion.id)
    }
  }

  private func feedbackRow(_ message: String, symbol: String, color: Color) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: symbol).foregroundStyle(color)
      Text(message)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private func message(for result: ActivationFeedbackState.Feedback) -> String {
    switch result {
    case .activated(let skipped) where skipped > 0:
      return String(localized: "已跳过 \(skipped) 个存在已知阻塞问题的服务器。", table: "ServerDetails")
    case .activated:
      return String(localized: "激活成功", table: "ServerDetails")
    case .rejected(let failure):
      return AppPresentation.message(for: failure)
    case .failed(let message):
      return message
    }
  }
}
