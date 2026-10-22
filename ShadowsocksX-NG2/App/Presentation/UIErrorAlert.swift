import SwiftUI

/// 主窗口共享的错误弹窗呈现状态（UI 持有的窗口状态）：目录工作流
/// module 以 typed error 上抛且不生成本地化文案，这里在呈现边缘统一转换。
@MainActor
final class ErrorAlertPresenter: ObservableObject {
  @Published var message: String?

  var isPresented: Bool { message != nil }

  func present(_ error: Error) {
    message = error.presentableMessage
  }

  func present(text: String) {
    message = text
  }

  func dismiss() {
    message = nil
  }
}

/// `ErrorAlertPresenter` 的唯一 alert 挂载边缘：标题固定「操作失败」，文案取
/// presenter 当前消息。此前这段 10 行样板复制在窗口壳、destination 包装与
/// 服务器分区共五处；挂载点各自独立呈现，互不冲突。
private struct PresentingErrors: ViewModifier {
  @ObservedObject var presenter: ErrorAlertPresenter

  func body(content: Content) -> some View {
    content
      .alert(
        "操作失败",
        isPresented: Binding(
          get: { presenter.isPresented },
          set: { if !$0 { presenter.dismiss() } })
      ) {
        Button("好", role: .cancel) {}
      } message: {
        Text(presenter.message ?? "")
      }
  }
}

extension View {
  /// 挂载共享错误弹窗：present 进 `presenter` 的失败由此统一弹出。
  func presentingErrors(_ presenter: ErrorAlertPresenter) -> some View {
    modifier(PresentingErrors(presenter: presenter))
  }
}
