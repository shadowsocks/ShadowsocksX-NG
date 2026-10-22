import SwiftUI

/// 重命名分组表单：名称初值取现名；失败保留名称，成功才关闭。
struct RenameGroupSheet: View {
  let workflow: CatalogWorkflow
  let errors: ErrorAlertPresenter
  let nodeID: NodeID
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var isSubmitting = false
  @FocusState private var nameFocused: Bool

  init(workflow: CatalogWorkflow, errors: ErrorAlertPresenter, nodeID: NodeID) {
    self.workflow = workflow
    self.errors = errors
    self.nodeID = nodeID
    // 打开时的现名仅作为初值，后续编辑由本表单持有。
    _name = State(initialValue: workflow.displayName(for: nodeID))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("重命名分组").font(.title2)
      TextField("名称", text: $name)
        .focused($nameFocused)
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
        Button("保存") { rename() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
    .disabled(isSubmitting)
    .interactiveDismissDisabled(isSubmitting)
    .defaultFocus($nameFocused, true)
  }

  private func rename() {
    guard !isSubmitting else { return }
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      do {
        try await workflow.renameGroup(nodeID, to: name)
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}
