import SwiftUI

/// 新建与编辑共用表单生命周期；编辑身份固定，新建位置可逐级上移。
struct ServerFormSheet: View {
  enum Operation: Identifiable {
    case create(parent: NodeID?)
    case edit(NodeID)

    var id: String {
      switch self {
      case .create: return "create"
      case .edit(let id): return "edit-\(id.rawValue)"
      }
    }
  }

  @ObservedObject var workflow: CatalogWorkflow
  @StateObject private var errors = ErrorAlertPresenter()
  let operation: Operation
  let onCreated: (NodeID) -> Void
  @Environment(\.dismiss) private var dismiss
  @StateObject private var fields: ServerFormFields
  @State private var parent: NodeID?
  @State private var isSubmitting = false
  @State private var isConfirmingDiscard = false
  @FocusState private var fieldFocus: ServerFormField?

  init(
    workflow: CatalogWorkflow, operation: Operation,
    onCreated: @escaping (NodeID) -> Void
  ) {
    self.workflow = workflow
    self.operation = operation
    self.onCreated = onCreated
    // 独立草稿和位置只在 sheet 打开时初始化，父视图更新不重建。
    switch operation {
    case .create(let parent):
      _fields = StateObject(wrappedValue: ServerFormFields.newForm())
      _parent = State(initialValue: parent)
    case .edit:
      _fields = StateObject(wrappedValue: ServerFormFields())
      _parent = State(initialValue: nil)
    }
  }

  private var editID: NodeID? {
    if case .edit(let id) = operation { return id }
    return nil
  }

  private var canSubmit: Bool {
    if editID != nil { return fields.hasChanges && fields.canSaveServer }
    return true
  }

  private var plugin: PluginSectionState? {
    if editID != nil { return fields.presentation?.plugin }
    return workflow.newFormPluginSection(selection: fields.pluginChoice)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(editID == nil ? String(localized: "新建服务器") : String(localized: "编辑服务器"))
        .font(.title2)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if editID != nil, fields.hasLoadedServer, fields.presentation == nil {
            Label("服务器已不存在，无法保存。", systemImage: "exclamationmark.triangle")
          }
          if let failure = fields.loadFailure {
            loadFailureNotice(failure)
          }
          if editID == nil || fields.hasLoadedServer {
            ServerFormFieldsGrid(
              fields: fields, plugin: plugin, isEditable: true,
              fieldFocus: $fieldFocus,
              location: editID == nil
                ? CreationLocationField(tree: workflow.tree, parent: $parent) : nil)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 焦点框绘制在控件边界外，需在滚动区内部预留空间。
        .padding(8)
      }
      HStack {
        Spacer()
        Button("取消", role: .cancel, action: requestDismiss)
          .keyboardShortcut(.cancelAction)
        if editID != nil {
          Button("重置") { fields.reloadServer(load: workflow.serverEditForm) }
            .disabled(!fields.hasChanges || fields.presentation?.isEditable != true)
        }
        Button(editID == nil ? String(localized: "创建") : String(localized: "保存"), action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(!canSubmit)
      }
    }
    .disabled(isSubmitting)
    .interactiveDismissDisabled(isSubmitting || fields.hasChanges)
    .onExitCommand(perform: requestDismiss)
    .alert("放弃更改？", isPresented: $isConfirmingDiscard) {
      Button("继续编辑", role: .cancel) {}
      Button("放弃更改", role: .destructive) { dismiss() }
    }
    .presentingErrors(errors)
    .defaultFocus($fieldFocus, .name)
    .padding(20)
    .frame(minWidth: 600, idealWidth: 640, minHeight: 400, idealHeight: 620)
    .onAppear {
      if let editID { fields.showServer(editID, load: workflow.serverEditForm) }
    }
    .onReceive(workflow.$tree) { _ in
      if let editID {
        fields.updatePresentation(
          workflow.serverFormPresentation(for: editID), preservingDraft: true)
      }
    }
  }

  private func loadFailureNotice(_ failure: ServerFormLoadError) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("无法加载服务器资料", systemImage: "exclamationmark.triangle")
        .font(.headline)
      if fields.hasLoadedServer {
        Text("重新加载失败。当前草稿已保留，重新加载成功后才能保存。")
      } else if failure == .notFound {
        Text("服务器已不存在，无法保存。")
      } else {
        Text("无法读取服务器凭据。请重新加载后再试。")
      }
      Button("重新加载") { fields.reloadServer(load: workflow.serverEditForm) }
    }
    .font(.callout)
  }

  private func requestDismiss() {
    guard !isSubmitting else { return }
    if fields.hasChanges { isConfirmingDiscard = true } else { dismiss() }
  }

  private func submit() {
    guard !isSubmitting, canSubmit else { return }
    guard fields.validateForSubmit(), let draft = fields.draft else {
      fieldFocus = fields.firstErrorField
      return
    }
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      do {
        switch operation {
        case .create:
          onCreated(try await workflow.createServer(draft, into: parent))
        case .edit(let id):
          try await workflow.updateServer(id, draft: draft)
        }
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}
