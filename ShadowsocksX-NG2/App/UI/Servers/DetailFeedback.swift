import SwiftUI

/// 稳定容器持有详情计时会话，即使暂时没有结果也能接收后续完成事件。
struct DetailFeedback<Result: DetailFeedbackResult, Content: View>: View {
  let completion: Result?
  @ViewBuilder let content: (Result) -> Content
  @State private var feedback: DetailFeedbackState<Result>

  init(completion: Result?, @ViewBuilder content: @escaping (Result) -> Content) {
    self.completion = completion
    self.content = content
    self._feedback = State(initialValue: DetailFeedbackState<Result>())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let result = feedback.completion, result.id == completion?.id {
        content(result)
      }
    }
    .task(id: completion?.id) {
      await feedback.present(completion)
    }
  }
}
