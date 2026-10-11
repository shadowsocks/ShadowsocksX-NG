import SwiftUI
import UniformTypeIdentifiers

private struct PluginTextDraft: Identifiable {
  let id = UUID()
  var value: String
}

struct PluginEditorSheet: View {
  @ObservedObject var model: PluginManagementModel
  let session: PluginEditorSession
  @Environment(\.dismiss) private var dismiss
  /// Each presentation seeds fresh drafts; row identities survive edits and moves.
  @State private var names: [PluginTextDraft]
  @State private var arguments: [PluginTextDraft]
  @State private var path: String
  @State private var failure: String?
  @State private var showFilePicker = false

  init(model: PluginManagementModel, session: PluginEditorSession) {
    self.model = model
    self.session = session
    _names = State(initialValue: session.initialNames.map { PluginTextDraft(value: $0) })
    _arguments = State(initialValue: session.initialArguments.map { PluginTextDraft(value: $0) })
    _path = State(initialValue: session.initialPath)
  }

  private var nameValues: [String] { names.map(\.value) }
  private var isManaged: Bool { session.managedProgram != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.title2)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("插件名称")
            if isManaged {
              Text(nameValues.joined(separator: ", ")).textSelection(.enabled)
            } else {
              PluginValueList(values: $names, placeholder: "插件名称", allowsReordering: false)
              if let issue = model.namesIssue(nameValues, session: session) { fieldError(issue) }
            }
          }
          if !isManaged {
            VStack(alignment: .leading, spacing: 8) {
              Text("可执行文件路径")
              HStack {
                TextField("可执行文件路径", text: $path).textFieldStyle(.roundedBorder)
                Button("选择文件…") { showFilePicker = true }
              }
              .padding(.all, 4)
              if let issue = model.pathIssue(path) { fieldError(issue) }
            }
            if nameValues.contains(where: {
              ManagedPluginCatalog.info(
                forProgram: $0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            }) {
              Text("保存后将覆盖所列名称对应的内置插件。")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            Text("本地启动参数")
            PluginValueList(values: $arguments, placeholder: "参数", allowsReordering: true)
            Text("每项作为一个完整参数传递，无需 shell 引号。仅在本机生效。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      if let failure {
        Label(failure, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote).foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button("保存") {
          do {
            try model.save(
              session, names: nameValues, path: path, arguments: arguments.map(\.value))
            dismiss()
          } catch { failure = PluginManagementCopy.error(error) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          model.snapshot.mappingsUnreadable
            || (!isManaged
              && (model.namesIssue(nameValues, session: session) != nil
                || model.pathIssue(path) != nil))
        )
      }
    }
    .padding(24)
    .frame(width: 600, height: 520)
    .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
      switch result {
      case .success(let url): path = url.path
      case .failure: failure = String(localized: "无法选择文件，请重试。")
      }
    }
  }

  private var title: String {
    if isManaged { return String(localized: "内置插件启动参数") }
    return session.isEditing ? String(localized: "编辑插件") : String(localized: "新增插件")
  }

  private func fieldError(_ error: PluginMappingError) -> some View {
    Text(PluginManagementCopy.error(error)).font(.caption).foregroundStyle(.red)
  }
}

private struct PluginValueList: View {
  @Binding var values: [PluginTextDraft]
  let placeholder: LocalizedStringKey
  let allowsReordering: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach($values) { $item in
        HStack {
          TextField(placeholder, text: $item.value).textFieldStyle(.roundedBorder)
          if allowsReordering {
            Button {
              move(item.id, by: -1)
            } label: {
              Image(systemName: "arrow.up")
                .frame(width: 16, height: 16)
            }
            .help("上移").accessibilityLabel("上移")
            .disabled(values.first?.id == item.id)
            Button {
              move(item.id, by: 1)
            } label: {
              Image(systemName: "arrow.down")
                .frame(width: 16, height: 16)
            }
            .help("下移").accessibilityLabel("下移")
            .disabled(values.last?.id == item.id)
          }
          Button {
            values.removeAll { $0.id == item.id }
          } label: {
            Image(systemName: "minus")
              .frame(width: 16, height: 16)
          }
          .help("删除此项").accessibilityLabel("删除此项")
        }
      }
      Button("添加一项") { values.append(PluginTextDraft(value: "")) }
    }
    .padding(.all, 4)
  }

  private func move(_ id: UUID, by offset: Int) {
    guard let index = values.firstIndex(where: { $0.id == id }),
      values.indices.contains(index + offset)
    else { return }
    values.swapAt(index, index + offset)
  }
}
