import SwiftUI

/// 失败保留名称和所选位置；创建成功才关闭表单。
struct NewGroupSheet: View {
  let workflow: CatalogWorkflow
  let errors: ErrorAlertPresenter
  let onCreated: (NodeID) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var parent: NodeID?
  @State private var isSubmitting = false
  @FocusState private var nameFocused: Bool

  init(
    workflow: CatalogWorkflow, errors: ErrorAlertPresenter, parent: NodeID?,
    onCreated: @escaping (NodeID) -> Void
  ) {
    self.workflow = workflow
    self.errors = errors
    self.onCreated = onCreated
    // 打开时的父组仅作为初值，后续位置由本表单持有。
    _parent = State(initialValue: parent)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("新建分组").font(.title2)
      TextField("名称", text: $name)
        .focused($nameFocused)
      CreationLocationField(tree: workflow.tree, parent: $parent)
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
        Button("创建") { create() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
    .disabled(isSubmitting)
    .interactiveDismissDisabled(isSubmitting)
    .defaultFocus($nameFocused, true)
  }

  private func create() {
    guard !isSubmitting else { return }
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      do {
        let id = try await workflow.createGroup(named: name, into: parent)
        onCreated(id)
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}
